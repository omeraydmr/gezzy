import ActivityKit
import Foundation

/// Kilit ekranı ve Dynamic Island'daki canlı uçuş kartının verisi (uygulama ve widget eklentisi ortak kullanır).
struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var gate: String?
        var seat: String?
        /// "Zamanında", "Biniş başladı" gibi kısa durum.
        var status: String
    }

    var tripID: String
    var tripName: String
    var flightNumber: String
    var fromCode: String
    var fromCity: String
    var toCode: String
    var toCity: String
    var departure: Date
    var arrival: Date
    /// Seyahat renginin onaltılık değeri (0xRRGGBB).
    var tint: UInt32
}
