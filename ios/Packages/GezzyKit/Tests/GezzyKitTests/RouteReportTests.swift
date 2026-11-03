import XCTest
@testable import GezzyKit

final class RouteReportTests: XCTestCase {
    let cal = TestCalendar.calendar
    let me = UUID(), other = UUID()
    let now = TestCalendar.date(2026, 11, 30)

    func trip() -> Trip {
        let d1 = TestCalendar.date(2026, 11, 19), d2 = TestCalendar.date(2026, 11, 20)
        var trip = Trip(name: "Kopenhag · Ayşe'nin doğum günü", destination: Destination(countryCode: "dk", city: "Kopenhag"),
                        startDate: d1, endDate: TestCalendar.date(2026, 11, 23), currency: "DKK",
                        members: [Member(id: me, name: "Ömer", role: .owner), Member(id: other, name: "Ayşe")])
        trip.stops = [
            Stop(day: d1, order: 1, name: "Strøget", kind: .sight, startMinutes: 607, durationMinutes: 60,
                 coordinate: .init(latitude: 55.678612, longitude: 12.574712), note: "Kapı kodu 4512"),
            Stop(day: d1, order: 0, name: "Nyhavn", kind: .sight, durationMinutes: 45,
                 coordinate: .init(latitude: 55.6798, longitude: 12.5907), note: "Meydan"),
            Stop(day: d1, order: 2, name: "Hotel SP34", kind: .stay, coordinate: .init(latitude: 55.6787, longitude: 12.5685)),
            Stop(day: d2, order: 0, name: "Tivoli", kind: .activity, startMinutes: 1088, durationMinutes: 150,
                 coordinate: .init(latitude: 55.6737, longitude: 12.5681)),
        ]
        trip.budget = [BudgetLine(category: .food, limit: 450_000)]
        trip.expenses = [
            Expense(title: "Ayşe'ye hediye", amount: 62_000, category: .food, paidBy: other, splitAmong: [me, other],
                    date: TestCalendar.date(2026, 11, 20), originalAmount: 8_300, originalCurrency: "EUR"),
            Expense(title: "Hesaplaşma", amount: 10_000, category: .other, paidBy: me, splitAmong: [other],
                    date: TestCalendar.date(2026, 11, 21), isTransfer: true),
            Expense(title: "Ön ödeme", amount: 5_000, category: .stays, paidBy: me, splitAmong: [me],
                    date: TestCalendar.date(2026, 10, 1)),
        ]
        return trip
    }

    func make(_ t: Trip? = nil, me id: UUID? = nil, now n: Date? = nil) -> RouteReport? {
        RouteReport.make(trip: t ?? trip(), me: id ?? me, reportID: "R1", now: n ?? now, calendar: cal)
    }

    func testSummaryFields() throws {
        let r = try XCTUnwrap(make())
        XCTAssertEqual(r.reportID, "R1")
        XCTAssertEqual(r.country, "DK")
        XCTAssertEqual(r.city, "Kopenhag")
        XCTAssertEqual(r.cities, ["Kopenhag"])
        XCTAssertEqual(r.year, 2026)
        XCTAssertEqual(r.month, 11)
        XCTAssertEqual(r.nights, 4)
        XCTAssertEqual(r.travellers, 2)
        XCTAssertEqual(r.currency, "DKK")
        XCTAssertEqual(r.budget, ["food": 450_000])
    }

    func testDaysKeepOrderRoundTimesAndSkipStays() throws {
        let r = try XCTUnwrap(make())
        XCTAssertEqual(r.places.map(\.name), ["Nyhavn", "Strøget", "Tivoli"])
        XCTAssertEqual(r.days.map(\.index), [0, 1])
        XCTAssertEqual(r.days[0].stops.map(\.ref), ["p0", "p1"])
        XCTAssertEqual(r.days[0].stops[1].startMinutes, 600)   // 607 → 600
        XCTAssertNil(r.days[0].stops[0].startMinutes)
        XCTAssertEqual(r.days[1].stops[0].startMinutes, 1095)  // 1088 → 1095
        XCTAssertEqual(r.days[1].stops[0].durationMinutes, 150)
        XCTAssertEqual(r.places[1].lat, 55.67861)
    }

