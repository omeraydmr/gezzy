import CoreLocation
import MapKit
import SwiftUI
import GezzyKit

/// Durağın konumu: adres yazılır (öneriler şehir çevresinden) ya da haritada iğne konur. Konumsuz durak haritada
/// görünmez ve yol tarifi alınamaz; bu yüzden elle eklemede zorunludur.
struct StopLocationSection: View {
    @Binding var stop: Stop
    /// Önerilerin ve haritanın açılacağı yer (seyahatin o günkü şehri).
    let center: Coordinate?
    var isRequired = false

    @State private var completer = AddressCompleter()
    @State private var query = ""
    @State private var isPickingOnMap = false
    @State private var isResolving = false

    var body: some View {
        Section {
            if let coordinate = stop.coordinate {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stop.address ?? String(localized: "Haritadan seçilen konum"))
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                        Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.ink2)
                    }
                    Spacer()
                    Button("Değiştir") {
                        stop.coordinate = nil
                        stop.address = nil
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                TextField("Adres ya da yer adı ara", text: $query)
                    .textInputAutocapitalization(.words)
                    .onChange(of: query) { _, value in completer.search(value, near: center) }
                if isResolving {
                    HStack { ProgressView(); Text("Konum bulunuyor…").foregroundStyle(Color.ink2) }
                }
                ForEach(completer.results.prefix(5), id: \.self) { result in
                    Button {
                        Task { await choose(result) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title).foregroundStyle(Color.ink)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle).font(.caption).foregroundStyle(Color.ink2)
                            }
                        }
                    }
                }
                Button {
                    isPickingOnMap = true
                } label: {
                    Label("Haritadan seç", systemImage: "map")
                }
            }
        } header: {
            Text("Konum")
        } footer: {
            if stop.coordinate == nil {
                Text(isRequired
                     ? String(localized: "Konum, durağın haritada görünmesi ve yol tarifi için gerekli.")
                     : String(localized: "Konum yoksa durak haritada görünmez ve yol tarifi alınamaz."))
            }
        }
        .sheet(isPresented: $isPickingOnMap) {
            MapPinPicker(start: stop.coordinate ?? center) { coordinate, address in
                stop.coordinate = coordinate
                stop.address = address
            }
        }
    }

    private func choose(_ completion: MKLocalSearchCompletion) async {
        isResolving = true
        defer { isResolving = false }
        let request = MKLocalSearch.Request(completion: completion)
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return }
        let location = item.placemark.coordinate
        stop.coordinate = Coordinate(latitude: location.latitude, longitude: location.longitude)
        stop.address = [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
        if stop.name.trimmingCharacters(in: .whitespaces).isEmpty { stop.name = completion.title }
        query = ""
    }
}

/// MapKit adres önerileri; şehir çevresine öncelik verir.
@MainActor
@Observable
final class AddressCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(_ text: String, near center: Coordinate?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        if let center {
            completer.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                                                  latitudinalMeters: 30_000, longitudinalMeters: 30_000)
        }
        completer.queryFragment = trimmed
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let found = completer.results
        Task { @MainActor in self.results = found }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }
}

/// Haritayı kaydırıp ortadaki iğneyle konum seçme; seçilen nokta adres olarak çözülür.
struct MapPinPicker: View {
    @Environment(\.dismiss) private var dismiss
    let start: Coordinate?
    let onPick: (Coordinate, String?) -> Void

    @State private var position: MapCameraPosition = .automatic
    @State private var center: CLLocationCoordinate2D?
    @State private var address: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Map(position: $position)
                .mapStyle(.standard(pointsOfInterest: .including([.museum, .park, .restaurant, .cafe])))
                .onMapCameraChange(frequency: .onEnd) { context in
                    center = context.region.center
                    Task { address = await Self.address(for: context.region.center) }
                }
                .overlay {
                    // İğnenin ucu haritanın tam ortasında.
                    Image(systemName: "mappin")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Color.food)
                        .shadow(radius: 2, y: 1)
                        .offset(y: -17)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottom) {
                    VStack(spacing: 10) {
                        Text(address ?? String(localized: "Haritayı kaydırıp iğneyi yere getir"))
                            .font(.subheadline)
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                        Button {
                            guard let center else { return }
                            onPick(Coordinate(latitude: center.latitude, longitude: center.longitude), address)
                            dismiss()
                        } label: {
                            Label("Bu konumu kullan", systemImage: "checkmark")
                        }
                        .buttonStyle(.primary)
                        .disabled(center == nil)
                    }
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
                    .padding(16)
                }
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Haritadan seç")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                }
                .onAppear {
                    if let start {
                        let point = CLLocationCoordinate2D(latitude: start.latitude, longitude: start.longitude)
                        position = .region(MKCoordinateRegion(center: point, latitudinalMeters: 2_000, longitudinalMeters: 2_000))
                    }
                }
        }
    }

    private static func address(for point: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let street = [placemark.thoroughfare, placemark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
        let parts = [placemark.name, street.isEmpty ? nil : street, placemark.locality].compactMap { $0 }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? nil : unique.joined(separator: ", ")
    }
}

/// Durağa yol tarifi: Apple Haritalar ya da Google Haritalar'da açar (yürüyüş).
enum StopDirections {
    static func openAppleMaps(_ stop: Stop) {
        guard let coordinate = stop.coordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude,
                                                                                       longitude: coordinate.longitude)))
        item.name = stop.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }

    /// Google Haritalar yüklüyse uygulamada, değilse tarayıcıda açılır (evrensel bağlantı).
    static func googleMapsURL(_ stop: Stop) -> URL? {
        guard let coordinate = stop.coordinate else { return nil }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "travelmode", value: "walking"),
        ]
        return components?.url
    }
}
