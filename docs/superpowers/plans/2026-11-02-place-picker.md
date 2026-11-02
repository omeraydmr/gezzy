# Yer ekle (harita önde, popülerliğe göre) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `AddStopSheet` and `PlaceSuggestionsSheet` with one map-first "Yer ekle" screen whose suggestions and search results are ranked by Wikipedia + community popularity.

**Architecture:** Pure ranking logic lives in GezzyKit (`PlaceRanking`, unit-tested). The app gets an `@Observable` `PlacePickerModel` (loading, search, add/undo) and three thin SwiftUI views: a full-screen map, a non-dismissable bottom drawer with detents, and a manual-entry form. A new `StopDetailsSheet` lets users set time/note after adding, since the add flow no longer asks.

**Tech Stack:** Swift 5.9+, SwiftUI, MapKit for SwiftUI (iOS 17), XCTest, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-11-02-place-picker-design.md`

## Global Constraints

- iOS deployment target 17.0. No iOS 18-only API without `#available`.
- UI text is Turkish, written as the localization key (`String(localized: "…")` / `Text("…")`), matching existing code. English values go in `ios/Gezzy/Resources/Localizable.xcstrings`.
- Code comments in Turkish, short, same style as surrounding files.
- No new dependencies, no server changes, no paid place APIs.
- Popularity labels: "Çok popüler" (≥ 0,8), "Popüler" (≥ 0,5), community: "Gezginler seçti · N kişi". No stars.
- Ranking constants: community bonus 0,1; match floor 0,35; weights 0,55 similarity / 0,35 popularity / 0,10 proximity; proximity range 15 km; search limit 25. Exact match = normalized similarity 1,0 → always on top.
- After adding files run `cd ios && xcodegen generate` (the `.xcodeproj` is generated and git-ignored).
- Unit tests: `cd ios/Packages/GezzyKit && swift test --filter <Name>`.
- App build: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build -quiet`.
- Commit messages: imperative English sentence, like the existing history ("Add …", "Replace …"), ending with the `Co-Authored-By` line.

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `ios/Packages/GezzyKit/Sources/GezzyKit/PlaceRanking.swift` | Create | Popularity percentiles, Wikipedia+community merge, badges, browse and search ordering |
| `ios/Packages/GezzyKit/Tests/GezzyKitTests/PlaceRankingTests.swift` | Create | Tests for the above |
| `ios/Gezzy/Features/Plan/StopDetailsSheet.swift` | Create | `StopFormFields` (shared fields) + `StopDetailsSheet` (edit an existing stop) |
| `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerModel.swift` | Create | Screen state: center, pool, next groups, search, filter, target, added/undo |
| `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerMap.swift` | Create | Map with numbered suggestion pins, faded plan pins, hotel, focus |
| `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerList.swift` | Create | Drawer: header, target menu, search field, filter chips, rows, banners |
| `ios/Gezzy/Features/Plan/PlacePicker/ManualPlaceForm.swift` | Create | "Elle ekle" form |
| `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerSheet.swift` | Create | Composes map + drawer, city chips, framing, close |
| `ios/Gezzy/Features/Plan/PlanSection.swift` | Modify | Open picker; add "Düzenle" to stop menu |
| `ios/Gezzy/Features/Plan/IdeasCard.swift` | Modify | One "Yer ekle" button |
| `ios/Gezzy/Features/Plan/AddStopSheet.swift` | Delete | Replaced |
| `ios/Gezzy/Features/Plan/AutoPlanViews.swift` | Modify | Remove `PlaceSuggestionsSheet`; keep `PlanCenter`, `AutoPlanSheet` |
| `ios/Gezzy/Resources/Localizable.xcstrings` | Modify | English values for new strings |

Note: the spec put data loading inside `PlacePickerSheet.swift`; this plan moves it to `PlacePickerModel.swift` so the sheet file stays small. Behaviour is unchanged. The spec was also tightened while planning (§1 framing, §2 exact match and Apple results); the spec file reflects that.

---

### Task 1: `PlaceRanking` (GezzyKit)

**Files:**
- Create: `ios/Packages/GezzyKit/Sources/GezzyKit/PlaceRanking.swift`
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/PlaceRankingTests.swift`

**Interfaces:**
- Consumes: `PlaceSuggestions.Suggestion` (fields `id`, `name`, `kind`, `category`, `coordinate`, `score`, `contributors`; methods `matches(_ stop: Stop) -> Bool`, `stop(day: Date) -> Stop`), `PlaceMatch.queryVariants(_:)`, `PlaceMatch.similarity(_:_:)`, `PlaceMatch.normalize(_:)`, `Geo.distance(_:_:)`.
- Produces:
  - `PlaceRanking.Badge` — `.community(Int)`, `.veryPopular`, `.popular`
  - `PlaceRanking.Ranked` — `suggestion: PlaceSuggestions.Suggestion`, `popularity: Double`, `id: String`, `badge: Badge?`; `init(suggestion:popularity:)`
  - `PlaceRanking.pool(wikipedia: [Suggestion], community: [Suggestion]) -> [Ranked]`
  - `PlaceRanking.browse(_ pool: [Ranked], center: Coordinate?) -> [Ranked]`
  - `PlaceRanking.search(_ query: String, pool: [Ranked], mapResults: [Suggestion], center: Coordinate?) -> [Ranked]`
  - `PlaceRanking.badge(popularity: Double, contributors: Int?) -> Badge?`

- [ ] **Step 1: Write the failing tests**

Create `ios/Packages/GezzyKit/Tests/GezzyKitTests/PlaceRankingTests.swift`:

