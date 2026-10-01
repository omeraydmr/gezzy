import MapKit
import SwiftUI
import TravellerKit

struct AddStopSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let day: Date

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    @State private var name = ""
    @State private var coordinate: Coordinate?
    @State private var kind: StopKind = .sight
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var duration = 60
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("\(trip.destination.city) içinde yer ara", text: $query)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
                    if isSearching {
                        ProgressView()
                    }
                    ForEach(results, id: \.self) { item in
                        Button {
                            select(item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Adsız yer").foregroundStyle(Color.ink)
                                if let address = item.placemark.title {
                                    Text(address).font(.footnote).foregroundStyle(Color.ink2).lineLimit(1)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Ara")
                }

                Section {
                    TextField("Durak adı", text: $name)
                    if coordinate != nil {
                        Label("Konum eklendi", systemImage: "mappin.circle.fill")
                            .foregroundStyle(Color.success)
                    }
                    Picker("Tür", selection: $kind) {
                        ForEach(StopKind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    Toggle("Saat belirle", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Başlangıç", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Stepper("Süre: \(AppFormat.duration(minutes: duration))", value: $duration, in: 15...600, step: 15)
                    TextField("Not (ör. Rezervasyon gerekli)", text: $note)
                } header: {
                    Text("\(AppFormat.dayPill(day)) için durak")
                }
            }
            .navigationTitle("Durak ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onDisappear { searchTask?.cancel() }
        }
    }

    private func select(_ item: MKMapItem) {
        name = item.name ?? name
        let location = item.placemark.coordinate
        coordinate = Coordinate(latitude: location.latitude, longitude: location.longitude)
        if let category = item.pointOfInterestCategory {
            kind = Self.kind(for: category)
        }
        results = []
        query = ""
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            isSearching = true
            defer { isSearching = false }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            if let center = trip.destination.coordinate {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                    latitudinalMeters: 40_000, longitudinalMeters: 40_000)
            }
            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = Array((response?.mapItems ?? []).prefix(8))
        }
    }

    private func save() {
        let order = (trip.stops(on: day).map(\.order).max() ?? -1) + 1
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        let stop = Stop(day: day, order: order, name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                        startMinutes: hasTime ? (components.hour ?? 0) * 60 + (components.minute ?? 0) : nil,
                        durationMinutes: duration, coordinate: coordinate,
                        note: note.trimmingCharacters(in: .whitespaces))
        store.update(trip.id) { $0.stops.append(stop) }
        dismiss()
    }

    private static func kind(for category: MKPointOfInterestCategory) -> StopKind {
        switch category {
        case .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .nightlife: .food
        case .hotel, .campground: .stay
        case .airport, .publicTransport, .carRental, .marina: .transport
        case .museum, .theater, .movieTheater, .amusementPark, .aquarium, .zoo, .stadium: .activity
        default: .sight
        }
    }
}
