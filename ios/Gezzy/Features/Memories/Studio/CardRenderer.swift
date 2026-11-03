import MapKit
import SwiftUI
import UIKit
import GezzyKit

/// Paylaşım kartını görsele çevirir: fotoğrafları ve rota haritasını yükler, `ImageRenderer` ile 1080 px çizer.
@MainActor
enum CardRenderer {
    enum RenderError: Error {
        /// Harita görüntüsü alınamadı (çevrimdışı, MapKit hatası).
        case map
        case image
    }

    /// Kartın görseli. Gezzy işareti `effectiveShowsBrand` ile belirlenir: ücretsiz kullanıcıda hep çizilir.
    /// Rota şablonunda harita alınamazsa `RenderError.map` (yer tutuculu kart dışa verilmez).
    static func render(trip: Trip, config: ShareCardConfig, palette: TripPalette, isPremium: Bool,
                       width: CGFloat = 1080) async throws -> UIImage {
        var config = config
        config.showsBrand = config.effectiveShowsBrand(isPremium: isPremium)
        // Fotoğraflı şablon fotoğrafsız (yalnızca gradyan) dışa verilmez.
        guard config.canExport(hasRoute: hasRoute(trip)) else { throw RenderError.image }
        let ids = Array(config.photoIDs.prefix(ShareCardConfig.photoLimit(config.template).upperBound))
        // Kartpostal tam kaplar (story'de yumuşamasın); kolajda hücre başına 2 kat yeter.
        let maxPixelSize: CGFloat = config.template == .collage
            ? (width / CGFloat(ShareCardConfig.collageColumns(count: ids.count, format: config.format)) * 2).rounded()
            : 2400
        var photos: [UIImage] = []
        for id in ids {
            try Task.checkCancellation()
            if let image = await PhotoLibrary.shared.fullImage(for: id, maxPixelSize: maxPixelSize) {
                photos.append(image)
            }
        }
        let height = (width / config.format.aspect).rounded()
        var mapImage: UIImage?
        if config.template == .route {
            guard let image = await mapSnapshot(trip: trip, palette: palette, size: mapSize(format: config.format))
            else { throw RenderError.map }
            mapImage = image
        }
        try Task.checkCancellation()
        let content = CardTemplateView(trip: trip, summary: TripSummary.make(trip), config: config, photos: photos,
                                       mapImage: mapImage, palette: palette, width: width)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw RenderError.image }
        return image
    }

    /// Harita görüntüsünün ölçeği: 360 pt × 3 = 1080 px; harita etiketleri çıktıda okunur kalır.
    static let mapScale: CGFloat = 3

    /// Rota şablonundaki harita alanının boyutu (kartın üst %70'i), nokta; piksel = nokta × `mapScale`.
    static func mapSize(format: ShareCardConfig.Format) -> CGSize {
        CGSize(width: 360, height: ((360 / format.aspect) * 0.7).rounded())
    }

    // MARK: Rota

    /// Konumlu durağı olan günler: gün sırası (palet pin rengi) ve o günün koordinatları.
    nonisolated static func routeDays(_ trip: Trip) -> [(index: Int, coordinates: [Coordinate])] {
        trip.days().enumerated().compactMap { index, day in
            let coordinates = trip.stops(on: day).compactMap(\.coordinate)
            return coordinates.isEmpty ? nil : (index, coordinates)
        }
    }

    nonisolated static func hasRoute(_ trip: Trip) -> Bool {
        trip.stops.contains { $0.coordinate != nil }
    }

    /// Harita önbelleği ~15 MB ile sınırlı (story haritası ~6 MB); stüdyo kapanınca ve bellek uyarısında boşalır.
    private static let snapshots: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 15 * 1024 * 1024
        return cache
    }()

    static func clearMapCache() { snapshots.removeAllObjects() }

    /// Tüm konumlu durakları kapsayan harita (%20 pay); üzerine gün gün palet renginde rota ve numaralı daireler.
    /// `size` nokta (`mapScale` ile çizilir); sonuç seyahat + palet + boyut + durak konumlarına göre önbelleğe alınır.
    static func mapSnapshot(trip: Trip, palette: TripPalette, size: CGSize) async -> UIImage? {
        let days = routeDays(trip)
        let all = days.flatMap(\.coordinates)
        guard !all.isEmpty, size.width > 0, size.height > 0 else { return nil }
        var hasher = Hasher()
        for day in days {
            hasher.combine(day.index)
            hasher.combine(day.coordinates)
        }
        let key = "\(trip.id)-\(palette.id)-\(palette.accent)-\(Int(size.width))x\(Int(size.height))-\(hasher.finalize())"
        if let cached = snapshots.object(forKey: key as NSString) { return cached }

        let options = MKMapSnapshotter.Options()
        options.region = region(for: all)
        options.size = size
        options.scale = mapScale
        options.mapType = .mutedStandard
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }

        // Çizim nokta uzayında; ölçüler kart birimine (`u`) göre.
        let u = size.width / 360
        let format = UIGraphicsImageRendererFormat()
        format.scale = snapshot.image.scale
        let image = UIGraphicsImageRenderer(size: snapshot.image.size, format: format).image { context in
            snapshot.image.draw(at: .zero)
            let cg = context.cgContext
            let points = days.map { day in
                (day.index, day.coordinates.map {
                    snapshot.point(for: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                })
            }
            // Önce çizgiler, sonra daireler (daireler çizgilerin üstünde kalsın).
            cg.setLineCap(.round)
            cg.setLineJoin(.round)
            for (index, line) in points where line.count > 1 {
                cg.setStrokeColor(UIColor(palette.pin(index)).cgColor)
                cg.setLineWidth(4 * u)
                cg.addLines(between: line)
                cg.strokePath()
            }
            let radius = 9 * u
            let font = UIFont.systemFont(ofSize: 10 * u, weight: .bold)
            for (index, line) in points {
                let color = UIColor(palette.pin(index))
                for (number, point) in line.enumerated() {
                    let circle = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
                    cg.setFillColor(UIColor.white.cgColor)
                    cg.fillEllipse(in: circle.insetBy(dx: -2 * u, dy: -2 * u))
                    cg.setFillColor(color.cgColor)
                    cg.fillEllipse(in: circle)
                    let text = NSAttributedString(string: "\(number + 1)",
                                                  attributes: [.font: font, .foregroundColor: UIColor.white])
                    let textSize = text.size()
                    text.draw(at: CGPoint(x: point.x - textSize.width / 2, y: point.y - textSize.height / 2))
                }
            }
        }
        let bytes = Int(image.size.width * image.scale * image.size.height * image.scale) * 4
        snapshots.setObject(image, forKey: key as NSString, cost: bytes)
        return image
    }

    private static func region(for coordinates: [Coordinate]) -> MKCoordinateRegion {
        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0, maxLon = lons.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        // Her yanda %20 pay; tek durakta en az ~1 km.
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.01))
        return MKCoordinateRegion(center: center, span: span)
    }
}
