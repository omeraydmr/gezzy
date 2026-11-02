import XCTest
@testable import GezzyKit

final class DayAnchorsTests: XCTestCase {
    let cal = TestCalendar.calendar
    let hotelA = Coordinate(latitude: 38.7139, longitude: -9.1394)
    let hotelB = Coordinate(latitude: 38.7069, longitude: -9.1356)

    /// Lizbon, 20–23 Ekim 2026 (4 gün, 3 gece).
    func trip() -> Trip {
        Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"),
             startDate: TestCalendar.date(2026, 10, 20), endDate: TestCalendar.date(2026, 10, 23))
    }

    func lodging(_ name: String, _ c: Coordinate, from: Int, to: Int) -> Lodging {
        Lodging(name: name, coordinate: c, checkIn: TestCalendar.date(2026, 10, from, 15),
                checkOut: TestCalendar.date(2026, 10, to, 11))
    }

    /// Lizbon saatiyle verilen tarihte uçuş.
    func lisbon(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        return c.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func flight(_ from: String, _ to: String, departure: Date, arrival: Date) -> FlightSegment {
        FlightSegment(flightNumber: "TK1755", fromCode: from, fromCity: from, toCode: to, toCity: to,
                      departure: departure, arrival: arrival, departureTimeZone: from == "LIS" ? "Europe/Lisbon" : "Europe/Istanbul",
                      arrivalTimeZone: to == "LIS" ? "Europe/Lisbon" : "Europe/Istanbul")
    }

    func testNightLodgingCoversCheckInUntilCheckOutDay() {
        var value = trip()
        value.lodgings = [lodging("A", hotelA, from: 20, to: 22), lodging("B", hotelB, from: 22, to: 23)]
        XCTAssertEqual(value.lodging(forNightOf: TestCalendar.date(2026, 10, 20), calendar: cal)?.name, "A")
        XCTAssertEqual(value.lodging(forNightOf: TestCalendar.date(2026, 10, 21), calendar: cal)?.name, "A")
        XCTAssertEqual(value.lodging(forNightOf: TestCalendar.date(2026, 10, 22), calendar: cal)?.name, "B")
        XCTAssertNil(value.lodging(forNightOf: TestCalendar.date(2026, 10, 23), calendar: cal), "Son gün gecesi yok")
    }

    func testNormalDayStartsAndEndsAtSameHotel() {
        var value = trip()
        value.lodgings = [lodging("A", hotelA, from: 20, to: 23)]
        let anchors = value.anchors(on: TestCalendar.date(2026, 10, 21), calendar: cal)
        XCTAssertEqual(anchors.start?.name, "A")
        XCTAssertEqual(anchors.end?.name, "A")
    }

    func testHotelChangeDayEndsAtNewHotel() {
        var value = trip()
        value.lodgings = [lodging("A", hotelA, from: 20, to: 22), lodging("B", hotelB, from: 22, to: 23)]
        let anchors = value.anchors(on: TestCalendar.date(2026, 10, 22), calendar: cal)
        XCTAssertEqual(anchors.start?.name, "A")
        XCTAssertEqual(anchors.end?.name, "B")
    }

    func testArrivalDayStartsAtAirportAndDepartureDayEndsAtAirport() throws {
        var value = trip()
        value.lodgings = [lodging("A", hotelA, from: 20, to: 23)]
        value.flights = [flight("IST", "LIS", departure: lisbon(20, 7), arrival: lisbon(20, 11, 20)),
                         flight("LIS", "IST", departure: lisbon(23, 9, 40), arrival: lisbon(23, 13))]
        let first = value.anchors(on: TestCalendar.date(2026, 10, 20), calendar: cal)
        guard case .airport(let arrival, _)? = first.start else { return XCTFail("İlk gün havalimanından başlamalı") }
        XCTAssertEqual(arrival.code, "LIS")
        XCTAssertEqual(first.end?.name, "A")
        let last = value.anchors(on: TestCalendar.date(2026, 10, 23), calendar: cal)
        XCTAssertEqual(last.start?.name, "A")
        guard case .airport(let departure, _)? = last.end else { return XCTFail("Son gün havalimanında bitmeli") }
        XCTAssertEqual(departure.code, "LIS")
    }

    func testDomesticCityChangeFlightIsNotADepartureAnchor() {
        var value = trip()
        value.lodgings = [lodging("A", hotelA, from: 20, to: 23)]
        // LIS → OPO aynı ülke: ayrılış değil.
        value.flights = [FlightSegment(flightNumber: "TP1940", fromCode: "LIS", fromCity: "Lizbon", toCode: "OPO", toCity: "Porto",
                                       departure: lisbon(21, 8), arrival: lisbon(21, 9), departureTimeZone: "Europe/Lisbon",
                                       arrivalTimeZone: "Europe/Lisbon")]
        let anchors = value.anchors(on: TestCalendar.date(2026, 10, 21), calendar: cal)
        XCTAssertNil(value.departureFlight(on: TestCalendar.date(2026, 10, 21), calendar: cal))
        guard case .airport(let airport, _)? = anchors.start else { return XCTFail("Varılan havalimanından başlamalı") }
        XCTAssertEqual(airport.code, "OPO")
        XCTAssertEqual(anchors.end?.name, "A")
    }

    func testUnknownAirportFallsBackToLodging() {
        var value = trip()
        value.lodgings = [lodging("A", hotelA, from: 20, to: 23)]
        value.flights = [flight("IST", "ZZZ", departure: lisbon(20, 7), arrival: lisbon(20, 11))]
        XCTAssertEqual(value.anchors(on: TestCalendar.date(2026, 10, 20), calendar: cal).start?.name, "A")
    }

    func testPlannedStartsUseFixedTimesAndWalkFromStart() {
        var value = trip()
        let day = TestCalendar.date(2026, 10, 21)
        value.stops = [
            Stop(day: day, order: 0, name: "Kale", kind: .sight, durationMinutes: 60, coordinate: hotelB),
            Stop(day: day, order: 1, name: "Akşam yemeği", kind: .food, startMinutes: 19 * 60, durationMinutes: 90),
        ]
        let starts = value.plannedStarts(on: day, from: hotelA, dayStart: 9 * 60, calendar: cal)
        let walk = Geo.walkingMinutes(meters: Geo.distance(hotelA, hotelB))
        XCTAssertEqual(starts[value.stops[0].id], 9 * 60 + walk)
        XCTAssertEqual(starts[value.stops[1].id], 19 * 60)
    }
}
