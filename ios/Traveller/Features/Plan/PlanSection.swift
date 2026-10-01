import MapKit
import SwiftUI
import TravellerKit

struct PlanSection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var selectedDay: Date?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isAddingStop = false
    @State private var lastOrderBeforeOptimize: [Stop.ID: Int]?

    private var days: [Date] { trip.days() }
    private var day: Date {
        if let selectedDay { return selectedDay }
        let today = Calendar.current.startOfDay(for: .now)
        return days.contains(today) ? today : (days.first ?? today)
    }
    private var stops: [Stop] { trip.stops(on: day) }
    private var coordinates: [Coordinate] { stops.compactMap(\.coordinate) }
    private var totalMeters: Double { Geo.routeDistance(coordinates) }

    var body: some View {
        ModuleCard("Gün planı", symbol: "map.fill") {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    PillPicker(selection: Binding(get: { day }, set: { selectedDay = $0 }), options: days) {
                        AppFormat.dayPill($0)
                    }
                }

                stopList

                if !coordinates.isEmpty {
                    map
                }

                HStack(spacing: 12) {
                    Button {
                        isAddingStop = true
                    } label: {
                        Label("Durak ekle", systemImage: "plus")
                    }
                    .buttonStyle(.primary)

                    if let lastOrderBeforeOptimize {
                        Button {
                            restore(lastOrderBeforeOptimize)
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .buttonStyle(.circleIcon)
                        .accessibilityLabel("Sıralamayı geri al")
                    } else {
                        Button(action: optimize) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                        }
                        .buttonStyle(.circleIcon)
                        .disabled(coordinates.count < 3)
                        .accessibilityLabel("Rotayı en kısa sıraya diz")
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingStop) {
            AddStopSheet(trip: trip, day: day)
        }
        .onChange(of: day) { _, _ in
            cameraPosition = .automatic
            lastOrderBeforeOptimize = nil
        }
    }

    // MARK: List

    @ViewBuilder
    private var stopList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(trip.destination.city).font(.tBodyStrong).foregroundStyle(Color.ink)
                Spacer()
                Text(summary).font(.tBody).foregroundStyle(Color.ink3)
            }
            .padding(.bottom, 14)

            if stops.isEmpty {
                EmptyHint(symbol: "mappin.and.ellipse", text: "Bu gün için henüz durak yok.")
            }

            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                if index > 0 {
                    HopRow(from: stops[index - 1], to: stop)
                }
                StopRow(stop: stop, number: index + 1)
                    .contextMenu { menu(for: stop, index: index) }
            }
        }
        .tray()
    }

    private var summary: String {
        var parts = ["\(stops.count) durak"]
        if totalMeters > 0 { parts.append(AppFormat.distance(meters: totalMeters)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func menu(for stop: Stop, index: Int) -> some View {
        if index > 0 {
            Button("Yukarı taşı", systemImage: "arrow.up") { move(stop, by: -1) }
        }
        if index < stops.count - 1 {
            Button("Aşağı taşı", systemImage: "arrow.down") { move(stop, by: 1) }
        }
        Menu("Başka güne taşı", systemImage: "calendar") {
            ForEach(days.filter { $0 != day }, id: \.self) { target in
                Button(AppFormat.dayPill(target)) { moveToDay(stop, target) }
            }
        }
        Button("Sil", systemImage: "trash", role: .destructive) {
            store.update(trip.id) { $0.stops.removeAll { $0.id == stop.id } }
        }
    }

    // MARK: Map

    private var map: some View {
        let pinned = stops.enumerated().compactMap { (index, stop) -> PinnedStop? in
            guard let coordinate = stop.coordinate else { return nil }
            return PinnedStop(stop: stop, number: index + 1,
                              coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        let walking = Geo.walkingMinutes(meters: totalMeters)
        return Map(position: $cameraPosition) {
            MapPolyline(coordinates: pinned.map(\.coordinate))
                .stroke(Color.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.5, 8]))
            ForEach(pinned) { item in
                Annotation(item.stop.name, coordinate: item.coordinate, anchor: .bottom) {
                    NumberedPin(number: item.number, accent: Accent.cycle(item.number - 1), size: 28)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        .overlay(alignment: .topLeading) {
            if pinned.count > 1 {
                Label("\(walking) dk yürüyüş", systemImage: "figure.walk")
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.tray, in: Capsule())
                    .softShadow()
                    .padding(12)
            }
        }
    }

    private struct PinnedStop: Identifiable {
        let stop: Stop
        let number: Int
        let coordinate: CLLocationCoordinate2D
        var id: Stop.ID { stop.id }
    }

    // MARK: Actions

    private func move(_ stop: Stop, by offset: Int) {
        var ordered = stops
        guard let index = ordered.firstIndex(where: { $0.id == stop.id }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        applyOrder(ordered.map(\.id))
    }

    private func moveToDay(_ stop: Stop, _ target: Date) {
        let nextOrder = (trip.stops(on: target).map(\.order).max() ?? -1) + 1
        store.update(trip.id) { trip in
            guard let index = trip.stops.firstIndex(where: { $0.id == stop.id }) else { return }
            trip.stops[index].day = target
            trip.stops[index].order = nextOrder
        }
    }

    /// Koordinatı olan durakları en kısa yürüyüş sırasına dizer; koordinatsızlar sona kalır.
    private func optimize() {
        let located = stops.filter { $0.coordinate != nil }
        let others = stops.filter { $0.coordinate == nil }
        let order = RouteOptimizer.order(located.compactMap(\.coordinate))
        lastOrderBeforeOptimize = Dictionary(uniqueKeysWithValues: stops.map { ($0.id, $0.order) })
        withAnimation(.spring(duration: 0.35)) {
            applyOrder(order.map { located[$0].id } + others.map(\.id))
        }
    }

    private func restore(_ orders: [Stop.ID: Int]) {
        withAnimation(.spring(duration: 0.35)) {
            store.update(trip.id) { trip in
                for index in trip.stops.indices {
                    if let order = orders[trip.stops[index].id] { trip.stops[index].order = order }
                }
            }
        }
        lastOrderBeforeOptimize = nil
    }

    private func applyOrder(_ ids: [Stop.ID]) {
        store.update(trip.id) { trip in
            for (order, id) in ids.enumerated() {
                if let index = trip.stops.firstIndex(where: { $0.id == id }) {
                    trip.stops[index].order = order
                }
            }
        }
    }
}

// MARK: - Rows

struct StopRow: View {
    let stop: Stop
    let number: Int

    var body: some View {
        let accent = Accent.cycle(number - 1)
        HStack(spacing: 12) {
            NumberedPin(number: number, accent: accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                Text(detail).font(.tBody).foregroundStyle(Color.ink2)
            }
            Spacer(minLength: 8)
            if let start = stop.startMinutes {
                Tag(text: AppFormat.time(minutes: start), accent: accent)
            }
            Image(systemName: stop.kind.symbol)
                .font(.system(size: 18))
                .foregroundStyle(accent.base)
                .frame(width: 48, height: 48)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        var parts = [stop.kind.title, AppFormat.duration(minutes: stop.durationMinutes)]
        if !stop.note.isEmpty { parts = [stop.kind.title, stop.note] }
        return parts.joined(separator: " · ")
    }
}

/// İki durak arasındaki geçiş satırı (tahmini yürüme süresi).
struct HopRow: View {
    let from: Stop
    let to: Stop

    var body: some View {
        HStack(spacing: 8) {
            VerticalLine()
                .stroke(Color.line, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 36)
            Image(systemName: symbol)
                .font(.system(size: 13))
            Text(text)
                .font(.tBody)
        }
        .foregroundStyle(Color.ink3)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }

    private var minutes: Int? {
        guard let a = from.coordinate, let b = to.coordinate else { return nil }
        return Geo.walkingMinutes(meters: Geo.distance(a, b))
    }

    private var symbol: String {
        guard let minutes else { return "arrow.down" }
        return minutes > 30 ? "tram.fill" : "figure.walk"
    }

    private var text: String {
        guard let minutes else { return "Geçiş" }
        return minutes > 30 ? "Toplu taşıma önerilir · \(minutes) dk yürüyüş" : "\(minutes) dk"
    }
}

struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}
