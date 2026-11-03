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

    /// Topluluk havuzu için oysuz katkı.
    public static func contribution(trip: Trip, calendar: Calendar = .current) -> CommunityPlaces.Contribution? {
        CommunityPlaces.contribution(for: trip, ratings: [:], verified: [], calendar: calendar)
    }

    public static func make(trip: Trip, me: UUID, reportID: String, now: Date = Date(),
                            calendar: Calendar = .current) -> RouteReport? {
        guard CommunityPlaces.canContribute(trip, now: now, calendar: calendar), isSender(trip, me: me),
              let contribution = contribution(trip: trip, calendar: calendar) else { return nil }
        // Katkıdaki ref'ler uygun durakların sırasıyla eşleşir ("p0", "p1"…).
        let eligible = CommunityPlaces.eligibleStops(in: trip)
        let start = calendar.startOfDay(for: trip.startDate)
        func dayIndex(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        }
        let dayCount = trip.days(calendar: calendar).count
        let places = Array(contribution.places.prefix(maxPlaces))
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
                         originalCurrency: expense.originalCurrency, splitCount: max(1, expense.splitAmong.count))
        }
        let parts = calendar.dateComponents([.year, .month], from: trip.startDate)
        let cities = trip.isMultiCity ? trip.cityLegs.map(\.destination.city) : [trip.destination.city]
        return RouteReport(
            reportID: reportID, country: trip.destination.countryCode.uppercased(), city: cities.first ?? trip.destination.city,
            cities: cities, year: parts.year ?? 0, month: parts.month ?? 0, nights: trip.nights(calendar: calendar),
            travellers: max(1, trip.members.count), currency: trip.currency.uppercased(), places: places,
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
