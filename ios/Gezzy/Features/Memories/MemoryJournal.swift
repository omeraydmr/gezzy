import MapKit
import SwiftUI
import GezzyKit

/// Harita üzerinde günlük: gün seçilir, o günün anları haritada fotoğraf pini, altında liste.
struct MemoryJournal: View {
    let trip: Trip
    let moments: [PhotoClusterer.Moment]
    let onOpen: (PhotoViewerContext) -> Void
    /// Bu seyahatte gizlenmiş fotoğraf sayısı; 0 değilse sonda "Göster" satırı.
    var hiddenCount: Int = 0
    var onShowHidden: () -> Void = {}

    @Environment(\.tripPalette) private var palette
    @Environment(\.tripTint) private var tint
    @Environment(\.tripText) private var tripText
    @State private var selection: Date
    @State private var camera: MapCameraPosition = .automatic
    @State private var expanded: String?
    @State private var flashed: String?

    init(trip: Trip, moments: [PhotoClusterer.Moment], onOpen: @escaping (PhotoViewerContext) -> Void,
         hiddenCount: Int = 0, onShowHidden: @escaping () -> Void = {}) {
        self.trip = trip
        self.moments = moments
        self.onOpen = onOpen
        self.hiddenCount = hiddenCount
        self.onShowHidden = onShowHidden
        // İlk fotoğraflı gün seçili başlar.
        let first = moments.map(\.start).min().map { Calendar.current.startOfDay(for: $0) }
        _selection = State(initialValue: first ?? trip.days().first ?? Calendar.current.startOfDay(for: .now))
    }

    private var dayMoments: [PhotoClusterer.Moment] {
        moments.filter { Calendar.current.isDate($0.start, inSameDayAs: selection) }.sorted { $0.start < $1.start }
    }

