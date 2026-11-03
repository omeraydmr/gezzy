import Foundation
import Observation
import GezzyKit

/// Biten seyahatlerin anonim rota raporunu, kullanıcı izin verdiyse (ve premium değilse) sunucuya gönderir.
@MainActor @Observable
final class RouteReporter {
    static let shared = RouteReporter()

    enum Choice: String { case yes, no }

    enum State: Codable, Equatable {
        case pending(lastAttempt: Date?), sent, rejected, withdrawn
    }

    private struct Entry: Codable {
        var reportID: String
        var state: State
    }

    private static let choiceKey = "gezzy.routeSharing.choice"
    private static let entriesKey = "gezzy.routeReports.v1"

    private(set) var choice: Choice?
    private var entries: [String: Entry]
    private var isRunning = false
    /// Kayıtlı durumlar okunamadıysa ham veri korunur: üzerine yazılmaz, gönderim yapılmaz
    /// (rapor kimlikleri yeniden üretilip seyahatler tekrar gönderilmesin).
    private var entriesUnreadable = false

    private init() {
        choice = UserDefaults.standard.string(forKey: Self.choiceKey).flatMap(Choice.init)
        entries = [:]
        if let data = UserDefaults.standard.data(forKey: Self.entriesKey) {
            do {
                entries = try JSONDecoder().decode([String: Entry].self, from: data)
            } catch {
                entriesUnreadable = true
                print("RouteReporter: kayıtlı rapor durumları okunamadı; gönderim durduruldu (\(error))")
            }
        }
    }

    func setChoice(_ newValue: Choice?) {
        choice = newValue
        if let newValue {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.choiceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.choiceKey)
        }
    }

    func state(for tripID: UUID) -> State? { entries[tripID.uuidString]?.state }

    private func save() {
        guard !entriesUnreadable else { return }
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: Self.entriesKey) }
    }

    /// Seyahat için kalıcı rapor kimliği (sunucu yalnızca UUID kabul eder).
    private func reportID(for trip: Trip) -> String {
        if let entry = entries[trip.id.uuidString] { return entry.reportID }
        let id = UUID().uuidString
        entries[trip.id.uuidString] = Entry(reportID: id, state: .pending(lastAttempt: nil))
        save()
        return id
    }

    private func set(_ state: State, for trip: Trip) {
        let id = reportID(for: trip)
        entries[trip.id.uuidString] = Entry(reportID: id, state: state)
        save()
    }

    func run(store: TripStore, isPremium: Bool) async {
        guard !isPremium, choice == .yes, !isRunning, !entriesUnreadable else { return }
        isRunning = true
        defer { isRunning = false }
        let service = CommunityService.shared
        for trip in store.trips {
            // Geri çekilen / reddedilen seyahat, topluluk tercihinden bağımsız olarak bir daha gönderilmez.
            var lastAttempt: Date?
            switch state(for: trip.id) {
            case .sent, .rejected, .withdrawn: continue
            case .pending(let date): lastAttempt = date
            case nil: break
            }
            if service.choice(for: trip) == .declined { continue }
            let now = Date()
            guard RouteReportRetry.shouldAttempt(lastAttempt: lastAttempt, now: now) else { continue }
            let id = reportID(for: trip)
            guard let report = RouteReport.make(trip: trip, me: store.me.id, reportID: id, now: now) else { continue }
            let contribution = RouteReport.contribution(trip: trip)
            do {
                if let contribution {
                    try await service.contribute(contribution)
                }
                // Bekleme sırasında geri alındıysa ya da izin kapandıysa raporu gönderme.
                guard isStillWanted(trip) else {
                    await undoIfWithdrawn(trip, reportID: nil, contribution: contribution)
                    continue
                }
                try await service.sendReport(report)
                guard isStillWanted(trip) else {
                    await undoIfWithdrawn(trip, reportID: id, contribution: contribution)
                    continue
                }
                set(.sent, for: trip)
                service.setChoice(.shared, for: trip)
            } catch CommunityService.Failure.notConfigured {
                continue
            } catch CommunityService.Failure.rejected(let status) where RouteReportRetry.isFinal(status: status) {
                print("RouteReporter: sunucu raporu reddetti (\(status))")
                set(.rejected, for: trip)
            } catch {
                set(.pending(lastAttempt: Date()), for: trip)
            }
        }
    }

    private func isStillWanted(_ trip: Trip) -> Bool {
        choice == .yes && state(for: trip.id) != .withdrawn
    }

    /// Gönderim sürerken geri alınan seyahatin sunucuya ulaşmış parçalarını (en iyi çabayla) geri çeker.
    private func undoIfWithdrawn(_ trip: Trip, reportID: String?, contribution: CommunityPlaces.Contribution?) async {
        guard state(for: trip.id) == .withdrawn else { return }
        let service = CommunityService.shared
        if let reportID { try? await service.withdrawReport(id: reportID) }
        if let contribution { try? await service.withdraw(contribution) }
    }

    /// Gönderilmiş raporu ve katkıları geri çeker. Topluluk kartı yeniden "Paylaş/Paylaşma" sorar.
    func withdraw(_ trip: Trip) async throws {
        let service = CommunityService.shared
        try await service.withdrawReport(id: reportID(for: trip))
        if let contribution = RouteReport.contribution(trip: trip) {
            try await service.withdraw(contribution)
        }
        set(.withdrawn, for: trip)
        service.clearChoice(for: trip)
    }

    /// Henüz gönderilmemiş seyahati gönderme; `.withdrawn` durumu tekrar gönderimi engeller.
    func exclude(_ trip: Trip) {
        set(.withdrawn, for: trip)
    }
}