    func testExpensesWithoutTitlesPayersOrTransfers() throws {
        let r = try XCTUnwrap(make())
        XCTAssertEqual(r.expenses.count, 2)
        // Tarihe göre sıralı: önce seyahat öncesi ön ödeme.
        XCTAssertNil(r.expenses[0].day) // seyahat dışı tarih
        XCTAssertEqual(r.expenses[0].category, "stays")
        XCTAssertEqual(r.expenses[1], .init(day: 1, category: "food", amount: 62_000, originalAmount: 8_300,
                                            originalCurrency: "EUR", splitCount: 2))
    }

    func testNoPersonalTextLeaks() throws {
        let json = String(data: try JSONEncoder().encode(try XCTUnwrap(make())), encoding: .utf8)!
        for secret in ["Ayşe", "Ömer", "doğum günü", "4512", "hediye", "Hesaplaşma", "Hotel SP34", "2026-11-19"] {
            XCTAssertFalse(json.contains(secret), secret)
        }
        XCTAssertTrue(json.contains("Meydan")) // bilinen tür etiketi kalır
    }

    func testOnlyOwnerSends() {
        XCTAssertNil(make(me: other))
        var solo = trip(); solo.members = []
        XCTAssertNotNil(make(solo, me: other))
    }

    func testNotBeforeTripEndsAndNeedsTwoPlaces() {
        XCTAssertNil(make(now: TestCalendar.date(2026, 11, 23)))
        var few = trip(); few.stops = [few.stops[0]]
        XCTAssertNil(make(few))
    }

    func testContributionHasNoVotes() throws {
        let c = try XCTUnwrap(RouteReport.contribution(trip: trip(), calendar: cal))
        XCTAssertTrue(c.places.allSatisfy { $0.liked == 0 && !$0.verified })
    }

    func testRetryGap() {
        XCTAssertTrue(RouteReportRetry.shouldAttempt(lastAttempt: nil, now: now))
        XCTAssertFalse(RouteReportRetry.shouldAttempt(lastAttempt: now.addingTimeInterval(-14 * 60), now: now))
        XCTAssertTrue(RouteReportRetry.shouldAttempt(lastAttempt: now.addingTimeInterval(-15 * 60), now: now))
        XCTAssertTrue(RouteReportRetry.isFinal(status: 400))
        XCTAssertTrue(RouteReportRetry.isFinal(status: 409))
        XCTAssertFalse(RouteReportRetry.isFinal(status: 429))
        XCTAssertFalse(RouteReportRetry.isFinal(status: 500))
    }

    func testStopsOutsideTripAreSkipped() throws {
        var t = trip()
        t.stops.append(Stop(day: TestCalendar.date(2026, 11, 10), order: 0, name: "Erken", kind: .sight,
                            coordinate: .init(latitude: 55.7, longitude: 12.5)))
        let r = try XCTUnwrap(make(t))
        XCTAssertEqual(r.days.map(\.index), [0, 1])
        XCTAssertEqual(r.days.flatMap(\.stops).count, 3)
    }

    func testVisitsPerDayCapped() throws {
        var t = trip()
        let d = TestCalendar.date(2026, 11, 21)
        for i in 0..<31 {
            t.stops.append(Stop(day: d, order: i, name: "Yer \(i)", kind: .sight,
                                coordinate: .init(latitude: 55.6 + Double(i) / 1000, longitude: 12.5)))
        }
        let r = try XCTUnwrap(make(t))
        XCTAssertEqual(r.days.first { $0.index == 2 }?.stops.count, 30)
    }

    func testDraftTripsAreNotReported() {
        var draft = trip(); draft.status = .draft
        XCTAssertNil(make(draft))
        XCTAssertFalse(RouteReport.willSend(trip: draft, me: me, now: now, calendar: cal))
        XCTAssertTrue(RouteReport.willSend(trip: trip(), me: me, now: now, calendar: cal))
    }

    /// Uzun seyahat: 3 günde 30'ar durak → 90 yer, 87 geçiş; katkı sunucu sınırına kırpılır, rapor kırpılmaz.
    func longTrip() -> Trip {
        var t = trip()
        t.endDate = TestCalendar.date(2026, 11, 25)
        for day in 0..<3 {
            let d = TestCalendar.date(2026, 11, 21 + day)
            for i in 0..<30 {
                t.stops.append(Stop(day: d, order: i, name: "Yer \(day)-\(i)", kind: .sight,
                                    coordinate: .init(latitude: 55.6 + Double(day * 30 + i) / 1000, longitude: 12.5)))
            }
        }
        return t
    }

