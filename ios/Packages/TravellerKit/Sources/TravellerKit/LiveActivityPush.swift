import Foundation

/// Canlı uçuş kartının sunucuya kaydı: sunucu bu uçuşun durumunu izler ve değişince
/// kartı APNs üzerinden (uygulama kapalıyken de) günceller. Sunucu: depodaki `server/`.
public struct LiveActivityRegistration: Codable, Hashable, Sendable {
    /// ActivityKit push token'ı (onaltılık).
    public var pushToken: String
    /// "development" (Xcode'dan kurulum) ya da "production" (TestFlight/App Store).
    public var environment: String
    /// Kart metinlerinin dili ("tr" ya da "en").
    public var language: String
    public var flightNumber: String
    /// Planlanan kalkışın havalimanı yerel tarihi, "yyyy-MM-dd" (AeroDataBox sorgusu için).
    public var localDate: String
    public var scheduledDeparture: Date
    public var scheduledArrival: Date
    public var seat: String?
    public var gate: String?

    public init(pushToken: String, environment: String, language: String, flight: FlightSegment) {
        self.pushToken = pushToken
        self.environment = environment
        self.language = language
        flightNumber = FlightStatusParser.normalizedNumber(flight.flightNumber)
        localDate = Self.localDate(flight.departure, timeZone: flight.departureTimeZone)
        scheduledDeparture = flight.departure
        scheduledArrival = flight.arrival
        seat = flight.seat
        gate = flight.gate
    }

    static func localDate(_ date: Date, timeZone: String?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Token verisini onaltılık metne çevirir.
    public static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
