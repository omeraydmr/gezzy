import Foundation

/// Fikirler havuzundaki yerleri seyahat günlerine dağıtır ve her günü sıralar (yapay zekâ kullanmaz).
///
/// 1. Her günün boş zamanı hesaplanır: gün penceresi (ör. 09:00–19:00), varış/dönüş uçuşları ve o güne
///    zaten konmuş durakların süreleri düşülür.
/// 2. Yerler, en az seçeneği olandan başlayarak (yalnızca birkaç gün açık olanlar önce) açık oldukları ve
///    yeri olan günlerden, o günün mevcut duraklarına/oteline en yakın olana konur. Böylece yakın yerler
///    aynı güne toplanır.
/// 3. Her gün `RouteOptimizer` ile açılış saatlerine ve en kısa yürüyüşe göre sıralanır; pencereye
///    sığmayan yeni yerler gün sonundan çıkarılıp "yerleşmeyenler"e bırakılır.
public enum ItineraryPlanner {
    public struct Settings: Hashable, Sendable {
        /// Gün başlangıcı ve bitişi (gece yarısından dakika).
        public var dayStart: Int
        public var dayEnd: Int
        /// Yolcunun uyruğu: uçuş günlerinde EES kuyruğu hesabı için.
        public var nationality: String

        public init(dayStart: Int = 9 * 60, dayEnd: Int = 19 * 60, nationality: String = "TR") {
            self.dayStart = dayStart
            self.dayEnd = dayEnd
            self.nationality = nationality
        }
    }

    public struct DayPlan: Hashable, Sendable {
        public var day: Date
        /// Günün yeni sırası: mevcut durakların ve yerleştirilen fikirlerin kimlikleri.
        public var order: [UUID]
        /// Yerleştirilen fikirlerin önerilen başlangıç saatleri (dakika).
        public var starts: [UUID: Int]
        /// Bu güne yerleştirilen fikirler.
        public var added: [UUID]
        /// Gün içi yürüyüş (metre, kuş uçuşu; otelden başlar).
        public var walkingMeters: Double
        /// Plana göre günün bitişi (dakika).
        public var endMinutes: Int
    }

    public struct Plan: Hashable, Sendable {
        public var days: [DayPlan]
        /// Hiçbir güne sığmayan ya da konumu olmayan fikirler.
        public var unscheduled: [UUID]

        public var addedCount: Int { days.reduce(0) { $0 + $1.added.count } }
    }

