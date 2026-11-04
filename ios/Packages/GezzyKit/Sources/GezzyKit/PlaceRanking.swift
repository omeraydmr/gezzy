import Foundation

/// Yer önerilerini popülerliğe göre sıralar ve etiketler. Wikipedia okunma sayısı ile topluluk puanı farklı
/// ölçekte olduğu için her kaynak kendi içinde yüzdelik sıraya (0…1) çevrilir.
public enum PlaceRanking {
    public enum Badge: Hashable, Sendable {
        /// Gezzy kullanıcılarının gidip seçtiği yer; kişi sayısıyla.
        case community(Int)
        case veryPopular
        case popular
    }

    public struct Ranked: Hashable, Identifiable, Sendable {
        public var suggestion: PlaceSuggestions.Suggestion
        /// Şehir içinde 0…1.
        public var popularity: Double

        public init(suggestion: PlaceSuggestions.Suggestion, popularity: Double) {
            self.suggestion = suggestion
            self.popularity = popularity
        }

        public var id: String { suggestion.id }
        public var badge: Badge? { PlaceRanking.badge(popularity: popularity, contributors: suggestion.contributors) }
    }

    /// Rozetler seçici: ilk %5 "Çok popüler", ilk %20 "Popüler"; her satırda rozet anlamsızlaşıyordu.
    public static let veryPopularThreshold = 0.95
    public static let popularThreshold = 0.8
    /// Göz atarken merkeze yakınlığın payı: 12 km ötedeki biraz daha popüler yer merkezdekinin önüne geçmesin.
    public static let browseProximityWeight = 0.3
    /// Hem Wikipedia'da hem toplulukta olan yer için ek puan.
    public static let communityBonus = 0.1
    /// Bu benzerliğin altındaki öneriler aramada gösterilmez (tür eşleşmesi hariç).
    public static let matchFloor = 0.35
    public static let similarityWeight = 0.55
    public static let popularityWeight = 0.35
    public static let proximityWeight = 0.10
    /// Merkeze yakınlık puanı bu mesafede sıfırlanır (metre).
    public static let proximityRange = 15_000.0
    public static let searchLimit = 25

    /// Aynı yer: 80 m içindeyse ya da adı tutup 300 m içindeyse. Ad tek başına yetmez; şehrin öbür ucundaki
    /// "Museu …" yerleri birbirini silmesin.
    private static let samePlaceDistance = 80.0
    private static let samePlaceNameDistance = 300.0

    private static func isSamePlace(_ a: PlaceSuggestions.Suggestion, _ b: PlaceSuggestions.Suggestion) -> Bool {
        let distance = Geo.distance(a.coordinate, b.coordinate)
        if distance < samePlaceDistance { return true }
        return distance < samePlaceNameDistance
            && OpeningHoursLookup.bestMatch(for: a.name, in: [.init(name: b.name, openingHours: "")]) != nil
    }

    private static func isSameNamedPlace(_ a: PlaceSuggestions.Suggestion, _ b: PlaceSuggestions.Suggestion) -> Bool {
        Geo.distance(a.coordinate, b.coordinate) < samePlaceNameDistance
            && OpeningHoursLookup.bestMatch(for: a.name, in: [.init(name: b.name, openingHours: "")]) != nil
    }

    public static func badge(popularity: Double, contributors: Int?) -> Badge? {
        if let contributors, contributors > 0 { return .community(contributors) }
        if popularity >= veryPopularThreshold { return .veryPopular }
        if popularity >= popularThreshold { return .popular }
        return nil
    }

    /// Her puanın listedeki yüzdelik sırası: kendisi dışında kaç puan ≤ bu puan, bölü (n − 1).
    /// Eşit puanlar aynı (üst) sırayı alır; 0 puan hep 0.
    static func percentiles(_ scores: [Int]) -> [Double] {
        guard scores.count > 1 else { return scores.map { $0 > 0 ? 1 : 0 } }
        let sorted = scores.sorted()
        return scores.map { score in
            guard score > 0, let last = sorted.lastIndex(of: score) else { return 0 }
            return Double(last) / Double(scores.count - 1)
        }
    }

