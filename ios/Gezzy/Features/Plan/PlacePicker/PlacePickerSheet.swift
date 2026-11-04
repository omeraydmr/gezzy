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
    /// Haritanın genişlik/yükseklik oranı; odak bölgesinde enlemi bağlayıcı kenar yapmak için.
    @State private var mapAspect: Double?
    /// Büyük çekmecede liste değişti; çekmece küçülünce yeniden çerçevelenecek.
    @State private var reframePending = false
    /// Haritada dokunulan Apple Haritalar noktası.
    @State private var selectedFeature: MapFeature?

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
        PlacePickerMap(trip: trip, model: model, position: $position, selection: $selectedFeature) { id in
            model.mapPick = nil
            let target = detent == Self.peek ? PresentationDetent.medium : detent
            focus(id, trip: trip, detent: target)
            detent = target
        } onLongPress: { coordinate in
            selectedFeature = nil
            model.focusedID = nil
            // Kart görünsün diye çekmece en küçüğe iner.
            detent = Self.peek
            Task { await model.drop(at: coordinate) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: model.mapPick?.id) { _, new in new?.hasPrefix("pin/") == true }
        .onChange(of: selectedFeature) { _, feature in
            if let feature {
                model.focusedID = nil
                model.pick(feature: feature)
                detent = Self.peek
                // Üstteki kart noktayı örtmesin: görünen alanın ortasına al.
                withAnimation(.easeInOut(duration: 0.4)) {
                    position = MapFraming.focus(feature.coordinate, visibleFraction: 0.7, aspect: mapAspect)
                }
            } else if model.mapPick?.id.hasPrefix("map/feature/") == true {
                model.mapPick = nil
            }
        }
        .onChange(of: model.mapPick?.id) { _, id in
            // Kart kapandı: Haritalar seçimi de kalksın.
            if id == nil { selectedFeature = nil }
        }
        .ignoresSafeArea()
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { mapAspect = aspect(proxy.size) }
                .onChange(of: proxy.size) { _, size in mapAspect = aspect(size) }
        })
        .overlay(alignment: .top) {
            VStack(spacing: 10) {
                cityChips(trip)
                if let pick = model.mapPick {
                    MapPickCard(pick: pick, isResolving: model.isResolvingPick, isAdded: model.added[pick.id] != nil,
                                targetTitle: targetTitle(trip)) {
                        withAnimation(.spring(duration: 0.25)) { model.toggle(suggestion: pick, store: store, trip: trip) }
                    } onClose: {
                        withAnimation { model.mapPick = nil }
                    }
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.3), value: model.mapPick?.id)
        }
        .sheet(isPresented: $showsDrawer) {
            PlacePickerList(trip: trip, model: model, detent: $detent,
                            onFocus: { focus($0, trip: trip) },
                            onRetry: { Task { await model.load(trip: trip); await model.search(trip: trip) } },
                            onDone: close)
                .presentationDetents([Self.peek, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
                // Cam çekmecede haritanın renkleri listeye vurup okunurluğu düşürüyor; düz zemin.
                .presentationBackground(Color(.systemGroupedBackground))
                .interactiveDismissDisabled()
        }
        .task(id: model.legID) {
            await model.load(trip: trip)
            // Yükleme aramayı sıfırlar; yazılı sorguyla yeniden ara.
            await model.search(trip: trip)
        }
        .task(id: model.query) { await model.search(trip: trip) }
        // Liste (arama, filtre, şehir) değişince harita yeniden çerçevelenir; eklemek listeyi değiştirmez.
        .onChange(of: model.numbered.map(\.id), initial: true) { _, _ in
            if detent == .large { reframePending = true } else { frame(trip) }
        }
        // Çekmece küçülünce: seçili yer varsa ona odaklan, yoksa çerçevele (büyükteyken kaçan yeniden çerçeveleme dahil).
        .onChange(of: detent) { _, new in
            guard new != .large else { return }
            reframePending = false
            // Haritadan seçim varken harita yerinde kalır.
            guard model.mapPick == nil else { return }
            if let id = model.focusedID { focus(id, trip: trip) } else { frame(trip) }
        }
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
                            .foregroundStyle(isOn ? Color.onInk : Color.ink)
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

    private func targetTitle(_ trip: Trip) -> String {
        switch model.target {
        case .ideas: return String(localized: "Fikirler")
        case .day(let day):
            let number = (trip.days().firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } ?? 0) + 1
            return String(localized: "\(number). gün")
        }
    }

    private func aspect(_ size: CGSize) -> Double? {
        size.height > 0 ? Double(size.width / size.height) : nil
    }

    /// Çekmecenin kapatmadığı üst bölümün oranı; büyük çekmecede harita zaten görünmez, nil.
    private func visibleFraction(_ detent: PresentationDetent) -> Double? {
        if detent == Self.peek { return 0.7 }
        if detent == .medium { return 0.5 }
        return nil
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
        let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        withAnimation(.easeInOut(duration: 0.4)) {
            if let fraction = visibleFraction(detent) {
                position = MapFraming.position(coordinates, visibleFraction: fraction, aspect: mapAspect)
            } else if case .large = detent {
                // Büyük çekmecede haritayı oynatma.
            } else {
                position = MapFraming.position(coordinates)
            }
        }
    }

    private func focus(_ id: String, trip: Trip, detent target: PresentationDetent? = nil) {
        model.focusedID = id
        guard let item = model.numbered.first(where: { $0.id == id }),
              let fraction = visibleFraction(target ?? detent) else { return }
        let c = item.suggestion.coordinate
        withAnimation(.easeInOut(duration: 0.4)) {
            position = MapFraming.focus(CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                                        visibleFraction: fraction, aspect: mapAspect)
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

/// Haritadan seçilen yerin kartı: ad, tür, hedefe ekle ya da geri al.
private struct MapPickCard: View {
    @Environment(\.tripPalette) private var palette
    let pick: PlaceSuggestions.Suggestion
    let isResolving: Bool
    let isAdded: Bool
    let targetTitle: String
    let onToggle: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: pick.id.hasPrefix("pin/") ? "mappin" : pick.kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.accentText)
                .frame(width: 36, height: 36)
                .background(palette.accentText.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(pick.name).font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(1)
                    if isResolving { ProgressView().controlSize(.mini) }
                }
                Text(isAdded ? String(localized: "\(targetTitle) listesine eklendi") : pick.category)
                    .font(.caption).foregroundStyle(isAdded ? Color.success : Color.ink2).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: onToggle) {
                Label(isAdded ? String(localized: "Geri al") : String(localized: "Ekle"),
                      systemImage: isAdded ? "arrow.uturn.backward" : "plus")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(isAdded ? Color.ink : Color.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(isAdded ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Color(hex: palette.accent)),
                                in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.ink2)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Kapat")
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}
