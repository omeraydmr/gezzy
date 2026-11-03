import SwiftUI
import GezzyKit

private struct OpenReservationsKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Plan'daki otel/uçuş satırından Rezervasyon sekmesine geçiş.
    var openReservations: () -> Void {
        get { self[OpenReservationsKey.self] }
        set { self[OpenReservationsKey.self] = newValue }
    }
}

struct TripDetailView: View {
    @Environment(TripStore.self) private var store
    let tripID: Trip.ID
    @State private var section: TripSection
    @State private var coverTarget: Trip.ID?
    @State private var isEditingTrip = false
    @Environment(Entitlements.self) private var entitlements
    @State private var isShowingPaywall = false
    @State private var saveMapsAfterPaywall = false
    @State private var calendarMessage: String?
    @State private var isHeroCollapsed = false
    @State private var isLiveActivityRunning = false

    init(tripID: Trip.ID, initialSection: TripSection = .plan) {
        self.tripID = tripID
        _section = State(initialValue: initialSection)
    }

    enum TripSection: String, CaseIterable, Hashable {
        case plan, reservations, money, packing, visa, crew, memories

        var title: String {
            switch self {
            case .plan: String(localized: "Plan")
            case .reservations: String(localized: "Rezervasyon")
            case .money: String(localized: "Bütçe")
            case .packing: String(localized: "Valiz")
            case .visa: String(localized: "Vize")
            case .crew: String(localized: "Ekip")
            case .memories: String(localized: "Anılar")
            }
        }

        var symbol: String {
            switch self {
            case .plan: "map.fill"
            case .reservations: "suitcase.rolling.fill"
            case .money: "chart.pie.fill"
            case .packing: "bag.fill"
            case .visa: "person.text.rectangle.fill"
            case .crew: "person.2.fill"
            case .memories: "photo.on.rectangle.angled"
            }
        }
    }

    static let heroHeight: CGFloat = 180

    var body: some View {
        if let trip = store.trip(tripID) {
            let palette = trip.palette
            let tint = Color(hex: palette.accent)
            let canEdit = store.canEdit(trip)
            GeometryReader { outer in
            ScrollView {
                VStack(spacing: 0) {
                    TripHero(trip: trip, height: Self.heroHeight + outer.safeAreaInsets.top, topInset: outer.safeAreaInsets.top, isCollapsed: $isHeroCollapsed)

                    TripTicketRow(trip: trip)
                        .padding(.horizontal, 16)
                        .padding(.top, -28)

                    if !canEdit {
                        Label("Bu seyahati yalnızca görüntüleyebilirsin", systemImage: "eye")
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(Color.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.track, in: Capsule())
                            .padding(.top, 12)
                    }

                    SectionTabs(selection: $section)
                        .padding(.top, 16)

                    Group {
                        switch section {
                        case .plan: PlanSection(trip: trip)
                        case .reservations: ReservationsSection(trip: trip)
                        case .money: MoneySection(trip: trip)
                        case .packing: PackingSection(trip: trip)
                        case .visa: VisaSection(trip: trip)
                        case .crew: CrewSection(trip: trip)
                        case .memories: MemoriesSection(trip: trip)
                        }
                    }
                    // Görüntüleyici: düğmeler ve alanlar kapalı (anılar yalnızca okuma olduğu için açık kalır).
                    .disabled(!canEdit && section != .memories)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                    .transition(.opacity)
                    .id(section)
                }
            }
            .ignoresSafeArea(edges: .top)
            }
            .background(TintGlow(tint: tint, offsetY: 260))
            .environment(\.tripTint, tint)
            .environment(\.tripPalette, palette)
            .environment(\.tripText, palette.accentText)
            .environment(\.openReservations) { section = .reservations }
            .navigationTitle(isHeroCollapsed ? trip.name : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isHeroCollapsed ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(isHeroCollapsed ? nil : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    coverMenu(trip)
                }
            }
            .onAppear { isLiveActivityRunning = LiveActivityController.isRunning(for: trip) }
            .coverPhotoPicker(for: $coverTarget)
            .sheet(isPresented: $isEditingTrip) { TripEditSheet(trip: trip) }
            .sheet(isPresented: $isShowingPaywall, onDismiss: {
                if saveMapsAfterPaywall {
                    saveMapsAfterPaywall = false
                    Task { await OfflineMapStore.shared.save(trip) }
                }
            }) {
                PaywallSheet(reason: .offlineMaps) { saveMapsAfterPaywall = true }
            }
            .alert("Takvim", isPresented: Binding(get: { calendarMessage != nil }, set: { if !$0 { calendarMessage = nil } })) {
                Button("Tamam", role: .cancel) {}
            } message: {
                Text(calendarMessage ?? "")
            }
            .animation(.easeInOut(duration: 0.2), value: isHeroCollapsed)
            .animation(.easeInOut(duration: 0.2), value: section)
        } else {
            ContentUnavailableView("Seyahat bulunamadı", systemImage: "suitcase")
        }
    }

