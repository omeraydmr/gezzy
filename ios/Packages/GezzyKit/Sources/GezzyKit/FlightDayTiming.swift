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
