import XCTest
@testable import GezzyKit

final class MemoryHighlightsTests: XCTestCase {
    let cal = TestCalendar.calendar

    func moment(_ ids: [String], day: Int, hour: Int, stop: String? = nil) -> PhotoClusterer.Moment {
        let start = cal.startOfDay(for: TestCalendar.date(2026, 11, day)).addingTimeInterval(Double(hour) * 3600)
        return PhotoClusterer.Moment(photoIDs: ids, start: start, end: start.addingTimeInterval(1800), center: nil, stopName: stop)
    }

    func testOnePerDayFromBiggestMomentMiddlePhoto() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1", "a2"], day: 19, hour: 10),
            moment(["b1", "b2", "b3"], day: 19, hour: 14, stop: "Nyhavn"),
            moment(["c1"], day: 20, hour: 9),
        ], favorites: [], hidden: [], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["b2", "c1"])
        XCTAssertEqual(picks[0].stopName, "Nyhavn")
        XCTAssertEqual(picks.map(\.day), [cal.startOfDay(for: TestCalendar.date(2026, 11, 19)), cal.startOfDay(for: TestCalendar.date(2026, 11, 20))])
    }

    func testFavoriteWinsEarliestFirst() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1", "a2"], day: 19, hour: 10),
            moment(["b1", "b2", "b3"], day: 19, hour: 14),
        ], favorites: ["b3", "a2"], hidden: [], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["a2"])
    }

    func testHiddenNeverPickedAndEmptyDaySkipped() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1"], day: 19, hour: 10),
            moment(["b1", "b2", "b3"], day: 20, hour: 14),
        ], favorites: ["a1"], hidden: ["a1", "b2"], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["b3"])
    }

    func testTieBreaksOnStopNameThenEarlier() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1", "a2"], day: 19, hour: 9),
            moment(["b1", "b2"], day: 19, hour: 12, stop: "Tivoli"),
        ], favorites: [], hidden: [], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["b2"])
    }
}