    private func coverMenu(_ trip: Trip) -> some View {
        Menu {
            Button("Seyahati düzenle", systemImage: "pencil") { isEditingTrip = true }
            Button("Takvime aktar", systemImage: "calendar.badge.plus") {
                Task {
                    do {
                        let count = try await CalendarExporter.export(trip)
                        calendarMessage = count == 0
                            ? String(localized: "Aktarılacak uçuş, konaklama ya da saatli durak yok.")
                            : String(localized: "\(count) etkinlik Takvim'deki Gezzy takvimine eklendi. Planı değiştirince tekrar aktarabilirsin.")
                    } catch {
                        calendarMessage = error.localizedDescription
                    }
                }
            }
            Button("Haritaları internetsiz kaydet", systemImage: entitlements.isPremium ? "arrow.down.circle" : "lock") {
                if entitlements.isPremium {
                    Task { await OfflineMapStore.shared.save(trip) }
                } else {
                    isShowingPaywall = true
                }
            }
            if LiveActivityController.canStart(for: trip) {
                let running = isLiveActivityRunning
                Button(running ? String(localized: "Kilit ekranından kaldır") : String(localized: "Kilit ekranında göster"),
                       systemImage: running ? "lock.slash" : "lock.iphone") {
                    if running { LiveActivityController.stop(for: trip) } else { LiveActivityController.start(for: trip) }
                    isLiveActivityRunning.toggle()
                }
            }
            Button("Kapak fotoğrafı seç", systemImage: "photo") { coverTarget = trip.id }
            if trip.coverPhoto != nil {
                Button("Fotoğrafı kaldır", systemImage: "photo.badge.minus", role: .destructive) {
                    withAnimation { store.removeCoverPhoto(for: trip.id) }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
        }
        .accessibilityLabel("Seyahat seçenekleri")
    }
}

// MARK: - Hero

/// Aşağı çekince esneyen, yukarı kayınca gezinme çubuğuna devreden kapak.
struct TripHero: View {
    @Environment(\.tripText) private var tintText
    let trip: Trip
    let height: CGFloat
    /// Üst güvenli alan: başlık bloğu gezinme düğmelerinin altında kalır.
    var topInset: CGFloat = 0
    @Binding var isCollapsed: Bool

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let stretch = max(0, minY)
            ZStack(alignment: .bottomLeading) {
                TripCover(trip: trip)
                    .frame(width: proxy.size.width, height: height + stretch)
                    .clipped()
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .clear, location: 0.3),
                                       .init(color: .clear, location: 0.45), .init(color: .black.opacity(0.6), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    let tag = trip.countdownTag
                    Text(trip.name)
                        .font(.system(.title, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 8) {
                        Text(trip.isMultiCity
                             ? "\(trip.countryCodes.map(Countries.flag).joined()) \(trip.cityTitle)"
                             : "\(Countries.flag(trip.destination.countryCode)) \(trip.destination.city), \(Countries.name(trip.destination.countryCode))")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text(tag.text)
                            .font(.system(.caption, weight: .semibold))
                            // Geri sayım seyahat renginde; taslak (turuncu) ve geçmiş (gri) durum rengi kalır.
                            .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent == .orange ? tag.accent.base : tintText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .fixedSize()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 44)
            }
            .frame(width: proxy.size.width, height: height + stretch)
            .offset(y: -stretch)
            .onChange(of: minY < -(height - topInset - 80)) { _, collapsed in
                isCollapsed = collapsed
            }
        }
        .frame(height: height)
    }
}

// MARK: - Ticket

/// Kapağın altına binen tek satırlık bilet: rota, tarih, gece, ekip. Dokununca Rezervasyon sekmesi.
struct TripTicketRow: View {
    let trip: Trip
    @Environment(\.tripTint) private var tint
    @Environment(\.openReservations) private var openReservations

