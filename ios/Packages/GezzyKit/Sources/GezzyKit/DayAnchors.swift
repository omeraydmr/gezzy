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

    /// O gün bu günün ülkesine inen, konumu bilinen havalimanına uçuş (yerel saatle), en son inen.
    /// Dönüş aktarmasının ülke içi bacağı (ayrılış uçuşuyla ya da sonra kalkan) varış sayılmaz.
    public func arrivalFlight(on day: Date, calendar: Calendar = .current) -> FlightSegment? {
        let country = destination(on: day, calendar: calendar).countryCode.uppercased()
        let leaving = departureFlight(on: day, calendar: calendar)
        return flights.filter { flight in
            guard let airport = Airports.airport(flight.toCode), airport.coordinate != nil else { return false }
            if let leaving, flight.departure >= leaving.departure { return false }
            return airport.countryCode.uppercased() == country
                && isSameDay(flight.localArrival(fallback: calendar.timeZone), day, calendar)
        }.max { $0.arrival < $1.arrival }
    }

    /// O gün bu günün ülkesinden ayrılış: o gün ülke dışına giden bir bacak varsa, o gün ülkedeki (konumu bilinen)
    /// bir havalimanından kalkan en erken bacak (OPO → LIS → IST'de OPO).
    public func departureFlight(on day: Date, calendar: Calendar = .current) -> FlightSegment? {
        let country = destination(on: day, calendar: calendar).countryCode.uppercased()
        let today = flights.filter { isSameDay($0.localDeparture(fallback: calendar.timeZone), day, calendar) }
        let leaves = today.contains { flight in
            guard let from = Airports.airport(flight.fromCode)?.countryCode.uppercased(),
                  let to = Airports.airport(flight.toCode)?.countryCode.uppercased() else { return false }
            return from == country && to != country
        }
        guard leaves else { return nil }
        return today.filter { flight in
            guard let airport = Airports.airport(flight.fromCode), airport.coordinate != nil else { return false }
            return airport.countryCode.uppercased() == country
        }.min { $0.departure < $1.departure }
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
