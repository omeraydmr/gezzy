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
    /// Gerçekte açık bölüm; "Daha fazla" altındakiler için `moreOpen` ile birlikte okunur.
    @State private var section: TripSection
    @State private var selectedTab: TripTab
    /// "Daha fazla" sekmesinde bir bölüm açık mı (değilse ızgara görünür).
    @State private var moreOpen: Bool
    @State private var coverTarget: Trip.ID?
    @State private var isEditingTrip = false
    @Environment(Entitlements.self) private var entitlements
    @State private var isShowingPaywall = false
    @State private var saveMapsAfterPaywall = false
    @State private var calendarMessage: String?
    @State private var isHeroCollapsed = false
    @State private var isLiveActivityRunning = false
    /// Sekme çubuğu gezinme çubuğunun altına sabitlendi mi.
    @State private var isTabsPinned = false
    /// Sekme başlığının tam yüksekliği (gezinme çubuğu payı dahil).
    @State private var tabsHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Sekmeler sabitken içerik değişimi: önce eski içerik dururken sekme bandına kaydırılır, sonra değiştirilir.
    @State private var pendingSwitch: ContentSwitch?

    private struct ContentSwitch: Equatable {
        let id = UUID()
        let tab: TripTab
        let section: TripSection
        let moreOpen: Bool
    }

    init(tripID: Trip.ID, initialSection: TripSection = .plan) {
        self.tripID = tripID
        _section = State(initialValue: initialSection)
        _selectedTab = State(initialValue: initialSection.tab)
        _moreOpen = State(initialValue: initialSection.tab == .more)
    }

    enum TripSection: String, CaseIterable, Hashable {
        case plan, reservations, money, packing, visa, crew, memories

        var title: String {
            switch self {
            case .plan: String(localized: "Plan")
            case .reservations: String(localized: "Rezervasyon")
            case .money: String(localized: "Para")
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
    /// Bilet/not ile sekmeler, sekmeler ile içerik arasındaki görünür boşluk.
    private static let tabsGap: CGFloat = 16
    /// Sekme başlığının iç dikey boşluğu (sabitken cam bant).
    private static let tabsInset: CGFloat = 8
    private static let tabsAnchor = "tabs"

    var body: some View {
        if let trip = store.trip(tripID) {
            let palette = trip.palette
            let tint = Color(hex: palette.accent)
            let canEdit = store.canEdit(trip)
            GeometryReader { outer in
                // Gezinme çubuğunun alt kenarı (durum çubuğu + çubuk); kaydırma görünümü üst güvenli alanı yok sayar.
                let navBarBottom = outer.safeAreaInsets.top
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            VStack(spacing: 0) {
                                TripHero(trip: trip, height: Self.heroHeight + navBarBottom, topInset: navBarBottom, isCollapsed: $isHeroCollapsed)

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
                            }
                            // Sekme başlığının üstündeki boşluk (gezinme çubuğu payı) bu bloğun altına biner; aradaki görünür boşluk 16 pt kalır.
                            .padding(.bottom, Self.tabsGap - Self.tabsInset - navBarBottom)

                            Section {
                                VStack(spacing: 0) {
                                    // Kaydırma hedefi: içeriğin üst kenarı. LazyVStack ekran dışındaki öğeleri kurmadığı için
                                    // hedef, sabitken hep görünen içerik satırının içinde durur.
                                    Color.clear
                                        .frame(height: 1)
                                        .id(Self.tabsAnchor)
                                    tabContent(trip, canEdit: canEdit, palette: palette)
                                }
                                // Kısa içerikte de sabit konuma kaydırılabilsin: en az görünür alan eksi sekme bandı.
                                .frame(minHeight: max(0, outer.size.height + navBarBottom - tabsHeight), alignment: .top)
                            } header: {
                                pinnedTabs(navBarBottom: navBarBottom)
                            }
                        }
                    }
                    .ignoresSafeArea(edges: .top)
                    .onChange(of: pendingSwitch) { _, change in
                        guard let change else { return }
                        // Eski (uzun) içerik hâlâ yerindeyken sekme bandına kaydır; içerik sonra değişir. Önce
                        // değiştirip sonra kaydırmak, kısalan içerikte ofseti içeriğin sonunun ötesinde bırakıp
                        // boş ekran gösteriyordu.
                        let viewport = outer.size.height + navBarBottom
                        let anchor = UnitPoint(x: 0.5, y: viewport > 0 ? min(1, tabsHeight / viewport) : 0)
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) { proxy.scrollTo(Self.tabsAnchor, anchor: anchor) }
                        DispatchQueue.main.async {
                            apply(change)
                            pendingSwitch = nil
                        }
                    }
                }
            }
            .background(TintGlow(tint: tint, offsetY: 260))
            .environment(\.tripTint, tint)
            .environment(\.tripPalette, palette)
            .environment(\.tripText, palette.accentText)
            .environment(\.openReservations) { selectTab(.reservations) }
            .navigationTitle(isHeroCollapsed ? trip.name : "")
            .navigationBarTitleDisplayMode(.inline)
            // Sekmeler sabitken çubuğun camı sekme başlığından gelir: tek bant, tek ayraç.
            .toolbarBackground(isHeroCollapsed && !isTabsPinned ? .visible : .hidden, for: .navigationBar)
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
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isTabsPinned)
        } else {
            ContentUnavailableView("Seyahat bulunamadı", systemImage: "suitcase")
        }
    }

    /// Seçili sekmenin içeriği: "Daha fazla" ızgarası ya da açık bölüm.
    private func tabContent(_ trip: Trip, canEdit: Bool, palette: TripPalette) -> some View {
        Group {
            if selectedTab == .more && !moreOpen {
                MoreSections(trip: trip) { opened in
                    switchContent(tab: .more, section: opened, moreOpen: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if moreOpen {
                        Button { switchContent(tab: .more, section: section, moreOpen: false) } label: {
                            Label("Daha fazla", systemImage: "chevron.left")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(palette.accentText)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    sectionContent(trip)
                        // Görüntüleyici: düğmeler ve alanlar kapalı (anılar yalnızca okuma olduğu için açık kalır).
                        .disabled(!canEdit && section != .memories)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, Self.tabsGap - Self.tabsInset)
        .padding(.bottom, 32)
        // Geçiş animasyonu yok: eski uzun içerik solarken yeni kısa içerik konumu bozuyordu.
        .id(contentID)
    }

    /// Sabitlenen sekme başlığı. Üstündeki saydam pay gezinme çubuğu kadar: kaydırma görünümü üstte (durum çubuğunun
    /// altında) sabitlediğinde sekmeler çubuğun hemen altında kalır; cam o payı da kaplar, çubukla tek bant olur.
    private func pinnedTabs(navBarBottom: CGFloat) -> some View {
        VStack(spacing: 0) {
            SectionTabs(selection: selectedTab, openSection: moreOpen ? section : nil, select: selectTab)
                .padding(.horizontal, 16)
                .padding(.vertical, Self.tabsInset)
        }
        .padding(.top, navBarBottom)
        .overlay(alignment: .bottom) {
            if isTabsPinned { Divider() }
        }
        .background {
            if isTabsPinned { Rectangle().fill(.bar) }
        }
        .background {
            GeometryReader { geo in
                let pinned = geo.frame(in: .scrollView).minY < 0.5
                let height = geo.size.height
                Color.clear
                    .onAppear { isTabsPinned = pinned; tabsHeight = height }
                    .onChange(of: pinned) { _, value in isTabsPinned = value }
                    .onChange(of: height) { _, value in tabsHeight = value }
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func sectionContent(_ trip: Trip) -> some View {
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

    /// İçeriğin kimliği: ızgara ya da açık bölüm. Değişince içerik yumuşakça yer değiştirir.
    private var contentID: String {
        selectedTab == .more && !moreOpen ? "more" : section.rawValue
    }

    /// Sekmeye dokunma; "Daha fazla" her dokunuşta ızgaraya döner.
    private func selectTab(_ tab: TripTab) {
        switchContent(tab: tab, section: tab.section ?? section, moreOpen: false)
    }

    /// Sekmeler sabitse önce kaydırma, sonra değişim (bkz. `pendingSwitch`); değilse konum korunur, doğrudan değişir.
    private func switchContent(tab: TripTab, section: TripSection, moreOpen: Bool) {
        let change = ContentSwitch(tab: tab, section: section, moreOpen: moreOpen)
        if isTabsPinned { pendingSwitch = change } else { apply(change) }
    }

    private func apply(_ change: ContentSwitch) {
        selectedTab = change.tab
        section = change.section
        moreOpen = change.moreOpen
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
                // Son çare: dar ekranda tarih küçülür, sığmazsa kesilir; satır kart dışına taşmaz.
                line(times: false, nights: false, shrinkDates: true)
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

    private func line(times: Bool, nights: Bool, shrinkDates: Bool = false) -> some View {
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
                .minimumScaleFactor(shrinkDates ? 0.75 : 1)
                .fixedSize(horizontal: !shrinkDates, vertical: false)
            Spacer(minLength: 0)
            AvatarStack(members: trip.members, size: 26, limit: 3)
        }
    }
}

// MARK: - Tabs

/// Dört eşit sekme; seçili olan seyahat rengiyle dolu. "Daha fazla" açık bölümün adını gösterir.
struct SectionTabs: View {
    let selection: TripTab
    /// "Daha fazla" altında açık bölüm (yoksa ızgara).
    let openSection: TripDetailView.TripSection?
    let select: (TripTab) -> Void
    @Environment(\.tripTint) private var tint
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TripTab.allCases, id: \.self) { tab in
                button(tab)
            }
        }
        .padding(4)
        .background(Color.track, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // Seçili zemin geçişi; Reduce Motion açıksa animasyonsuz (dıştaki içerik animasyonunu da ezer).
        .animation(reduceMotion ? nil : .spring(duration: 0.3), value: selection)
    }

    /// Sekme çubuğu düzeni: üstte simge, altta etiket; dört etiket 320 pt'de de sığar.
    private func button(_ tab: TripTab) -> some View {
        let isSelected = tab == selection
        let shown = tab == .more ? openSection : nil
        let title = shown?.title ?? tab.title
        let symbol = shown?.symbol ?? tab.symbol
        let iconOnly = dynamicTypeSize >= .accessibility1
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            select(tab)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.ink3)
                if !iconOnly {
                    Text(title)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.ink2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                if isSelected {
                    shape
                        .fill(tint)
                        .matchedGeometryEffect(id: "tab", in: namespace)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
