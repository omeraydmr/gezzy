import MapKit
import SwiftUI
import GezzyKit

/// Önerilen yerler listedeki numarasıyla; plandaki duraklar ve otel soluk, yalnızca bağlam için.
/// Bu oturumda eklenenler yeşil onay pini. Apple Haritalar noktaları dokunulabilir; basılı tutmak iğne bırakır.
struct PlacePickerMap: View {
    @Environment(\.tripPalette) private var palette
    let trip: Trip
    @Bindable var model: PlacePickerModel
    @Binding var position: MapCameraPosition
    @Binding var selection: MapFeature?
    let onTapPin: (String) -> Void
    let onLongPress: (CLLocationCoordinate2D) -> Void

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

    /// İlk 15 öneri + seçili + eklenenler; numara listedeki sırasıdır.
    private var pinned: [(number: Int, item: PlaceRanking.Ranked)] {
        model.numbered.enumerated().compactMap { index, item in
            index < 15 || item.id == model.focusedID || model.added[item.id] != nil ? (index + 1, item) : nil
        }
    }

    /// Bırakılan iğne (haritadan seçilen nokta değil; o Haritalar'ın kendi seçim işaretiyle görünür).
    private var droppedPin: PlaceSuggestions.Suggestion? {
        model.mapPick.flatMap { $0.id.hasPrefix("pin/") ? $0 : nil }
    }

    /// Basılı tutma: parmak 0,45 sn yerinde kalırsa iğne. Map uzun basma hareketini yuttuğu için sürüklemeyle izlenir.
    @State private var press: (start: CGPoint, moved: Bool, id: UUID)?

    var body: some View {
        MapReader { proxy in
            map
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if let current = press {
                                let d = hypot(value.location.x - current.start.x, value.location.y - current.start.y)
                                if d > 10 { press?.moved = true }
                                return
                            }
                            let id = UUID()
                            press = (value.location, false, id)
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(450))
                                guard let current = press, current.id == id, !current.moved,
                                      let coordinate = proxy.convert(current.start, from: .local) else { return }
                                press?.moved = true // bir kez
                                onLongPress(coordinate)
                            }
                        }
                        .onEnded { _ in press = nil }
                )
        }
    }

    private var map: some View {
        Map(position: $position, selection: $selection) {
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
            ForEach(pinned, id: \.item.id) { number, item in
                let c = item.suggestion.coordinate
                let isFocused = model.focusedID == item.id
                Annotation(item.suggestion.name, coordinate: CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude),
                           anchor: .bottom) {
                    pin(number: number, isAdded: model.added[item.id] != nil)
                        .scaleEffect(isFocused ? 1.25 : 1)
                        .animation(.spring(duration: 0.25), value: isFocused)
                        .onTapGesture { onTapPin(item.id) }
                }
                .annotationTitles(isFocused ? .visible : .hidden)
            }
            if let pin = droppedPin {
                Marker(pin.name, systemImage: "mappin",
                       coordinate: CLLocationCoordinate2D(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude))
                    .tint(model.added[pin.id] != nil ? Color.success : Color(hex: palette.accent))
            }
        }
        // Haritalar'daki gibi saray, müze, kafe… noktaları; dokununca eklenebilir.
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .all))
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
            NumberedPin(number: number, color: palette.pin(number - 1), size: 30)
        }
    }
}
