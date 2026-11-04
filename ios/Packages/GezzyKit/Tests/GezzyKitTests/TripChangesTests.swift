import XCTest
@testable import GezzyKit

final class TripChangesTests: XCTestCase {
    let me = Member(name: "Ben")
    let elif = Member(name: "Elif")
    func money(_ minor: Int, _ code: String) -> String { "\(code) \(minor / 100)" }

    func base() -> Trip {
        Trip(name: "Lizbon", destination: Destination(countryCode: "PT", city: "Lizbon"), startDate: .now, endDate: .now,
             currency: "EUR", members: [me, elif], packing: [PackingItem(title: "Pasaport", assignee: elif.id)])
    }

    func testDescribesOthersChanges() {
        let old = base()
        var new = old
        new.expenses.append(Expense(title: "Akşam yemeği", amount: 8_600, category: .food, paidBy: elif.id,
                                    splitAmong: [me.id, elif.id], date: .now))
        new.stops.append(Stop(day: .now, order: 0, name: "Pena Sarayı", kind: .sight))
        new.packing[0].isPacked = true

        let summary = TripChanges.summarize(old: old, new: new, me: me.id, money: money)
        XCTAssertEqual(summary?.title, "Lizbon")
        XCTAssertEqual(summary?.lines, ["Elif bir harcama ekledi: Akşam yemeği · EUR 86", "Plana eklendi: Pena Sarayı",
                                        "Valize konuldu: Pasaport"])
    }

    func testIgnoresOwnChangesAndNoOps() {
        let old = base()
        var new = old
        new.expenses.append(Expense(title: "Taksi", amount: 1_000, category: .transport, paidBy: me.id,
                                    splitAmong: [me.id], date: .now))
        XCTAssertNil(TripChanges.summarize(old: old, new: new, me: me.id, money: money))
        XCTAssertNil(TripChanges.summarize(old: old, new: old, me: me.id, money: money))
    }

    func testLodgingLinksToReservations() {
        let old = base()
        var new = old
        new.lodgings = [Lodging(name: "Otel", checkIn: .now, checkOut: .now)]
        XCTAssertEqual(TripChanges.summarize(old: old, new: new, me: me.id, money: money)?.link.section, "reservations")
    }

    func testNewSharedTrip() {
        XCTAssertEqual(TripChanges.summarize(old: nil, new: base(), me: me.id, money: money)?.lines, ["Seyahat seninle paylaşıldı."])
    }

    func testNamesEditorAndDescribesRemovalsAndMoves() {
        let day = Calendar.current.startOfDay(for: .now)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        var old = base()
        let a = Stop(day: day, order: 0, name: "Pena Sarayı", kind: .sight)
        let b = Stop(day: day, order: 1, name: "Belém Kulesi", kind: .sight)
        let c = Stop(day: day, order: 2, name: "Time Out Market", kind: .food)
        old.stops = [a, b, c]
        var new = old
        new.updatedBy = elif.id
        new.stops.removeAll { $0.id == c.id }
        new.stops[0].order = 1
        new.stops[1].order = 0
        var moved = new.stops[1]
        moved.day = next
        new.stops[1] = moved

        let lines = TripChanges.summarize(old: old, new: new, me: me.id, money: money)?.lines ?? []
        XCTAssertTrue(lines.contains("Elif plandan çıkardı: Time Out Market"))
        XCTAssertTrue(lines.contains { $0.hasPrefix("Elif, Belém Kulesi durağını") })
        XCTAssertTrue(lines.contains("Elif planın sırasını değiştirdi"))
        XCTAssertEqual(TripChanges.summarize(old: old, new: new, me: me.id, money: money)?.editor, "Elif")
    }

    func testSkipsChangesIMadeOnAnotherDevice() {
        let old = base()
        var new = old
        new.updatedBy = me.id
        new.stops.append(Stop(day: .now, order: 0, name: "Pena Sarayı", kind: .sight))
        XCTAssertNil(TripChanges.summarize(old: old, new: new, me: me.id, money: money))
    }
}
