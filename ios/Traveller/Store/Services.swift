import CoreLocation
import Foundation
import TravellerKit

/// Avrupa Merkez Bankası referans kurları (Frankfurter, anahtarsız). Kurlar gün içinde önbellekte tutulur.
@MainActor
final class RateService {
    static let shared = RateService()
    private var cache: [String: (quote: CurrencyConverter.Quote, fetchedAt: Date)] = [:]

    func quote(from: String, to: String) async throws -> CurrencyConverter.Quote {
        let key = "\(from)-\(to)"
        if let cached = cache[key], Date().timeIntervalSince(cached.fetchedAt) < 6 * 3600 {
            return cached.quote
        }
        guard CurrencyConverter.isSupported(from), CurrencyConverter.isSupported(to),
              let url = CurrencyConverter.rateURL(from: from, to: to) else {
            throw ServiceError.unsupportedCurrency
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.badResponse }
        let quote = try CurrencyConverter.decodeQuote(data, to: to)
        cache[key] = (quote, Date())
        return quote
    }
}

/// Open-Meteo üzerinden seyahat tarihleri için hava özeti (anahtarsız).
@MainActor
final class WeatherFetcher {
    static let shared = WeatherFetcher()
    private var cache: [String: WeatherSummary] = [:]

    func summary(latitude: Double, longitude: Double, start: Date, end: Date) async throws -> WeatherSummary {
        guard let request = WeatherService.requestURL(latitude: latitude, longitude: longitude, start: start, end: end) else {
            throw ServiceError.badResponse
        }
        let key = request.url.absoluteString
        if let cached = cache[key] { return cached }
        let (data, response) = try await URLSession.shared.data(from: request.url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.badResponse }
        let summary = try WeatherService.decodeSummary(data, source: request.source)
        cache[key] = summary
        return summary
    }
}

enum DestinationGeocoder {
    /// Şehir + ülke adından koordinat bulur (Apple).
    static func coordinate(for destination: Destination) async -> Coordinate? {
        let query = "\(destination.city), \(Countries.name(destination.countryCode))"
        guard let placemark = try? await CLGeocoder().geocodeAddressString(query).first,
              let location = placemark.location else { return nil }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }
}

enum ServiceError: LocalizedError {
    case unsupportedCurrency, badResponse

    var errorDescription: String? {
        switch self {
        case .unsupportedCurrency: "Bu para birimi için güncel kur yok; kuru elle girebilirsin."
        case .badResponse: "Sunucuya ulaşılamadı."
        }
    }
}

extension TripStore {
    /// Seyahatin koordinatı yoksa şehirden bulup kaydeder.
    func ensureCoordinate(for id: Trip.ID) async -> Coordinate? {
        guard let trip = trip(id) else { return nil }
        if let coordinate = trip.destination.coordinate { return coordinate }
        guard let found = await DestinationGeocoder.coordinate(for: trip.destination) else { return nil }
        update(id) { $0.destination.coordinate = found }
        return found
    }
}
