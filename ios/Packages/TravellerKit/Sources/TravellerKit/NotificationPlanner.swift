import Foundation

/// Seyahat için yerel bildirim planı (saf mantık; zamanlama uygulamada yapılır).
public struct PlannedNotification: Hashable, Sendable {
    /// "trip-<id>-<tür>" biçiminde; seyahat değişince aynı kimlikle yeniden kurulur.
    public var id: String
    public var date: Date
    public var title: String
    public var body: String
    /// Dokununca açılacak seyahat ve sekme (`TripLink`).
    public var link: TripLink
}

public enum NotificationPlanner {
    /// iOS en fazla 64 bekleyen bildirime izin verir; seyahat başına bundan azını kullan.
    public static let perTripLimit = 20

    public static func plan(for trip: Trip, now: Date = Date(), calendar: Calendar = .current) -> [PlannedNotification] {
        guard trip.status == .planned else { return [] }
        var result: [PlannedNotification] = []
        let prefix = "trip-\(trip.id.uuidString)"
        let days = trip.days(calendar: calendar)
        guard let firstDay = days.first else { return [] }

        // Gitmeden önceki akşam: valiz durumu.
        if let eve = at(hour: 20, minute: 0, on: calendar.date(byAdding: .day, value: -1, to: firstDay), calendar) {
            let missing = trip.packing.filter { !$0.isPacked }.count
            let body = missing == 0
                ? "Valiz hazır görünüyor. İyi yolculuklar!"
                : "Valizde \(missing) madde eksik. Son kontrol için iyi bir zaman."
            result.append(PlannedNotification(id: "\(prefix)-eve", date: eve, title: "Yarın \(trip.destination.city)!", body: body,
                                              link: TripLink(tripID: trip.id, section: "packing")))
        }

        // Uçuştan 3 saat önce.
        if let flight = trip.primaryFlight,
           let reminder = calendar.date(byAdding: .hour, value: -3, to: flight.departure) {
            var details = ["\(flight.fromCode) → \(flight.toCode)"]
            if let gate = flight.gate { details.append("kapı \(gate)") }
            if let seat = flight.seat { details.append("koltuk \(seat)") }
            result.append(PlannedNotification(id: "\(prefix)-flight", date: reminder,
                                              title: "Uçuş \(flight.flightNumber) · 3 saat kaldı",
                                              body: details.joined(separator: " · "),
                                              link: TripLink(tripID: trip.id, section: "plan")))
        }

        // Konaklama: giriş günü sabahı ve çıkış günü sabahı.
        for lodging in trip.lodgingList {
            let checkInClock = String(format: "%02d:%02d", calendar.component(.hour, from: lodging.checkIn),
                                      calendar.component(.minute, from: lodging.checkIn))
            let checkOutClock = String(format: "%02d:%02d", calendar.component(.hour, from: lodging.checkOut),
                                       calendar.component(.minute, from: lodging.checkOut))
            if let morning = at(hour: 9, minute: 0, on: calendar.startOfDay(for: lodging.checkIn), calendar) {
                var body = "Giriş saati \(checkInClock)"
                if !lodging.confirmation.isEmpty { body += " · rezervasyon \(lodging.confirmation)" }
                result.append(PlannedNotification(id: "\(prefix)-checkin-\(lodging.id.uuidString)", date: morning,
                                                  title: "Bugün otel girişi: \(lodging.name)", body: body,
                                                  link: TripLink(tripID: trip.id, section: "plan")))
            }
            if let morning = at(hour: 8, minute: 0, on: calendar.startOfDay(for: lodging.checkOut), calendar) {
                result.append(PlannedNotification(id: "\(prefix)-checkout-\(lodging.id.uuidString)", date: morning,
                                                  title: "Bugün çıkış: \(lodging.name)",
                                                  body: "Çıkış saati en geç \(checkOutClock).",
                                                  link: TripLink(tripID: trip.id, section: "plan")))
            }
        }

        // Her sabah günün planı.
        for (index, day) in days.enumerated() {
            let stops = trip.stops(on: day, calendar: calendar)
            guard !stops.isEmpty, let morning = at(hour: 8, minute: 30, on: day, calendar) else { continue }
            let first = stops[0]
            var body = "\(stops.count) durak"
            if let start = first.startMinutes {
                body += " · ilk durak \(first.name), \(String(format: "%02d:%02d", start / 60, start % 60))"
            } else {
                body += " · ilk durak \(first.name)"
            }
            result.append(PlannedNotification(id: "\(prefix)-day\(index)", date: morning,
                                              title: "\(index + 1). gün · \(trip.destination.city)", body: body,
                                              link: TripLink(tripID: trip.id, section: "plan")))
        }

        // Rezervasyonlu ya da saatli duraklardan 45 dk önce (yalnızca notu olanlar: "bilet", "rezervasyon" vb.).
        for stop in trip.stops where stop.startMinutes != nil && !stop.note.isEmpty {
            guard let start = stop.startMinutes,
                  let time = calendar.date(byAdding: .minute, value: start - 45, to: calendar.startOfDay(for: stop.day)) else { continue }
            result.append(PlannedNotification(id: "\(prefix)-stop-\(stop.id.uuidString)", date: time,
                                              title: "45 dk sonra: \(stop.name)", body: stop.note,
                                              link: TripLink(tripID: trip.id, section: "plan")))
        }

        return Array(result.filter { $0.date > now }.sorted { $0.date < $1.date }.prefix(perTripLimit))
    }

    static func at(hour: Int, minute: Int, on day: Date?, _ calendar: Calendar) -> Date? {
        guard let day else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
