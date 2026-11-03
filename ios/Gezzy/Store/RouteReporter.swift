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
        /// Premium iken biten seyahat; abonelik bitse de gönderilmez.
        case skippedPremium
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
    /// Bu oturumda geri alınan / gönderilmeyecek seyahatler; kayıt yazılamasa da gönderimi engeller.
    private var excludedThisSession: Set<UUID> = []

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

    /// Premium durumu her seferinde canlı okunur; StoreKit ilk cevabı vermeden gönderim yapılmaz.
    func run(store: TripStore) async {
        let entitlements = Entitlements.shared
        guard entitlements.hasLoaded, !isRunning, !entriesUnreadable else { return }
        if entitlements.isPremium {
            skipEndedTrips(in: store)
            return
        }
        guard choice == .yes else { return }
        isRunning = true
        defer { isRunning = false }
        let service = CommunityService.shared
        for trip in store.trips {
            // Geri çekilen / reddedilen seyahat, topluluk tercihinden bağımsız olarak bir daha gönderilmez.
            var lastAttempt: Date?
            switch state(for: trip.id) {
            case .sent, .rejected, .withdrawn, .skippedPremium: continue
            case .pending(let date): lastAttempt = date
            case nil: break
            }
            if excludedThisSession.contains(trip.id) || service.choice(for: trip) == .declined { continue }
            // Önceki beklemede premium olunduysa kalanlar gönderilmez.
            guard isStillWanted(trip) else { break }
            let now = Date()
            guard RouteReportRetry.shouldAttempt(lastAttempt: lastAttempt, now: now) else { continue }
            // Kimlik yalnızca rapor gerçekten oluşuyorsa kaydedilir (üyesi olunan seyahatler kayıt bırakmaz).
            let id = entries[trip.id.uuidString]?.reportID ?? UUID().uuidString
            guard let report = RouteReport.make(trip: trip, me: store.me.id, reportID: id, now: now) else { continue }
            if entries[trip.id.uuidString] == nil {
                entries[trip.id.uuidString] = Entry(reportID: id, state: .pending(lastAttempt: nil))
                save()
            }
            var contribution = RouteReport.contribution(trip: trip)
            do {
                if let pending = contribution {
                    // Katkı en iyi çabayla: kalıcı ret ya da kota raporu engellemez.
                    do {
                        try await service.contribute(pending)
                    } catch CommunityService.Failure.rejected(let status) where RouteReportRetry.isFinal(status: status) || status == 429 {
                        print("RouteReporter: katkı gönderilemedi (\(status)); rapora devam")
                        contribution = nil
                    }
                }
                // Bekleme sırasında geri alındıysa, izin kapandıysa ya da premium olunduysa raporu gönderme.
                guard isStillWanted(trip) else {
                    await stopUnwanted(trip, reportID: nil, contribution: contribution)
                    continue
                }
                try await service.sendReport(report)
                guard isStillWanted(trip) else {
                    await stopUnwanted(trip, reportID: id, contribution: contribution)
                    continue
                }
                set(.sent, for: trip)
                service.setChoice(.shared, for: trip)
            } catch CommunityService.Failure.notConfigured {
                continue
            } catch CommunityService.Failure.rejected(let status) where RouteReportRetry.isFinal(status: status) {
                print("RouteReporter: sunucu raporu reddetti (\(status))")
                // Bekleme sırasında geri alındıysa o karar korunur.
                if isExcluded(trip) || Entitlements.shared.isPremium {
                    await stopUnwanted(trip, reportID: id, contribution: contribution)
                } else {
                    set(.rejected, for: trip)
                }
            } catch {
                if isExcluded(trip) || Entitlements.shared.isPremium {
                    await stopUnwanted(trip, reportID: id, contribution: contribution)
                } else {
                    set(.pending(lastAttempt: Date()), for: trip)
                }
            }
        }
    }

    /// Premium iken bitmiş ve gönderilmemiş seyahatler kalıcı olarak dışarıda bırakılır (sunucuya gidilmez).
    private func skipEndedTrips(in store: TripStore) {
        var changed = false
        for trip in store.trips where trip.isPast() {
            switch state(for: trip.id) {
            case .sent, .rejected, .withdrawn, .skippedPremium: continue
            case .pending, nil: break
            }
            excludedThisSession.insert(trip.id)
            let id = entries[trip.id.uuidString]?.reportID ?? UUID().uuidString
            entries[trip.id.uuidString] = Entry(reportID: id, state: .skippedPremium)
            changed = true
        }
        if changed { save() }
    }

    /// İstenmeyen gönderimi durdurur: premium olunduysa seyahati dışarıda bırakır, ulaşan parçaları geri çeker.
    private func stopUnwanted(_ trip: Trip, reportID: String?, contribution: CommunityPlaces.Contribution?) async {
        if Entitlements.shared.isPremium, !isExcluded(trip) {
            excludedThisSession.insert(trip.id)
            set(.skippedPremium, for: trip)
        }
        await undoIfWithdrawn(trip, reportID: reportID, contribution: contribution)
    }

    /// Geri alınmış ya da premium nedeniyle dışarıda bırakılmış.
    private func isExcluded(_ trip: Trip) -> Bool {
        excludedThisSession.contains(trip.id) || [.withdrawn, .skippedPremium].contains(state(for: trip.id))
    }

    private func isStillWanted(_ trip: Trip) -> Bool {
        choice == .yes && !Entitlements.shared.isPremium && !isExcluded(trip)
    }

    /// Geri alma kararını kaydeder; kayıt okunamıyorsa en azından bu oturumda gönderimi engeller.
    private func markWithdrawn(_ trip: Trip) {
        excludedThisSession.insert(trip.id)
        if entriesUnreadable {
            print("RouteReporter: kayıtlar okunamadığı için geri alma yalnızca bu oturumda tutuluyor")
        }
        set(.withdrawn, for: trip)
    }

    /// Gönderim sürerken geri alınan seyahatin sunucuya ulaşmış parçalarını (en iyi çabayla) geri çeker.
    private func undoIfWithdrawn(_ trip: Trip, reportID: String?, contribution: CommunityPlaces.Contribution?) async {
        guard isExcluded(trip) else { return }
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
        markWithdrawn(trip)
        service.clearChoice(for: trip)
    }

    /// Henüz gönderilmemiş seyahati gönderme; `.withdrawn` durumu tekrar gönderimi engeller.
    func exclude(_ trip: Trip) {
        markWithdrawn(trip)
    }
}
