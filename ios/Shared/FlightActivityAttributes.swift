import ActivityKit
import Foundation

/// Kilit ekranı ve Dynamic Island'daki canlı uçuş kartının verisi (uygulama ve widget eklentisi ortak kullanır).
struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var gate: String?
        var seat: String?
        var terminal: String?
        /// "Zamanında", "Rötarlı +40 dk", "Biniş" gibi kısa durum.
        var status: String
        /// Geçerli kalkış/varış (rötar varsa tahmini); geri sayım buna göre.
        var departure: Date
        var arrival: Date
        var isDelayed: Bool
        var isCanceled: Bool
    }

    var tripID: String
    var tripName: String
    var flightNumber: String
    var fromCode: String
    var fromCity: String
    var toCode: String
    var toCity: String
    /// Planlanan kalkış (rötar varsa üstü çizili gösterilir).
    var scheduledDeparture: Date
    /// Seyahat renginin onaltılık değeri (0xRRGGBB).
    var tint: UInt32
}
