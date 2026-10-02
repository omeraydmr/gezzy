import ActivityKit
import Foundation
import TravellerKit

/// Canlı uçuş kartının push token'ını Traveller sunucusuna kaydeder (bkz. depodaki `server/`).
/// Topluluk önerileri (`CommunityService`) de aynı sunucuyu ve anahtarı kullanır.
/// `LIVE_ACTIVITY_SERVER_HOST` boşsa kapalıdır; kart yalnızca uygulama açıkken güncellenir.
enum LiveActivityPushClient {
    static var baseURL: URL? {
        guard let host = info("LiveActivityServerHost") else { return nil }
        return URL(string: host.hasPrefix("http") ? host : "https://\(host)")
    }

    static var isConfigured: Bool { baseURL != nil }

    static var apiKey: String? { info("LiveActivityServerKey") }

    private static func info(_ key: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static var environment: String {
        #if DEBUG
        "development"
        #else
        "production"
        #endif
    }

    static func register(token: Data, flight: FlightSegment) async {
        guard let baseURL else { return }
        let language = Bundle.main.preferredLocalizations.first == "tr" ? "tr" : "en"
        let registration = LiveActivityRegistration(pushToken: LiveActivityRegistration.hex(token),
                                                    environment: environment, language: language, flight: flight)
        var request = URLRequest(url: baseURL.appendingPathComponent("activities"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Traveller-Key") }
        request.httpBody = try? LiveActivityRegistration.encoder.encode(registration)
        _ = try? await URLSession.shared.data(for: request)
    }

    static func unregister(token: Data) async {
        guard let baseURL else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("activities/\(LiveActivityRegistration.hex(token))"))
        request.httpMethod = "DELETE"
        if let apiKey { request.setValue(apiKey, forHTTPHeaderField: "X-Traveller-Key") }
        _ = try? await URLSession.shared.data(for: request)
    }
}
