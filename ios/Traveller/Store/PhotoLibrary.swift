import CoreLocation
import Observation
import Photos
import TravellerKit
import UIKit

/// Fotoğraf arşivinden seyahat tarihlerindeki fotoğrafları okur ve küçük görsellerini verir.
/// Fotoğraflar cihazdan çıkmaz; yalnızca yerel kimlikleri ve konum/zaman bilgisi kullanılır.
@MainActor
@Observable
final class PhotoLibrary {
    static let shared = PhotoLibrary()

    private(set) var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    private let manager = PHCachingImageManager()
    private let thumbnails = NSCache<NSString, UIImage>()

    var canRead: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Seyahatin ilk gününün başından son gününün sonuna kadar çekilen fotoğraflar.
    func photos(for trip: Trip, calendar: Calendar = .current) async -> [PhotoClusterer.Photo] {
        guard canRead else { return [] }
        let start = calendar.startOfDay(for: trip.startDate)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: trip.endDate)) ?? trip.endDate
        return await Task.detached(priority: .userInitiated) { () -> [PhotoClusterer.Photo] in
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@ AND mediaType == %d",
                                            start as NSDate, end as NSDate, PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            let assets = PHAsset.fetchAssets(with: options)
            var result: [PhotoClusterer.Photo] = []
            result.reserveCapacity(assets.count)
            assets.enumerateObjects { asset, _, _ in
                guard let date = asset.creationDate else { return }
                let coordinate = asset.location.map {
                    Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                }
                result.append(PhotoClusterer.Photo(id: asset.localIdentifier, date: date, coordinate: coordinate))
            }
            return result
        }.value
    }

    /// Kare küçük görsel (piksel cinsinden kenar).
    func thumbnail(for id: String, side: CGFloat) async -> UIImage? {
        let key = "\(id)@\(Int(side))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let image: UIImage? = await withCheckedContinuation { continuation in
            manager.requestImage(for: asset, targetSize: CGSize(width: side, height: side), contentMode: .aspectFill,
                                 options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if let image { thumbnails.setObject(image, forKey: key) }
        return image
    }
}
