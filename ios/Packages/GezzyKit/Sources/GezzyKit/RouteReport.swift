import Foundation

/// Biten seyahatin rota raporu (kullanıcı izin verdiyse sunucuya gider). Kişi adı, gün tarihi, not, otel, uçuş,
/// harcama başlığı ve ödeyen kişi gönderilmez; yalnızca yıl ve ay.
public struct RouteReport: Codable, Hashable, Sendable {
    public struct Visit: Codable, Hashable, Sendable {
        public var ref: String
        public var startMinutes: Int?
        public var durationMinutes: Int
    }
    public struct Day: Codable, Hashable, Sendable {
        public var index: Int
        public var stops: [Visit]
    }
    public struct Spend: Codable, Hashable, Sendable {
        public var day: Int?
        public var category: String
        public var amount: Int
        public var originalAmount: Int?
        public var originalCurrency: String?
        public var splitCount: Int
    }

    /// Sunucunun kabul sınırları; aşılırsa rapor kalıcı reddedilirdi.
    static let maxDays = 60, maxVisitsPerDay = 30, maxPlaces = 200, maxExpenses = 500
    static let maxNights = 90, maxTravellers = 30, maxSplit = 30, maxCities = 20
    /// `places/contribute` sınırları (sunucu: community.ts `validate`).
    static let maxContributionPlaces = 60, maxContributionTransitions = 60

    public var reportID: String
    public var country: String
    public var city: String
    public var cities: [String]
    public var year: Int
    public var month: Int
    public var nights: Int
    public var travellers: Int
    public var currency: String
    public var places: [CommunityPlaces.Place]
    public var days: [Day]
    public var budget: [String: Int]
    public var expenses: [Spend]

    /// Ekipli seyahatte yalnızca sahibin cihazı gönderir; üye yoksa herkes (tek kişi).
    public static func isSender(_ trip: Trip, me: UUID) -> Bool {
        guard let owner = trip.members.first(where: { $0.role == .owner }) else { return true }
        return owner.id == me
    }

    /// Sunucunun reddedeceği adlı duraklar (bağlantı, telefon, yalnızca simge…) gönderilmez.
    static func implausibleStops(in trip: Trip) -> Set<UUID> {
        Set(CommunityPlaces.eligibleStops(in: trip).filter { !PlaceName.isPlausible($0.name) }.map(\.id))
    }

    /// Adı uygun duraklarla tam katkı (rapor için; sınırsız).
    static func fullContribution(trip: Trip, calendar: Calendar) -> CommunityPlaces.Contribution? {
        CommunityPlaces.contribution(for: trip, ratings: [:], verified: [], excluded: implausibleStops(in: trip),
                                     calendar: calendar)
    }

    /// Topluluk havuzu için oysuz katkı; sunucu sınırına (60 yer, 60 geçiş) kırpılır.
    public static func contribution(trip: Trip, calendar: Calendar = .current) -> CommunityPlaces.Contribution? {
        guard var full = fullContribution(trip: trip, calendar: calendar) else { return nil }
        full.places = Array(full.places.prefix(maxContributionPlaces))
        let kept = Set(full.places.map(\.ref))
        full.transitions = Array(full.transitions.filter { $0.allSatisfy(kept.contains) }.prefix(maxContributionTransitions))
        return full
    }

    /// Bu cihaz bu seyahatin raporunu gönderir mi (sahip, planlı, bitmiş, en az iki uygun yer).
    public static func willSend(trip: Trip, me: UUID, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        make(trip: trip, me: me, reportID: "", now: now, calendar: calendar) != nil
    }

    public static func make(trip: Trip, me: UUID, reportID: String, now: Date = Date(),
                            calendar: Calendar = .current) -> RouteReport? {
        // Taslak seyahatler gerçekten yapılmamış olabilir; yalnızca planlananlar.
        guard trip.status == .planned, CommunityPlaces.canContribute(trip, now: now, calendar: calendar),
              isSender(trip, me: me),
              let contribution = fullContribution(trip: trip, calendar: calendar) else { return nil }
        let cities = (trip.isMultiCity ? trip.cityLegs.map(\.destination.city) : [trip.destination.city])
            .filter { PlaceName.isPlausible($0) && $0.utf16.count <= 80 }
        guard let city = cities.first else { return nil }
        // Katkıdaki ref'ler uygun (adı geçerli) durakların sırasıyla eşleşir ("p0", "p1"…).
        let implausible = implausibleStops(in: trip)
        let eligible = CommunityPlaces.eligibleStops(in: trip).filter { !implausible.contains($0.id) }
        let start = calendar.startOfDay(for: trip.startDate)
        func dayIndex(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        }
        let dayCount = trip.days(calendar: calendar).count
        let places = contribution.places.prefix(maxPlaces).map { place in
            var place = place
            if place.category.utf16.count > 40 || (!place.category.isEmpty && !PlaceName.isPlausible(place.category)) {
                place.category = ""
            }
            return place
        }
        let keptRefs = Set(places.map(\.ref))
        var byDay: [Int: [Visit]] = [:]
        for (index, stop) in eligible.enumerated() {
            let ref = "p\(index)"
            let day = dayIndex(stop.day)
            guard keptRefs.contains(ref), (0..<dayCount).contains(day), byDay[day, default: []].count < maxVisitsPerDay else { continue }
            let rounded = stop.startMinutes.map { max(0, min(1425, (($0 + 7) / 15) * 15)) }
            byDay[day, default: []].append(Visit(ref: ref, startMinutes: rounded, durationMinutes: max(0, min(1440, stop.durationMinutes))))
        }
        let spends = trip.expenses.filter { !$0.isTransfer }.sorted { $0.date < $1.date }.prefix(maxExpenses).map { expense in
            let index = dayIndex(expense.date)
            return Spend(day: (0..<dayCount).contains(index) ? index : nil, category: expense.category.rawValue,
                         amount: expense.amount, originalAmount: expense.originalAmount,
                         originalCurrency: expense.originalCurrency, splitCount: max(1, min(maxSplit, expense.splitAmong.count)))
        }
        let parts = calendar.dateComponents([.year, .month], from: trip.startDate)
        return RouteReport(
            reportID: reportID, country: trip.destination.countryCode.uppercased(), city: city,
            cities: Array(cities.prefix(maxCities)), year: parts.year ?? 0, month: parts.month ?? 0,
            nights: max(0, min(maxNights, trip.nights(calendar: calendar))),
            travellers: max(1, min(maxTravellers, trip.members.count)), currency: trip.currency.uppercased(), places: places,
            days: byDay.keys.sorted().prefix(maxDays).map { Day(index: $0, stops: byDay[$0]!) },
            budget: Dictionary(trip.budget.map { ($0.category.rawValue, $0.limit) }, uniquingKeysWith: max),
            expenses: Array(spends))
    }
}

/// Gönderilemeyen rapor her ön plana gelişte yeniden denenir; denemeler arası en az 15 dk.
public enum RouteReportRetry {
    public static let minimumGap: TimeInterval = 15 * 60

    public static func shouldAttempt(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minimumGap
    }

    /// Sunucu veriyi kalıcı olarak reddetti; yeniden denenmez.
    public static func isFinal(status: Int) -> Bool {
        [400, 409, 413].contains(status)
    }
}
