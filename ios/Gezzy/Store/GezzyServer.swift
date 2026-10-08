import Foundation

/// Gezzy sunucusu (bkz. depodaki `server/`): topluluk öneri havuzu. `GEZZY_SERVER_HOST` boşsa kapalıdır.
enum GezzyServer {
    static var baseURL: URL? {
        guard let host = info("GezzyServerHost") else { return nil }
        return URL(string: host.hasPrefix("http") ? host : "https://\(host)")
    }

    static var isConfigured: Bool { baseURL != nil }

    static var apiKey: String? { info("GezzyServerKey") }

    private static func info(_ key: String) -> String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmingCharacters(in: .whitespaces)
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