    var body: some View {
        let today = dayMoments
        VStack(alignment: .leading, spacing: 12) {
            DayChips(days: trip.days(), selection: $selection, stopCount: photoCount(on:),
                     countLabel: { String(localized: "\($0) fotoğraf") })
            if today.contains(where: { $0.center != nil }) || trip.stops(on: selection).contains(where: { $0.coordinate != nil }) {
                map(today)
            }
            ScrollViewReader { reader in
                VStack(alignment: .leading, spacing: 10) {
                    Text(dayTitle(selection)).font(.tCaption).foregroundStyle(Color.ink3)
                    if today.isEmpty {
                        Text("Bu günde fotoğraf yok.").font(.tBody).foregroundStyle(Color.ink2)
                    } else {
                        ForEach(today) { moment in
                            momentRow(moment)
                                .padding(8)
                                .background(tint.opacity(flashed == moment.id ? 0.14 : 0),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .id(moment.id)
                        }
                    }
                }
                .tray(padding: 14)
                .onChange(of: flashed) { _, id in
                    guard let id else { return }
                    withAnimation(.spring(duration: 0.35)) { reader.scrollTo(id, anchor: .center) }
                }
            }
            if hiddenCount > 0 {
                Button(action: onShowHidden) {
                    HStack(spacing: 4) {
                        Text("\(hiddenCount) gizli fotoğraf").foregroundStyle(Color.ink3)
                        Text("· Göster").fontWeight(.semibold).foregroundStyle(tripText)
                    }
                    .font(.tBody)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Harita

    private func map(_ today: [PhotoClusterer.Moment]) -> some View {
        let located = today.compactMap { m in m.center.map { (moment: m, coordinate: cl($0)) } }
        let stops = trip.stops(on: selection).compactMap { s in s.coordinate.map { (stop: s, coordinate: cl($0)) } }
        let route = stops.map(\.coordinate)
        // Pin yoksa duraklar çerçevelenir.
        let framed = located.isEmpty ? route : located.map(\.coordinate)
        return Map(position: $camera) {
            if route.count > 1 {
                MapPolyline(coordinates: route)
                    .stroke(Color(hex: palette.accent).opacity(0.5), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(Array(stops.enumerated()), id: \.element.stop.id) { index, item in
                Annotation(item.stop.name, coordinate: item.coordinate, anchor: .bottom) {
                    NumberedPin(number: index + 1, color: palette.pin(index), size: 24).opacity(0.45)
                }
                .annotationTitles(.hidden)
            }
            ForEach(located, id: \.moment.id) { item in
                Annotation(item.moment.stopName ?? "", coordinate: item.coordinate, anchor: .center) {
                    Button { flash(item.moment.id) } label: { photoPin(item.moment) }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(pinLabel(item.moment)))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // Gün ya da anlar değişince yeniden çerçevelenir.
        .task(id: framed.map { "\($0.latitude),\($0.longitude)" }) {
            camera = MapFraming.position(framed)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
    }

    private func photoPin(_ moment: PhotoClusterer.Moment) -> some View {
        PhotoThumb(id: moment.photoIDs[moment.photoIDs.count / 2], side: 44)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                Text("\(moment.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(tint, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                    .offset(x: 6, y: -6)
                    .accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }

    /// "<durak ya da saat>, N fotoğraf"
    private func pinLabel(_ moment: PhotoClusterer.Moment) -> String {
        String(localized: "\(moment.stopName ?? timeRange(moment)), \(moment.count) fotoğraf")
    }

    /// Pine dokununca liste o ana kayar ve 1 sn vurgulanır.
    private func flash(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) { flashed = id }
        Task {
            try? await Task.sleep(for: .seconds(1))
            if flashed == id { withAnimation(.easeInOut(duration: 0.3)) { flashed = nil } }
        }
    }

    // MARK: Anlar

    private func momentRow(_ moment: PhotoClusterer.Moment) -> some View {
        let isExpanded = expanded == moment.id
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded = isExpanded ? nil : moment.id }
                // Harita o ana gider.
                if let center = moment.center {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        camera = .region(MKCoordinateRegion(center: cl(center), latitudinalMeters: 1_500,
                                                            longitudinalMeters: 1_500))
                    }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(moment.stopName ?? timeRange(moment)).font(.tBodyStrong).foregroundStyle(Color.ink)
                        Text(moment.stopName == nil ? String(localized: "\(moment.count) fotoğraf") : String(localized: "\(timeRange(moment)) · \(moment.count) fotoğraf"))
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 4)], spacing: 4) {
                    ForEach(Array(moment.photoIDs.enumerated()), id: \.element) { index, id in
                        openable(moment, index) { PhotoThumb(id: id, side: 76) }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(moment.photoIDs.prefix(10).enumerated()), id: \.element) { index, id in
                            openable(moment, index) { PhotoThumb(id: id, side: 64) }
                        }
                    }
                }
            }
        }
    }

    /// Dokununca anın fotoğrafları tam ekran açılır.
    private func openable<Thumb: View>(_ moment: PhotoClusterer.Moment, _ index: Int,
                                       @ViewBuilder thumb: () -> Thumb) -> some View {
        Button {
            onOpen(PhotoViewerContext(items: moment.photoIDs.map { .library($0) }, index: index))
        } label: {
            thumb()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fotoğrafı aç")
    }

    // MARK: Yardımcılar

    private func photoCount(on day: Date) -> Int {
        moments.filter { Calendar.current.isDate($0.start, inSameDayAs: day) }.reduce(0) { $0 + $1.count }
    }

    private func cl(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    private func dayTitle(_ day: Date) -> String {
        let number = (trip.days().firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } ?? 0) + 1
        return String(localized: "\(number). gün · \(AppFormat.dayPill(day))")
    }

    private func timeRange(_ moment: PhotoClusterer.Moment) -> String {
        let start = AppFormat.time(moment.start)
        let end = AppFormat.time(moment.end)
        return start == end ? start : "\(start)–\(end)"
    }
}
