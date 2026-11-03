import XCTest
@testable import GezzyKit

final class PlaceRankingTests: XCTestCase {
    typealias Suggestion = PlaceSuggestions.Suggestion
    let center = Coordinate(latitude: 38.7139, longitude: -9.1394)

    /// Her yer ayrı bir noktada (~1,1 km arayla) ki konumdan eşleşmesinler.
    func place(_ id: String, _ name: String, score: Int, slot: Int, kind: StopKind = .sight,
               category: String = "Simge yapı", contributors: Int? = nil) -> Suggestion {
        var suggestion = Suggestion(id: id, name: name, kind: kind, category: category,
                                    coordinate: Coordinate(latitude: 38.70 + Double(slot) * 0.01, longitude: -9.15),
                                    openingHours: nil, duration: 60, score: score)
        suggestion.contributors = contributors
        return suggestion
    }

    func sixWiki() -> [Suggestion] {
        [place("wiki/1", "Alfama", score: 100, slot: 0),
         place("wiki/2", "Gulbenkian", score: 200, slot: 1, category: "Müze"),
         place("wiki/3", "Belém Tower", score: 300, slot: 2),
         place("wiki/4", "Rossio", score: 400, slot: 3),
         place("wiki/5", "Oceanário", score: 500, slot: 4),
         place("wiki/6", "Santa Justa Lift", score: 600, slot: 5)]
    }

