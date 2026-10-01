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
    @State private var dropTarget: Stop.ID?
    @State private var editingHours: Stop?
    private var network: NetworkMonitor { .shared }
    private var offlineMaps: OfflineMapStore { .shared }
    @Environment(\.tripTint) private var tint

    private var days: [Date] { trip.days() }
    private var day: Date { Self.day(selected: selectedDay, in: days) }
    private var stops: [Stop] { trip.stops(on: day) }

    private static func day(selected: Date?, in days: [Date]) -> Date {
        if let selected { return selected }
        let today = Calendar.current.startOfDay(for: .now)
        return days.contains(today) ? today : (days.first ?? today)
    }

    /// Seçili günün çizim için gereken her şeyi; gövde başına bir kez hesaplanır
    /// (durak süzme/sıralama, mesafe, açılış saati durumları ve önerileri tekrar tekrar yapılmaz).
    private struct DayPlan {
        let days: [Date]
        let day: Date
        let stops: [Stop]
        let coordinates: [Coordinate]
        let totalMeters: Double
        let hours: [Stop.ID: OpeningHours.Status]
        let fixes: [Stop.ID: Trip.HoursFix]
        let stopCounts: [Date: Int]

        var warningCount: Int { hours.values.filter(\.isWarning).count }
    }

    private func makePlan() -> DayPlan {
        let days = trip.days()
        let day = Self.day(selected: selectedDay, in: days)
        let calendar = Calendar.current
        var counts: [Date: Int] = [:]
        for stop in trip.stops { counts[calendar.startOfDay(for: stop.day), default: 0] += 1 }
        let stops = trip.stops(on: day)
        let coordinates = stops.compactMap(\.coordinate)
        var hours: [Stop.ID: OpeningHours.Status] = [:]
        var fixes: [Stop.ID: Trip.HoursFix] = [:]
        for stop in stops {
            hours[stop.id] = trip.hoursStatus(of: stop)
            fixes[stop.id] = trip.hoursFix(for: stop)
        }
        return DayPlan(days: days, day: day, stops: stops, coordinates: coordinates,
                       totalMeters: Geo.routeDistance(coordinates), hours: hours, fixes: fixes, stopCounts: counts)
    }

    var body: some View {
        let plan = makePlan()
        VStack(alignment: .leading, spacing: 16) {
            DayChips(days: plan.days, selection: Binding(get: { plan.day }, set: { selectedDay = $0 }),
                     stopCount: { plan.stopCounts[Calendar.current.startOfDay(for: $0)] ?? 0 },
                     onDropStop: { id, target in moveStop(id, before: nil, on: target) })

            if !plan.coordinates.isEmpty {
                if !network.isOnline, let offline = offlineMaps.image(tripID: trip.id, day: plan.day) {
                    OfflineMapImage(image: offline)
                } else {
                    map(plan)
                }
                OfflineMapRow(trip: trip)
            }

            stopList(plan)

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
                    .disabled(plan.coordinates.count < 3)
                    .accessibilityLabel("Rotayı en kısa sıraya diz")
                }
            }
        }
        .sheet(isPresented: $isAddingStop) {
            AddStopSheet(trip: trip, day: plan.day)
        }
        .sheet(item: $editingHours) { stop in
            OpeningHoursEditor(stop: stop) { hours in
                store.update(trip.id) { trip in
                    if let index = trip.stops.firstIndex(where: { $0.id == stop.id }) {
                        trip.stops[index].openingHours = hours
                        trip.stops[index].openingHoursLookedUp = true
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .task(id: trip.stops.filter { $0.coordinate != nil }.count) { await lookUpOpeningHours() }
        .onChange(of: plan.day) { _, _ in
            cameraPosition = .automatic
            lastOrderBeforeOptimize = nil
        }
    }

    // MARK: List

    private func stopList(_ plan: DayPlan) -> some View {
        let stops = plan.stops
        let totalMeters = plan.totalMeters
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text(dayTitle(plan))
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                HStack(spacing: 6) {
                    StatChip(symbol: "mappin", text: "\(stops.count) durak")
                    if totalMeters > 0 {
                        StatChip(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                 text: AppFormat.distance(meters: totalMeters))
                        StatChip(symbol: "figure.walk", text: "\(Geo.walkingMinutes(meters: totalMeters)) dk")
                    }
                    let warnings = plan.warningCount
                    if warnings > 0 {
                        StatChip(symbol: "clock.badge.exclamationmark", text: "\(warnings) saat uyarısı", accent: .orange)
                    }
                }
            }
            .padding(.bottom, 14)

            if stops.isEmpty {
                EmptyHint(symbol: "mappin.and.ellipse", text: "Bu gün için henüz durak yok.")
            }

            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                if index > 0 {
                    HopRow(from: stops[index - 1], to: stop)
                }
                StopRow(stop: stop, number: index + 1, hours: plan.hours[stop.id],
                        fix: plan.fixes[stop.id]) { fix in apply(fix, to: stop) }
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(tint)
                            .frame(height: 3)
                            .offset(y: -4)
                            .opacity(dropTarget == stop.id ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .draggable(stop.id.uuidString) {
                        Label(stop.name, systemImage: stop.kind.symbol)
                            .font(.system(.subheadline, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.tray, in: Capsule())
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                        moveStop(id, before: stop.id, on: plan.day)
                        return true
                    } isTargeted: { targeted in
                        if targeted { dropTarget = stop.id } else if dropTarget == stop.id { dropTarget = nil }
                    }
                    .contextMenu { menu(for: stop, index: index, in: plan) }
            }

            if stops.contains(where: { $0.openingHours != nil }) {
                Link(destination: Attribution.openStreetMap.url) {
                    Text("Açılış saatleri: \(Attribution.openStreetMap.notice)")
                        .font(.caption2)
                        .foregroundStyle(Color.ink3)
                        .underline()
                }
                .padding(.top, 10)
            }

            if stops.count > 1 {
                Text("Sıralamak için durağı basılı tutup sürükle; başka güne taşımak için üstteki güne bırak.")
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
                    .padding(.top, 10)
            }
        }
        .tray()
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let id = UUID(uuidString: first) else { return false }
            moveStop(id, before: nil, on: plan.day)
            return true
        }
        .animation(.spring(duration: 0.3), value: stops.map(\.id))
    }

    private func dayTitle(_ plan: DayPlan) -> String {
        let number = (plan.days.firstIndex(of: plan.day) ?? 0) + 1
        return "\(number). gün · \(AppFormat.dayPill(plan.day)) · \(trip.destination.city)"
    }

    @ViewBuilder
    private func menu(for stop: Stop, index: Int, in plan: DayPlan) -> some View {
        if index > 0 {
            Button("Yukarı taşı", systemImage: "arrow.up") { move(stop, by: -1) }
        }
        if index < plan.stops.count - 1 {
            Button("Aşağı taşı", systemImage: "arrow.down") { move(stop, by: 1) }
        }
        Button("Açılış saatleri", systemImage: "clock") { editingHours = stop }
        Menu("Başka güne taşı", systemImage: "calendar") {
            ForEach(plan.days.filter { $0 != plan.day }, id: \.self) { target in
                Button(AppFormat.dayPill(target)) { moveToDay(stop, target) }
            }
        }
        Button("Sil", systemImage: "trash", role: .destructive) {
            store.update(trip.id) { $0.stops.removeAll { $0.id == stop.id } }
        }
    }

    // MARK: Map

    private func map(_ plan: DayPlan) -> some View {
        let pinned = plan.stops.enumerated().compactMap { (index, stop) -> PinnedStop? in
            guard let coordinate = stop.coordinate else { return nil }
            return PinnedStop(stop: stop, number: index + 1,
                              coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
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
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        // Gölge haritanın kendisinden değil zemin şeklinden: canlı harita katmana birleştirilmez.
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
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

    // MARK: Opening hours

    /// Açılış saati henüz aranmamış, konumu olan duraklar (tüm günler).
    private var pendingHoursLookup: [Stop.ID] {
        trip.stops.filter { $0.coordinate != nil && $0.openingHoursLookedUp != true }.map(\.id)
    }

    /// OpenStreetMap'ten açılış saatlerini sırayla sorgular; Overpass'ı yormamak için aralarında kısa bekleme var.
    private func lookUpOpeningHours() async {
        for id in pendingHoursLookup {
            guard !Task.isCancelled,
                  let stop = trip.stops.first(where: { $0.id == id }), let coordinate = stop.coordinate else { continue }
            do {
                let hours = try await OpeningHoursService.shared.lookup(name: stop.name, coordinate: coordinate)
                store.update(trip.id) { trip in
                    if let index = trip.stops.firstIndex(where: { $0.id == id }) {
                        if trip.stops[index].openingHours == nil { trip.stops[index].openingHours = hours }
                        trip.stops[index].openingHoursLookedUp = true
                    }
                }
            } catch {
                return // Ağ hatası: işaretlemeden çık, bir sonraki açılışta yeniden denenir.
            }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    private func apply(_ fix: Trip.HoursFix, to stop: Stop) {
        switch fix {
        case let .setStart(minutes):
            withAnimation(.spring(duration: 0.3)) {
                store.update(trip.id) { trip in
                    if let index = trip.stops.firstIndex(where: { $0.id == stop.id }) {
                        trip.stops[index].startMinutes = minutes
                    }
                }
            }
        case let .moveTo(day):
            moveStop(stop.id, before: nil, on: day)
        }
    }

    private func moveStop(_ id: Stop.ID, before target: Stop.ID?, on targetDay: Date) {
        dropTarget = nil
        lastOrderBeforeOptimize = nil
        withAnimation(.spring(duration: 0.3)) {
            store.update(trip.id) { $0.moveStop(id, before: target, on: targetDay) }
        }
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
    var hours: OpeningHours.Status?
    var fix: Trip.HoursFix?
    var onFix: (Trip.HoursFix) -> Void = { _ in }

    var body: some View {
        let accent = Accent.cycle(number - 1)
        HStack(spacing: 12) {
            NumberedPin(number: number, accent: accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                Text(detail).font(.tBody).foregroundStyle(Color.ink2)
                if let hours {
                    HoursLabel(status: hours)
                }
                if let fix {
                    Button {
                        onFix(fix)
                    } label: {
                        Label(fixTitle(fix), systemImage: fixSymbol(fix))
                            .font(.system(.caption, weight: .bold))
                            .foregroundStyle(Color.onInk)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
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

    private func fixTitle(_ fix: Trip.HoursFix) -> String {
        switch fix {
        case let .setStart(minutes): "Saati \(AppFormat.time(minutes: minutes)) yap"
        case let .moveTo(day): "Taşı: \(AppFormat.dayPill(day))"
        }
    }

    private func fixSymbol(_ fix: Trip.HoursFix) -> String {
        switch fix {
        case .setStart: "clock.arrow.circlepath"
        case .moveTo: "calendar.badge.plus"
        }
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

/// Durağın açılış saatine göre kısa durum etiketi.
struct HoursLabel: View {
    let status: OpeningHours.Status

    var body: some View {
        Label(text, systemImage: status.isWarning ? "exclamationmark.circle.fill" : "clock")
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var color: Color {
        switch status {
        case .closedAllDay, .alreadyClosed: Color(hex: 0xD64545)
        case .opensLater, .closesDuringVisit: .food
        case .open, .openToday: .ink3
        }
    }

    private var text: String {
        let clock = OpeningHours.clock
        switch status {
        case .closedAllDay: return "O gün kapalı"
        case let .alreadyClosed(at): return "Bu saatte kapalı · kapanış \(clock(at))"
        case let .opensLater(at): return "Henüz kapalı · açılış \(clock(at))"
        case let .closesDuringVisit(at): return "Kapanış \(clock(at)) · süre yetmeyebilir"
        case let .open(until): return "Açık · kapanış \(clock(until))"
        case let .openToday(intervals):
            return intervals.map { "\(clock($0.start))–\(clock($0.end))" }.joined(separator: ", ")
        }
    }
}

/// Açılış saatlerini gösterir ve düzenletir (OpenStreetMap biçimi).
struct OpeningHoursEditor: View {
    @Environment(\.dismiss) private var dismiss
    let stop: Stop
    let onSave: (String?) -> Void
    @State private var text: String

    init(stop: Stop, onSave: @escaping (String?) -> Void) {
        self.stop = stop
        self.onSave = onSave
        _text = State(initialValue: stop.openingHours ?? "")
    }

    private var parsed: OpeningHours? { OpeningHours(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Mo-Fr 09:00-18:00; Sa 10:00-14:00; Su off", text: $text, axis: .vertical)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text(stop.name)
                } footer: {
                    Text("Günler: Mo Tu We Th Fr Sa Su. Kapalı günler için \"off\". Saatler OpenStreetMap'ten otomatik gelir; yanlışsa buradan düzeltebilirsin. \(Attribution.openStreetMap.notice)")
                }

                Section("Önizleme") {
                    if text.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Açılış saati yok").foregroundStyle(Color.ink3)
                    } else if let parsed {
                        Text(parsed.turkishSummary).foregroundStyle(Color.ink)
                    } else {
                        Label("Bu biçim anlaşılamadı", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.food)
                    }
                }
            }
            .navigationTitle("Açılış saatleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .disabled(!text.trimmingCharacters(in: .whitespaces).isEmpty && parsed == nil)
                }
            }
        }
    }
}

/// İnternet yokken gösterilen kayıtlı harita görüntüsü.
struct OfflineMapImage: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(height: 240)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
            .overlay(alignment: .topLeading) {
                Label("Çevrimdışı harita", systemImage: "wifi.slash")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
            }
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
            .accessibilityLabel("Kayıtlı çevrimdışı harita")
    }
}

/// Haritaları çevrimdışı kullanım için kaydetme satırı.
struct OfflineMapRow: View {
    let trip: Trip
    private var store: OfflineMapStore { .shared }

    var body: some View {
        let state = store.state(for: trip.id)
        HStack(spacing: 10) {
            Image(systemName: icon(state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(state))
            Text(text(state))
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
            Spacer()
            if case .saving = state {
                ProgressView().controlSize(.small)
            } else {
                Button(isSaved(state) ? "Güncelle" : "Kaydet") {
                    Task { await store.save(trip) }
                }
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.ink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .cardBackground(Color.tray, in: Capsule())
    }

    private func isSaved(_ state: OfflineMapStore.State) -> Bool {
        if case .saved = state { return true }
        return false
    }

    private func icon(_ state: OfflineMapStore.State) -> String {
        switch state {
        case .idle: "arrow.down.circle"
        case .saving: "arrow.down.circle.dotted"
        case .saved: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ state: OfflineMapStore.State) -> Color {
        switch state {
        case .saved: .success
        case .failed: .food
        default: .ink2
        }
    }

    private func text(_ state: OfflineMapStore.State) -> String {
        switch state {
        case .idle: "Haritaları internetsiz kullanım için kaydet"
        case let .saving(done, total): "Kaydediliyor · \(done + 1)/\(total) gün"
        case let .saved(date): "Çevrimdışı kayıtlı · \(AppFormat.shortDate(date)) \(AppFormat.time(date))"
        case let .failed(message): message
        }
    }
}
