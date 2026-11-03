import SwiftUI
import GezzyKit

// MARK: - Adlar

extension ShareCardConfig.Template {
    var title: String {
        switch self {
        case .postcard: String(localized: "Kartpostal")
        case .stats: String(localized: "İstatistik")
        case .route: String(localized: "Rota")
        case .collage: String(localized: "Kolaj")
        case .ticket: String(localized: "Bilet")
        }
    }

    var symbol: String {
        switch self {
        case .postcard: "envelope"
        case .stats: "chart.bar"
        case .route: "map"
        case .collage: "square.grid.2x2"
        case .ticket: "ticket"
        }
    }

    /// Bilgi anahtarlarının gösterildiği şablonlar.
    var showsStats: Bool { self == .stats || self == .postcard || self == .ticket }
}

extension ShareCardConfig.Format {
    var title: String {
        switch self {
        case .story: String(localized: "Story")
        case .post: String(localized: "Gönderi")
        case .square: String(localized: "Kare")
        }
    }
}

extension ShareCardConfig.Stat {
    var title: String {
        switch self {
        case .days: String(localized: "Gün")
        case .stops: String(localized: "Durak")
        case .distance: String(localized: "Km")
        case .travellers: String(localized: "Kişi")
        case .spent: String(localized: "Harcama")
        case .perPerson: String(localized: "Kişi başı")
        }
    }
}

// MARK: - Kontroller

/// Stüdyonun düzenleme bölümleri: fotoğraf, renk, metin, bilgiler ve Gezzy işareti.
struct StudioControls: View {
    @Binding var config: ShareCardConfig
    let trip: Trip
    let highlights: [MemoryHighlights.Highlight]
    /// Gizliler çıkarılmış anlar.
    let moments: [PhotoClusterer.Moment]
    let isPremium: Bool
    /// Seçili ilk fotoğraftan türetilen palet (hesaplandıysa).
    var photoPalette: TripPalette?

    @Environment(\.tripPalette) private var tripPalette
    @State private var showsPaywall = false
    /// Satın alma bu ekranda yapıldıysa ortam değeri gelmeden de kapatılabilsin.
    @State private var purchased = false

