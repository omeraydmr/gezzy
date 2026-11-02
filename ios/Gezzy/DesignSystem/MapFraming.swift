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
    /// `aspect` (genişlik/yükseklik) verilirse enlem bağlayıcı kenar olur: asgari genişlik (minimumSpan) yüzünden
    /// MapKit yüksekliği büyütüp merkezi kaydırmasın diye boylam aralığı görünür oranı aşmayacak kadar kısılır.
    static func position(_ coordinates: [CLLocationCoordinate2D], visibleFraction: Double, aspect: Double? = nil,
                         minimumSpan: CLLocationDistance = 4_000, padding: Double = 1.4) -> MapCameraPosition {
        guard let fitted = region(coordinates, minimumSpan: minimumSpan, padding: padding) else { return .automatic }
        let f = min(1, max(0.2, visibleFraction))
        let span = fitted.span.latitudeDelta
        let grown = span / f
        let center = CLLocationCoordinate2D(latitude: fitted.center.latitude - (grown - span) / 2,
                                            longitude: fitted.center.longitude)
        var lonDelta = fitted.span.longitudeDelta
        if let aspect, aspect > 0 {
            // Noktaların kendi (dolgulu) boylam genişliği korunur; yalnızca asgari genişlik kısılır.
            let lons = coordinates.map(\.longitude)
            let pointsLon = ((lons.max() ?? 0) - (lons.min() ?? 0)) * padding
            let metersPerDegreeLon = 111_320 * max(0.2, cos(fitted.center.latitude * .pi / 180))
            let aspectLon = grown * 111_320 * aspect / metersPerDegreeLon
            lonDelta = max(pointsLon, min(lonDelta, aspectLon))
        }
        return .region(MKCoordinateRegion(center: center,
                                          span: MKCoordinateSpan(latitudeDelta: grown, longitudeDelta: lonDelta)))
    }

    /// Tek noktaya yakın bakış: görünür bölümde ~`visibleMeters` dikey alan, nokta görünür bölümün ortasında.
    /// Toplam enlem aralığı S = visibleMeters / f; bölge merkezi noktanın (0.5 - f/2) x S güneyindedir,
    /// böylece nokta ekran merkezinin üstüne, görünür alanın ortasına düşer.
    /// `aspect` = harita genişliği/yüksekliği; boylam aralığı buna göre ayarlanır ki enlem bağlayıcı kenar kalsın
    /// (portre telefonda genişlik bağlarsa MapKit yüksekliği büyütür, nokta çekmeceye kayar). Yoksa 0,4 varsayılır.
    static func focus(_ coordinate: CLLocationCoordinate2D, visibleMeters: CLLocationDistance = 3_000,
                      visibleFraction: Double, aspect: Double? = nil) -> MapCameraPosition {
        let f = min(1, max(0.2, visibleFraction))
        let span = visibleMeters / f
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude - (0.5 - f / 2) * span / 111_320,
                                            longitude: coordinate.longitude)
        return .region(MKCoordinateRegion(center: center, latitudinalMeters: span,
                                          longitudinalMeters: span * (aspect.map { $0 > 0 ? $0 : 0.4 } ?? 0.4)))
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
