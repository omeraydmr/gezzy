import XCTest
@testable import GezzyKit

final class RouteEndAnchorTests: XCTestCase {
    let start = Coordinate(latitude: 0, longitude: 0)
    let a = Coordinate(latitude: 0.005, longitude: 0)
    let b = Coordinate(latitude: 0, longitude: 0.01)
    let end = Coordinate(latitude: 0.012, longitude: 0)

    func testEndAnchorChangesOrder() {
        XCTAssertEqual(RouteOptimizer.order([a, b], from: start), [0, 1])
        XCTAssertEqual(RouteOptimizer.order([a, b], from: start, to: end), [1, 0], "Bitişe yakın A sona kalır")
        XCTAssertEqual(RouteOptimizer.order([a, b], from: start, to: nil), [0, 1])
    }

    func testVisitOrderUsesEnd() {
        let visits = [RouteOptimizer.Visit(coordinate: a, duration: 30), RouteOptimizer.Visit(coordinate: b, duration: 30)]
        XCTAssertEqual(RouteOptimizer.order(visits, from: start, dayStart: 540), [0, 1])
        XCTAssertEqual(RouteOptimizer.order(visits, from: start, to: end, dayStart: 540), [1, 0])
    }

    func testPlannerWalkIncludesReturnToHotel() throws {
        let cal = TestCalendar.calendar
        let hotel = Coordinate(latitude: 38.7139, longitude: -9.1394)
        let sight = Coordinate(latitude: 38.7239, longitude: -9.1394)
        // Tek günlük seyahat: fikir mutlaka 20 Ekim'e yerleşir; otel o gece de geçerli.
        var trip = Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
                        startDate: TestCalendar.date(2026, 10, 20), endDate: TestCalendar.date(2026, 10, 20))
        trip.lodgings = [Lodging(name: "Otel", coordinate: hotel, checkIn: TestCalendar.date(2026, 10, 20, 15),
                                 checkOut: TestCalendar.date(2026, 10, 21, 11))]
        trip.ideas = [Stop(day: TestCalendar.date(2026, 10, 20), order: 0, name: "Bakış", kind: .sight,
                           durationMinutes: 60, coordinate: sight)]
        let plan = ItineraryPlanner.plan(trip, calendar: cal)
        let day = try XCTUnwrap(plan.days.first { !$0.order.isEmpty })
        XCTAssertEqual(day.walkingMeters, 2 * Geo.distance(hotel, sight), accuracy: 1)
    }
}
