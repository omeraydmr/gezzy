import MapKit
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
    /// Haritadan seçilen yer: Apple Haritalar noktası ya da basılı tutup bırakılan iğne ("pin/…").
    var mapPick: PlaceSuggestions.Suggestion?
    /// Bırakılan iğnenin adı aranıyor.
    private(set) var isResolvingPick = false

    private(set) var center: Coordinate?
    private(set) var isLoading = false
    private(set) var errorText: String?
    /// Şehrin konumu bulunamadı: yalnızca arama çalışır.
    private(set) var noCenter = false
    private(set) var isSearching = false
    /// Bu oturumda eklenen öneri → eklenen durağın kimliği.
    private(set) var added: [String: Stop.ID] = [:]

    /// Havuz: "sonra genelde" yerleri de dahil; bölümde gösterilenler `rows` içinde süzülür.
    private var pool: [PlaceRanking.Ranked] = []
    private var nextGroups: [NextGroup] = []
    /// nil: arama yok.
    private var searchResults: [PlaceRanking.Ranked]?
    /// Eski (iptal edilmiş) yüklemelerin ve aramaların state yazmasını engeller.
    private var loadGeneration = 0
    private var searchGeneration = 0
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

    /// Ana liste: filtre uygulanır; bölümlerde görünen yerler burada tekrar edilmez. Filtre açıkken bölüm
    /// başlığı gizlenir ama yerler ana listede kalır.
    var rows: [PlaceRanking.Ranked] {
        let base = searchResults ?? pool
        let filtered = filter.kind.map { kind in base.filter { $0.suggestion.kind == kind } } ?? base
        let shownIDs = Set(visibleNextGroups.flatMap(\.places).map(\.id))
        return filtered.filter { !shownIDs.contains($0.id) }
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
        // Yeni yükleme eskisinin (ve açık aramanın) sonucunu geçersiz kılar.
        loadGeneration += 1
        searchGeneration += 1
        let generation = loadGeneration
        errorText = nil
        noCenter = false
        isLoading = true
        searchResults = nil
        isSearching = false
        focusedID = nil
        defer { if generation == loadGeneration { isLoading = false } }
        let found = await PlanCenter.find(for: trip, leg: leg(in: trip))
        // Iptal edilmiş ya da yerine yenisi başlamış yükleme state yazmaz.
        guard generation == loadGeneration, !Task.isCancelled else { return }
        guard let center = found else {
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
            guard generation == loadGeneration, !Task.isCancelled else { return }
            // "Sonra genelde" yerleri havuza da girer; aynı kimlik iki kez yazılmaz.
            var merged = PlaceRanking.pool(wikipedia: wikipedia, community: fresh)
            var ids = Set(merged.map(\.id))
            merged += groups.flatMap(\.places).filter { ids.insert($0.id).inserted }
            withAnimation {
                pool = PlaceRanking.browse(merged, center: center)
                nextGroups = groups
            }
        } catch {
            guard generation == loadGeneration, !Task.isCancelled else { return }
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
        // Aynı yer iki bölümde tekrar etmez; ilk bölüm kalır.
        var seen: Set<String> = []
        for anchor in anchors.reversed() {
            let places = await CommunityService.shared.next(after: anchor.coordinate!)
                .filter { suggestion in !existing.contains(where: suggestion.matches) }
            let ranked = PlaceRanking.pool(wikipedia: [], community: places).filter { seen.insert($0.id).inserted }
            if !ranked.isEmpty {
                groups.append(NextGroup(anchor: anchor.name, places: ranked))
            }
        }
        return groups
    }

    // MARK: Arama

    /// `query` değişince çağrılır (350 ms gecikmeyle). İki harften kısaysa arama kapanır.
    func search(trip: Trip) async {
        searchGeneration += 1
        let generation = searchGeneration
        let typed = query.trimmingCharacters(in: .whitespaces)
        guard typed.count >= 2 else {
            searchResults = nil
            isSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard generation == searchGeneration, !Task.isCancelled else { return }
        isSearching = true
        defer { if generation == searchGeneration { isSearching = false } }
        let leg = leg(in: trip)
        let found = await PlaceSearch.places(typed, city: leg.destination.city, countryCode: leg.destination.countryCode,
                                             center: center, limit: 8)
        guard generation == searchGeneration, !Task.isCancelled else { return }
        let existing = trip.stops + trip.ideaList
        // Kategorisiz sonuçlar sokak/adres; "Adres" etiketi alır.
        let addressIDs = Set(found.filter { $0.item.pointOfInterestCategory == nil }.map { "map/\($0.id)" })
        let mapped = found.map { result -> PlaceSuggestions.Suggestion in
            let kind = PlaceSearch.kind(for: result.item.pointOfInterestCategory)
            let isAddress = result.item.pointOfInterestCategory == nil
            return PlaceSuggestions.Suggestion(id: "map/\(result.id)", name: result.name, kind: kind,
                                               category: isAddress ? String(localized: "Adres") : kind.title,
                                               coordinate: result.coordinate, openingHours: nil, duration: 60, score: 0)
        }.filter { suggestion in added[suggestion.id] != nil || !existing.contains(where: suggestion.matches) }
        let ranked = PlaceRanking.search(typed, pool: pool, mapResults: mapped, center: center)
        // Adresler (tam eşleşme hariç) gerçek yerlerin arkasına; kendi aralarında sıra korunur.
        func isDemoted(_ item: PlaceRanking.Ranked) -> Bool {
            addressIDs.contains(item.id) && PlaceMatch.similarity(typed, item.suggestion.name) < 1
        }
        withAnimation {
            searchResults = ranked.filter { !isDemoted($0) } + ranked.filter(isDemoted)
        }
    }

    // MARK: Ekleme

    /// Öneriyi hedefe ekler; eklenmişse geri alır.
    func toggle(_ item: PlaceRanking.Ranked, store: TripStore, trip: Trip) {
        toggle(suggestion: item.suggestion, store: store, trip: trip)
    }

    func toggle(suggestion: PlaceSuggestions.Suggestion, store: TripStore, trip: Trip) {
        if let stopID = added[suggestion.id] {
            store.update(trip.id) { trip in
                trip.stops.removeAll { $0.id == stopID }
                trip.ideas?.removeAll { $0.id == stopID }
            }
            added[suggestion.id] = nil
        } else {
            var stop = suggestion.stop(day: trip.startDate)
            // Apple Haritalar önerisinde ve haritadan seçilende not kategoriyi tekrarlar; boş bırak.
            if suggestion.id.hasPrefix("map/") || suggestion.id.hasPrefix("pin/") { stop.note = "" }
            insert(stop, store: store, tripID: trip.id)
            added[suggestion.id] = stop.id
        }
    }

    // MARK: Haritadan seçme

    /// Haritadaki Apple Haritalar noktasına dokunuldu.
    func pick(feature: MapFeature) {
        let c = feature.coordinate
        let kind = PlaceSearch.kind(for: feature.pointOfInterestCategory)
        let name = feature.title ?? String(localized: "Seçilen yer")
        mapPick = PlaceSuggestions.Suggestion(id: "map/feature/\(name)/\(c.latitude),\(c.longitude)", name: name,
                                              kind: kind, category: kind.title, coordinate: Coordinate(latitude: c.latitude, longitude: c.longitude),
                                              openingHours: nil, duration: 60, score: 0)
    }

    /// Haritada basılı tutulan noktaya iğne bırakır; adı yakındaki yerden ya da adresten gelir.
    func drop(at c: CLLocationCoordinate2D) async {
        let id = "pin/\(c.latitude),\(c.longitude)"
        let coordinate = Coordinate(latitude: c.latitude, longitude: c.longitude)
        mapPick = PlaceSuggestions.Suggestion(id: id, name: String(localized: "İşaretli yer"), kind: .sight,
                                              category: String(localized: "Haritadan"), coordinate: coordinate,
                                              openingHours: nil, duration: 60, score: 0)
        isResolvingPick = true
        defer { if mapPick?.id == id { isResolvingPick = false } }
        let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
        var name: String?
        var kind = StopKind.sight
        // Önce 60 m içindeki en yakın adlı yer; yoksa adres.
        let request = MKLocalPointsOfInterestRequest(center: c, radius: 60)
        if let items = try? await MKLocalSearch(request: request).start().mapItems,
           let nearest = items.min(by: { location.distance(from: $0.placemark.location ?? location) <
                                         location.distance(from: $1.placemark.location ?? location) }),
           let found = nearest.name {
            name = found
            kind = PlaceSearch.kind(for: nearest.pointOfInterestCategory)
        } else if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            name = placemark.name ?? placemark.thoroughfare
        }
        guard mapPick?.id == id, added[id] == nil, let name else { return }
        mapPick?.name = name
        mapPick?.kind = kind
        if kind != .sight { mapPick?.category = kind.title }
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
