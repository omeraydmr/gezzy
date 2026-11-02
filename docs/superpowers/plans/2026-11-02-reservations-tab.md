# Rezervasyon sekmesi ve uçuş günleri — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move flights and lodging to a new "Rezervasyon" tab with a single add path per card, and make each day start/end at the right lodging or airport with realistic flight-day timing and warnings.

**Architecture:** Pure logic in GezzyKit — `lodging(forNightOf:)` and day anchors (`DayAnchors.swift`), flight-day timing (`FlightDayTiming.swift`), end-anchored route ordering (`RouteOptimizer`, `ItineraryPlanner`) — all unit-tested. The app adds a `ReservationsSection` tab and an `AddPlaceholder` component, and `PlanSection` renders anchors, airport rows, an "otele uğra" suggestion and timing warnings from those pure functions.

**Tech Stack:** Swift 5.9+, SwiftUI, MapKit (iOS 17), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-02-reservations-tab-design.md`

## Global Constraints

- iOS deployment target 17.0. No iOS 18-only API without `#available`.
- UI text Turkish, written as the localization key (`Text("…")`, `String(localized: "…")`); English values in `ios/Gezzy/Resources/Localizable.xcstrings` (keep its JSON style; validate with `python3 -c "import json;json.load(open('ios/Gezzy/Resources/Localizable.xcstrings'))"`). Interpolated keys use `%lld` for Int and `%@` for String.
- Code comments Turkish, short, like surrounding code. No new dependencies, no server changes.
- Timing constants (minutes): departureLeadInternational 180, departureLeadShort 120, arrivalExitDomestic 30, arrivalExitInternational 60, arrivalExitEES 90. Transfer estimate `20 + km × 2`, rounded up to a multiple of 5.
- Flight kind: domestic (same country), schengen (both Schengen), international (otherwise). EES applies when exactly one side is Schengen and the traveller's nationality is not in `VisaRules.schengenCountries ∪ {IE, CY}`. Nationality: `TripStore.me.passport?.nationality`, default "TR".
- Tab order: Plan · Rezervasyon · Bütçe · Valiz · Vize · Ekip · Anılar. Rezervasyon icon `suitcase.rolling.fill`.
- After adding/removing files: `cd ios && xcodegen generate`.
- Unit tests: `cd ios/Packages/GezzyKit && swift test --filter <Name>`; full: `swift test`.
- App build: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build` → "BUILD SUCCEEDED" (don't use `-quiet`; it prints a spurious error line in this project).
- Commits: imperative English subject + the attribution trailer your harness requires.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `ios/Packages/GezzyKit/Sources/GezzyKit/DayAnchors.swift` | Create | `lodging(forNightOf:)`, flight-on-day lookups, `DayAnchor`, `anchors(on:)`, `plannedStarts(on:…)` |
| `ios/Packages/GezzyKit/Sources/GezzyKit/FlightDayTiming.swift` | Create | Flight kind, EES, constants, transfer estimate, arrival/departure timing, stop warnings |
| `ios/Packages/GezzyKit/Sources/GezzyKit/Geo.swift` | Modify | `RouteOptimizer` end anchor |
| `ios/Packages/GezzyKit/Sources/GezzyKit/ItineraryPlanner.swift` | Modify | Bucket end anchor |
| `ios/Packages/GezzyKit/Tests/GezzyKitTests/DayAnchorsTests.swift` | Create | |
| `ios/Packages/GezzyKit/Tests/GezzyKitTests/FlightDayTimingTests.swift` | Create | |
| `ios/Packages/GezzyKit/Tests/GezzyKitTests/RouteEndAnchorTests.swift` | Create | Optimizer + planner end anchor |
| `ios/Gezzy/DesignSystem/AddPlaceholder.swift` | Create | Dashed "＋ X ekle" menu row |
| `ios/Gezzy/Features/Plan/ReservationsSection.swift` | Create | Tab content: FlightsCard + LodgingCard |
| `ios/Gezzy/Features/Plan/FlightViews.swift`, `LodgingViews.swift` | Modify | Prominent "+", placeholder when empty |
| `ios/Gezzy/Features/TripDetail/TripDetailView.swift` | Modify | New tab, `openReservations` environment action |
| `ios/Gezzy/Features/Plan/DayAnchorRows.swift` | Create | Start/end rows (lodging, airport), hotel suggestion row, timing notes |
| `ios/Gezzy/Features/Plan/PlanSection.swift` | Modify | Remove cards; anchors in list/map/totals/optimize; warnings |

---

### Task 1: Day anchors (GezzyKit)

**Files:**
- Create: `ios/Packages/GezzyKit/Sources/GezzyKit/DayAnchors.swift`
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/DayAnchorsTests.swift`

**Interfaces:**
- Consumes: `Trip.lodgingList`, `Trip.lodging(forMorningOf:calendar:)`, `Trip.destination(on:calendar:)`, `Trip.flights`, `FlightSegment` (`fromCode`, `toCode`, `departure`, `arrival`, `departureTimeZone`, `arrivalTimeZone`), `Airports.airport(_:)`.
- Produces:
  - `Trip.lodging(forNightOf day: Date, calendar: Calendar = .current) -> Lodging?`
  - `Trip.arrivalFlight(on:calendar:) -> FlightSegment?`, `Trip.departureFlight(on:calendar:) -> FlightSegment?`
  - `enum DayAnchor: Hashable, Sendable { case lodging(Lodging); case airport(Airports.Airport, flight: FlightSegment) }` with `coordinate: Coordinate?`, `name: String`
  - `Trip.anchors(on:calendar:) -> (start: DayAnchor?, end: DayAnchor?)`
  - `FlightSegment.localDayAndMinutes(_ date: Date, timeZone: String?, fallback: TimeZone) -> (year: Int, month: Int, day: Int, minutes: Int)` (internal helper is fine; public for app use: `public func arrivalMinutes(fallback:)`, `departureMinutes(fallback:)`)