```swift
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

    func testSearchIsLimited() {
        let many = (0..<40).map { place("wiki/\($0)", "Museu \($0)", score: $0 + 1, slot: $0) }
        let ranked = PlaceRanking.search("museu", pool: PlaceRanking.pool(wikipedia: many, community: []),
                                         mapResults: [], center: center)
        XCTAssertEqual(ranked.count, PlaceRanking.searchLimit)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/GezzyKit && swift test --filter PlaceRankingTests`
Expected: build FAIL — `cannot find 'PlaceRanking' in scope`.

- [ ] **Step 3: Implement `PlaceRanking`**

Create `ios/Packages/GezzyKit/Sources/GezzyKit/PlaceRanking.swift`:

```swift
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

    public static let veryPopularThreshold = 0.8
    public static let popularThreshold = 0.5
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

    public static func badge(popularity: Double, contributors: Int?) -> Badge? {
        if let contributors { return .community(contributors) }
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
            if let index = wiki.firstIndex(where: { place.matches($0.suggestion.stop(day: .distantPast)) }) {
                result.append(Ranked(suggestion: place, popularity: min(1, max(popularity, wiki[index].popularity) + communityBonus)))
                wiki.remove(at: index)
            } else {
                result.append(Ranked(suggestion: place, popularity: popularity))
            }
        }
        return result + wiki
    }

    /// Arama yokken: popülerlik azalan, eşitlikte merkeze yakın olan önce.
    public static func browse(_ pool: [Ranked], center: Coordinate?) -> [Ranked] {
        pool.sorted { a, b in
            if a.popularity != b.popularity { return a.popularity > b.popularity }
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
            let stop = result.stop(day: .distantPast)
            if let known = pool.first(where: { $0.suggestion.matches(stop) }) {
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios/Packages/GezzyKit && swift test --filter PlaceRankingTests`
Expected: all 10 tests PASS.

If `testExactNameBeatsMorePopularPrefixMatch` fails because "rossıo" does not normalize to "rossio": `PlaceMatch.normalize` maps `ı` → `i`, so similarity must be 1; check that `queryVariants` includes the folded form. Do not change test expectations.

- [ ] **Step 5: Run the whole GezzyKit suite**

Run: `cd ios/Packages/GezzyKit && swift test`
Expected: all tests PASS (no regressions).

- [ ] **Step 6: Commit**

```bash
git add ios/Packages/GezzyKit/Sources/GezzyKit/PlaceRanking.swift ios/Packages/GezzyKit/Tests/GezzyKitTests/PlaceRankingTests.swift
git commit -m "Rank place suggestions by popularity

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Stop editing (`StopDetailsSheet` + "Düzenle")

**Files:**
- Create: `ios/Gezzy/Features/Plan/StopDetailsSheet.swift`
- Modify: `ios/Gezzy/Features/Plan/PlanSection.swift` (state near line 14, sheets near line 117, `menu(for:index:in:)` near line 237)

**Interfaces:**
- Consumes: `Stop`, `StopKind.title`, `StopKind.symbol`, `AppFormat.duration(minutes:)`, `TripStore.update(_:_:)`.
- Produces:
  - `StopFormFields(stop: Binding<Stop>, showsTime: Bool = true)` — a `View` that emits form rows (no `Section`)
  - `StopDetailsSheet(stop: Stop, onSave: (Stop) -> Void)`

- [ ] **Step 1: Create the shared fields and the edit sheet**

Create `ios/Gezzy/Features/Plan/StopDetailsSheet.swift`:

```swift
import SwiftUI
import GezzyKit

/// Durağın ad, tür, saat, süre ve not alanları; düzenleme ve elle ekleme formları paylaşır.
struct StopFormFields: View {
    @Binding var stop: Stop
    var showsTime = true

    var body: some View {
        TextField("Durak adı", text: $stop.name)
        Picker("Tür", selection: $stop.kind) {
            ForEach(StopKind.allCases, id: \.self) { kind in
                Label(kind.title, systemImage: kind.symbol).tag(kind)
            }
        }
        if showsTime {
            Toggle("Saat belirle", isOn: Binding(
                get: { stop.startMinutes != nil },
                set: { stop.startMinutes = $0 ? (stop.startMinutes ?? 10 * 60) : nil }))
            if let minutes = stop.startMinutes {
                DatePicker("Başlangıç", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        stop.startMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    }), displayedComponents: .hourAndMinute)
            }
        }
        Stepper("Süre: \(AppFormat.duration(minutes: stop.durationMinutes))", value: $stop.durationMinutes, in: 15...600, step: 15)
        TextField("Not (ör. Rezervasyon gerekli)", text: $stop.note)
    }
}