    func testContributionCappedToServerLimits() throws {
        let c = try XCTUnwrap(RouteReport.contribution(trip: longTrip(), calendar: cal))
        XCTAssertEqual(c.places.count, 60)
        XCTAssertLessThanOrEqual(c.transitions.count, 60)
        let refs = Set(c.places.map(\.ref))
        XCTAssertTrue(c.transitions.allSatisfy { $0.allSatisfy(refs.contains) })
        // Kota maliyeti (yer + geçiş) günlük 300'ün altında.
        XCTAssertLessThanOrEqual(c.places.count + c.transitions.count, 300)
        let r = try XCTUnwrap(make(longTrip()))
        XCTAssertEqual(r.places.count, 93)
    }

    func testShortTripContributionUntouched() throws {
        let c = try XCTUnwrap(RouteReport.contribution(trip: trip(), calendar: cal))
        XCTAssertEqual(c.places.count, 3)
        XCTAssertEqual(c.transitions, [["p0", "p1"]])
    }

    func testClampsToServerRanges() throws {
        var t = trip()
        t.endDate = TestCalendar.date(2027, 3, 30) // 131 gece
        t.members = [Member(id: me, name: "Ömer", role: .owner)] + (0..<40).map { Member(id: UUID(), name: "Kişi \($0)") }
        t.expenses = [Expense(title: "Akşam", amount: 1_000, category: .food, paidBy: me,
                              splitAmong: t.members.map(\.id), date: TestCalendar.date(2026, 11, 20))]
        let r = try XCTUnwrap(make(t, now: TestCalendar.date(2027, 4, 5)))
        XCTAssertEqual(r.nights, 90)
        XCTAssertEqual(r.travellers, 30)
        XCTAssertEqual(r.expenses.first?.splitCount, 30)
    }

    func testImplausiblePlaceNamesDropped() throws {
        var t = trip()
        let d = TestCalendar.date(2026, 11, 21)
        t.stops += [
            Stop(day: d, order: 0, name: "Ali'nin evi 0532 123 45 67", kind: .sight, coordinate: .init(latitude: 55.61, longitude: 12.5)),
            Stop(day: d, order: 1, name: "🍕", kind: .food, coordinate: .init(latitude: 55.62, longitude: 12.5)),
            Stop(day: d, order: 2, name: "Kastellet", kind: .sight, coordinate: .init(latitude: 55.69, longitude: 12.59)),
            Stop(day: d, order: 3, name: "insta @yer", kind: .sight, coordinate: .init(latitude: 55.63, longitude: 12.5)),
        ]
        let r = try XCTUnwrap(make(t))
        XCTAssertEqual(r.places.map(\.name), ["Nyhavn", "Strøget", "Tivoli", "Kastellet"])
        let refs = Set(r.places.map(\.ref))
        XCTAssertTrue(r.days.flatMap(\.stops).allSatisfy { refs.contains($0.ref) })
        XCTAssertEqual(r.days.first { $0.index == 2 }?.stops.map(\.ref), ["p3"])
        let c = try XCTUnwrap(RouteReport.contribution(trip: t, calendar: cal))
        XCTAssertEqual(c.places.map(\.name), ["Nyhavn", "Strøget", "Tivoli", "Kastellet"])
    }

    func testPlaceNameMirrorsServerRule() {
        for ok in ["Nyhavn", "Ayasofya", "Café 1900", "東京タワー", "  Tivoli  "] { XCTAssertTrue(PlaceName.isPlausible(ok), ok) }
        for bad in ["A", "🍕🍕", "12345", "www.yer", "yer.com", "a@b", "t.me/x", "Tel 0532 123 4567", "Yeeeeeeer",
                    String(repeating: "ab", count: 41)] {
            XCTAssertFalse(PlaceName.isPlausible(bad), bad)
        }
    }

    func testImplausibleCityIsNotReported() throws {
        var t = trip()
        t.destination = Destination(countryCode: "dk", city: "🏙️")
        XCTAssertNil(make(t))
    }
}