    var body: some View {
        Button { openReservations() } label: {
            ViewThatFits(in: .horizontal) {
                line(times: true, nights: true)
                line(times: true, nights: false)
                line(times: false, nights: false)
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
            .overlay(alignment: .top) {
                Capsule().fill(tint).frame(width: 36, height: 4).offset(y: -2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .accessibilityHint("Rezervasyonları aç")
    }

    private var dates: String { AppFormat.dateRange(trip.startDate, trip.endDate) }
    private var nightsText: String { String(localized: "\(trip.nights()) gece") }

    private var summary: String {
        var parts: [String] = []
        if let f = trip.primaryFlight {
            parts.append("\(f.fromCode) \(AppFormat.time(f.departure, timeZone: f.departureTimeZone)) – \(f.toCode) \(AppFormat.time(f.arrival, timeZone: f.arrivalTimeZone))")
        }
        parts.append(dates)
        parts.append(nightsText)
        parts.append(String(localized: "\(trip.members.count) kişi"))
        return parts.joined(separator: ", ")
    }

    private func line(times: Bool, nights: Bool) -> some View {
        HStack(spacing: 8) {
            if let flight = trip.primaryFlight {
                Group {
                    Text(flight.fromCode).font(.system(.subheadline, weight: .semibold))
                    if times {
                        Text(AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))
                            .font(.footnote).foregroundStyle(Color.ink2)
                    }
                    Image(systemName: "airplane").font(.caption).foregroundStyle(tint)
                    if times {
                        Text(AppFormat.time(flight.arrival, timeZone: flight.arrivalTimeZone))
                            .font(.footnote).foregroundStyle(Color.ink2)
                    }
                    Text(flight.toCode).font(.system(.subheadline, weight: .semibold))
                }
                .lineLimit(1)
                .fixedSize()
                Circle().fill(Color.ink3).frame(width: 3, height: 3)
            } else {
                Image(systemName: "calendar").font(.caption).foregroundStyle(tint)
            }
            Text(nights ? "\(dates) · \(nightsText)" : dates)
                .font(.footnote)
                .foregroundStyle(Color.ink2)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            AvatarStack(members: trip.members, size: 26, limit: 3)
        }
    }
}

// MARK: - Tabs

/// İkonlu sekme hapları; seçili sekmenin ikonu seyahat rengini alır.
struct SectionTabs: View {
    @Binding var selection: TripDetailView.TripSection
    @Environment(\.tripText) private var tintText
    @Namespace private var namespace

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TripDetailView.TripSection.allCases, id: \.self) { section in
                        let isSelected = section == selection
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                selection = section
                                reader.scrollTo(section, anchor: .center)
                            }
                        } label: {
                            Label(section.title, systemImage: section.symbol)
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.ink : Color.ink2)
                                .labelStyle(TintedIconLabelStyle(iconColor: isSelected ? tintText : Color.ink3))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.tray)
                                            .softShadow()
                                            .matchedGeometryEffect(id: "tab", in: namespace)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(section)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
    }
}

struct TintedIconLabelStyle: LabelStyle {
    let iconColor: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(iconColor)
            configuration.title
        }
    }
}