    public static func plan(_ trip: Trip, ideas: [UUID]? = nil, settings: Settings = Settings(),
                            calendar: Calendar = .current) -> Plan {
        let pool = trip.ideaList.filter { ideas?.contains($0.id) ?? true }
        let days = trip.days(calendar: calendar)
        var unscheduled = pool.filter { $0.coordinate == nil }.map(\.id)
        let located = pool.filter { $0.coordinate != nil }
        guard !days.isEmpty else { return Plan(days: [], unscheduled: pool.map(\.id)) }

        // Gün pencereleri ve mevcut yük.
        struct Bucket {
            var day: Date
            var weekday: Int
            var start: Int
            var end: Int
            /// Uçuş günü: pencere sınırına tolerans yok.
            var arrives: Bool
            var departs: Bool
            var anchor: Coordinate?
            var endAnchor: Coordinate?
            var existing: [Stop]
            var added: [Stop] = []
            var used: Int {
                (existing + added).reduce(0) { $0 + $1.durationMinutes } + (existing.count + added.count) * ItineraryPlanner.travelAllowance
            }
            var free: Int { end - start - used }
            var center: Coordinate? {
                let points = (existing + added).compactMap(\.coordinate) + (anchor.map { [$0] } ?? [])
                guard !points.isEmpty else { return nil }
                return Coordinate(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                                  longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
            }
        }

        var buckets: [Bucket] = days.map { day in
            let window = window(for: day, trip: trip, settings: settings, calendar: calendar)
            let anchors = trip.anchors(on: day, calendar: calendar)
            // Yürüyüş uçları yalnızca konaklama: havalimanı bacağı transferdir (pencereye dahil).
            var start: Coordinate?
            switch anchors.start {
            case .lodging(let lodging)?: start = lodging.coordinate
            case .airport?: start = trip.lodging(forNightOf: day, calendar: calendar)?.coordinate
            case nil: start = nil
            }
            var end: Coordinate?
            switch anchors.end {
            case .lodging(let lodging)?: end = lodging.coordinate
            case .airport?: end = trip.lodging(forMorningOf: day, calendar: calendar)?.coordinate
            case nil: end = nil
            }
            return Bucket(day: day,
                          weekday: OpeningHours.dayIndex(calendarWeekday: calendar.component(.weekday, from: day)),
                          start: window.start, end: window.end,
                          arrives: trip.arrivalFlight(on: day, calendar: calendar) != nil,
                          departs: trip.departureFlight(on: day, calendar: calendar) != nil,
                          anchor: start, endAnchor: end,
                          existing: trip.stops(on: day, calendar: calendar))
        }

        // Çok şehirli seyahat: her fikir konumuna en yakın şehrin günlerine yerleşir (şehir konumu bilinmiyorsa serbest).
        let legOfBucket = buckets.map { trip.leg(on: $0.day, calendar: calendar).id }
        let locatedLegs = trip.cityLegs.compactMap { leg in leg.destination.coordinate.map { (leg.id, $0) } }
        func leg(of stop: Stop) -> UUID? {
            guard trip.isMultiCity, locatedLegs.count == trip.cityLegs.count, let point = stop.coordinate else { return nil }
            return locatedLegs.min { Geo.distance($0.1, point) < Geo.distance($1.1, point) }?.0
        }

        func openDays(_ stop: Stop) -> [Int] {
            let city = leg(of: stop)
            return buckets.indices.filter { index in
                if let city, legOfBucket[index] != city { return false }
                guard let raw = stop.openingHours, let hours = OpeningHours.cached(raw) else { return true }
                let intervals = hours.intervals(onDay: buckets[index].weekday)
                // O gün, ziyaret süresi kadar açık kaldığı bir aralık olmalı.
                return intervals.contains { min($0.end, buckets[index].end) - max($0.start, buckets[index].start) >= stop.durationMinutes }
            }
        }

        // Yerleşimi zor olandan kolaya: az açık günü olan ve uzun süren önce.
        let ordered = located.sorted { lhs, rhs in
            let l = openDays(lhs).count, r = openDays(rhs).count
            return l != r ? l < r : lhs.durationMinutes > rhs.durationMinutes
        }

        // Boş günleri birbirinden uzak bölgelerle başlat (ilk fikir, ondan en uzak fikir…). Mevcut bölgelere
        // `regionSpacing`'den yakın yerler yeni bir gün açmaz: aynı semtteki yerler bölünmesin. Çok şehirlide şehir şehir.
        let groups: [(days: [Int], points: [Coordinate])] = trip.isMultiCity && locatedLegs.count == trip.cityLegs.count
            ? trip.cityLegs.map { city in
                (buckets.indices.filter { legOfBucket[$0] == city.id },
                 located.filter { leg(of: $0) == city.id }.compactMap(\.coordinate))
            }
            : [(Array(buckets.indices), located.compactMap(\.coordinate))]
        for group in groups {
            var seeds: [Coordinate] = group.days.compactMap { buckets[$0].center }
            let fixedSeeds = seeds.count
            while seeds.count - fixedSeeds < group.days.count, let next = group.points.max(by: { a, b in
                (seeds.map { Geo.distance($0, a) }.min() ?? .infinity) < (seeds.map { Geo.distance($0, b) }.min() ?? .infinity)
            }) {
                if let nearest = seeds.map({ Geo.distance($0, next) }).min(), nearest < regionSpacing { break }
                seeds.append(next)
            }
            seeds.removeFirst(fixedSeeds)
            var seedIndex = 0
            for index in group.days where buckets[index].center == nil && seedIndex < seeds.count
                && buckets[index].end - buckets[index].start >= 120 {
                buckets[index].anchor = seeds[seedIndex]
                seedIndex += 1
            }
        }

        for stop in ordered {
            guard let coordinate = stop.coordinate else { continue }
            let candidates = openDays(stop).filter { buckets[$0].free >= stop.durationMinutes + travelAllowance }
            let best = candidates.min { a, b in
                // Hiç yeri olmayan gün en son seçenek: yakın bir bölgeye sığıyorsa oraya.
                let da = buckets[a].center.map { Geo.distance($0, coordinate) } ?? 1_000_000
                let db = buckets[b].center.map { Geo.distance($0, coordinate) } ?? 1_000_000
                // Mesafe yakınsa daha boş güne koy.
                if abs(da - db) > 400 { return da < db }
                return buckets[a].free > buckets[b].free
            }
            if let best {
                buckets[best].added.append(stop)
            } else {
                unscheduled.append(stop.id)
            }
        }

        // Günleri sırala; pencereye sığmayan yenileri çıkar.
        var plans: [DayPlan] = []
        for var bucket in buckets {
            var result = order(bucket.existing, bucket.added, bucket: (bucket.day, bucket.weekday, bucket.start, bucket.anchor, bucket.endAnchor))
            // Uçuş günü: hazır olmadan başlayan ya da çıkış saatinden sonra biten yeni yer kalmaz.
            func violation(_ r: Ordered) -> UUID? {
                if bucket.arrives, let early = r.addedStarts.first(where: { $0.value < bucket.start })?.key { return early }
                if bucket.departs ? r.addedEnd > bucket.end : r.end > bucket.end + 30 { return r.lastAdded }
                return nil
            }
            while let drop = violation(result) {
                bucket.added.removeAll { $0.id == drop }
                unscheduled.append(drop)
                result = order(bucket.existing, bucket.added, bucket: (bucket.day, bucket.weekday, bucket.start, bucket.anchor, bucket.endAnchor))
            }
            plans.append(DayPlan(day: bucket.day, order: result.order, starts: result.starts,
                                 added: bucket.added.map(\.id), walkingMeters: result.meters, endMinutes: result.end))
        }
        return Plan(days: plans, unscheduled: unscheduled)
    }

    /// Bu mesafeden yakın yerler aynı bölge sayılır; yeni bir güne başlatılmaz (metre).
    static let regionSpacing = 2500.0

    /// Duraklar arası yürüme ve mola için durak başına ayrılan süre (dakika).
    static let travelAllowance = 20

    private struct Ordered {
        var order: [UUID]
        var starts: [UUID: Int]
        var end: Int
        var meters: Double
        var lastAdded: UUID?
        /// Yeni yerlerin (yuvarlanmış) başlangıçları ve en geç bitişi.
        var addedStarts: [UUID: Int]
        var addedEnd: Int
    }

    private static func order(_ existing: [Stop], _ added: [Stop],
                              bucket: (day: Date, weekday: Int, start: Int, hotel: Coordinate?, end: Coordinate?)) -> Ordered {
        let all = existing + added
        let located = all.filter { $0.coordinate != nil }
        let unlocated = all.filter { $0.coordinate == nil }
        let addedIDs = Set(added.map(\.id))
        let visits = located.map { stop in
            RouteOptimizer.Visit(coordinate: stop.coordinate!, duration: stop.durationMinutes,
                                 open: stop.openingHours.flatMap(OpeningHours.cached)?.intervals(onDay: bucket.weekday),
                                 fixedStart: addedIDs.contains(stop.id) ? nil : stop.startMinutes)
        }
        let dayStart = min(bucket.start, located.compactMap { addedIDs.contains($0.id) ? nil : $0.startMinutes }.min() ?? bucket.start)
        let route = RouteOptimizer.order(visits, from: bucket.hotel, to: bucket.end, dayStart: dayStart)
        let schedule = RouteOptimizer.schedule(route, visits: visits, from: bucket.hotel, dayStart: dayStart)
        var starts: [UUID: Int] = [:]
        var end = bucket.start
        for index in route {
            let stop = located[index]
            let begin = schedule.starts[index] ?? bucket.start
            if addedIDs.contains(stop.id) { starts[stop.id] = Int((Double(begin) / 5).rounded(.up)) * 5 }
            end = max(end, begin + stop.durationMinutes)
        }
        let path = (bucket.hotel.map { [$0] } ?? []) + route.map { located[$0].coordinate! }
            + (bucket.hotel != nil && !route.isEmpty ? (bucket.end.map { [$0] } ?? []) : [])
        let lastAdded = route.reversed().map { located[$0].id }.first { addedIDs.contains($0) }
        let addedEnd = located.filter { addedIDs.contains($0.id) }
            .compactMap { stop in starts[stop.id].map { $0 + stop.durationMinutes } }.max() ?? 0
        return Ordered(order: route.map { located[$0].id } + unlocated.map(\.id), starts: starts, end: end,
                       meters: Geo.routeDistance(path), lastAdded: lastAdded, addedStarts: starts, addedEnd: addedEnd)
    }

    /// Günün kullanılabilir penceresi; o gün inilen/kalkılan uçuşa göre `FlightDayTiming` ile daralır
    /// (iniş: gece otele hazır olma; kalkış: sabah otelinden yola çıkma).
    static func window(for day: Date, trip: Trip, settings: Settings, calendar: Calendar) -> (start: Int, end: Int) {
        var start = settings.dayStart
        var end = settings.dayEnd
        if let flight = trip.arrivalFlight(on: day, calendar: calendar),
           let arrival = FlightDayTiming.arrival(flight, firstPoint: trip.lodging(forNightOf: day, calendar: calendar)?.coordinate,
                                                 nationality: settings.nationality, fallback: calendar.timeZone) {
            start = max(start, arrival.readyAt)
        }
        if let flight = trip.departureFlight(on: day, calendar: calendar),
           let departure = FlightDayTiming.departure(flight, lastPoint: trip.lodging(forMorningOf: day, calendar: calendar)?.coordinate,
                                                     nationality: settings.nationality, fallback: calendar.timeZone) {
            end = min(end, departure.leaveBy)
        }
        return (start, max(start, end))
    }

    /// Planı seyahate uygular: yerleştirilen fikirler ilgili güne durak olarak (yeni kimlikle) taşınır,
    /// günlerin sırası güncellenir. Mevcut durakların saatlerine dokunulmaz.
    public static func apply(_ plan: Plan, to trip: inout Trip, calendar: Calendar = .current) {
        let ideas = Dictionary(trip.ideaList.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var newIDs: [UUID: UUID] = [:]
        for day in plan.days {
            for id in day.added {
                guard var stop = ideas[id] else { continue }
                stop.id = UUID()
                stop.day = calendar.startOfDay(for: day.day)
                stop.startMinutes = day.starts[id]
                newIDs[id] = stop.id
                trip.stops.append(stop)
            }
            for (order, id) in day.order.enumerated() {
                let target = newIDs[id] ?? id
                if let index = trip.stops.firstIndex(where: { $0.id == target }) { trip.stops[index].order = order }
            }
        }
        trip.ideas?.removeAll { newIDs[$0.id] != nil }
        if trip.ideas?.isEmpty == true { trip.ideas = nil }
    }
}