    func testPopularityIsPercentileWithinSource() {
        let ranked = PlaceRanking.pool(wikipedia: sixWiki(), community: [])
        let byName = Dictionary(uniqueKeysWithValues: ranked.map { ($0.suggestion.name, $0.popularity) })
        XCTAssertEqual(byName["Alfama"]!, 0, accuracy: 1e-9)
        XCTAssertEqual(byName["Belém Tower"]!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(byName["Oceanário"]!, 0.8, accuracy: 1e-9)
        XCTAssertEqual(byName["Santa Justa Lift"]!, 1, accuracy: 1e-9)
    }

    func testTiesShareTopPercentileAndZeroScoreStaysZero() {
        let tied = PlaceRanking.pool(wikipedia: [place("wiki/1", "Alfama", score: 50, slot: 0),
                                                 place("wiki/2", "Rossio", score: 50, slot: 1)], community: [])
        XCTAssertEqual(tied.map(\.popularity), [1, 1])
        let fallback = PlaceRanking.pool(wikipedia: [place("map/1", "Alfama", score: 0, slot: 0),
                                                    place("map/2", "Rossio", score: 0, slot: 1)], community: [])
        XCTAssertEqual(fallback.map(\.popularity), [0, 0], "MapKit yedek önerilerinin popülerliği yok")
    }

    func testBadges() {
        XCTAssertEqual(PlaceRanking.badge(popularity: 1, contributors: 4), .community(4))
        XCTAssertEqual(PlaceRanking.badge(popularity: 0.8, contributors: nil), .veryPopular)
        XCTAssertEqual(PlaceRanking.badge(popularity: 0.79, contributors: nil), .popular)
        XCTAssertEqual(PlaceRanking.badge(popularity: 0.5, contributors: nil), .popular)
        XCTAssertNil(PlaceRanking.badge(popularity: 0.49, contributors: nil))
        XCTAssertNil(PlaceRanking.badge(popularity: 0.1, contributors: 0), "0 katkıcı rozet olmaz")
    }

    func testCommunityPlaceMatchingWikipediaReplacesItWithBonus() {
        // "Belém Kulesi" Wikipedia'daki "Belém Tower" ile aynı noktada.
        let community = [place("community/9", "Belém Kulesi", score: 2, slot: 2, contributors: 3),
                         place("community/8", "Pastelaria Aloma", score: 7, slot: 9, kind: .food, contributors: 5)]
        let ranked = PlaceRanking.pool(wikipedia: sixWiki(), community: community)
        XCTAssertEqual(ranked.count, 7)
        XCTAssertFalse(ranked.contains { $0.id == "wiki/3" }, "Aynı yer iki kez gösterilmez")
        let belem = ranked.first { $0.id == "community/9" }!
        // Wikipedia 0,4, topluluk 0 → büyüğü + 0,1.
        XCTAssertEqual(belem.popularity, 0.5, accuracy: 1e-9)
        XCTAssertEqual(belem.badge, .community(3))
        XCTAssertEqual(ranked.first { $0.id == "community/8" }!.popularity, 1, accuracy: 1e-9)
    }

    func testBrowseSortsByPopularityThenDistance() {
        let near = place("wiki/1", "Rossio", score: 50, slot: 1)
        let far = place("wiki/2", "Alfama", score: 50, slot: 5)
        let top = place("wiki/3", "Oceanário", score: 90, slot: 9)
        let pool = PlaceRanking.pool(wikipedia: [far, near, top], community: [])
        XCTAssertEqual(PlaceRanking.browse(pool, center: center).map(\.id), ["wiki/3", "wiki/1", "wiki/2"])
    }

    func testExactNameBeatsMorePopularPrefixMatch() {
        let pool = PlaceRanking.pool(wikipedia: [place("wiki/1", "Rossio", score: 1, slot: 0),
                                                 place("wiki/2", "Rossio Square Café", score: 900, slot: 1),
                                                 place("wiki/3", "Alfama", score: 5, slot: 2)], community: [])
        let ids = PlaceRanking.search("rossıo", pool: pool, mapResults: [], center: center).map(\.id)
        XCTAssertEqual(ids, ["wiki/1", "wiki/2"], "Tam ad en üstte; benzemeyen Alfama elenir")
    }

    func testPrefixMatchesAreOrderedByPopularity() {
        let pool = PlaceRanking.pool(wikipedia: [place("wiki/1", "Museu do Fado", score: 1, slot: 0),
                                                 place("wiki/2", "Museu Nacional do Azulejo", score: 900, slot: 1)],
                                     community: [])
        let ids = PlaceRanking.search("museu", pool: pool, mapResults: [], center: center).map(\.id)
        XCTAssertEqual(ids, ["wiki/2", "wiki/1"])
    }

    func testCategoryMatchKeepsPlaceWithUnrelatedName() {
        let ids = PlaceRanking.search("müze", pool: PlaceRanking.pool(wikipedia: sixWiki(), community: []),
                                      mapResults: [], center: center).map(\.id)
        XCTAssertEqual(ids, ["wiki/2"], "Gulbenkian türünden (Müze) bulunur, diğerleri elenir")
    }

    func testMapResultTakesPoolPopularityAndIsNotRepeated() {
        let pool = PlaceRanking.pool(wikipedia: [place("wiki/1", "Mosteiro dos Jerónimos", score: 900, slot: 0),
                                                 place("wiki/2", "Alfama", score: 1, slot: 1)], community: [])
        let sameSpot = place("map/a", "Jerónimos Monastery", score: 0, slot: 0)
        let other = place("map/b", "Igreja de Santa Maria", score: 0, slot: 6)
        let ranked = PlaceRanking.search("jeronimos", pool: pool, mapResults: [sameSpot, other], center: center)
        XCTAssertEqual(ranked.map(\.id), ["wiki/1", "map/b"],
                       "Apple sonucu havuzdaki kayda dönüşür; eşleşmeyen Apple sonucu eşiğe takılmaz")
        XCTAssertEqual(ranked[1].popularity, 0)
    }

    func testMapResultWithDifferentNameNearPoolPlaceStaysSeparate() {
        let pool = PlaceRanking.pool(wikipedia: [place("wiki/1", "Rossio", score: 9, slot: 3)], community: [])
        var cafe = place("map/cafe", "Café Nicola", score: 0, slot: 3)
        cafe.coordinate = Coordinate(latitude: cafe.coordinate.latitude + 0.00045, longitude: cafe.coordinate.longitude)
        let ids = PlaceRanking.search("nicola", pool: pool, mapResults: [cafe], center: center).map(\.id)
        XCTAssertEqual(ids, ["map/cafe"], "Yakındaki farklı adlı yer Apple sonucunu silmez")
    }

    func testSearchIsLimited() {
        let many = (0..<40).map { place("wiki/\($0)", "Museu \($0)", score: $0 + 1, slot: $0) }
        let ranked = PlaceRanking.search("museu", pool: PlaceRanking.pool(wikipedia: many, community: []),
                                         mapResults: [], center: center)
        XCTAssertEqual(ranked.count, PlaceRanking.searchLimit)
    }

    func testSameNameFarApartStaysSeparateInPool() {
        // Aynı tür kelimeleri (museu, do) var ama üç km'den uzakta: farklı yerler.
        let community = [place("community/1", "Museu do Fado", score: 5, slot: 0, contributors: 2)]
        let ranked = PlaceRanking.pool(wikipedia: [place("wiki/1", "Museu Nacional do Azulejo", score: 9, slot: 3)],
                                       community: community)
        XCTAssertEqual(ranked.map(\.id).sorted(), ["community/1", "wiki/1"])
    }

    func testMapResultFarFromSameNamedPoolPlaceIsKept() {
        let pool = PlaceRanking.pool(wikipedia: [place("wiki/1", "Museu do Fado", score: 9, slot: 0)], community: [])
        let far = place("map/a", "Museu Nacional de Arte Antiga", score: 0, slot: 3)
        let ids = PlaceRanking.search("museu", pool: pool, mapResults: [far], center: center).map(\.id)
        XCTAssertEqual(ids.sorted(), ["map/a", "wiki/1"], "Uzaktaki Apple sonucu havuzdaki yerin yerini almaz")
    }

    func testSameNameWithinSmallDistanceStillMerges() {
        // Aynı ad, ~220 m: 80 m'den uzak ama 300 m içinde → aynı yer.
        var community = place("community/3", "Belém Tower", score: 0, slot: 2, contributors: 3)
        community.coordinate = Coordinate(latitude: community.coordinate.latitude + 0.002,
                                          longitude: community.coordinate.longitude)
        let ranked = PlaceRanking.pool(wikipedia: sixWiki(), community: [community])
        XCTAssertEqual(ranked.count, 6)
        XCTAssertEqual(ranked.first { $0.id == "community/3" }!.popularity, 0.5, accuracy: 1e-9)
        XCTAssertFalse(ranked.contains { $0.id == "wiki/3" })
    }
}
