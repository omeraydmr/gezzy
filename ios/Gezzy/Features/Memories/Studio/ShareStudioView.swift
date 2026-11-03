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
    /// Anlardan ve seyahatten türetilenler; init'te değil, açılışta ve girdiler değişince hesaplanır.
    @State private var highlights: [MemoryHighlights.Highlight] = []
    @State private var visible: [PhotoClusterer.Moment] = []
    @State private var summary: TripSummary?
    @State private var didSetUp = false
    /// Önizleme görselleri (küçük boy) ve rota haritası.
    @State private var previewPhotos: [UIImage] = []
    @State private var mapImage: UIImage?
    @State private var busy: ExportAction?
    @State private var shareItem: ShareImage?
    @State private var mapFailed = false
    @State private var toast: Toast?
    @State private var exportTask: Task<Void, Never>?
    @State private var toastTask: Task<Void, Never>?
    private var hasRoute: Bool { CardRenderer.hasRoute(trip) }
    private var studioStore: ShareStudioStore { .shared }

    private enum ExportAction { case save, share }

    /// Kısa bilgi (VoiceOver'a da duyurulur); izin reddinde Ayarlar'ı açar.
    private struct Toast {
        let text: String
        var opensSettings = false
    }

    init(trip: Trip, request: StudioRequest, moments: [PhotoClusterer.Moment]? = nil) {
        self.trip = trip
        self.request = request
        self.moments = moments
        // Asıl config açılışta (`setUp`) kayıttan gelir.
        _config = State(initialValue: .default(for: request.template))
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
        .onAppear(perform: setUp)
        .onChange(of: moments) { _, _ in
            derive()
            resanitize()
        }
        .onChange(of: trip) { _, newValue in summary = TripSummary.make(newValue) }
        // Kayıt seyrek: son değişiklikten 0,5 sn sonra ve kapanırken.
        .task(id: config) {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, didSetUp else { return }
            studioStore.save(config, for: trip.id)
        }
        .onDisappear {
            if didSetUp { studioStore.save(config, for: trip.id) }
            exportTask?.cancel()
            CardRenderer.clearMapCache()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            CardRenderer.clearMapCache()
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
            Group {
                if let summary {
                    CardTemplateView(trip: trip, summary: summary, config: previewConfig, photos: previewPhotos,
                                     mapImage: mapImage, palette: resolvedPalette, width: width, mapFailed: mapFailed)
                } else {
                    Color.tray.frame(width: width, height: width / aspect)
                }
            }
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
                    let dimmed = (template == .route && !hasRoute)
                        || (ShareCardConfig.needsPhotos(template) && !hasPhotos)
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
                    .opacity(dimmed && !isSelected ? 0.4 : 1)
                    .accessibilityHint(ShareCardConfig.needsPhotos(template) && !hasPhotos
                                       ? Text("Fotoğraf gerekli") : Text(verbatim: ""))
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
            // Fotoğraflı şablonlar seçilebilir kalır (erişim/seçim oradan); fotoğrafsız dışa verilmez.
            if !hasPhotos {
                Text("Fotoğraf gerekli: Kartpostal, Kolaj")
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
            config = Self.sanitized(next, tripID: trip.id, moments: moments)
        }
    }

    /// Kullanılabilir fotoğraf var mı: erişim ve (anlar yüklendiyse) görünür an ya da hazır seçim.
    private var hasPhotos: Bool {
        if !config.photoIDs.isEmpty || !request.photoIDs.isEmpty { return true }
        guard PhotoLibrary.shared.canRead else { return false }
        return moments == nil || !visible.isEmpty
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
            .accessibilityLabel(Text("Kaydet"))
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
            .accessibilityLabel(Text("Paylaş"))
        }
        .disabled(!canExport || busy != nil)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Color.canvas)
    }

    /// Kartpostal 1, kolaj en az 2 fotoğraf; rota konumlu durak ister.
    private var canExport: Bool { summary != nil && config.canExport(hasRoute: hasRoute) }

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
                showToast(Toast(text: String(localized: "Harita oluşturulamadı, internet bağlantını kontrol et.")))
                return
            } catch is CancellationError {
                return
            } catch {
                showToast(Toast(text: String(localized: "Kart oluşturulamadı")))
                return
            }
            guard !Task.isCancelled else { return }
            switch action {
            case .share:
                shareItem = ShareImage(image: image)
            case .save:
                switch await save(image) {
                case .saved: showToast(Toast(text: String(localized: "Fotoğraflar'a kaydedildi")))
                case .denied: showToast(Toast(text: String(localized: "Ayarlar'dan Fotoğraflar iznini aç"), opensSettings: true), seconds: 4)
                case .failed: showToast(Toast(text: String(localized: "Fotoğraflar'a kaydedilemedi")))
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
        UIAccessibility.post(notification: .announcement, argument: next.text)
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

    /// Açılışta bir kez: özet, anlar ve kayıtlı config. Fotoğraf yoksa fotoğrafsız şablonla açılır.
    private func setUp() {
        guard !didSetUp else { return }
        summary = TripSummary.make(trip)
        derive()
        let template = ShareCardConfig.initialTemplate(request.template, hasRoute: hasRoute, hasPhotos: hasPhotos)
        var next = studioStore.config(for: trip.id, template: template)
        if !request.photoIDs.isEmpty { next.photoIDs = request.photoIDs }
        config = Self.sanitized(next, tripID: trip.id, moments: moments)
        didSetUp = true
    }

    private func resanitize() {
        let next = Self.sanitized(config, tripID: trip.id, moments: moments)
        if next != config { config = next }
    }

    private static func sanitized(_ config: ShareCardConfig, tripID: UUID,
                                  moments: [PhotoClusterer.Moment]?) -> ShareCardConfig {
        config.sanitized(hidden: MemoryPrefs.shared.hidden(tripID),
                         available: moments.map { Set($0.flatMap(\.photoIDs)) })
    }

    /// Öne çıkanlar ve gizliler çıkarılmış anlar.
    private func derive() {
        let moments = moments ?? []
        let hidden = MemoryPrefs.shared.hidden(trip.id)
        let favorites = MemoryPrefs.shared.favorites(trip.id)
        visible = moments.compactMap { moment -> PhotoClusterer.Moment? in
            var moment = moment
            moment.photoIDs.removeAll(where: hidden.contains)
            return moment.photoIDs.isEmpty ? nil : moment
        }
        highlights = MemoryHighlights.pick(moments: moments, favorites: favorites, hidden: hidden)
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
