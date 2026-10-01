import SwiftUI
import TravellerKit

struct TripDetailView: View {
    @Environment(TripStore.self) private var store
    let tripID: Trip.ID
    @State private var section: TripSection
    @State private var coverTarget: Trip.ID?
    @State private var isHeroCollapsed = false

    init(tripID: Trip.ID, initialSection: TripSection = .plan) {
        self.tripID = tripID
        _section = State(initialValue: initialSection)
    }

    enum TripSection: String, CaseIterable, Hashable {
        case plan, money, packing, visa, crew

        var title: String {
            switch self {
            case .plan: "Plan"
            case .money: "Bütçe"
            case .packing: "Valiz"
            case .visa: "Vize"
            case .crew: "Ekip"
            }
        }

        var symbol: String {
            switch self {
            case .plan: "map.fill"
            case .money: "chart.pie.fill"
            case .packing: "bag.fill"
            case .visa: "person.text.rectangle.fill"
            case .crew: "person.2.fill"
            }
        }
    }

    static let heroHeight: CGFloat = 300

    var body: some View {
        if let trip = store.trip(tripID) {
            let tint = trip.tint
            ScrollView {
                VStack(spacing: 0) {
                    TripHero(trip: trip, height: Self.heroHeight, isCollapsed: $isHeroCollapsed)

                    TripStub(trip: trip)
                        .padding(.horizontal, 16)
                        .padding(.top, -44)

                    SectionTabs(selection: $section)
                        .padding(.top, 16)

                    Group {
                        switch section {
                        case .plan: PlanSection(trip: trip)
                        case .money: MoneySection(trip: trip)
                        case .packing: PackingSection(trip: trip)
                        case .visa: VisaSection(trip: trip)
                        case .crew: CrewSection(trip: trip)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                    .transition(.opacity)
                    .id(section)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(TintGlow(tint: tint, offsetY: 260))
            .environment(\.tripTint, tint)
            .navigationTitle(isHeroCollapsed ? trip.name : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isHeroCollapsed ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(isHeroCollapsed ? nil : .dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    coverMenu(trip)
                }
            }
            .coverPhotoPicker(for: $coverTarget)
            .animation(.easeInOut(duration: 0.2), value: isHeroCollapsed)
            .animation(.easeInOut(duration: 0.2), value: section)
        } else {
            ContentUnavailableView("Seyahat bulunamadı", systemImage: "suitcase")
        }
    }

    private func coverMenu(_ trip: Trip) -> some View {
        Menu {
            Button("Kapak fotoğrafı seç", systemImage: "photo") { coverTarget = trip.id }
            if trip.coverPhoto != nil {
                Button("Fotoğrafı kaldır", systemImage: "photo.badge.minus", role: .destructive) {
                    withAnimation { store.removeCoverPhoto(for: trip.id) }
                }
            }
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: 14, weight: .semibold))
        }
        .accessibilityLabel("Kapak fotoğrafı")
    }
}

// MARK: - Hero

/// Aşağı çekince esneyen, yukarı kayınca gezinme çubuğuna devreden kapak.
struct TripHero: View {
    let trip: Trip
    let height: CGFloat
    @Binding var isCollapsed: Bool

    var body: some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView).minY
            let stretch = max(0, minY)
            ZStack(alignment: .bottomLeading) {
                TripCover(trip: trip)
                    .frame(width: proxy.size.width, height: height + stretch)
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    let tag = trip.countdownTag
                    Text(tag.text)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent.base)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                    Text(trip.name)
                        .font(.system(.largeTitle, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("\(Countries.flag(trip.destination.countryCode)) \(trip.destination.city), \(Countries.name(trip.destination.countryCode))")
                        .font(.system(.subheadline, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 60)
            }
            .frame(width: proxy.size.width, height: height + stretch)
            .offset(y: -stretch)
            .onChange(of: minY < -(height - 140)) { _, collapsed in
                isCollapsed = collapsed
            }
        }
        .frame(height: height)
    }
}

// MARK: - Stub

/// Kapağın altına binen bilet koçanı: rota, tarih, gece, ekip.
struct TripStub: View {
    let trip: Trip
    @Environment(\.tripTint) private var tint
    @State private var isLiveActivityRunning = false
    private var flightStatus: FlightStatusService { .shared }

