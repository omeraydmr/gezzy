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
            let target = detent == Self.peek ? PresentationDetent.medium : detent
            focus(id, trip: trip, detent: target)
            detent = target
        }
        .ignoresSafeArea()
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { mapAspect = aspect(proxy.size) }
                .onChange(of: proxy.size) { _, size in mapAspect = aspect(size) }
        })
        .overlay(alignment: .top) { cityChips(trip) }
        .sheet(isPresented: $showsDrawer) {
            PlacePickerList(trip: trip, model: model, detent: $detent,
                            onFocus: { focus($0, trip: trip) },
                            onRetry: { Task { await model.load(trip: trip); await model.search(trip: trip) } },
                            onDone: close)
                .presentationDetents([Self.peek, .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
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
