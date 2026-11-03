import SwiftUI
import GezzyKit

/// Paylaşım stüdyosu: üstte kart önizlemesi, altında şablon, biçim ve düzenleme kontrolleri.
/// Ayarlar her değişiklikte seyahat başına saklanır.
struct ShareStudioView: View {
    let trip: Trip
    let request: StudioRequest
    /// Anılar'daki anlar; nil ise henüz yüklenmedi (kayıtlı seçimler görünürlüğe göre elenmez).
    var moments: [PhotoClusterer.Moment]?

    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @Environment(\.tripPalette) private var tripPalette
    @State private var config: ShareCardConfig
    @State private var photoPalette: TripPalette?
    /// Anlardan türetilenler; her body geçişinde değil, anlar değişince hesaplanır.
    @State private var highlights: [MemoryHighlights.Highlight]
    @State private var visible: [PhotoClusterer.Moment]
    private var studioStore: ShareStudioStore { .shared }

    init(trip: Trip, request: StudioRequest, moments: [PhotoClusterer.Moment]? = nil) {
        self.trip = trip
        self.request = request
        self.moments = moments
        var config = ShareStudioStore.shared.config(for: trip.id, template: request.template)
        if !request.photoIDs.isEmpty { config.photoIDs = request.photoIDs }
        // Premium bilgisi ortamdan gelir; işaret kuralı görünüm açılınca uygulanır.
        _config = State(initialValue: Self.sanitized(config, tripID: trip.id, moments: moments, isPremium: true))
        let derived = Self.derive(moments, tripID: trip.id)
        _highlights = State(initialValue: derived.highlights)
        _visible = State(initialValue: derived.visible)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    preview
                        .frame(height: geometry.size.height * 0.42)
                        .padding(.vertical, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            templateStrip
                            PillPicker(selection: $config.format, options: ShareCardConfig.Format.allCases,
                                       label: \.title, fillsWidth: true)
                            StudioControls(
                                config: $config,
                                trip: trip,
                                highlights: highlights,
                                moments: visible,
                                isPremium: entitlements.isPremium,
                                photoPalette: photoPalette)
                        }
                        .padding(16)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .background(Color.canvas)
            .navigationTitle("Paylaş")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .onAppear { resanitize() }
        // Premium biterse işaret yeniden açılır.
        .onChange(of: entitlements.isPremium) { _, isPremium in
            if !isPremium { resanitize() }
        }
        .onChange(of: moments) { _, newValue in
            let derived = Self.derive(newValue, tripID: trip.id)
            highlights = derived.highlights
            visible = derived.visible
            resanitize()
        }
        // Kayıt seyrek: son değişiklikten 0,5 sn sonra ve kapanırken.
        .task(id: config) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            studioStore.save(config, for: trip.id)
        }
        .onDisappear { studioStore.save(config, for: trip.id) }
        .task(id: config.photoIDs.first) { await loadPhotoPalette() }
    }

    // MARK: Önizleme

    /// Yer tutucu; şablon görünümleri Task 5'te gelir.
    private var preview: some View {
        let palette = resolvedPalette
        return RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: palette.bands[0]), Color(hex: palette.accent)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: config.template.symbol)
                        .font(.system(size: 28, weight: .semibold))
                    Text(config.template.title).font(.tBodyStrong)
                    Text(config.format.title).font(.caption)
                }
                .foregroundStyle(.white)
            }
            .overlay(alignment: .bottom) {
                if config.effectiveShowsBrand(isPremium: entitlements.isPremium) {
                    GezzyMark(onDark: true).padding(.bottom, 12)
                }
            }
            .aspectRatio(config.format.aspect, contentMode: .fit)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .frame(maxWidth: .infinity)
            .animation(.spring(duration: 0.3), value: config.format)
    }

    /// Seçili palet: seyahat, fotoğraftan ya da hazır palet.
    private var resolvedPalette: TripPalette {
        switch config.paletteID {
        case nil: tripPalette
        case "photo": config.photoIDs.isEmpty ? tripPalette : (photoPalette ?? tripPalette)
        case let id?: TripPalette.all.first { $0.id == id } ?? tripPalette
        }
    }

    // MARK: Şablon şeridi

    private var templateStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ShareCardConfig.Template.allCases, id: \.self) { template in
                    let isSelected = template == config.template
                    Button {
                        select(template)
                    } label: {
                        Label(template.title, systemImage: template.symbol)
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(isSelected ? Color.onInk : Color.ink)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(isSelected ? Color.ink : Color.tray, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
        }
    }

    /// Şablon değişince o şablonun kayıtlı config'i gelir; fotoğrafı yoksa mevcut seçim taşınır.
    private func select(_ template: ShareCardConfig.Template) {
        guard template != config.template else { return }
        var next = studioStore.config(for: trip.id, template: template)
        if next.photoIDs.isEmpty { next.photoIDs = config.photoIDs }
        withAnimation(.spring(duration: 0.3)) {
            config = Self.sanitized(next, tripID: trip.id, moments: moments, isPremium: entitlements.isPremium)
        }
    }

    // MARK: Alt çubuk

    /// Kaydet ve Paylaş; Task 5'te görsel üretimine bağlanır.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
            } label: {
                Label("Kaydet", systemImage: "square.and.arrow.down")
                    .font(.system(.body, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.tray, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
            } label: {
                Label("Paylaş", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.primary)
        }
        .disabled(true)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.canvas)
    }

    // MARK: Yardımcılar

    private func loadPhotoPalette() async {
        guard let id = config.photoIDs.first,
              let image = await PhotoLibrary.shared.thumbnail(for: id, side: 64),
              let hex = CoverImageStore.shared.averageHex(of: image) else {
            photoPalette = nil
            return
        }
        photoPalette = TripPalette.derived(from: hex, fallbackSeed: trip.coverSeed)
    }

    private func resanitize() {
        let next = Self.sanitized(config, tripID: trip.id, moments: moments, isPremium: entitlements.isPremium)
        if next != config { config = next }
    }

    private static func sanitized(_ config: ShareCardConfig, tripID: UUID,
                                  moments: [PhotoClusterer.Moment]?, isPremium: Bool) -> ShareCardConfig {
        config.sanitized(hidden: MemoryPrefs.shared.hidden(tripID),
                         available: moments.map { Set($0.flatMap(\.photoIDs)) }, isPremium: isPremium)
    }

    /// Öne çıkanlar ve gizliler çıkarılmış anlar.
    private static func derive(_ moments: [PhotoClusterer.Moment]?, tripID: UUID)
        -> (highlights: [MemoryHighlights.Highlight], visible: [PhotoClusterer.Moment]) {
        let moments = moments ?? []
        let hidden = MemoryPrefs.shared.hidden(tripID)
        let favorites = MemoryPrefs.shared.favorites(tripID)
        let visible = moments.compactMap { moment -> PhotoClusterer.Moment? in
            var moment = moment
            moment.photoIDs.removeAll(where: hidden.contains)
            return moment.photoIDs.isEmpty ? nil : moment
        }
        return (MemoryHighlights.pick(moments: moments, favorites: favorites, hidden: hidden), visible)
    }
}
