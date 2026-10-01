import XCTest
@testable import TravellerKit

final class FlightStatusTests: XCTestCase {
    let scheduled = TestCalendar.date(2026, 10, 3, 9) // 06:00 UTC

    func flight(gate: String? = "F7") -> FlightSegment {
        FlightSegment(flightNumber: "TK 1759", fromCode: "IST", fromCity: "İstanbul", toCode: "LIS", toCity: "Lizbon",
                      departure: scheduled, arrival: scheduled.addingTimeInterval(5 * 3600), gate: gate)
    }

    func response(status: String, gate: String?, revised: String?) -> Data {
        var departure: [String: Any] = ["scheduledTime": ["utc": "2026-10-03 06:00Z", "local": "2026-10-03 09:00+03:00"],
                                        "terminal": "1"]
        if let gate { departure["gate"] = gate }
        if let revised { departure["revisedTime"] = ["utc": revised] }
        let other: [String: Any] = ["status": "Expected",
                                    "departure": ["scheduledTime": ["utc": "2026-10-04 06:00Z"]], "arrival": [:]]
        let entry: [String: Any] = ["number": "TK 1759", "status": status, "departure": departure,
                                    "arrival": ["baggageBelt": "5"]]
        return try! JSONSerialization.data(withJSONObject: [other, entry])
    }

    func testParsesClosestFlightWithDelayAndGate() throws {
        let data = response(status: "Expected", gate: "F12", revised: "2026-10-03 06:40Z")
        let status = try XCTUnwrap(FlightStatusParser.parseAeroDataBox(data, scheduledDeparture: scheduled))
        XCTAssertEqual(status.phase, .delayed)
        XCTAssertEqual(status.departureGate, "F12")
        XCTAssertEqual(status.departureTerminal, "1")
        XCTAssertEqual(status.baggageBelt, "5")
        XCTAssertEqual(status.estimatedDeparture, scheduled.addingTimeInterval(40 * 60))

        let updated = flight().applying(status)
        XCTAssertEqual(updated.gate, "F12")
        XCTAssertEqual(updated.delayMinutes, 40)
        XCTAssertEqual(updated.statusText, "Rötarlı +40 dk")
        XCTAssertEqual(updated.effectiveDeparture, scheduled.addingTimeInterval(40 * 60))
    }

    func testSmallDelayIsOnTime() throws {
        let data = response(status: "Expected", gate: nil, revised: "2026-10-03 06:10Z")
        let status = try XCTUnwrap(FlightStatusParser.parseAeroDataBox(data, scheduledDeparture: scheduled))
        XCTAssertEqual(status.phase, .scheduled)
        let updated = flight().applying(status)
        XCTAssertEqual(updated.gate, "F7")
        XCTAssertFalse(updated.isDelayed)
        XCTAssertEqual(updated.effectiveDeparture, scheduled)
        XCTAssertEqual(updated.statusText, "Zamanında")
    }

    func testDescribesGateChangeDelayAndBoarding() {
        let old = flight()
        let delayed = old.applying(FlightLiveStatus(phase: .delayed, departureGate: "F12",
                                                    estimatedDeparture: scheduled.addingTimeInterval(40 * 60)))
        let lines = FlightStatusChange.describe(old: old, new: delayed) { _ in "09:40" }
        XCTAssertEqual(lines, ["Kapı değişti: F7 → F12", "Rötar: kalkış 09:40 (+40 dk)"])

        // Aynı durum tekrar gelirse sessiz kalır.
        XCTAssertEqual(FlightStatusChange.describe(old: delayed, new: delayed) { _ in "09:40" }, [])

        let boarding = delayed.applying(FlightLiveStatus(phase: .boarding, departureGate: "F12",
                                                         estimatedDeparture: scheduled.addingTimeInterval(40 * 60)))
        XCTAssertEqual(FlightStatusChange.describe(old: delayed, new: boarding) { _ in "" }, ["Biniş başladı · Kapı F12"])

        let canceled = delayed.applying(FlightLiveStatus(phase: .canceled))
        XCTAssertEqual(FlightStatusChange.describe(old: delayed, new: canceled) { _ in "" }.count, 1)
    }

    func testFirstGateAssignment() {
        let old = flight(gate: nil)
        let new = old.applying(FlightLiveStatus(phase: .scheduled, departureGate: "B3"))
        XCTAssertEqual(FlightStatusChange.describe(old: old, new: new) { _ in "" }, ["Kapı belli oldu: B3"])
    }

    func testPhaseMappingAndNumber() {
        XCTAssertEqual(FlightStatusParser.phase(from: "EnRoute"), .enRoute)
        XCTAssertEqual(FlightStatusParser.phase(from: "GateClosed"), .gateClosed)
        XCTAssertEqual(FlightStatusParser.phase(from: nil), .unknown)
        XCTAssertEqual(FlightStatusParser.normalizedNumber("tk 1759"), "TK1759")
    }

    func testOldRecordsDecodeWithoutLiveStatus() throws {
        let json = """
        {"id":"\(UUID().uuidString)","flightNumber":"TK1","fromCode":"IST","fromCity":"İstanbul","toCode":"LIS",
         "toCity":"Lizbon","departure":0,"arrival":3600}
        """
        let decoded = try JSONDecoder().decode(FlightSegment.self, from: Data(json.utf8))
        XCTAssertNil(decoded.live)
        XCTAssertNil(decoded.statusText)
    }
}
