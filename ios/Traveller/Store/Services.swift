import CoreLocation
import Foundation
import ImageIO
import TravellerKit
import UIKit
import Vision

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

/// Makbuz fotoğrafındaki metni cihaz üzerinde (Vision) okuyup toplamı çıkarır; görüntü cihazdan çıkmaz.
enum ReceiptReader {
    static func read(_ image: UIImage) async -> ReceiptParser.Result? {
        guard let cgImage = image.cgImage else { return nil }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines: [String] = await Task.detached(priority: .userInitiated) { () -> [String] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["tr-TR", "en-US", "de-DE", "fr-FR", "it-IT", "es-ES", "pt-PT"]
            request.usesLanguageCorrection = false
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                return []
            }
            // Yukarıdan aşağıya sırala (Vision'da y ekseni aşağıdan yukarı artar).
            return (request.results ?? [])
                .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                .compactMap { $0.topCandidates(1).first?.string }
        }.value
        return ReceiptParser.parse(lines: lines)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// OpenStreetMap (Overpass API) üzerinden bir durağın açılış saatlerini bulur.
@MainActor
final class OpeningHoursService {
    static let shared = OpeningHoursService()
    private let endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    func lookup(name: String, coordinate: Coordinate) async throws -> String? {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let query = OpeningHoursLookup.query(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        request.httpBody = Data("data=\(encoded)".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ServiceError.badResponse }
        let candidates = try OpeningHoursLookup.decodeCandidates(data)
        return OpeningHoursLookup.bestMatch(for: name, in: candidates)?.openingHours
    }
}
