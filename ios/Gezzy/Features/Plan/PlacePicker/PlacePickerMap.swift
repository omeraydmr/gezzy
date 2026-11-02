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
