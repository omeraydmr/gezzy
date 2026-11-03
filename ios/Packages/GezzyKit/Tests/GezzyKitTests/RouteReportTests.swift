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
}
