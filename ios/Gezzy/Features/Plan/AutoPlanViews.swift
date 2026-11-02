import MapKit
import SwiftUI
import GezzyKit

/// Önerilerin merkezi: şehir konumu, yoksa otel ya da duraklar, o da yoksa şehir adından arama. Çok şehirli
/// seyahatte verilen şehrin konumu (yoksa yalnızca adından arama; başka şehrin otel/durakları karışmasın).
enum PlanCenter {
    @MainActor
    static func find(for trip: Trip, leg: TripLeg? = nil) async -> Coordinate? {
        let destination = leg?.destination ?? trip.destination
        if let coordinate = destination.coordinate { return coordinate }
        if trip.isMultiCity { return await DestinationGeocoder.coordinate(for: destination) }
        if let hotel = trip.lodgingList.compactMap(\.coordinate).first { return hotel }
        let points = (trip.stops + trip.ideaList).compactMap(\.coordinate)
        if !points.isEmpty {
            return Coordinate(latitude: points.map(\.latitude).reduce(0, +) / Double(points.count),
                              longitude: points.map(\.longitude).reduce(0, +) / Double(points.count))
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(destination.city), \(Countries.name(destination.countryCode))"
        request.resultTypes = .address
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        return Coordinate(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)
    }
}

/// Fikirleri günlere dağıtan otomatik rotanın önizlemesi; "Uygula" ile plana yazılır.
struct AutoPlanSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    /// Uygulamadan önceki duraklar ve fikirler (geri almak için).
    let onApply: (_ before: (stops: [Stop], ideas: [Stop]?)) -> Void

    @State private var dayStart = 9 * 60
    @State private var dayEnd = 19 * 60

    private var plan: ItineraryPlanner.Plan {
        ItineraryPlanner.plan(trip, settings: .init(dayStart: dayStart, dayEnd: dayEnd,
                                                    nationality: store.me.passport?.nationality ?? "TR"))
    }

    var body: some View {
        let plan = plan
        let ideas = Dictionary(trip.ideaList.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let stops = Dictionary(trip.stops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        NavigationStack {
            List {
                Section {
                    Stepper("Güne başlama · \(AppFormat.time(minutes: dayStart))", value: $dayStart, in: 6 * 60...12 * 60, step: 30)
                    Stepper("Günü bitirme · \(AppFormat.time(minutes: dayEnd))", value: $dayEnd, in: 15 * 60...23 * 60, step: 30)
                } footer: {
                    Text("Yakın yerler aynı güne toplanır; açılış saatleri, otel, varış ve dönüş uçuşları dikkate alınır. Mevcut durakların saatleri değişmez.")
                }

                ForEach(plan.days.filter { !$0.order.isEmpty }, id: \.day) { day in
                    Section {
                        ForEach(day.order, id: \.self) { id in
                            if let idea = ideas[id] {
                                line(idea, start: day.starts[id], isNew: true)
                            } else if let stop = stops[id] {
                                line(stop, start: stop.startMinutes, isNew: false)
                            }
                        }
                    } header: {
                        Text(dayHeader(day))
                    }
                }

                if !plan.unscheduled.isEmpty {
                    Section {
                        ForEach(plan.unscheduled, id: \.self) { id in
                            if let idea = ideas[id] {
                                Label(idea.name, systemImage: idea.coordinate == nil ? "mappin.slash" : "clock.badge.xmark")
                                    .foregroundStyle(Color.ink2)
                            }
                        }
                    } header: {
                        Text("Sığmayanlar")
                    } footer: {
                        Text("Konumu olmayan, açık olduğu günlerde yeri kalmayan ya da güne sığmayan yerler Fikirler'de kalır.")
                    }
                }
            }
            .navigationTitle("Otomatik rota")
            // Çok şehirli seyahatte fikirler şehirlerine ayrılabilsin diye konumu bilinmeyen şehirler bulunur.
            .task { await store.ensureAllCoordinates(for: trip.id) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Uygula") {
                        let before = (trip.stops, trip.ideas)
                        store.update(trip.id) { ItineraryPlanner.apply(plan, to: &$0) }
                        onApply(before)
                        dismiss()
                    }
                    .disabled(plan.addedCount == 0)
                }
            }
        }
    }

    private func dayHeader(_ day: ItineraryPlanner.DayPlan) -> String {
        let number = (trip.days().firstIndex { Calendar.current.isDate($0, inSameDayAs: day.day) } ?? 0) + 1
        return String(localized: "\(number). gün · \(AppFormat.dayPill(day.day)) · \(AppFormat.distance(meters: day.walkingMeters)) yürüyüş")
    }

    private func line(_ stop: Stop, start: Int?, isNew: Bool) -> some View {
        HStack(spacing: 12) {
            Text(start.map { AppFormat.time(minutes: $0) } ?? "—")
                .font(.system(.subheadline, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.ink2)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name).foregroundStyle(Color.ink)
                Text(AppFormat.duration(minutes: stop.durationMinutes)).font(.caption).foregroundStyle(Color.ink3)
            }
            Spacer()
            if isNew { Tag(text: String(localized: "Yeni"), accent: .green) }
        }
    }
}
