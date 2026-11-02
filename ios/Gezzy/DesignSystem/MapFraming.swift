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

    /// Tek noktaya yakın bakış: görünür bölümde ~`visibleMeters` dikey alan, nokta görünür bölümün ortasında.
    /// Toplam enlem aralığı S = visibleMeters / f; bölge merkezi noktanın (0.5 - f/2) x S güneyindedir,
    /// böylece nokta ekran merkezinin üstüne, görünür alanın ortasına düşer.
    static func focus(_ coordinate: CLLocationCoordinate2D, visibleMeters: CLLocationDistance = 3_000,
                      visibleFraction: Double) -> MapCameraPosition {
        let f = min(1, max(0.2, visibleFraction))
        let span = visibleMeters / f
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude - (0.5 - f / 2) * span / 111_320,
                                            longitude: coordinate.longitude)
        return .region(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span))
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