    private var limit: Int { ShareCardConfig.photoLimit(config.template).upperBound }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if limit > 0 { photoSection }
            colorSection
            textSection
            if config.template.showsStats { statsSection }
            brandSection
        }
        .sheet(isPresented: $showsPaywall) {
            PaywallSheet(reason: .branding) {
                purchased = true
                config.showsBrand = false
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.tBodyStrong).foregroundStyle(Color.ink)
    }

    // MARK: Fotoğraf

    /// Sıra: favoriler, öne çıkanlar, diğer anlar; tekrarsız.
    private var candidates: [String] {
        let all = moments.flatMap(\.photoIDs)
        let favorites = MemoryPrefs.shared.favorites(trip.id)
        var seen = Set<String>()
        var result: [String] = []
        for id in all.filter(favorites.contains) + highlights.map(\.photoID) + all where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                header(String(localized: "Fotoğraf"))
                Spacer()
                Text("\(config.photoIDs.count)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.ink3)
            }
            if !PhotoLibrary.shared.canRead {
                Text("Fotoğraf seçmek için Anılar'dan erişim ver.")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
            } else if candidates.isEmpty {
                Text("Seyahat tarihlerinde çekilmiş fotoğraf bulunamadı.")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
                morePhotosButton
            } else {
                let minimum = ShareCardConfig.photoLimit(config.template).lowerBound
                if config.photoIDs.count < minimum {
                    Text("En az \(minimum) fotoğraf seç.")
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                    ForEach(candidates, id: \.self) { id in
                        photoTile(id)
                    }
                }
                morePhotosButton
            }
        }
    }

    /// Sınırlı erişimde seçimi genişletir; anlar Anılar'da yeniden yüklenir.
    @ViewBuilder private var morePhotosButton: some View {
        if PhotoLibrary.shared.isLimited {
            Button {
                Task { await PhotoLibrary.shared.presentLimitedPicker() }
            } label: {
                Label("Daha fazla fotoğraf seç", systemImage: "plus.circle")
                    .font(.system(.subheadline, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink)
        }
    }

    private func photoTile(_ id: String) -> some View {
        let order = config.photoIDs.firstIndex(of: id)
        return Button {
            toggle(id)
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        PhotoThumb(id: id, side: geometry.size.width)
                    }
                }
                .overlay {
                    if order != nil {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.ink, lineWidth: 3)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let order {
                        Text("\(order + 1)")
                            .font(.system(.caption2, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.onInk)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color.ink))
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(order.map { Text("Fotoğraf \($0 + 1), seçili") } ?? Text("Fotoğraf"))
        .accessibilityAddTraits(order != nil ? .isSelected : [])
    }

    /// Seç/bırak; sınır dolunca en eski seçim düşer.
    private func toggle(_ id: String) {
        if let index = config.photoIDs.firstIndex(of: id) {
            config.photoIDs.remove(at: index)
            if config.photoIDs.isEmpty && config.paletteID == "photo" { config.paletteID = nil }
            return
        }
        config.photoIDs.append(id)
        if config.photoIDs.count > limit {
            config.photoIDs.removeFirst(config.photoIDs.count - limit)
        }
    }

    // MARK: Renk

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(String(localized: "Renk"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    swatch(tripPalette, id: nil, label: String(localized: "Seyahat"))
                    if !config.photoIDs.isEmpty, let photoPalette {
                        swatch(photoPalette, id: "photo", label: String(localized: "Fotoğraf"))
                    }
                    ForEach(TripPalette.all, id: \.id) { palette in
                        swatch(palette, id: palette.id, label: nil)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
            }
        }
    }

    /// Fotoğraf paleti seçili ama hesaplanamadıysa (fotoğraf yok/yükleniyor) seyahat paleti seçili görünür.
    private var effectivePaletteID: String? {
        config.paletteID == "photo" && (config.photoIDs.isEmpty || photoPalette == nil) ? nil : config.paletteID
    }

    private func swatch(_ palette: TripPalette, id: String?, label: String?) -> some View {
        let isSelected = effectivePaletteID == id
        return Button {
            config.paletteID = id
        } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: palette.bands[0]), Color(hex: palette.accent)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 36, height: 36)
                    .padding(3)
                    .overlay(Circle().strokeBorder(isSelected ? Color.ink : .clear, lineWidth: 2))
                Text(label ?? " ")
                    .font(.caption2)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label ?? palette.id))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Metin

    private var textSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(String(localized: "Metin"))
            VStack(spacing: 0) {
                TextField(trip.name, text: textBinding(\.title))
                    .padding(.vertical, 12)
                Divider()
                TextField("\(trip.cityTitle) · \(AppFormat.dateRange(trip.startDate, trip.endDate))",
                          text: textBinding(\.subtitle))
                    .padding(.vertical, 12)
            }
            .font(.tBody)
            .padding(.horizontal, 16)
            .background(Color.tray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    /// Boş metin varsayılana döner; en çok 40 karakter (kırpma kayıtta `clampedText` ile).
    private func textBinding(_ keyPath: WritableKeyPath<ShareCardConfig, String?>) -> Binding<String> {
        Binding {
            config[keyPath: keyPath] ?? ""
        } set: { newValue in
            let limited = String(newValue.prefix(ShareCardConfig.maxTextLength))
            config[keyPath: keyPath] = limited.isEmpty ? nil : limited
        }
    }

    // MARK: Bilgiler

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(String(localized: "Bilgiler"))
            VStack(spacing: 0) {
                ForEach(Array(ShareCardConfig.Stat.allCases.enumerated()), id: \.element) { index, stat in
                    if index > 0 { Divider() }
                    Toggle(stat.title, isOn: Binding {
                        config.stats.contains(stat)
                    } set: { isOn in
                        if isOn { config.stats.insert(stat) } else { config.stats.remove(stat) }
                    })
                    .font(.tBody)
                    .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 16)
            .background(Color.tray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: Gezzy işareti

    private var brandSection: some View {
        let canRemove = isPremium || purchased
        return HStack(spacing: 10) {
            // Kayıtlı tercih korunur; ücretsizde anahtar kuralı (hep açık) gösterir.
            Toggle(isOn: Binding {
                config.effectiveShowsBrand(isPremium: canRemove)
            } set: { isOn in
                // Ücretsizde kapatılamaz: anahtar açık kalır, paywall açılır.
                if isOn || canRemove {
                    config.showsBrand = isOn
                } else {
                    showsPaywall = true
                }
            }) {
                HStack(spacing: 6) {
                    Text("Gezzy ile planlandı").font(.tBody)
                    if !canRemove {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(Color.ink3)
                            .accessibilityLabel(Text("Premium"))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.tray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
