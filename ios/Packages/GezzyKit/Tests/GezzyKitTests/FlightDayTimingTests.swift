import XCTest
@testable import GezzyKit

final class FlightDayTimingTests: XCTestCase {
    func lisbon(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func flight(_ from: String, _ to: String, departure: Date, arrival: Date) -> FlightSegment {
        FlightSegment(flightNumber: "X1", fromCode: from, fromCity: from, toCode: to, toCity: to,
                      departure: departure, arrival: arrival)
    }

    let hotel = Coordinate(latitude: 38.7139, longitude: -9.1394)

    func testKinds() {
        XCTAssertEqual(FlightDayTiming.kind(flight("LIS", "OPO", departure: lisbon(20, 8), arrival: lisbon(20, 9))), .domestic)
        XCTAssertEqual(FlightDayTiming.kind(flight("LIS", "MAD", departure: lisbon(20, 8), arrival: lisbon(20, 10))), .schengen)
        XCTAssertEqual(FlightDayTiming.kind(flight("IST", "LIS", departure: lisbon(20, 7), arrival: lisbon(20, 11))), .international)
    }

    func testEESOnlyForNonEUCrossingSchengenBorder() {
        let entry = flight("IST", "LIS", departure: lisbon(20, 7), arrival: lisbon(20, 11))
        XCTAssertTrue(FlightDayTiming.requiresEES(entry, nationality: "TR"))
        XCTAssertFalse(FlightDayTiming.requiresEES(entry, nationality: "DE"))
        XCTAssertFalse(FlightDayTiming.requiresEES(entry, nationality: "IE"))
        XCTAssertFalse(FlightDayTiming.requiresEES(flight("LIS", "MAD", departure: lisbon(20, 8), arrival: lisbon(20, 10)),
                                                    nationality: "TR"))
    }

    func testTransferEstimateRoundsUpToFive() {
        // ~5,56 km kuzeye: 20 + 11,1 = 31,1 → 35.
        let north = Coordinate(latitude: hotel.latitude + 0.05, longitude: hotel.longitude)
        XCTAssertEqual(FlightDayTiming.transferMinutes(hotel, north), 35)
        XCTAssertEqual(FlightDayTiming.transferMinutes(hotel, hotel), 20)
    }

    func testArrivalReadyTimeWithEES() throws {
        let landing = flight("IST", "LIS", departure: lisbon(20, 7), arrival: lisbon(20, 11, 20))
        let lis = try XCTUnwrap(Airports.airport("LIS")?.coordinate)
        let arrival = try XCTUnwrap(FlightDayTiming.arrival(landing, firstPoint: hotel, nationality: "TR"))
        let transfer = FlightDayTiming.transferMinutes(lis, hotel)
        XCTAssertEqual(arrival.landing, 11 * 60 + 20)
        XCTAssertEqual(arrival.exit, 90)
        XCTAssertTrue(arrival.ees)
        XCTAssertEqual(arrival.transfer, transfer)
        XCTAssertEqual(arrival.readyAt, 11 * 60 + 20 + 90 + transfer)
    }

    func testArrivalWithoutPointHasNoTransfer() throws {
        let landing = flight("LIS", "OPO", departure: lisbon(20, 8), arrival: lisbon(20, 9))
        let arrival = try XCTUnwrap(FlightDayTiming.arrival(landing, firstPoint: nil, nationality: "TR"))
        XCTAssertEqual(arrival.exit, 30)
        XCTAssertNil(arrival.transfer)
        XCTAssertEqual(arrival.readyAt, 9 * 60 + 30)
        XCTAssertFalse(arrival.ees)
    }

    func testDepartureLeaveByAndEarlyFlight() throws {
        let home = flight("LIS", "IST", departure: lisbon(23, 9, 40), arrival: lisbon(23, 13))
        let lis = try XCTUnwrap(Airports.airport("LIS")?.coordinate)
        let departure = try XCTUnwrap(FlightDayTiming.departure(home, lastPoint: hotel, nationality: "TR"))
        let transfer = FlightDayTiming.transferMinutes(hotel, lis)
        XCTAssertEqual(departure.takeoff, 9 * 60 + 40)
        XCTAssertEqual(departure.beAtAirport, 6 * 60 + 40)
        XCTAssertEqual(departure.leaveBy, 6 * 60 + 40 - transfer)
        XCTAssertTrue(departure.ees)

        let short = flight("LIS", "MAD", departure: lisbon(23, 7), arrival: lisbon(23, 9))
        let early = try XCTUnwrap(FlightDayTiming.departure(short, lastPoint: nil, nationality: "TR"))
        XCTAssertEqual(early.beAtAirport, 5 * 60)
        XCTAssertEqual(early.leaveBy, 5 * 60)
    }

    func testStopWarnings() throws {
        let landing = flight("IST", "LIS", departure: lisbon(20, 7), arrival: lisbon(20, 11, 20))
        let arrival = try XCTUnwrap(FlightDayTiming.arrival(landing, firstPoint: nil, nationality: "TR"))
        XCTAssertEqual(FlightDayTiming.warning(start: 12 * 60, duration: 60, arrival: arrival, departure: nil),
                       .beforeReady(arrival.readyAt))
        XCTAssertNil(FlightDayTiming.warning(start: 14 * 60, duration: 60, arrival: arrival, departure: nil))

        let home = flight("LIS", "IST", departure: lisbon(23, 18), arrival: lisbon(23, 22))
        let departure = try XCTUnwrap(FlightDayTiming.departure(home, lastPoint: nil, nationality: "TR"))
        // 18:00 kalkış, dış hat: 15:00'te havalimanında; aktarma noktası yok → 15:00'te çık.
        XCTAssertEqual(FlightDayTiming.warning(start: 14 * 60 + 30, duration: 60, arrival: nil, departure: departure),
                       .afterLeave(departure.leaveBy))
        XCTAssertNil(FlightDayTiming.warning(start: 14 * 60, duration: 60, arrival: nil, departure: departure), "Tam sınırda biten durak sorun değil")
        XCTAssertNil(FlightDayTiming.warning(start: 10 * 60, duration: 60, arrival: nil, departure: departure))
    }
}