    var body: some View {
        VStack(spacing: 14) {
            if let flight = trip.primaryFlight {
                HStack(spacing: 12) {
                    endpoint(flight.fromCode, "\(flight.fromCity) · \(AppFormat.time(flight.effectiveDeparture, timeZone: flight.departureTimeZone))")
                    VStack(spacing: 2) {
                        FlightArc(accent: tint).frame(height: 26)
                        Text(AppFormat.duration(minutes: flight.durationMinutes))
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                    }
                    endpoint(flight.toCode, "\(AppFormat.time(flight.effectiveArrival, timeZone: flight.arrivalTimeZone)) · \(flight.toCity)",
                             trailing: true)
                }
                if flight.live != nil || (flightStatus.isConfigured && FlightStatusService.isWatched(flight)) {
                    liveStatus(flight)
                }
                Divider().overlay(Color.line)
            }
            HStack(alignment: .top) {
                meta("Tarih", AppFormat.dateRange(trip.startDate, trip.endDate))
                Spacer()
                meta("Konaklama", "\(trip.nights()) gece")
                Spacer()
                if let flight = trip.primaryFlight, let seat = flight.seat {
                    meta("Koltuk", seat)
                    Spacer()
                }
                AvatarStack(members: trip.members, size: 30, limit: 3)
            }
            if LiveActivityController.canStart(for: trip) {
                let running = isLiveActivityRunning
                Button {
                    if running { LiveActivityController.stop(for: trip) } else { LiveActivityController.start(for: trip) }
                    isLiveActivityRunning.toggle()
                } label: {
                    Label(running ? "Kilit ekranından kaldır" : "Kilit ekranında göster",
                          systemImage: running ? "lock.slash" : "lock.iphone")
                        .font(.system(.subheadline, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(running ? Color.ink : Color.onInk)
                        .background(running ? Color.track : Color.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear { isLiveActivityRunning = LiveActivityController.isRunning(for: trip) }
        .padding(18)
        .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.tray, style: .continuous))
        .overlay(alignment: .top) {
            Capsule().fill(tint).frame(width: 36, height: 4).offset(y: -2)
        }
    }

    /// Servisten gelen durum: "Rötarlı +40 dk", kapı/terminal, son kontrol zamanı ve yenileme.
    private func liveStatus(_ flight: FlightSegment) -> some View {
        let accent: Color = flight.live?.phase == .canceled ? .red : (flight.isDelayed ? Accent.orange.base : Accent.green.base)
        let checked = flightStatus.lastChecked[flight.id] ?? flight.live?.fetchedAt
        let isChecking = flightStatus.checking.contains(flight.id)
        return HStack(spacing: 8) {
            Text(flight.statusText ?? "Durum bekleniyor")
                .font(.system(.footnote, weight: .bold))
                .foregroundStyle(flight.live == nil ? Color.ink2 : accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background((flight.live == nil ? Color.ink3 : accent).opacity(0.14), in: Capsule())
            if flight.isDelayed {
                Text(AppFormat.time(flight.departure, timeZone: flight.departureTimeZone))
                    .font(.footnote)
                    .strikethrough()
                    .foregroundStyle(Color.ink3)
            }
            if let terminal = flight.live?.departureTerminal {
                Text("T\(terminal)").font(.footnote.weight(.semibold)).foregroundStyle(Color.ink2)
            }
            Spacer(minLength: 4)
            if let checked {
                Text(checked, style: .relative)
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(1)
            }
            if flightStatus.isConfigured {
                Button {
                    Task { await flightStatus.refresh(flightID: flight.id, in: trip.id, force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(isChecking ? 360 : 0))
                        .animation(isChecking ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                                   value: isChecking)
                }
                .buttonStyle(.circleIcon(size: 28))
                .disabled(isChecking)
                .accessibilityLabel("Uçuş durumunu yenile")
            }
        }
    }

    private func endpoint(_ code: String, _ detail: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(code).font(.system(.title, weight: .semibold)).foregroundStyle(Color.ink)
            Text(detail).font(.caption).foregroundStyle(Color.ink2).lineLimit(1)
        }
        .fixedSize()
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.tCaption).foregroundStyle(Color.ink3)
            Text(value).font(.system(.subheadline, weight: .semibold)).foregroundStyle(Color.ink)
        }
    }
}

// MARK: - Tabs

/// İkonlu sekme hapları; seçili sekmenin ikonu seyahat rengini alır.
struct SectionTabs: View {
    @Binding var selection: TripDetailView.TripSection
    @Environment(\.tripTint) private var tint
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
                                .labelStyle(TintedIconLabelStyle(iconColor: isSelected ? tint : Color.ink3))
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