/// Plandaki bir durağın ayrıntılarını düzenler.
struct StopDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Stop
    let onSave: (Stop) -> Void

    init(stop: Stop, onSave: @escaping (Stop) -> Void) {
        _draft = State(initialValue: stop)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { StopFormFields(stop: $draft) }
            }
            .navigationTitle("Durağı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        var saved = draft
                        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                        saved.note = saved.note.trimmingCharacters(in: .whitespaces)
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wire "Düzenle" into the plan's stop menu**

In `ios/Gezzy/Features/Plan/PlanSection.swift`:

Add state next to `editingHours` (line 14):

```swift
    @State private var editingStop: Stop?
```

Add a sheet right after the `.sheet(item: $editingHours) { … }` block:

```swift
        .sheet(item: $editingStop) { stop in
            StopDetailsSheet(stop: stop) { saved in
                store.update(trip.id) { trip in
                    if let index = trip.stops.firstIndex(where: { $0.id == saved.id }) { trip.stops[index] = saved }
                }
            }
        }
```

In `menu(for:index:in:)`, insert as the first item (before "Yukarı taşı"):

```swift
        Button("Düzenle", systemImage: "pencil") { editingStop = stop }
```

- [ ] **Step 3: Generate and build**

Run: `cd ios && xcodegen generate && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build -quiet`
Expected: build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add ios/Gezzy/Features/Plan/StopDetailsSheet.swift ios/Gezzy/Features/Plan/PlanSection.swift
git commit -m "Let stops be edited after they are added

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `PlacePickerModel`

**Files:**
- Create: `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerModel.swift`

**Interfaces:**
- Consumes: `PlaceRanking` (Task 1); `PlanCenter.find(for:leg:)`, `PlaceSuggestionService.shared.suggestions(around:excluding:)`, `CommunityService.shared.nearby(_:)`, `.next(after:)`, `.isConfigured`, `.report(_:reason:)`, `PlaceSearch.places(_:city:countryCode:center:limit:)`, `PlaceSearch.kind(for:)`, `TripStore.update(_:_:)`, `Trip.cityLegs`, `Trip.leg(on:)`.
- Produces (`@MainActor @Observable final class PlacePickerModel`):
  - `enum Target: Hashable { case day(Date), ideas }`
  - `enum Filter: CaseIterable, Hashable { case all, sight, food, activity }` with `kind: StopKind?`, `title: String`
  - `struct NextGroup: Identifiable { anchor: String; places: [PlaceRanking.Ranked] }`
  - `init(trip: Trip, target: Target, openingDay: Date)`
  - vars: `target`, `filter`, `query`, `legID: UUID?`, `focusedID: String?`
  - read-only: `center: Coordinate?`, `isLoading: Bool`, `errorText: String?`, `noCenter: Bool`, `isSearching: Bool`, `added: [String: Stop.ID]`
  - `rows: [PlaceRanking.Ranked]`, `visibleNextGroups: [NextGroup]`, `numbered: [PlaceRanking.Ranked]`, `number(of: String) -> Int?`
  - `leg(in: Trip) -> TripLeg`
  - `load(trip: Trip) async`, `search(trip: Trip) async`
  - `toggle(_ item: PlaceRanking.Ranked, store: TripStore, trip: Trip)`, `insert(_ stop: Stop, store: TripStore, tripID: Trip.ID)`
  - `report(_ item: PlaceRanking.Ranked, reason: CommunityService.ReportReason)`

- [ ] **Step 1: Create the model**

Create `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerModel.swift`:

```swift
import SwiftUI
import GezzyKit

/// "Yer ekle" ekranının durumu: öneri havuzu, "sonra genelde" bölümleri, arama, filtre, hedef ve bu oturumda
/// eklenenler (geri almak için).
@MainActor
@Observable
final class PlacePickerModel {
    enum Target: Hashable {
        case day(Date)
        case ideas
    }

    enum Filter: CaseIterable, Hashable {
        case all, sight, food, activity

        var kind: StopKind? {
            switch self {
            case .all: nil
            case .sight: .sight
            case .food: .food
            case .activity: .activity
            }
        }

        var title: String {
            switch self {
            case .all: String(localized: "Tümü")
            case .sight: String(localized: "Görülecek")
            case .food: String(localized: "Yeme-içme")
            case .activity: String(localized: "Aktivite")
            }
        }
    }

    struct NextGroup: Identifiable {
        let anchor: String
        let places: [PlaceRanking.Ranked]
        var id: String { anchor }
    }

    var target: Target
    var filter: Filter = .all
    var query = ""
    /// Çok şehirli seyahatte seçili şehir; nil ise açılış gününün şehri.
    var legID: UUID?
    /// Haritada ve listede vurgulanan öneri.
    var focusedID: String?

    private(set) var center: Coordinate?
    private(set) var isLoading = false
    private(set) var errorText: String?
    /// Şehrin konumu bulunamadı: yalnızca arama çalışır.
    private(set) var noCenter = false
    private(set) var isSearching = false
    /// Bu oturumda eklenen öneri → eklenen durağın kimliği.
    private(set) var added: [String: Stop.ID] = [:]

    private var pool: [PlaceRanking.Ranked] = []
    private var nextGroups: [NextGroup] = []
    /// nil: arama yok.
    private var searchResults: [PlaceRanking.Ranked]?
    private let openingDay: Date

    init(trip: Trip, target: Target, openingDay: Date) {
        self.target = target
        self.openingDay = openingDay
    }

    func leg(in trip: Trip) -> TripLeg {
        trip.cityLegs.first { $0.id == legID } ?? trip.leg(on: openingDay)
    }

    // MARK: Görünen liste

    var isFiltering: Bool { searchResults != nil }

    var rows: [PlaceRanking.Ranked] {
        let base = searchResults ?? pool
        guard let kind = filter.kind else { return base }
        return base.filter { $0.suggestion.kind == kind }
    }

    var visibleNextGroups: [NextGroup] {
        searchResults == nil && filter == .all ? nextGroups : []
    }

    /// Haritadaki ve listedeki numaraların sırası: önce "sonra genelde" bölümleri, sonra ana liste.
    var numbered: [PlaceRanking.Ranked] {
        var seen: Set<String> = []
        return (visibleNextGroups.flatMap(\.places) + rows).filter { seen.insert($0.id).inserted }
    }

    func number(of id: String) -> Int? {
        numbered.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    // MARK: Yükleme

    func load(trip: Trip) async {
        errorText = nil
        noCenter = false
        isLoading = true
        defer { isLoading = false }
        guard let center = await PlanCenter.find(for: trip, leg: leg(in: trip)) else {
            self.center = nil
            noCenter = true
            pool = []
            nextGroups = []
            return
        }
        self.center = center
        let existing = trip.stops + trip.ideaList
        async let community = CommunityService.shared.nearby(center)
        async let next = loadNextGroups(trip: trip, excluding: existing)
        do {
            let wikipedia = try await PlaceSuggestionService.shared.suggestions(around: center, excluding: existing)
            let fresh = await community.filter { suggestion in !existing.contains(where: suggestion.matches) }
            let groups = await next
            // "Sonra genelde" bölümünde çıkanlar ana listede tekrar edilmez.
            let shown = Set(groups.flatMap(\.places).map(\.id))
            withAnimation {
                pool = PlaceRanking.browse(PlaceRanking.pool(wikipedia: wikipedia, community: fresh), center: center)
                    .filter { !shown.contains($0.id) }
                nextGroups = groups
            }
        } catch {
            pool = []
            nextGroups = []
            errorText = String(localized: "Öneriler alınamadı; internet bağlantını kontrol et.")
        }
    }

    /// Plandaki son iki konumlu yer için "sonra nereye" önerileri (topluluk havuzu).
    private func loadNextGroups(trip: Trip, excluding existing: [Stop]) async -> [NextGroup] {
        guard CommunityService.shared.isConfigured else { return [] }
        let anchors = trip.stops.filter { $0.coordinate != nil && $0.kind != .transport && $0.kind != .stay }
            .sorted { ($0.day, $0.order) < ($1.day, $1.order) }.suffix(2)
        var groups: [NextGroup] = []
        for anchor in anchors.reversed() {
            let places = await CommunityService.shared.next(after: anchor.coordinate!)
                .filter { suggestion in !existing.contains(where: suggestion.matches) }
            if !places.isEmpty {
                groups.append(NextGroup(anchor: anchor.name, places: PlaceRanking.pool(wikipedia: [], community: places)))
            }
        }
        return groups
    }

    // MARK: Arama

    /// `query` değişince çağrılır (350 ms gecikmeyle). İki harften kısaysa arama kapanır.
    func search(trip: Trip) async {
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard typed.count >= 2 else {
            searchResults = nil
            isSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        let leg = leg(in: trip)
        let found = await PlaceSearch.places(typed, city: leg.destination.city, countryCode: leg.destination.countryCode,
                                             center: center, limit: 8)
        guard !Task.isCancelled else { return }
        let existing = trip.stops + trip.ideaList
        let mapped = found.map { result in
            let kind = PlaceSearch.kind(for: result.item.pointOfInterestCategory)
            return PlaceSuggestions.Suggestion(id: "map/\(result.id)", name: result.name, kind: kind, category: kind.title,
                                               coordinate: result.coordinate, openingHours: nil, duration: 60, score: 0)
        }.filter { suggestion in added[suggestion.id] != nil || !existing.contains(where: suggestion.matches) }
        withAnimation {
            searchResults = PlaceRanking.search(typed, pool: pool + nextGroups.flatMap(\.places), mapResults: mapped,
                                                center: center)
        }
    }

    // MARK: Ekleme

    /// Öneriyi hedefe ekler; eklenmişse geri alır.
    func toggle(_ item: PlaceRanking.Ranked, store: TripStore, trip: Trip) {
        if let stopID = added[item.id] {
            store.update(trip.id) { trip in
                trip.stops.removeAll { $0.id == stopID }
                trip.ideas?.removeAll { $0.id == stopID }
            }
            added[item.id] = nil
        } else {
            let stop = item.suggestion.stop(day: trip.startDate)
            insert(stop, store: store, tripID: trip.id)
            added[item.id] = stop.id
        }
    }

    /// Durağı hedefe yazar: güne eklenirse günün sonuna, saatsiz.
    func insert(_ stop: Stop, store: TripStore, tripID: Trip.ID) {
        let target = target
        store.update(tripID) { trip in
            var stop = stop
            stop.startMinutes = nil
            switch target {
            case .ideas:
                stop.day = trip.startDate
                trip.ideas = (trip.ideas ?? []) + [stop]
            case .day(let day):
                stop.day = day
                stop.order = (trip.stops(on: day).map(\.order).max() ?? -1) + 1
                trip.stops.append(stop)
            }
        }
    }

    /// Bildirilen topluluk yeri listeden hemen kalkar; sunucuda yeterince bildirilince herkesten gizlenir.
    func report(_ item: PlaceRanking.Ranked, reason: CommunityService.ReportReason) {
        withAnimation {
            pool.removeAll { $0.id == item.id }
            searchResults?.removeAll { $0.id == item.id }
            nextGroups = nextGroups.map { NextGroup(anchor: $0.anchor, places: $0.places.filter { $0.id != item.id }) }
                .filter { !$0.places.isEmpty }
        }
        Task { try? await CommunityService.shared.report(item.suggestion, reason: reason) }
    }
}
```

Note: `insert` keeps a manually entered `startMinutes` out on purpose; time is set afterwards with "Düzenle" (Task 2), per spec §3.

- [ ] **Step 2: Generate and build**

Run: `cd ios && xcodegen generate && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build -quiet`
Expected: build succeeds. (`PlanCenter` still lives in `AutoPlanViews.swift`, so it resolves.)

- [ ] **Step 3: Commit**

```bash
git add ios/Gezzy/Features/Plan/PlacePicker/PlacePickerModel.swift
git commit -m "Add the place picker model

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Picker views (map, drawer, manual form, sheet)

**Files:**
- Create: `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerMap.swift`
- Create: `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerList.swift`
- Create: `ios/Gezzy/Features/Plan/PlacePicker/ManualPlaceForm.swift`
- Create: `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerSheet.swift`

**Interfaces:**
- Consumes: `PlacePickerModel` (Task 3), `StopFormFields` (Task 2), `PlaceRanking.Ranked`/`Badge` (Task 1), design system: `NumberedPin(number:accent:size:)`, `Accent.cycle(_:)`, `Accent.green`, `Accent.gray`, `Tag(text:accent:)`, `Color.ink/ink2/ink3/success/food`, `MapFraming.position(_:)`, `AppFormat.distance(meters:)`, `AppFormat.duration(minutes:)`, `AppFormat.dayPill(_:)`, `TripStore.trip(_:)`.
- Produces: `PlacePickerSheet(trip: Trip, target: PlacePickerModel.Target, openingDay: Date)` — presented with `.fullScreenCover`. Stores only `trip.id` and reads the live trip from `TripStore`, so adds show up immediately.

- [ ] **Step 1: Map view**

Create `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerMap.swift`:

```swift
import MapKit
import SwiftUI
import GezzyKit

/// Önerilen yerler listedeki numarasıyla; plandaki duraklar ve otel soluk, yalnızca bağlam için.
/// Bu oturumda eklenenler yeşil onay pini.
struct PlacePickerMap: View {
    let trip: Trip
    @Bindable var model: PlacePickerModel
    @Binding var position: MapCameraPosition
    let onTapPin: (String) -> Void

    private var contextStops: [Stop] {
        let addedIDs = Set(model.added.values)
        let stops: [Stop] = switch model.target {
        case .day(let day): trip.stops(on: day)
        case .ideas: trip.ideaList
        }
        return stops.filter { $0.coordinate != nil && !addedIDs.contains($0.id) }
    }

    private var hotel: Lodging? {
        if case .day(let day) = model.target { return trip.lodging(forMorningOf: day) }
        return nil
    }

    var body: some View {
        Map(position: $position) {
            ForEach(contextStops) { stop in
                let c = stop.coordinate!
                Annotation(stop.name, coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                           anchor: .center) {
                    Circle()
                        .fill(Color.ink3)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
            if let hotel, let c = hotel.coordinate {
                Annotation(hotel.name, coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                           anchor: .center) {
                    Image(systemName: "bed.double.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Accent.gray.base, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
            ForEach(Array(model.numbered.enumerated()), id: \.element.id) { index, item in
                let c = item.suggestion.coordinate
                let isFocused = model.focusedID == item.id
                Annotation(item.suggestion.name, coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                           anchor: .bottom) {
                    pin(number: index + 1, isAdded: model.added[item.id] != nil)
                        .scaleEffect(isFocused ? 1.25 : 1)
                        .animation(.spring(duration: 0.25), value: isFocused)
                        .onTapGesture { onTapPin(item.id) }
                }
                .annotationTitles(isFocused ? .visible : .hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    @ViewBuilder
    private func pin(number: Int, isAdded: Bool) -> some View {
        if isAdded {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.success, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                .accessibilityLabel(Text("Eklendi"))
        } else {
            NumberedPin(number: number, accent: Accent.cycle(number - 1), size: 30)
        }
    }
}
```

- [ ] **Step 2: Drawer view**

Create `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerList.swift`:

```swift
import SwiftUI
import GezzyKit

/// Alttaki çekmece: hedef, arama, filtre ve popülerliğe göre sıralı liste.
struct PlacePickerList: View {
    @Environment(TripStore.self) private var store
    let trip: Trip
    @Bindable var model: PlacePickerModel
    @Binding var detent: PresentationDetent
    let onFocus: (String) -> Void
    let onRetry: () -> Void
    let onDone: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var isAddingManually = false

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            filterChips
            ScrollViewReader { proxy in
                List {
                    banners
                    ForEach(model.visibleNextGroups) { group in
                        Section {
                            ForEach(group.places) { row($0) }
                        } header: {
                            Text("\(group.anchor) sonrası gezginler genelde")
                        }
                    }
                    Section {
                        ForEach(model.rows) { row($0) }
                        if model.rows.isEmpty && !model.isLoading && model.errorText == nil && !model.noCenter {
                            Text(model.isFiltering ? String(localized: "Aramaya uyan yer bulunamadı.")
                                                   : String(localized: "Bu şehir için yeni öneri bulunamadı."))
                                .foregroundStyle(Color.ink2)
                        }
                        Button {
                            isAddingManually = true
                        } label: {
                            Label("Listede yok mu? Elle ekle", systemImage: "square.and.pencil")
                        }
                    } footer: {
                        Text("Popülerlik Wikipedia'da son 30 günde okunma ve Gezzy gezginlerinin seçimlerinden gelir.")
                    }
                }
                .listStyle(.insetGrouped)
                .onChange(of: model.focusedID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { detent = .large }
        }
        .sheet(isPresented: $isAddingManually) {
            ManualPlaceForm(initialName: model.query, day: trip.startDate) { stop in
                model.insert(stop, store: store, tripID: trip.id)
            }
        }
        .sensoryFeedback(.success, trigger: model.added.count)
    }

    // MARK: Üst kısım

    private var header: some View {
        HStack {
            Menu {
                Button {
                    model.target = .ideas
                } label: {
                    Label("Fikirler", systemImage: "lightbulb")
                }
                ForEach(Array(trip.days().enumerated()), id: \.element) { index, day in
                    Button(String(localized: "\(index + 1). gün · \(AppFormat.dayPill(day))")) { model.target = .day(day) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Ekleneceği yer:").foregroundStyle(Color.ink2)
                    Text(targetTitle).foregroundStyle(Color.ink).bold()
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(Color.ink2)
                }
                .font(.subheadline)
            }
            Spacer()
            Button("Bitti", action: onDone).bold()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var targetTitle: String {
        switch model.target {
        case .ideas: return String(localized: "Fikirler")
        case .day(let day):
            let number = (trip.days().firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } ?? 0) + 1
            return String(localized: "\(number). gün")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.ink3)
            TextField("\(model.leg(in: trip).destination.city) içinde ara", text: $model.query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if model.isSearching {
                ProgressView().controlSize(.small)
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ink3)
                }
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlacePickerModel.Filter.allCases, id: \.self) { filter in
                    let isOn = model.filter == filter
                    Button(filter.title) { withAnimation { model.filter = filter } }
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.white : Color.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isOn ? Color.ink : Color(.tertiarySystemFill), in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: Bantlar

    @ViewBuilder
    private var banners: some View {
        if model.isLoading && model.rows.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("\(model.leg(in: trip).destination.city) için yerler aranıyor…").foregroundStyle(Color.ink2)
            }
        }
        if let errorText = model.errorText {
            Section {
                Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(Color.food)
                Button("Tekrar dene", action: onRetry)
            }
        }
        if model.noCenter && !model.isFiltering {
            Label("Şehrin konumu bulunamadı. Aramak için bir yer adı yaz.", systemImage: "magnifyingglass")
                .foregroundStyle(Color.ink2)
        }
    }

    // MARK: Satır

    @ViewBuilder
    private func row(_ item: PlaceRanking.Ranked) -> some View {
        let content = rowContent(item).id(item.id)
        if item.suggestion.contributors != nil {
            content.contextMenu {
                Menu("Bildir", systemImage: "flag") {
                    ForEach(CommunityService.ReportReason.allCases) { reason in
                        Button(reason.title) { model.report(item, reason: reason) }
                    }
                }
            }
        } else {
            content
        }
    }

    private func rowContent(_ item: PlaceRanking.Ranked) -> some View {
        let isAdded = model.added[item.id] != nil
        let number = model.number(of: item.id) ?? 0
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(isAdded ? Color.success : Accent.cycle(number - 1).base, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.suggestion.name).foregroundStyle(Color.ink).lineLimit(2)
                if let badge = item.badge { badgeView(badge) }
                Text(detail(item)).font(.caption).foregroundStyle(Color.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.spring(duration: 0.25)) { model.toggle(item, store: store, trip: trip) }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isAdded ? Color.success : Color.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? String(localized: "Eklemeyi geri al") : String(localized: "Ekle"))
        }
        .contentShape(Rectangle())
        .onTapGesture { onFocus(item.id) }
        .listRowBackground(model.focusedID == item.id ? Color.success.opacity(0.08) : nil)
    }

    @ViewBuilder
    private func badgeView(_ badge: PlaceRanking.Badge) -> some View {
        switch badge {
        case .community(let count):
            Label(String(localized: "Gezginler seçti · \(count) kişi"), systemImage: "person.3.sequence.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(Color.success)
        case .veryPopular:
            Label("Çok popüler", systemImage: "flame.fill").font(.caption.weight(.semibold)).foregroundStyle(Color.food)
        case .popular:
            Label("Popüler", systemImage: "chart.line.uptrend.xyaxis").font(.caption.weight(.semibold)).foregroundStyle(Color.ink2)
        }
    }

    private func detail(_ item: PlaceRanking.Ranked) -> String {
        var parts = [item.suggestion.category, AppFormat.duration(minutes: item.suggestion.duration)]
        if let center = model.center {
            parts.append(String(localized: "Merkeze \(AppFormat.distance(meters: Geo.distance(center, item.suggestion.coordinate)))"))
        }
        return parts.joined(separator: " · ")
    }
}
```

- [ ] **Step 3: Manual form**

Create `ios/Gezzy/Features/Plan/PlacePicker/ManualPlaceForm.swift`:

```swift
import SwiftUI
import GezzyKit

/// Listede olmayan yeri elle ekleme: ad, tür, süre. Saat ve not sonradan "Düzenle" ile verilir.
struct ManualPlaceForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Stop
    let onAdd: (Stop) -> Void

    init(initialName: String, day: Date, onAdd: @escaping (Stop) -> Void) {
        _draft = State(initialValue: Stop(day: day, order: 0, name: initialName.trimmingCharacters(in: .whitespaces),
                                          kind: .sight))
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { StopFormFields(stop: $draft, showsTime: false) }
            }
            .navigationTitle("Elle ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        var stop = draft
                        stop.name = stop.name.trimmingCharacters(in: .whitespaces)
                        stop.note = stop.note.trimmingCharacters(in: .whitespaces)
                        onAdd(stop)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 4: Sheet that composes them**

Create `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerSheet.swift`:

```swift
import MapKit
import SwiftUI
import GezzyKit

/// "Yer ekle": üstte harita, altta kapatılamayan çekmece. Plan ve Fikirler buradan doldurulur.
/// `.fullScreenCover` ile açılır.
struct PlacePickerSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let tripID: Trip.ID
    @State private var model: PlacePickerModel
    @State private var position: MapCameraPosition = .automatic
    @State private var detent: PresentationDetent = .medium
    @State private var showsDrawer = true

    /// Çekmecenin en küçük hâli: harita baskın.
    static let peek = PresentationDetent.fraction(0.3)

    init(trip: Trip, target: PlacePickerModel.Target, openingDay: Date) {
        tripID = trip.id
        _model = State(initialValue: PlacePickerModel(trip: trip, target: target, openingDay: openingDay))
    }

    var body: some View {
        if let trip = store.trip(tripID) {
            content(trip)
        } else {
            Color.clear.onAppear { dismiss() }
        }
    }

    private func content(_ trip: Trip) -> some View {
        PlacePickerMap(trip: trip, model: model, position: $position) { id in
            focus(id, trip: trip)
            if detent == Self.peek { detent = .medium }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { cityChips(trip) }
        .sheet(isPresented: $showsDrawer) {
            PlacePickerList(trip: trip, model: model, detent: $detent,
                            onFocus: { focus($0, trip: trip) },
                            onRetry: { Task { await model.load(trip: trip) } },
                            onDone: close)
                .presentationDetents([Self.peek, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .task(id: model.legID) {
            await model.load(trip: trip)
        }
        .task(id: model.query) { await model.search(trip: trip) }
        // Liste (arama, filtre, şehir) değişince harita yeniden çerçevelenir; eklemek listeyi değiştirmez.
        .onChange(of: model.numbered.map(\.id), initial: true) { _, _ in frame(trip) }
    }

    @ViewBuilder
    private func cityChips(_ trip: Trip) -> some View {
        if trip.isMultiCity {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(trip.cityLegs) { leg in
                        let isOn = model.leg(in: trip).id == leg.id
                        Button(leg.destination.city) { model.legID = leg.id }
                            .font(.subheadline.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? Color.white : Color.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isOn ? AnyShapeStyle(Color.ink) : AnyShapeStyle(.regularMaterial), in: Capsule())
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.top, 8)
        }
    }

    /// İlk 10 öneri ve plandaki duraklar birlikte sığar.
    private func frame(_ trip: Trip) {
        var points = model.numbered.prefix(10).map(\.suggestion.coordinate)
        switch model.target {
        case .day(let day): points += trip.stops(on: day).compactMap(\.coordinate)
        case .ideas: points += trip.ideaList.compactMap(\.coordinate)
        }
        if points.isEmpty, let center = model.center { points = [center] }
        guard !points.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.4)) {
            position = MapFraming.position(points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
        }
    }

    private func focus(_ id: String, trip: Trip) {
        model.focusedID = id
        guard let item = model.numbered.first(where: { $0.id == id }) else { return }
        let c = item.suggestion.coordinate
        withAnimation(.easeInOut(duration: 0.4)) {
            position = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                                         distance: 2500))
        }
    }

    /// Önce çekmece, sonra ekran kapanır; iç içe sunumu aynı anda kapatmak SwiftUI'da güvenilir değil.
    private func close() {
        showsDrawer = false
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            dismiss()
        }
    }
}
```

- [ ] **Step 5: Generate and build**

Run: `cd ios && xcodegen generate && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build -quiet`
Expected: build succeeds. Fix compile errors in place (common ones: `Lodging.coordinate` name, `Accent.gray` existence — check `ios/Gezzy/DesignSystem/Theme.swift` `enum Accent` and use an existing case if `gray` is missing).

- [ ] **Step 6: Commit**

```bash
git add ios/Gezzy/Features/Plan/PlacePicker
git commit -m "Add the map-first place picker screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Switch entry points and remove the old sheets

**Files:**
- Modify: `ios/Gezzy/Features/Plan/PlanSection.swift:117-119`
- Modify: `ios/Gezzy/Features/Plan/IdeasCard.swift` (state lines 10-11, header button lines 27-33, pill lines 40-46, empty hint line 36, sheets lines 111-116)
- Modify: `ios/Gezzy/Features/Plan/AutoPlanViews.swift` (delete `PlaceSuggestionsSheet`, lines 5 up to the `PlanCenter` doc comment)
- Delete: `ios/Gezzy/Features/Plan/AddStopSheet.swift`
- Modify: `ios/Gezzy/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `PlacePickerSheet(trip:target:openingDay:)` (Task 4).

- [ ] **Step 1: Plan day entry point**

In `PlanSection.swift` replace:

```swift
        .sheet(isPresented: $isAddingStop) {
            AddStopSheet(trip: trip, day: plan.day)
        }
```

with:

```swift
        .fullScreenCover(isPresented: $isAddingStop) {
            PlacePickerSheet(trip: trip, target: .day(plan.day), openingDay: plan.day)
        }
```

- [ ] **Step 2: Ideas card entry point**

In `IdeasCard.swift`:

1. Replace the two state vars `isAdding` and `isSuggesting` with one:

```swift
    @State private var isPicking = false
```

2. Delete the header's `plus` circle button (the `Button { isAdding = true } … .accessibilityLabel("Fikir ekle")` block) so the header is `Label` + count + `Spacer()`.

3. Replace the "Yer öner" pill:

```swift
                Button {
                    isPicking = true
                } label: {
                    Label("Yer ekle", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
```

4. Change the empty hint text to:

```swift
                EmptyHint(symbol: "lightbulb", text: String(localized: "Gitmek istediğin yerleri ekle; sonra otomatik rota günlere dağıtsın."))
```

5. Replace the two sheets (`AddStopSheet` and `PlaceSuggestionsSheet`) with:

```swift
        .fullScreenCover(isPresented: $isPicking) {
            PlacePickerSheet(trip: trip, target: .ideas, openingDay: day)
        }
```

- [ ] **Step 3: Delete the old sheets**

```bash
git rm ios/Gezzy/Features/Plan/AddStopSheet.swift
```

In `AutoPlanViews.swift` delete the whole `struct PlaceSuggestionsSheet: View { … }` (from its doc comment `/// Gidilen şehirde görülecek yer önerileri; …` through its closing brace), keeping the imports, `enum PlanCenter` and `struct AutoPlanSheet`.

Then check nothing else references them:

Run: `grep -rn "AddStopSheet\|PlaceSuggestionsSheet\|isSuggesting\|isAdding\b" ios/Gezzy`
Expected: no output.

- [ ] **Step 4: Generate and build**

Run: `cd ios && xcodegen generate && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build -quiet`
Expected: build succeeds. Building also adds the new keys to `Localizable.xcstrings` (state "new").

- [ ] **Step 5: English strings**

Open `ios/Gezzy/Resources/Localizable.xcstrings` and give each new key an `en` value (follow the JSON shape of an existing key such as `"Önerilen yerler"`). Keys and values:

| Key | en |
|---|---|
| `Yer ekle` | `Add place` |
| `Ekleneceği yer:` | `Add to:` |
| `Fikirler` | `Ideas` (exists — skip if present) |
| `%lld. gün` | `Day %lld` |
| `%lld. gün · %@` | `Day %lld · %@` |
| `%@ içinde ara` | `Search in %@` |
| `Aramayı temizle` | `Clear search` |
| `Tümü` | `All` |
| `Görülecek` | `Sights` |
| `Yeme-içme` | `Food & drink` |
| `Çok popüler` | `Very popular` |
| `Popüler` | `Popular` |
| `Listede yok mu? Elle ekle` | `Not listed? Add it yourself` |
| `Elle ekle` | `Add manually` |
| `Popülerlik Wikipedia'da son 30 günde okunma ve Gezzy gezginlerinin seçimlerinden gelir.` | `Popularity comes from Wikipedia views in the last 30 days and picks by Gezzy travellers.` |
| `Şehrin konumu bulunamadı. Aramak için bir yer adı yaz.` | `Couldn't find the city. Type a place name to search.` |
| `Merkeze %@` | `%@ from centre` |
| `Eklendi` | `Added` |
| `Eklemeyi geri al` | `Undo add` |
| `Durağı düzenle` | `Edit stop` |
| `Düzenle` | `Edit` |
| `Kaydet` | `Save` (exists — skip if present) |
| `Gitmek istediğin yerleri ekle; sonra otomatik rota günlere dağıtsın.` | `Add places you want to visit; then let auto route spread them over the days.` |

Then confirm no new key is left without English:

Run: `cd ios && python3 -c "import json;d=json.load(open('Gezzy/Resources/Localizable.xcstrings'));print([k for k,v in d['strings'].items() if k and 'en' not in v.get('localizations',{}) and v.get('extractionState')!='stale'])"`
Expected: `[]` (or only keys that were already missing before this work — compare with `git stash` if unsure).

Remove keys now marked `"extractionState" : "stale"` that belonged only to the deleted sheets ("Önerilen yerler", "Önerilerde ya da haritada ara", "Yer öner", "Fikir ekle", "Durak ekle" stays — still used in `PlanSection`).

- [ ] **Step 6: Build again and commit**

Run: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build -quiet`
Expected: success.

```bash
git add -A ios/Gezzy
git commit -m "Open the place picker from the plan and ideas; drop the old add sheets

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Verify in the simulator

**Files:** none (fixes go back to the file that owns the bug, with a follow-up commit).

- [ ] **Step 1: Run all package tests**

Run: `cd ios/Packages/GezzyKit && swift test`
Expected: all PASS.

- [ ] **Step 2: Launch on simulator**

Build and run Gezzy on "iPhone Air" (use the `run` skill or the iOS Simulator tool: build with the command in Global Constraints, then `launch` the built `.app` from DerivedData).

- [ ] **Step 3: Check each scenario and screenshot it**

With a single-city Lizbon trip that has at least two located stops on day 1:

1. Day 1 → "Durak ekle": picker opens full screen, drawer at half height, map shows numbered pins + grey plan pins + hotel. List order: "sonra genelde" sections (if server configured), then badges "Çok popüler" first.
2. Tap pin 3 → drawer row 3 highlighted and scrolled into view; pin grows and shows its title.
3. Tap a row → map flies to it.
4. Filter "Yeme-içme" → only food rows; pins and numbers match the list.
5. Type "jeronimos" → drawer goes to full height; Jerónimos is first; clear → popular list returns.
6. Type the full name of a less popular place → it is first.
7. Tap **+** on two places → ✓ and green pins, haptic; tap ✓ on one → removed from plan. "Bitti" → both screens close; day 1 shows the remaining added stop at the end.
8. Long-press that stop → "Düzenle" → set 14:00 and a note → saved and shown in the plan.
9. Ideas card → "Yer ekle" → target shows "Fikirler"; change target to "2. gün" via the menu → next add lands on day 2.
10. "Listede yok mu? Elle ekle" with query "Test kafe" → form prefilled → Ekle → appears in the target.
11. Multi-city trip (Lizbon → Porto): city chips on top; switching city reloads the list and re-frames the map.
12. Airplane mode (Network Link Conditioner or turn off Mac Wi-Fi): error banner + "Tekrar dene"; plan pins still visible; manual add still works.

Expected: every scenario behaves as described. Fix anything that doesn't, rebuild, re-check that scenario, commit the fix.

- [ ] **Step 4: Final commit (only if fixes were made)**

```bash
git add -A ios
git commit -m "Fix place picker issues found in simulator testing

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
