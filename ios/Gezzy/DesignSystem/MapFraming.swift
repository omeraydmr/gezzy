import MapKit
import SwiftUI

/// Harita kamerası: noktaları kenar payıyla sığdırır ama en az bir semt genişliğinde (varsayılan ~4 km) gösterir;
/// tek nokta seçilince bina ölçeğine yakınlaşıp çevreyi kaybettirmesin.
enum MapFraming {
    static func position(_ coordinates: [CLLocationCoordinate2D], minimumSpan: CLLocationDistance = 4_000,
                         padding: Double = 1.4) -> MapCameraPosition {
        guard let region = region(coordinates, minimumSpan: minimumSpan, padding: padding) else { return .automatic }
        return .region(region)
    }

    /// Çekmece haritanın altını kapatıyorsa: noktalar haritanın üstteki `visibleFraction` kadarlık görünür
    /// bölümüne sığar. Enlem aralığı 1/f katına çıkar, merkez güneye kayar (üst kenar sabit kalır).
    static func position(_ coordinates: [CLLocationCoordinate2D], visibleFraction: Double,
                         minimumSpan: CLLocationDistance = 4_000, padding: Double = 1.4) -> MapCameraPosition {
        guard let fitted = region(coordinates, minimumSpan: minimumSpan, padding: padding) else { return .automatic }
        let f = min(1, max(0.2, visibleFraction))
        let span = fitted.span.latitudeDelta
        let grown = span / f
        let center = CLLocationCoordinate2D(latitude: fitted.center.latitude - (grown - span) / 2,
                                            longitude: fitted.center.longitude)
        return .region(MKCoordinateRegion(center: center,
                                          span: MKCoordinateSpan(latitudeDelta: grown, longitudeDelta: fitted.span.longitudeDelta)))
    }

    /// Tek noktaya yakın bakış: nokta görünür bölümün ortasına gelir (merkez güneye kayar).
    /// Görünür yükseklik yaklaşık kamera mesafesi kadar kabul edilir.
    static func focus(_ coordinate: CLLocationCoordinate2D, distance: CLLocationDistance,
                      visibleFraction: Double) -> MapCameraPosition {
        let f = min(1, max(0.2, visibleFraction))
        let shiftMeters = distance * (1 / f - 1) / 2
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude - shiftMeters / 111_320,
                                            longitude: coordinate.longitude)
        return .camera(MapCamera(centerCoordinate: center, distance: distance))
    }

    private static func region(_ coordinates: [CLLocationCoordinate2D], minimumSpan: CLLocationDistance,
                               padding: Double) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let metersPerDegreeLon = 111_320 * max(0.2, cos(center.latitude * .pi / 180))
        let height = max((maxLat - minLat) * 111_320 * padding, minimumSpan)
        let width = max((maxLon - minLon) * metersPerDegreeLon * padding, minimumSpan)
        return MKCoordinateRegion(center: center, latitudinalMeters: height, longitudinalMeters: width)
    }
}
