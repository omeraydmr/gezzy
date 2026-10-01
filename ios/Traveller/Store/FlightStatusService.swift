import BackgroundTasks
import Foundation
import Observation
import TravellerKit

/// Uçuşların rötar, kapı ve aşama bilgisini AeroDataBox'tan alır; değişince seyahati günceller,
/// bildirim gönderir ve kilit ekranındaki canlı kartı yeniler.
///
/// API anahtarı `FlightStatusAPIKey` (Info.plist) değeridir; boşsa servis kapalıdır.
@MainActor
@Observable
final class FlightStatusService {
    static let shared = FlightStatusService()
    static let backgroundTaskID = "app.traveller.ios.flightstatus"

    /// Kalkıştan bu kadar önce izlemeye başlanır.
    static let watchWindow: TimeInterval = 36 * 3600
    /// Aynı uçuş en fazla bu aralıkla sorulur (ücretsiz kotayı korumak için).
    static let minimumInterval: TimeInterval = 5 * 60

    private(set) var lastChecked: [UUID: Date] = [:]
    private(set) var checking: Set<UUID> = []
    private(set) var lastError: String?

    @ObservationIgnored private weak var store: TripStore?
    private let session = URLSession(configuration: .ephemeral)

    private var apiKey: String? {
        let key = (Bundle.main.object(forInfoDictionaryKey: "FlightStatusAPIKey") as? String)?
            .trimmingCharacters(in: .whitespaces)
        guard let key, !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }

    var isConfigured: Bool { apiKey != nil }

    func attach(_ store: TripStore) {
        self.store = store
    }

    /// İzlenen uçuş: kalkışa 36 saatten az kalmış ya da henüz inmemiş.
    static func isWatched(_ flight: FlightSegment, now: Date = .now) -> Bool {
        let departure = flight.effectiveDeparture
        return departure.timeIntervalSince(now) < watchWindow && flight.effectiveArrival.addingTimeInterval(3600) > now
            && flight.live?.phase != .arrived && flight.live?.phase != .canceled
    }

    /// İzlenen tüm uçuşları yeniler. `force` sıklık sınırını yok sayar (elle yenileme).
    @discardableResult
    func refreshAll(force: Bool = false) async -> Bool {
        guard let store, isConfigured else { return false }
        var changed = false
        for trip in store.trips {
            for flight in trip.flights where Self.isWatched(flight) {
                if await refresh(flightID: flight.id, in: trip.id, force: force) { changed = true }
            }
        }
        LiveActivityController.refresh(trips: store.trips)
        scheduleBackgroundRefresh()
        return changed
    }

    /// Tek uçuşu yeniler; önemli bir değişiklik olduysa true.
    @discardableResult
    func refresh(flightID: UUID, in tripID: UUID, force: Bool = false) async -> Bool {
        guard let store, let apiKey,
              let trip = store.trip(tripID), let flight = trip.flights.first(where: { $0.id == flightID }),
              !checking.contains(flightID) else { return false }
        if !force, let last = lastChecked[flightID], Date.now.timeIntervalSince(last) < Self.minimumInterval { return false }

        checking.insert(flightID)
        defer { checking.remove(flightID) }
        do {
            guard let status = try await fetch(flight, apiKey: apiKey) else {
                lastChecked[flightID] = .now
                lastError = String(localized: "Uçuş bulunamadı: \(flight.flightNumber)")
                return false
            }
            lastChecked[flightID] = .now
            lastError = nil
            return apply(status, to: flightID, in: tripID)
        } catch {
            lastError = String(localized: "Uçuş durumu alınamadı.")
            return false
        }
    }

    private func apply(_ status: FlightLiveStatus, to flightID: UUID, in tripID: UUID) -> Bool {
        guard let store, let trip = store.trip(tripID),
              let old = trip.flights.first(where: { $0.id == flightID }) else { return false }
        var comparable = status
        comparable.fetchedAt = old.live?.fetchedAt ?? status.fetchedAt
        let new = old.applying(status)
        // Yalnızca zaman damgası değiştiyse kaydetme (gereksiz iCloud eşitlemesi olmasın).
        guard old.live != comparable || old.gate != new.gate else { return false }

        store.update(tripID) { trip in
            if let index = trip.flights.firstIndex(where: { $0.id == flightID }) { trip.flights[index] = new }
        }
        let lines = FlightStatusChange.describe(old: old, new: new) { AppFormat.time($0, timeZone: new.departureTimeZone) }
        if !lines.isEmpty {
            let summary = TripChanges.Summary(title: "\(new.flightNumber) · \(new.fromCode) → \(new.toCode)", lines: lines,
                                              link: TripLink(tripID: tripID, section: "plan"))
            Task { await NotificationScheduler.shared.notifyCloudChange(summary) }
        }
        LiveActivityController.refresh(trips: store.trips)
        return true
    }

    private func fetch(_ flight: FlightSegment, apiKey: String) async throws -> FlightLiveStatus? {
        // Tarih kalkış havalimanının yerel günüdür.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = flight.departureTimeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: flight.departure)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let number = FlightStatusParser.normalizedNumber(flight.flightNumber)
        guard let url = URL(string: "https://aerodatabox.p.rapidapi.com/flights/number/\(number)/\(date)?withLocation=false")
        else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue("aerodatabox.p.rapidapi.com", forHTTPHeaderField: "X-RapidAPI-Host")
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 204 || code == 404 { return nil }
        guard (200..<300).contains(code) else { throw URLError(.badServerResponse) }
        return try FlightStatusParser.parseAeroDataBox(data, scheduledDeparture: flight.departure)
    }

    // MARK: Arka plan

    /// iOS uygun gördüğünde (en erken 15 dk sonra) arka planda yeniden sorar.
    func scheduleBackgroundRefresh() {
        guard isConfigured, let store,
              store.trips.contains(where: { $0.flights.contains { Self.isWatched($0) } }) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
