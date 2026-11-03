import SwiftUI
import GezzyKit

/// Alttaki çekmece: hedef, arama, filtre ve popülerliğe göre sıralı liste.
struct PlacePickerList: View {
    @Environment(\.tripPalette) private var palette
    @Environment(TripStore.self) private var store
    let trip: Trip
    @Bindable var model: PlacePickerModel
    @Binding var detent: PresentationDetent
    let onFocus: (String) -> Void
    let onRetry: () -> Void
    let onDone: () -> Void

    @FocusState private var searchFocused: Bool
    @State private var isAddingManually = false

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            filterChips
            ScrollViewReader { proxy in
                List {
                    banners
                    ForEach(model.visibleNextGroups) { group in
                        Section {
                            ForEach(group.places) { row($0) }
                        } header: {
                            Text("\(group.anchor) sonrası gezginler genelde")
                        }
                    }
                    Section {
                        ForEach(model.rows) { row($0) }
                        if model.rows.isEmpty && !model.isLoading && model.errorText == nil && !model.noCenter {
                            Text(model.isFiltering ? String(localized: "Aramaya uyan yer bulunamadı.")
                                                   : String(localized: "Bu şehir için yeni öneri bulunamadı."))
                                .foregroundStyle(Color.ink2)
                        }
                        Button {
                            isAddingManually = true
                        } label: {
                            Label("Listede yok mu? Elle ekle", systemImage: "square.and.pencil")
                        }
                    } footer: {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Haritada bir yere dokun ya da basılı tutarak iğne bırak; oradan da eklenir.",
                                  systemImage: "hand.tap")
                            Text("Popülerlik Wikipedia'da son 30 günde okunma ve Gezzy gezginlerinin seçimlerinden gelir.")
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .onChange(of: model.focusedID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .onChange(of: searchFocused) { _, focused in
            if focused { detent = .large }
        }
        .sheet(isPresented: $isAddingManually) {
            ManualPlaceForm(initialName: model.query, day: trip.startDate) { stop in
                model.insert(stop, store: store, tripID: trip.id)
            }
        }
        .sensoryFeedback(.success, trigger: model.added.count)
    }

    // MARK: Üst kısım

    private var header: some View {
        HStack {
            Menu {
                Button {
                    model.target = .ideas
                } label: {
                    Label("Fikirler", systemImage: "lightbulb")
                }
                ForEach(Array(trip.days().enumerated()), id: \.element) { index, day in
                    Button(String(localized: "\(index + 1). gün · \(AppFormat.dayPill(day))")) { model.target = .day(day) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Ekleneceği yer:").foregroundStyle(Color.ink2)
                    Text(targetTitle).foregroundStyle(Color.ink).bold()
                    Image(systemName: "chevron.down").font(.caption).foregroundStyle(Color.ink2)
                }
                .font(.subheadline)
            }
            Spacer()
            Button("Bitti", action: onDone).bold()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var targetTitle: String {
        switch model.target {
        case .ideas: return String(localized: "Fikirler")
        case .day(let day):
            let number = (trip.days().firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } ?? 0) + 1
            return String(localized: "\(number). gün")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.ink3)
            TextField("\(model.leg(in: trip).destination.city) içinde ara", text: $model.query)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if model.isSearching {
                ProgressView().controlSize(.small)
            } else if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.ink3)
                }
                .accessibilityLabel("Aramayı temizle")
            }
        }
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 16)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlacePickerModel.Filter.allCases, id: \.self) { filter in
                    let isOn = model.filter == filter
                    Button(filter.title) { withAnimation { model.filter = filter } }
                        .font(.subheadline.weight(isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? Color.onInk : Color.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isOn ? Color.ink : Color(.tertiarySystemFill), in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: Bantlar

    @ViewBuilder
    private var banners: some View {
        if model.isLoading && model.rows.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                Text("\(model.leg(in: trip).destination.city) için yerler aranıyor…").foregroundStyle(Color.ink2)
            }
        }
        if let errorText = model.errorText {
            Section {
                Label(errorText, systemImage: "exclamationmark.triangle").foregroundStyle(Color.food)
                Button("Tekrar dene", action: onRetry)
            }
        }
        if model.noCenter && !model.isFiltering {
            Label("Şehrin konumu bulunamadı. Aramak için bir yer adı yaz.", systemImage: "magnifyingglass")
                .foregroundStyle(Color.ink2)
        }
    }

    // MARK: Satır

    @ViewBuilder
    private func row(_ item: PlaceRanking.Ranked) -> some View {
        let content = rowContent(item).id(item.id)
        if item.suggestion.contributors != nil {
            content.contextMenu {
                Menu("Bildir", systemImage: "flag") {
                    ForEach(CommunityService.ReportReason.allCases) { reason in
                        Button(reason.title) { model.report(item, reason: reason) }
                    }
                }
            }
        } else {
            content
        }
    }

    private func rowContent(_ item: PlaceRanking.Ranked) -> some View {
        let isAdded = model.added[item.id] != nil
        let number = model.number(of: item.id) ?? 0
        return HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(isAdded ? Color.success : palette.pin(number - 1), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(item.suggestion.name).foregroundStyle(Color.ink).lineLimit(2)
                if let badge = item.badge { badgeView(badge) }
                Text(detail(item)).font(.caption).foregroundStyle(Color.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.spring(duration: 0.25)) { model.toggle(item, store: store, trip: trip) }
            } label: {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(isAdded ? Color.success : Color.ink)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isAdded ? String(localized: "Eklemeyi geri al") : String(localized: "Ekle"))
        }
        .contentShape(Rectangle())
        .onTapGesture { onFocus(item.id) }
        .listRowBackground(model.focusedID == item.id ? Color.success.opacity(0.08) : nil)
    }

    @ViewBuilder
    private func badgeView(_ badge: PlaceRanking.Badge) -> some View {
        switch badge {
        case .community(let count):
            HStack(spacing: 4) {
                Image(systemName: "person.3.sequence.fill")
                Text(String(localized: "Gezginler seçti · \(count) kişi"))
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Color.success)
        case .veryPopular:
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                Text("Çok popüler")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Color.food)
        case .popular:
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                Text("Popüler")
            }
            .font(.caption.weight(.semibold)).foregroundStyle(Color.ink2)
        }
    }

    private func detail(_ item: PlaceRanking.Ranked) -> String {
        var parts = [item.suggestion.category, AppFormat.duration(minutes: item.suggestion.duration)]
        if let center = model.center {
            parts.append(String(localized: "Merkeze \(AppFormat.distance(meters: Geo.distance(center, item.suggestion.coordinate)))"))
        }
        return parts.joined(separator: " · ")
    }
}
