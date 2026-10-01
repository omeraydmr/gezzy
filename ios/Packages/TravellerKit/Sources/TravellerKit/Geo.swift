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
