import Foundation
import TravellerKit

/// İlk açılışta gösterilen örnek seyahatler. Tarihler bugüne göre hesaplanır.
enum SampleData {
    static func trips(me: Member, now: Date = .now, calendar: Calendar = .current) -> [Trip] {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        func at(_ offset: Int, _ hour: Int, _ minute: Int, _ zone: String) -> Date {
            var components = calendar.dateComponents([.year, .month, .day], from: day(offset))
            components.hour = hour
            components.minute = minute
            components.timeZone = TimeZone(identifier: zone)
            return Calendar(identifier: .gregorian).date(from: components)!
        }

        var owner = me
        owner.role = .owner
        let elif = Member(name: "Elif", role: .editor, colorIndex: 0,
                          passport: Passport(expiresOn: day(900), heldVisas: [HeldVisa(zone: .schengen, validUntil: day(300))]))
        let can = Member(name: "Can", role: .editor, colorIndex: 1, passport: Passport(expiresOn: day(1500)))
        let deniz = Member(name: "Deniz", role: .viewer, colorIndex: 2, passport: Passport(expiresOn: day(70)))

        return [lisbon(owner: owner, elif: elif, can: can, deniz: deniz, day: day, at: at),
                Trip(name: "Kyoto'da Sonbahar",
                     destination: Destination(countryCode: "JP", city: "Kyoto",
                                              coordinate: Coordinate(latitude: 35.0116, longitude: 135.7681)),
                     startDate: day(41), endDate: day(49), currency: "JPY", coverSeed: 1,
                     members: [owner, elif, can],
                     budget: [BudgetLine(category: .stays, limit: 18_000_000), BudgetLine(category: .food, limit: 9_000_000)]),
                Trip(name: "Reykjavík ışıkları",
                     destination: Destination(countryCode: "IS", city: "Reykjavík",
                                              coordinate: Coordinate(latitude: 64.1466, longitude: -21.9426)),
                     startDate: day(120), endDate: day(124), coverSeed: 2, members: [owner, can]),
                Trip(name: "Erivan & Dilican",
                     destination: Destination(countryCode: "AM", city: "Erivan",
                                              coordinate: Coordinate(latitude: 40.1792, longitude: 44.4991)),
                     startDate: day(156), endDate: day(160), status: .draft, currency: "AMD", coverSeed: 3,
                     members: [owner])]
    }

    private static func lisbon(owner: Member, elif: Member, can: Member, deniz: Member,
                               day: (Int) -> Date, at: (Int, Int, Int, String) -> Date) -> Trip {
        let all = [owner.id, elif.id, can.id, deniz.id]
        let start = 11
        return Trip(
            name: "Lizbon Kaçamağı",
            destination: Destination(countryCode: "PT", city: "Lizbon",
                                     coordinate: Coordinate(latitude: 38.7223, longitude: -9.1393)),
            startDate: day(start), endDate: day(start + 6), currency: "EUR", coverSeed: 0,
            members: [owner, elif, can, deniz],
            flights: [
                FlightSegment(flightNumber: "TK1759", fromCode: "IST", fromCity: "İstanbul", toCode: "LIS", toCity: "Lizbon",
                              departure: at(start, 7, 40, "Europe/Istanbul"), arrival: at(start, 10, 15, "Europe/Lisbon"),
                              departureTimeZone: "Europe/Istanbul", arrivalTimeZone: "Europe/Lisbon",
                              gate: "F7", seat: "14C"),
            ],
            stops: [
                Stop(day: day(start), order: 0, name: "Alfama'daki ev", kind: .stay, startMinutes: 13 * 60, durationMinutes: 60,
                     coordinate: Coordinate(latitude: 38.7118, longitude: -9.1300), note: "Anahtar kutusu kapıda"),
                Stop(day: day(start), order: 1, name: "Time Out Market", kind: .food, startMinutes: 19 * 60 + 30,
                     durationMinutes: 90, coordinate: Coordinate(latitude: 38.7069, longitude: -9.1460)),
                Stop(day: day(start + 1), order: 0, name: "Pena Sarayı", kind: .sight, startMinutes: 10 * 60,
                     durationMinutes: 150, coordinate: Coordinate(latitude: 38.7876, longitude: -9.3906),
                     note: "Biletler önceden alınmalı"),
                Stop(day: day(start + 2), order: 0, name: "Miradouro da Graça", kind: .sight, startMinutes: 9 * 60 + 30,
                     durationMinutes: 40, coordinate: Coordinate(latitude: 38.7166, longitude: -9.1316)),
                Stop(day: day(start + 2), order: 1, name: "Tram 28", kind: .transport, startMinutes: 10 * 60 + 30,
                     durationMinutes: 25, coordinate: Coordinate(latitude: 38.7133, longitude: -9.1360)),
                Stop(day: day(start + 2), order: 2, name: "Pastéis de Belém", kind: .food, startMinutes: 12 * 60 + 15,
                     durationMinutes: 45, coordinate: Coordinate(latitude: 38.6975, longitude: -9.2032), note: "Sıra olabilir"),
                Stop(day: day(start + 2), order: 3, name: "Torre de Belém", kind: .sight, startMinutes: 13 * 60 + 30,
                     durationMinutes: 60, coordinate: Coordinate(latitude: 38.6916, longitude: -9.2160)),
            ],
            budget: [
                BudgetLine(category: .stays, limit: 160_000),
                BudgetLine(category: .transport, limit: 90_000),
                BudgetLine(category: .food, limit: 130_000),
                BudgetLine(category: .activities, limit: 100_000),
            ],
            expenses: [
                Expense(title: "Alfama'daki ev · 6 gece", amount: 140_000, category: .stays, paidBy: owner.id,
                        splitAmong: all, date: day(-20)),
                Expense(title: "Uçak biletleri", amount: 90_000, category: .transport, paidBy: elif.id, splitAmong: all,
                        date: day(-30)),
                Expense(title: "Pena Sarayı biletleri", amount: 8_000, category: .activities, paidBy: can.id,
                        splitAmong: all, date: day(-3)),
            ],
            packing: [
                PackingItem(title: "Pasaportlar", assignee: owner.id, isPacked: true),
                PackingItem(title: "Şarj aletleri", assignee: elif.id, isPacked: true),
                PackingItem(title: "Güneş gözlüğü", assignee: can.id),
                PackingItem(title: "Güneş kremi"),
            ]
        )
    }
}