    /// Wikipedia ve topluluk önerilerini tek havuzda toplar. Aynı yer ikisinde de varsa topluluk kaydı kalır,
    /// popülerliği iki kaynağın büyüğü + `communityBonus`.
    public static func pool(wikipedia: [PlaceSuggestions.Suggestion],
                            community: [PlaceSuggestions.Suggestion]) -> [Ranked] {
        var wiki = zip(wikipedia, percentiles(wikipedia.map(\.score))).map { Ranked(suggestion: $0, popularity: $1) }
        var result: [Ranked] = []
        for (place, popularity) in zip(community, percentiles(community.map(\.score))) {
            if let index = wiki.firstIndex(where: { isSamePlace(place, $0.suggestion) }) {
                result.append(Ranked(suggestion: place, popularity: min(1, max(popularity, wiki[index].popularity) + communityBonus)))
                wiki.remove(at: index)
            } else {
                result.append(Ranked(suggestion: place, popularity: popularity))
            }
        }
        return result + wiki
    }

    /// Arama yokken: popülerlik + yakınlık payı azalan, eşitlikte merkeze yakın olan önce.
    public static func browse(_ pool: [Ranked], center: Coordinate?) -> [Ranked] {
        func score(_ item: Ranked) -> Double {
            let proximity = center.map { max(0, 1 - Geo.distance(item.suggestion.coordinate, $0) / proximityRange) } ?? 0
            return item.popularity + browseProximityWeight * proximity
        }
        return pool.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            if let center {
                let da = Geo.distance(a.suggestion.coordinate, center), db = Geo.distance(b.suggestion.coordinate, center)
                if da != db { return da < db }
            }
            return a.suggestion.name < b.suggestion.name
        }
    }

    /// Arama varken: adı birebir tutanlar en üstte, sonra benzerlik + popülerlik + yakınlık puanı.
    /// Havuzdaki öneriler eşiğe göre süzülür; Apple Haritalar sonuçları zaten aramaya göre geldiği için süzülmez,
    /// havuzdaki bir yerle eşleşirlerse o kayda (ve popülerliğine) dönüşür.
    public static func search(_ query: String, pool: [Ranked], mapResults: [PlaceSuggestions.Suggestion],
                              center: Coordinate?) -> [Ranked] {
        let variants = PlaceMatch.queryVariants(query)
        let folded = PlaceMatch.normalize(query)
        guard !variants.isEmpty, !folded.isEmpty else { return [] }
        func similarity(_ name: String) -> Double { variants.map { PlaceMatch.similarity($0, name) }.max() ?? 0 }

        var candidates = pool.filter { item in
            similarity(item.suggestion.name) >= matchFloor || PlaceMatch.normalize(item.suggestion.category).contains(folded)
        }
        for result in mapResults {
            // Aramada Apple sonucu yalnızca adı tutan, 300 m içindeki en yakın havuz kaydına dönüşür.
            let known = pool.filter { isSameNamedPlace($0.suggestion, result) }
                .min { Geo.distance($0.suggestion.coordinate, result.coordinate) < Geo.distance($1.suggestion.coordinate, result.coordinate) }
            if let known {
                if !candidates.contains(where: { $0.id == known.id }) { candidates.append(known) }
            } else if !candidates.contains(where: { $0.id == result.id }) {
                candidates.append(Ranked(suggestion: result, popularity: 0))
            }
        }

        func proximity(_ coordinate: Coordinate) -> Double {
            center.map { max(0, 1 - Geo.distance(coordinate, $0) / proximityRange) } ?? 0
        }
        let scored = candidates.map { item -> (item: Ranked, exact: Bool, score: Double) in
            let similar = similarity(item.suggestion.name)
            let score = similarityWeight * similar + popularityWeight * item.popularity
                + proximityWeight * proximity(item.suggestion.coordinate)
            return (item, similar >= 1, score)
        }
        return scored.sorted { a, b in
            if a.exact != b.exact { return a.exact }
            if a.score != b.score { return a.score > b.score }
            return a.item.suggestion.name < b.item.suggestion.name
        }.prefix(searchLimit).map(\.item)
    }
}