- [ ] **Step 1: Write the failing tests**

Create `DayAnchorsTests.swift`:

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/GezzyKit && swift test --filter DayAnchorsTests`
Expected: build FAIL — `value of type 'Trip' has no member 'lodging(forNightOf:calendar:)'` (and the other new members).

- [ ] **Step 3: Implement `DayAnchors.swift`**

```swift
import Foundation

/// Günün başlangıç ve bitiş noktası: o sabahın/gecenin konaklaması ya da o gün inilen/kalkılan havalimanı.
public enum DayAnchor: Hashable, Sendable {
    case lodging(Lodging)
    case airport(Airports.Airport, flight: FlightSegment)

    public var coordinate: Coordinate? {
        switch self {
        case .lodging(let lodging): lodging.coordinate
        case .airport(let airport, _): airport.coordinate
        }
    }

    public var name: String {
        switch self {
        case .lodging(let lodging): lodging.name
        case .airport(let airport, _): airport.code
        }
    }
}

extension FlightSegment {
    /// Tarihin verilen saat dilimindeki günü ve gün başından dakikası.
    static func local(_ date: Date, timeZone: String?, airportCode: String, fallback: TimeZone)
        -> (year: Int, month: Int, day: Int, minutes: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:))
            ?? Airports.airport(airportCode).flatMap { TimeZone(identifier: $0.timeZone) } ?? fallback
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return (c.year ?? 0, c.month ?? 0, c.day ?? 0, (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// İnişin yerel günü ve dakikası.
    public func localArrival(fallback: TimeZone = .current) -> (year: Int, month: Int, day: Int, minutes: Int) {
        Self.local(arrival, timeZone: arrivalTimeZone, airportCode: toCode, fallback: fallback)
    }

    /// Kalkışın yerel günü ve dakikası.
    public func localDeparture(fallback: TimeZone = .current) -> (year: Int, month: Int, day: Int, minutes: Int) {
        Self.local(departure, timeZone: departureTimeZone, airportCode: fromCode, fallback: fallback)
    }
}

extension Trip {
    /// O gece kalınan yer: giriş günü ≤ gün < çıkış günü.
    public func lodging(forNightOf day: Date, calendar: Calendar = .current) -> Lodging? {
        let target = calendar.startOfDay(for: day)
        return lodgingList.first {
            calendar.startOfDay(for: $0.checkIn) <= target && target < calendar.startOfDay(for: $0.checkOut)
        }
    }

    private func isSameDay(_ local: (year: Int, month: Int, day: Int, minutes: Int), _ day: Date, _ calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return c.year == local.year && c.month == local.month && c.day == local.day
    }

    /// O gün bu günün ülkesine inen uçuş (yerel saatle), en son inen.
    public func arrivalFlight(on day: Date, calendar: Calendar = .current) -> FlightSegment? {
        let country = destination(on: day, calendar: calendar).countryCode.uppercased()
        return flights.filter { flight in
            Airports.airport(flight.toCode)?.countryCode.uppercased() == country
                && isSameDay(flight.localArrival(fallback: calendar.timeZone), day, calendar)
        }.max { $0.arrival < $1.arrival }
    }

    /// O gün bu günün ülkesinden çıkıp başka ülkeye giden uçuş (yerel saatle), en son kalkan.
    public func departureFlight(on day: Date, calendar: Calendar = .current) -> FlightSegment? {
        let country = destination(on: day, calendar: calendar).countryCode.uppercased()
        return flights.filter { flight in
            guard let from = Airports.airport(flight.fromCode)?.countryCode.uppercased(),
                  let to = Airports.airport(flight.toCode)?.countryCode.uppercased() else { return false }
            return from == country && to != country && isSameDay(flight.localDeparture(fallback: calendar.timeZone), day, calendar)
        }.max { $0.departure < $1.departure }
    }

    /// Günün başlangıç ve bitiş noktası (bkz. spec §3). Konumu bilinmeyen havalimanı çapa olmaz.
    public func anchors(on day: Date, calendar: Calendar = .current) -> (start: DayAnchor?, end: DayAnchor?) {
        var start: DayAnchor? = lodging(forMorningOf: day, calendar: calendar).map(DayAnchor.lodging)
        if let flight = arrivalFlight(on: day, calendar: calendar), let airport = Airports.airport(flight.toCode),
           airport.coordinate != nil {
            start = .airport(airport, flight: flight)
        }
        var end: DayAnchor? = lodging(forNightOf: day, calendar: calendar).map(DayAnchor.lodging)
        if let flight = departureFlight(on: day, calendar: calendar), let airport = Airports.airport(flight.fromCode),
           airport.coordinate != nil {
            end = .airport(airport, flight: flight)
        }
        return (start, end)
    }

    /// Günün duraklarının planlanan başlangıçları (dakika): saati verilenler o saatte, diğerleri `start`'tan
    /// yürüyerek sırayla. Konumsuz ve saatsiz duraklar sonuçta yoktur.
    public func plannedStarts(on day: Date, from start: Coordinate?, dayStart: Int,
                              calendar: Calendar = .current) -> [Stop.ID: Int] {
        let stops = self.stops(on: day, calendar: calendar)
        let weekday = OpeningHours.dayIndex(calendarWeekday: calendar.component(.weekday, from: day))
        var result: [Stop.ID: Int] = [:]
        var clock = dayStart
        var previous = start
        for stop in stops {
            if let coordinate = stop.coordinate {
                if let previous { clock += Geo.walkingMinutes(meters: Geo.distance(previous, coordinate)) }
                previous = coordinate
            }
            if let fixed = stop.startMinutes {
                clock = fixed
            } else if stop.coordinate == nil {
                continue
            } else if let open = stop.openingHours.flatMap(OpeningHours.cached)?.intervals(onDay: weekday),
                      let later = open.first(where: { $0.start > clock && $0.start + stop.durationMinutes <= $0.end }),
                      !open.contains(where: { $0.start <= clock && clock + stop.durationMinutes <= $0.end }) {
                clock = later.start
            }
            result[stop.id] = clock
            clock += stop.durationMinutes
        }
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios/Packages/GezzyKit && swift test --filter DayAnchorsTests`
Expected: 7/7 PASS. If `testArrivalDayStartsAtAirport…` fails because `Airports.airport("LIS")?.coordinate` is nil, check `airports.tsv` has LIS with a coordinate (it should); do not change expectations.

- [ ] **Step 5: Full suite and commit**

Run: `cd ios/Packages/GezzyKit && swift test` → all PASS.

```bash
git add ios/Packages/GezzyKit/Sources/GezzyKit/DayAnchors.swift ios/Packages/GezzyKit/Tests/GezzyKitTests/DayAnchorsTests.swift
git commit -m "Anchor each day at its lodging or airport"
```

---

### Task 2: Flight-day timing (GezzyKit)

**Files:**
- Create: `ios/Packages/GezzyKit/Sources/GezzyKit/FlightDayTiming.swift`
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/FlightDayTimingTests.swift`

**Interfaces:**
- Consumes: `FlightSegment.localArrival(fallback:)`, `.localDeparture(fallback:)` (Task 1), `Airports.airport(_:)`, `VisaRules.schengenCountries`, `Geo.distance`.
- Produces (`public enum FlightDayTiming`):
  - `enum Kind { case domestic, schengen, international }`; `static func kind(_ flight: FlightSegment) -> Kind`
  - `static func requiresEES(_ flight: FlightSegment, nationality: String) -> Bool`
  - constants listed in Global Constraints; `static func transferMinutes(_ a: Coordinate, _ b: Coordinate) -> Int`
  - `struct Arrival { airport: Airports.Airport; landing: Int; exit: Int; transfer: Int?; readyAt: Int; ees: Bool }`; `static func arrival(_ flight:, firstPoint: Coordinate?, nationality:, fallback: TimeZone = .current) -> Arrival?`
  - `struct Departure { airport; takeoff: Int; beAtAirport: Int; transfer: Int?; leaveBy: Int; ees: Bool }`; `static func departure(_ flight:, lastPoint: Coordinate?, nationality:, fallback:) -> Departure?`
  - `enum StopWarning: Equatable { case beforeReady(Int), afterLeave(Int) }`; `static func warning(start: Int, duration: Int, arrival: Arrival?, departure: Departure?) -> StopWarning?`

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/GezzyKit && swift test --filter FlightDayTimingTests`
Expected: build FAIL — `cannot find 'FlightDayTiming' in scope`.

- [ ] **Step 3: Implement `FlightDayTiming.swift`**

```swift
import Foundation

/// Uçuş günlerinin zamanlaması: inişten şehre hazır olma, kalkıştan önce havalimanında olma ve yola çıkma saatleri.
/// Süreler yaygın öneriler ve 2026 EES (AB giriş-çıkış sistemi) kuyruk raporlarına göre seçildi (bkz. spec).
public enum FlightDayTiming {
    public enum Kind: Equatable, Sendable { case domestic, schengen, international }

    public static let departureLeadInternational = 180
    public static let departureLeadShort = 120
    public static let arrivalExitDomestic = 30
    public static let arrivalExitInternational = 60
    public static let arrivalExitEES = 90

    /// AB ya da Schengen vatandaşları EES kaydına girmez.
    static let euOrSchengen: Set<String> = VisaRules.schengenCountries.union(["IE", "CY"])

    static func countries(_ flight: FlightSegment) -> (from: String?, to: String?) {
        (Airports.airport(flight.fromCode)?.countryCode.uppercased(), Airports.airport(flight.toCode)?.countryCode.uppercased())
    }

    public static func kind(_ flight: FlightSegment) -> Kind {
        let (from, to) = countries(flight)
        guard let from, let to else { return .international }
        if from == to { return .domestic }
        if VisaRules.schengenCountries.contains(from) && VisaRules.schengenCountries.contains(to) { return .schengen }
        return .international
    }

    /// Schengen sınırı geçiliyor ve yolcu AB/Schengen vatandaşı değil.
    public static func requiresEES(_ flight: FlightSegment, nationality: String) -> Bool {
        let (from, to) = countries(flight)
        guard let from, let to else { return false }
        let crosses = VisaRules.schengenCountries.contains(from) != VisaRules.schengenCountries.contains(to)
        return crosses && !euOrSchengen.contains(nationality.uppercased())
    }

    /// Havalimanı ile şehir arası tahmini yol süresi (dakika): 20 + km × 2, 5'in katına yukarı yuvarlanır.
    public static func transferMinutes(_ a: Coordinate, _ b: Coordinate) -> Int {
        let raw = 20 + Geo.distance(a, b) / 1000 * 2
        return Int((raw / 5).rounded(.up)) * 5
    }

    public struct Arrival: Hashable, Sendable {
        public var airport: Airports.Airport
        public var landing: Int
        public var exit: Int
        public var transfer: Int?
        public var readyAt: Int
        public var ees: Bool
    }

    public struct Departure: Hashable, Sendable {
        public var airport: Airports.Airport
        public var takeoff: Int
        public var beAtAirport: Int
        public var transfer: Int?
        public var leaveBy: Int
        public var ees: Bool
    }

    /// İniş günü: `firstPoint` günün ilk durağı ya da o gecenin oteli.
    public static func arrival(_ flight: FlightSegment, firstPoint: Coordinate?, nationality: String,
                               fallback: TimeZone = .current) -> Arrival? {
        guard let airport = Airports.airport(flight.toCode) else { return nil }
        let ees = requiresEES(flight, nationality: nationality)
        let exit: Int = ees ? arrivalExitEES : (kind(flight) == .international ? arrivalExitInternational : arrivalExitDomestic)
        let transfer = zip2(airport.coordinate, firstPoint).map { transferMinutes($0, $1) }
        let landing = flight.localArrival(fallback: fallback).minutes
        return Arrival(airport: airport, landing: landing, exit: exit, transfer: transfer,
                       readyAt: landing + exit + (transfer ?? 0), ees: ees)
    }

    /// Kalkış günü: `lastPoint` günün son durağı ya da sabah oteli.
    public static func departure(_ flight: FlightSegment, lastPoint: Coordinate?, nationality: String,
                                 fallback: TimeZone = .current) -> Departure? {
        guard let airport = Airports.airport(flight.fromCode) else { return nil }
        let lead = kind(flight) == .international ? departureLeadInternational : departureLeadShort
        let takeoff = flight.localDeparture(fallback: fallback).minutes
        let transfer = zip2(lastPoint, airport.coordinate).map { transferMinutes($0, $1) }
        let beAtAirport = takeoff - lead
        return Departure(airport: airport, takeoff: takeoff, beAtAirport: beAtAirport, transfer: transfer,
                         leaveBy: beAtAirport - (transfer ?? 0), ees: requiresEES(flight, nationality: nationality))
    }

    public enum StopWarning: Equatable, Sendable {
        /// Durak, şehre varılabilecek saatten (dakika) önce başlıyor.
        case beforeReady(Int)
        /// Durak, havalimanına çıkılması gereken saatten (dakika) sonra bitiyor.
        case afterLeave(Int)
    }

    public static func warning(start: Int, duration: Int, arrival: Arrival?, departure: Departure?) -> StopWarning? {
        if let arrival, start < arrival.readyAt { return .beforeReady(arrival.readyAt) }
        if let departure, start + duration > departure.leaveBy { return .afterLeave(departure.leaveBy) }
        return nil
    }

    private static func zip2(_ a: Coordinate?, _ b: Coordinate?) -> (Coordinate, Coordinate)? {
        guard let a, let b else { return nil }
        return (a, b)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios/Packages/GezzyKit && swift test --filter FlightDayTimingTests`
Expected: 7/7 PASS (7 test methods). `testKinds` needs LIS/OPO in PT, MAD in ES, IST in TR in `airports.tsv`; if a country code differs, fix the test fixture to a real airport rather than the logic.

- [ ] **Step 5: Full suite and commit**

Run: `cd ios/Packages/GezzyKit && swift test` → all PASS.

```bash
git add ios/Packages/GezzyKit/Sources/GezzyKit/FlightDayTiming.swift ios/Packages/GezzyKit/Tests/GezzyKitTests/FlightDayTimingTests.swift
git commit -m "Time flight days with airport and border buffers"
```

---

### Task 3: End-anchored route ordering (GezzyKit)

**Files:**
- Modify: `ios/Packages/GezzyKit/Sources/GezzyKit/Geo.swift` (`RouteOptimizer`, lines ~54-180)
- Modify: `ios/Packages/GezzyKit/Sources/GezzyKit/ItineraryPlanner.swift` (Bucket ~line 61-90, `order(_:_:bucket:)` ~190-215, the two `order(... bucket:)` calls ~163-168)
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/RouteEndAnchorTests.swift`

**Interfaces:**
- Consumes: `Trip.anchors(on:calendar:)` (Task 1).
- Produces: `RouteOptimizer.order(_ points: [Coordinate], from start: Coordinate, to end: Coordinate?) -> [Int]`; `RouteOptimizer.order(_ visits: [Visit], from start: Coordinate?, to end: Coordinate? = nil, dayStart: Int) -> [Int]` (existing call sites without `to:` keep working); `ItineraryPlanner` uses the day's start and end anchor coordinates, and `DayPlan.walkingMeters` includes the leg to the end anchor.

- [ ] **Step 1: Write the failing tests**

```swift
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/GezzyKit && swift test --filter RouteEndAnchorTests`
Expected: build FAIL — extra argument `to` in call.

- [ ] **Step 3: Implement in `Geo.swift`**

Add to `RouteOptimizer` (below `order(_:from:)`):

```swift
    /// Başlangıç ve bitiş (ör. sabah ve gece oteli) sabitken noktaları sıralar. Bitiş nil ise `order(_:from:)`.
    public static func order(_ points: [Coordinate], from start: Coordinate, to end: Coordinate?) -> [Int] {
        guard let end else { return order(points, from: start) }
        guard !points.isEmpty else { return [] }
        let all = [start] + points + [end]
        let last = all.count - 1
        var route = [0]
        var remaining = Set(1..<last)
        while let current = route.last, !remaining.isEmpty {
            let next = remaining.min { lhs, rhs in
                let l = Geo.distance(all[current], all[lhs]), r = Geo.distance(all[current], all[rhs])
                return l != r ? l < r : lhs < rhs
            }!
            route.append(next)
            remaining.remove(next)
        }
        route.append(last)
        // 2-opt: iki uç sabit.
        var improved = route.count > 3
        while improved {
            improved = false
            for i in 1..<(route.count - 2) {
                for j in (i + 1)..<(route.count - 1) {
                    var candidate = route
                    candidate[i...j].reverse()
                    if length(candidate, all) + 0.5 < length(route, all) {
                        route = candidate
                        improved = true
                    }
                }
            }
        }
        return route.dropFirst().dropLast().map { $0 - 1 }
    }
```

Change the visit-based `order` signature and its two uses of the path:

```swift
    public static func order(_ visits: [Visit], from start: Coordinate?, to end: Coordinate? = nil, dayStart: Int) -> [Int] {
        guard !visits.isEmpty else { return [] }
        let points = visits.map(\.coordinate)
        // Bitiş yalnızca başlangıç varken kullanılır.
        var best = start.map { order(points, from: $0, to: end) } ?? order(points)
        guard visits.contains(where: { $0.open != nil || $0.fixedStart != nil }), visits.count > 1 else { return best }

        func cost(_ route: [Int]) -> (Int, Double) {
            let conflicts = schedule(route, visits: visits, from: start, dayStart: dayStart).conflicts
            let path = (start.map { [$0] } ?? []) + route.map { points[$0] } + (start != nil ? (end.map { [$0] } ?? []) : [])
            return (conflicts, Geo.routeDistance(path))
        }
        // … rest unchanged
```

- [ ] **Step 4: Implement in `ItineraryPlanner.swift`**

1. In `Bucket`, add `var endAnchor: Coordinate?`; when building buckets, use anchors:

```swift
        var buckets: [Bucket] = days.map { day in
            let window = window(for: day, trip: trip, settings: settings, calendar: calendar)
            let anchors = trip.anchors(on: day, calendar: calendar)
            return Bucket(day: day,
                          weekday: OpeningHours.dayIndex(calendarWeekday: calendar.component(.weekday, from: day)),
                          start: window.start, end: window.end,
                          anchor: anchors.start?.coordinate, endAnchor: anchors.end?.coordinate,
                          existing: trip.stops(on: day, calendar: calendar))
        }
```

(`Bucket` is a local struct with a memberwise init; add `endAnchor` right after `anchor` in the declaration so the call order matches.)

2. Change the private `order` to take the end:

```swift
    private static func order(_ existing: [Stop], _ added: [Stop],
                              bucket: (day: Date, weekday: Int, start: Int, hotel: Coordinate?, end: Coordinate?)) -> Ordered {
```

and inside: `RouteOptimizer.order(visits, from: bucket.hotel, to: bucket.end, dayStart: dayStart)`; the path becomes
`let path = (bucket.hotel.map { [$0] } ?? []) + route.map { located[$0].coordinate! } + (bucket.hotel != nil && !route.isEmpty ? (bucket.end.map { [$0] } ?? []) : [])`.

3. Replace both call sites (`order(bucket.existing, bucket.added, bucket: (…, trip.lodging(forMorningOf: …)?.coordinate))`) with
`order(bucket.existing, bucket.added, bucket: (bucket.day, bucket.weekday, bucket.start, bucket.anchor, bucket.endAnchor))`.

- [ ] **Step 5: Run tests**

Run: `cd ios/Packages/GezzyKit && swift test --filter RouteEndAnchorTests` → 3/3 PASS.
Run: `cd ios/Packages/GezzyKit && swift test` → all PASS. If an existing `ItineraryPlannerTests` case changes because its trip has lodgings (walking meters now include the return), update that expectation only if the new value equals old value + the return leg, and say so in the report.

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GezzyKit
git commit -m "End routes at the night's lodging or airport"
```

---

### Task 4: Rezervasyon tab and single add path

**Files:**
- Create: `ios/Gezzy/DesignSystem/AddPlaceholder.swift`
- Create: `ios/Gezzy/Features/Plan/ReservationsSection.swift`
- Modify: `ios/Gezzy/Features/Plan/FlightViews.swift` (header ~lines 15-45), `ios/Gezzy/Features/Plan/LodgingViews.swift` (header ~18-50)
- Modify: `ios/Gezzy/Features/TripDetail/TripDetailView.swift` (enum ~19-41, switch ~72-79)
- Modify: `ios/Gezzy/Features/Plan/PlanSection.swift` (remove `FlightsCard(trip:)` and `LodgingCard(trip:)` from the body ~113-115)

**Interfaces:**
- Produces: `AddPlaceholder(title: String, subtitle: String, menu: () -> some View)`; `ReservationsSection(trip: Trip)`; `TripDetailView.TripSection.reservations`; environment value `\.openReservations: () -> Void` (default no-op) set by `TripDetailView`.

- [ ] **Step 1: `AddPlaceholder`**

```swift
import SwiftUI

/// Boş kartta tek ekleme yolu: kesik çizgili satır; dokununca verilen menü açılır.
struct AddPlaceholder<MenuContent: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let menu: () -> MenuContent
    @Environment(\.tripTint) private var tint

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Color.ink2)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Cards**

In `FlightsCard`:
- Header button: keep the `Menu`, change its label to a filled tinted circle: `Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.white).frame(width: 32, height: 32).background(tint, in: Circle())`, remove `.buttonStyle(.circleIcon(size: 32))`, add `@Environment(\.tripTint) private var tint`.
- Replace the whole `if flights.isEmpty { EmptyHint …; HStack { two buttons } }` with:

```swift
            if flights.isEmpty {
                AddPlaceholder(title: String(localized: "Uçuş ekle"), subtitle: String(localized: "elle ya da biletten")) {
                    Button("Elle ekle", systemImage: "square.and.pencil") { isAdding = true }
                    Button("Biletten içe aktar", systemImage: "doc.viewfinder") { isImporting = true }
                }
            }
```

Same in `LodgingCard` with title "Konaklama ekle", subtitle "elle ya da rezervasyondan", and its menu items ("Elle ekle", "Rezervasyondan içe aktar"). Keep the uncovered-nights warning as is.

- [ ] **Step 3: `ReservationsSection`**

```swift
import SwiftUI
import GezzyKit

/// Rezervasyon sekmesi: uçuşlar ve konaklama.
struct ReservationsSection: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FlightsCard(trip: trip)
            LodgingCard(trip: trip)
        }
    }
}
```

- [ ] **Step 4: Tab and environment action**

In `TripDetailView.TripSection`: `case plan, reservations, money, packing, visa, crew, memories`; title `.reservations: String(localized: "Rezervasyon")`; symbol `"suitcase.rolling.fill"`; switch `case .reservations: ReservationsSection(trip: trip)`.

Add an environment key (in `TripDetailView.swift`, file scope):

```swift
private struct OpenReservationsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Plan'daki otel/uçuş satırından Rezervasyon sekmesine geçiş.
    var openReservations: () -> Void {
        get { self[OpenReservationsKey.self] }
        set { self[OpenReservationsKey.self] = newValue }
    }
}
```

and on the `ScrollView` chain add `.environment(\.openReservations) { section = .reservations }`.

- [ ] **Step 5: Remove cards from Plan**

In `PlanSection.body`, delete `FlightsCard(trip: trip)` and `LodgingCard(trip: trip)`; keep `IdeasCard(trip: trip, day: plan.day)`.

- [ ] **Step 6: Build and commit**

Run: `cd ios && xcodegen generate && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build` → BUILD SUCCEEDED.

```bash
git add ios/Gezzy
git commit -m "Move flights and lodging to a Rezervasyon tab with one add path"
```

---

### Task 5: Anchors, airport rows and warnings in the day plan

**Files:**
- Create: `ios/Gezzy/Features/Plan/DayAnchorRows.swift`
- Modify: `ios/Gezzy/Features/Plan/PlanSection.swift` (`DayPlan`/`makePlan` ~32-61, `stopList` ~154-240, `map` ~285-320, `optimize` ~405-420, `StopRow` call)

**Interfaces:**
- Consumes: `Trip.anchors(on:)`, `Trip.lodging(forNightOf:)`, `Trip.plannedStarts(on:from:dayStart:)`, `DayAnchor` (Task 1); `FlightDayTiming.arrival/departure/warning` (Task 2); `RouteOptimizer.order(_:from:to:dayStart:)` (Task 3); `\.openReservations` (Task 4); `TripStore.me.passport?.nationality`; existing `HopRow(from:to:)`, `LodgingStartRow`, `StatChip`, `AppFormat.time(minutes:)`.
- Produces: `AnchorRow(anchor: DayAnchor, role: AnchorRow.Role, timing: AnchorRow.Timing?)`, `HotelVisitSuggestion(lodging: Lodging, onAdd: () -> Void, onDismiss: () -> Void)`, `FlightTimingNote(text: String, symbol: String)`.

- [ ] **Step 1: `DayAnchorRows.swift`**

```swift
import SwiftUI
import GezzyKit

/// Günün başındaki/sonundaki otel ya da havalimanı satırı; dokununca Rezervasyon sekmesi açılır.
struct AnchorRow: View {
    enum Role { case start, end }
    enum Timing {
        case arrival(FlightDayTiming.Arrival)
        case departure(FlightDayTiming.Departure)
    }

    let anchor: DayAnchor
    let role: Role
    var timing: Timing?
    @Environment(\.openReservations) private var openReservations

    var body: some View {
        Button(action: openReservations) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAirport ? "airplane" : "bed.double.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isAirport ? Accent.blue.base : Accent.green.base)
                    .frame(width: 36, height: 36)
                    .background(isAirport ? Accent.blue.tint : Accent.green.tint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.tBody).foregroundStyle(Color.ink).lineLimit(1)
                    ForEach(notes, id: \.text) { note in
                        FlightTimingNote(text: note.text, symbol: note.symbol)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var isAirport: Bool { if case .airport = anchor { true } else { false } }

    private var title: String {
        switch (anchor, timing) {
        case (.airport(let airport, _), .arrival(let a)?):
            String(localized: "\(airport.code) · iniş \(AppFormat.time(minutes: a.landing))")
        case (.airport(let airport, _), .departure(let d)?):
            String(localized: "\(airport.code) · kalkış \(AppFormat.time(minutes: d.takeoff))")
        case (.lodging(let lodging), _):
            role == .start ? String(localized: "\(lodging.name) · başlangıç") : String(localized: "\(lodging.name) · bitiş")
        default:
            anchor.name
        }
    }

    private var notes: [(text: String, symbol: String)] {
        switch timing {
        case .arrival(let a)?:
            var list = [(String(localized: "Şehirde yaklaşık \(AppFormat.time(minutes: a.readyAt))"), "clock")]
            if a.ees { list.append((String(localized: "Yeni AB sınır kaydı (EES) nedeniyle pasaport sırası uzun sürebilir."), "person.badge.clock")) }
            return list
        case .departure(let d)?:
            var list: [(String, String)] = []
            if d.leaveBy < 6 * 60 {
                list.append((String(localized: "Sabah erken uçuş; bu gün için durak planlama."), "sunrise"))
            }
            list.append((String(localized: "Havalimanında ol: en geç \(AppFormat.time(minutes: max(0, d.beAtAirport)))"), "clock.badge.exclamationmark"))
            if d.transfer != nil {
                list.append((String(localized: "Havalimanına çıkış: yaklaşık \(AppFormat.time(minutes: max(0, d.leaveBy)))"), "car"))
            }
            list.append((String(localized: "Kapı ve biniş saatini bilette kontrol et."), "ticket"))
            if d.ees { list.append((String(localized: "Yeni AB sınır kaydı (EES) nedeniyle pasaport sırası uzun sürebilir."), "person.badge.clock")) }
            return list
        case nil:
            return []
        }
    }
}

struct FlightTimingNote: View {
    let text: String
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(Color.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Varış günü: "Önce otele uğramak ister misin?" önerisi.
struct HotelVisitSuggestion: View {
    let lodging: Lodging
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "suitcase.rolling").foregroundStyle(Accent.green.base)
            Text("Önce otele uğramak ister misin?").font(.subheadline).foregroundStyle(Color.ink)
            Spacer(minLength: 4)
            Button("Ekle", action: onAdd).font(.subheadline.bold())
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.caption)
            }
            .accessibilityLabel("Öneriyi kapat")
        }
        .padding(10)
        .background(Accent.green.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.vertical, 6)
    }
}
```

Note: `AppFormat.time(minutes:)` already exists (used by `AutoPlanSheet`).

- [ ] **Step 2: Extend `DayPlan` / `makePlan`**

Add to `DayPlan`: `let start: DayAnchor?`, `let end: DayAnchor?`, `let arrival: FlightDayTiming.Arrival?`, `let departure: FlightDayTiming.Departure?`, `let flightWarnings: [Stop.ID: FlightDayTiming.StopWarning]`; change `warningCount` to `hours.values.filter(\.isWarning).count + flightWarnings.count`.

In `makePlan()` after computing `stops`:

```swift
        let anchors = trip.anchors(on: day)
        let nationality = store.me.passport?.nationality ?? "TR"
        let firstPoint = stops.first(where: { $0.coordinate != nil })?.coordinate ?? trip.lodging(forNightOf: day)?.coordinate
        let lastPoint = stops.last(where: { $0.coordinate != nil })?.coordinate ?? trip.lodging(forMorningOf: day)?.coordinate
        var arrival: FlightDayTiming.Arrival?
        if case .airport(_, let flight)? = anchors.start {
            arrival = FlightDayTiming.arrival(flight, firstPoint: firstPoint, nationality: nationality)
        }
        var departure: FlightDayTiming.Departure?
        if case .airport(_, let flight)? = anchors.end {
            departure = FlightDayTiming.departure(flight, lastPoint: lastPoint, nationality: nationality)
        }
        var flightWarnings: [Stop.ID: FlightDayTiming.StopWarning] = [:]
        if arrival != nil || departure != nil {
            let starts = trip.plannedStarts(on: day, from: anchors.start?.coordinate, dayStart: arrival?.readyAt ?? 9 * 60)
            for stop in stops {
                guard let start = starts[stop.id] else { continue }
                flightWarnings[stop.id] = FlightDayTiming.warning(start: start, duration: stop.durationMinutes,
                                                                 arrival: arrival, departure: departure)
            }
        }
        let path = (anchors.start?.coordinate.map { [$0] } ?? []) + coordinates
            + (coordinates.isEmpty && anchors.start == nil ? [] : (anchors.end?.coordinate.map { [$0] } ?? []))
```

and pass `totalMeters: Geo.routeDistance(path)` plus the new fields.

- [ ] **Step 3: Stop list**

In `stopList(_:)`, replace the `if let lodging = trip.lodging(forMorningOf:) … LodgingStartRow …` block with:

```swift
            if let start = plan.start {
                AnchorRow(anchor: start, role: .start, timing: plan.arrival.map(AnchorRow.Timing.arrival))
                if plan.arrival != nil, !dismissedHotelSuggestion.contains(plan.day),
                   let hotel = trip.lodging(forNightOf: plan.day),
                   !stops.contains(where: { $0.kind == .stay && $0.name == hotel.name }) {
                    HotelVisitSuggestion(lodging: hotel,
                                         onAdd: { addHotelVisit(hotel, on: plan.day) },
                                         onDismiss: { dismissedHotelSuggestion.insert(plan.day) })
                }
                if let first = stops.first { HopRow(from: start.coordinate, to: first.coordinate) }
            }
```

After the `ForEach` of stops, add:

```swift
            if let end = plan.end {
                if let last = stops.last { HopRow(from: last.coordinate, to: end.coordinate) }
                else if let start = plan.start { HopRow(from: start.coordinate, to: end.coordinate) }
                AnchorRow(anchor: end, role: .end, timing: plan.departure.map(AnchorRow.Timing.departure))
            }
```

Add state `@State private var dismissedHotelSuggestion: Set<Date> = []` and:

```swift
    /// Varış gününde otele uğrama durağı listenin başına; basılı tutup sürüklenerek taşınabilir.
    private func addHotelVisit(_ hotel: Lodging, on day: Date) {
        withAnimation(.spring(duration: 0.3)) {
            store.update(trip.id) { trip in
                for index in trip.stops.indices where Calendar.current.isDate(trip.stops[index].day, inSameDayAs: day) {
                    trip.stops[index].order += 1
                }
                trip.stops.append(Stop(day: day, order: 0, name: hotel.name, kind: .stay, durationMinutes: 30,
                                       coordinate: hotel.coordinate))
            }
        }
    }
```

Stop warnings: pass the flight warning into the stop row. `StopRow` currently shows `hours`; add an optional `flightWarning: FlightDayTiming.StopWarning?` parameter (default nil) rendered under the name as `FlightTimingNote` with symbol `"exclamationmark.circle.fill"` and text:
- `.beforeReady(let t)`: `String(localized: "İnişten sonra şehre en erken varış: \(AppFormat.time(minutes: t))")`
- `.afterLeave(let t)`: `String(localized: "Havalimanına çıkış saatinden (\(AppFormat.time(minutes: max(0, t)))) sonra bitiyor")`
colored `Color.food` (warning orange). Call site: `StopRow(stop: stop, number: index + 1, hours: plan.hours[stop.id], fix: plan.fixes[stop.id], flightWarning: plan.flightWarnings[stop.id]) { … }`.

- [ ] **Step 4: Map**

In `map(_:)`, replace the hotel-only start with anchors: `route = [start] + pinned + [end]` (each optional). Start/end annotations: lodging → existing green bed circle; airport → same circle with `"airplane"` and `Accent.blue.base`. If start and end are the same lodging (same id), draw one annotation. Keep `MapFraming.position(route)` reframing.

- [ ] **Step 5: Optimize**

In `optimize()`, use anchors: `let anchors = trip.anchors(on: day)`; `RouteOptimizer.order(visits, from: anchors.start?.coordinate, to: anchors.end?.coordinate, dayStart: dayStart)`. Keep `dayStart` logic.

- [ ] **Step 6: Build and commit**

Run: `cd ios && xcodegen generate && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build` → BUILD SUCCEEDED.

```bash
git add ios/Gezzy
git commit -m "Show lodging and airport anchors with flight-day timing in the plan"
```

---

### Task 6: Strings and simulator verification

**Files:**
- Modify: `ios/Gezzy/Resources/Localizable.xcstrings`

- [ ] **Step 1: English strings**

Add `en` for every new key used in Tasks 4-5 (look up exact extracted keys; Int → `%lld`, String → `%@`). Expected keys and values:

| Key | en |
|---|---|
| `Rezervasyon` | `Bookings` |
| `Uçuş ekle` | `Add flight` |
| `elle ya da biletten` | `manually or from a ticket` |
| `Konaklama ekle` | `Add stay` (exists? skip if present) |
| `elle ya da rezervasyondan` | `manually or from a booking` |
| `%@ · iniş %@` | `%1$@ · lands %2$@` |
| `%@ · kalkış %@` | `%1$@ · departs %2$@` |
| `%@ · başlangıç` | `%@ · start` |
| `%@ · bitiş` | `%@ · end` |
| `Şehirde yaklaşık %@` | `In the city around %@` |
| `Yeni AB sınır kaydı (EES) nedeniyle pasaport sırası uzun sürebilir.` | `Passport queues can be long because of the new EU Entry/Exit System (EES).` |
| `Sabah erken uçuş; bu gün için durak planlama.` | `Early morning flight; don't plan stops for this day.` |
| `Havalimanında ol: en geç %@` | `Be at the airport by %@` |
| `Havalimanına çıkış: yaklaşık %@` | `Leave for the airport around %@` |
| `Kapı ve biniş saatini bilette kontrol et.` | `Check the gate and boarding time on your ticket.` |
| `Önce otele uğramak ister misin?` | `Drop by the hotel first?` |
| `Ekle` | `Add` (exists) |
| `Öneriyi kapat` | `Dismiss suggestion` |
| `İnişten sonra şehre en erken varış: %@` | `Earliest arrival in the city after landing: %@` |
| `Havalimanına çıkış saatinden (%@) sonra bitiyor` | `Ends after you need to leave for the airport (%@)` |

Remove keys left unused by Task 4 only if grep confirms no use (e.g. "Uçuşunu elle yaz ya da e-bilet, ekran görüntüsü veya Wallet kartından içe aktar.", "Otel ya da ev ekle ya da Booking.com, Airbnb onayından içe aktar; günlerin planı oradan başlasın.", "İçe aktar"). Validate JSON. Build. Commit "Translate the reservations tab and flight-day notes".

- [ ] **Step 2: Simulator check (controller)**

On "iPhone Air" with a Lizbon trip (lodging 20–23, IST→LIS 20 Oct 11:20, LIS→IST 23 Oct 09:40, passport nationality empty → TR):
1. Tabs show Plan · Rezervasyon · …; Rezervasyon shows both cards; empty card shows the dashed placeholder; tapping it opens the menu.
2. Plan no longer shows flight/lodging cards.
3. Day 1: list starts with "LIS · iniş 11:20", "Şehirde yaklaşık …", EES note, hotel suggestion; "Ekle" adds a hotel stop at the top that can be dragged; a stop at 12:00 shows the before-ready warning; list ends at the hotel ("· bitiş").
4. Day 2: starts and ends at the hotel; map line returns to the hotel; walking total includes the return.
5. Day 4: starts at the hotel, ends at "LIS · kalkış 09:40" with "Havalimanında ol: en geç 06:40", leave-by line, gate note, EES note; a 10:00 stop shows the after-leave warning.
6. Tapping a hotel/airport row switches to the Rezervasyon tab.
