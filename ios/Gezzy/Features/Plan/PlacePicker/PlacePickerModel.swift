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
        let mapped = found.map { result -> PlaceSuggestions.Suggestion in
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
