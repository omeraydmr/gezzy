import Photos
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
    /// Önizleme görselleri (küçük boy) ve rota haritası.
    @State private var previewPhotos: [UIImage] = []
    @State private var mapImage: UIImage?
    @State private var busy: ExportAction?
    @State private var shareItem: ShareImage?
    @State private var mapFailed = false
    @State private var toast: Toast?
    @State private var exportTask: Task<Void, Never>?
    @State private var toastTask: Task<Void, Never>?
    private let summary: TripSummary
    private let hasRoute: Bool
    private var studioStore: ShareStudioStore { .shared }

    private enum ExportAction { case save, share }

    /// Kısa bilgi; izin reddinde Ayarlar'ı açar.
    private struct Toast {
        let text: LocalizedStringKey
        var opensSettings = false
    }

    init(trip: Trip, request: StudioRequest, moments: [PhotoClusterer.Moment]? = nil) {
        self.trip = trip
        self.request = request
        self.moments = moments
        let hasRoute = CardRenderer.hasRoute(trip)
        self.hasRoute = hasRoute
        self.summary = TripSummary.make(trip)
        // Konumlu durak yoksa Rota pasif; kartpostala düşülür.
        let template = request.template == .route && !hasRoute ? .postcard : request.template
        var config = ShareStudioStore.shared.config(for: trip.id, template: template)
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
        .onDisappear {
            studioStore.save(config, for: trip.id)
            exportTask?.cancel()
        }
        .task(id: config.photoIDs.first) { await loadPhotoPalette() }
        .task(id: "\(config.template)-\(config.photoIDs)") { await loadPreviewPhotos() }
        .task(id: "\(config.template)-\(config.format)-\(resolvedPalette.id)-\(resolvedPalette.accent)") {
            await loadMap()
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.image])
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
    }

    // MARK: Önizleme

    /// Kartın canlı önizlemesi: seçili biçim oranında, alana sığar.
    private var preview: some View {
        GeometryReader { geometry in
            let aspect = config.format.aspect
            let width = max(1, min(geometry.size.width - 32, geometry.size.height * aspect))
            CardTemplateView(trip: trip, summary: summary, config: previewConfig, photos: previewPhotos,
                             mapImage: mapImage, palette: resolvedPalette, width: width, mapFailed: mapFailed)
                .clipShape(RoundedRectangle(cornerRadius: 12 * width / 360 + 4, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(config.template.title) önizlemesi"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if let toast {
                        Group {
                            if toast.opensSettings {
                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Label(toast.text, systemImage: "gearshape")
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(toast.text)
                            }
                        }
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                    }
                }
        }
        .animation(.spring(duration: 0.3), value: config.format)
    }

    /// İşaret kuralı uygulanmış config (ücretsizde hep açık).
    private var previewConfig: ShareCardConfig {
        var config = config
        config.showsBrand = config.effectiveShowsBrand(isPremium: entitlements.isPremium)
        return config
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
        VStack(alignment: .leading, spacing: 8) {
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
                    .disabled(template == .route && !hasRoute)
                    .opacity(template == .route && !hasRoute ? 0.4 : 1)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 2)
            }
            if !hasRoute {
                Text("Rota için konumlu durak gerekli")
                    .font(.caption)
                    .foregroundStyle(Color.ink3)
            }
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

    /// Kaydet (Fotoğraflar'a) ve Paylaş (sistem paylaşım sayfası); üretim sırasında düğmede ilerleme.
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                export(.save)
            } label: {
                Group {
                    if busy == .save {
                        ProgressView()
                    } else {
                        Label("Kaydet", systemImage: "square.and.arrow.down")
                    }
                }
                .font(.system(.body, weight: .medium))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Color.tray, in: Capsule())
            }
            .buttonStyle(.plain)
            Button {
                export(.share)
            } label: {
                if busy == .share {
                    ProgressView().tint(Color.onInk)
                } else {
                    Label("Paylaş", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.primary)
        }
        .disabled(!canExport || busy != nil)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.canvas)
    }

    /// Kolajda en az 2 fotoğraf; rota konumlu durak ister.
    private var canExport: Bool {
        switch config.template {
        case .route: hasRoute
        case .collage: config.photoIDs.count >= ShareCardConfig.photoLimit(.collage).lowerBound
        case .postcard, .stats, .ticket: true
        }
    }

    private func export(_ action: ExportAction) {
        exportTask?.cancel()
        busy = action
        let config = config, palette = resolvedPalette, isPremium = entitlements.isPremium
        exportTask = Task {
            defer { if !Task.isCancelled { busy = nil } }
            let image: UIImage
            do {
                image = try await CardRenderer.render(trip: trip, config: config, palette: palette, isPremium: isPremium)
            } catch CardRenderer.RenderError.map {
                showToast(Toast(text: "Harita oluşturulamadı, internet bağlantını kontrol et."))
                return
            } catch is CancellationError {
                return
            } catch {
                showToast(Toast(text: "Kart oluşturulamadı"))
                return
            }
            guard !Task.isCancelled else { return }
            switch action {
            case .share:
                shareItem = ShareImage(image: image)
            case .save:
                switch await save(image) {
                case .saved: showToast(Toast(text: "Fotoğraflar'a kaydedildi"))
                case .denied: showToast(Toast(text: "Ayarlar'dan Fotoğraflar iznini aç", opensSettings: true), seconds: 4)
                case .failed: showToast(Toast(text: "Fotoğraflar'a kaydedilemedi"))
                }
            }
        }
    }

    private enum SaveResult { case saved, denied, failed }

    /// Yalnızca ekleme izniyle Fotoğraflar'a yazar.
    private func save(_ image: UIImage) async -> SaveResult {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            return .saved
        } catch {
            return .failed
        }
    }

    private func showToast(_ next: Toast, seconds: Double = 1.8) {
        toastTask?.cancel()
        toastTask = Task {
            withAnimation { toast = next }
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }

    // MARK: Yardımcılar

    /// Önizleme fotoğrafları küçük boyda (600 px).
    private func loadPreviewPhotos() async {
        var images: [UIImage] = []
        for id in config.photoIDs.prefix(ShareCardConfig.photoLimit(config.template).upperBound) {
            if let image = await PhotoLibrary.shared.thumbnail(for: id, side: 600) { images.append(image) }
        }
        guard !Task.isCancelled else { return }
        previewPhotos = images
    }

    /// Rota şablonunda harita; çıktıyla aynı boyutta üretilir ve önbelleğe alınır.
    private func loadMap() async {
        guard config.template == .route, hasRoute else { return }
        mapFailed = false
        let image = await CardRenderer.mapSnapshot(trip: trip, palette: resolvedPalette,
                                                   size: CardRenderer.mapSize(format: config.format))
        guard !Task.isCancelled else { return }
        if let image { mapImage = image } else { mapImage = nil; mapFailed = true }
    }

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

/// Paylaşım sayfasına verilen görsel.
private struct ShareImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Sistem paylaşım sayfası.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
