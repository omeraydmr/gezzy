import Foundation

public enum Geo {
    /// Ortalama yürüme hızı: 4,8 km/s = 80 m/dk.
    public static let walkingMetersPerMinute = 80.0

    /// İki nokta arasındaki büyük daire mesafesi (metre).
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Ardışık noktalar arasındaki toplam mesafe (metre).
    public static func routeDistance(_ points: [Coordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Noktaları kenarlarda pay bırakarak kapsayan bölge (harita görüntüsü için).
    public struct Bounds: Hashable, Sendable {
        public var center: Coordinate
        public var latitudeSpan: Double
        public var longitudeSpan: Double
    }

    public static func bounds(_ points: [Coordinate], padding: Double = 0.3, minimumSpan: Double = 0.01) -> Bounds {
        guard let first = points.first else {
            return Bounds(center: Coordinate(latitude: 0, longitude: 0), latitudeSpan: 180, longitudeSpan: 360)
        }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in points {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        return Bounds(center: Coordinate(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                      latitudeSpan: max(minimumSpan, (maxLat - minLat) * (1 + padding * 2)),
                      longitudeSpan: max(minimumSpan, (maxLon - minLon) * (1 + padding * 2)))
    }

    /// Kuş uçuşu mesafeden tahmini yürüme süresi; sokak dolambacı için 1,25 çarpanı.
    public static func walkingMinutes(meters: Double) -> Int {
        Int((meters * 1.25 / walkingMetersPerMinute).rounded(.up))
    }
}

/// Yapay zekâ kullanmayan basit rota sıralayıcı.
public enum RouteOptimizer {
    /// İlk noktayı sabit tutarak en yakın komşu sezgiseli + 2-opt iyileştirmesiyle ziyaret sırası döndürür.
    /// Dönen dizi, giriş dizisinin indekslerinden oluşur.
    public static func order(_ points: [Coordinate]) -> [Int] {
        guard points.count > 2 else { return Array(points.indices) }

        var route = [0]
        var remaining = Set(points.indices.dropFirst())
        while let last = route.last, !remaining.isEmpty {
            let next = remaining.min { lhs, rhs in
                let l = Geo.distance(points[last], points[lhs])
                let r = Geo.distance(points[last], points[rhs])
                return l != r ? l < r : lhs < rhs
            }!
            route.append(next)
            remaining.remove(next)
        }

        // 2-opt: kesişen kenarları açarak açık rotayı kısalt.
        var improved = true
        while improved {
            improved = false
            for i in 1..<(route.count - 1) {
                for j in (i + 1)..<route.count {
                    let before = length(route, points)
                    var candidate = route
                    candidate[i...j].reverse()
                    if length(candidate, points) + 0.5 < before {
                        route = candidate
                        improved = true
                    }
                }
            }
        }
        return route
    }

    static func length(_ route: [Int], _ points: [Coordinate]) -> Double {
        Geo.routeDistance(route.map { points[$0] })
    }
}
