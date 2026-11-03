import MapKit
import Photos
import SwiftUI
import GezzyKit

/// Paylaşım stüdyosunu açma isteği (şablon ve önceden seçili fotoğraflar).
struct StudioRequest: Identifiable {
    let id = UUID()
    let template: ShareCardConfig.Template
    let photoIDs: [String]
}

/// Anılar: seyahat tarihlerindeki fotoğraflar zamana ve konuma göre anlara ayrılır, en yakın durakla
/// adlandırılır; öne çıkanlar, harita üzerinde günlük ve paylaşım stüdyosu girişi.
struct MemoriesSection: View {
    @Environment(TripStore.self) private var store
    @Environment(\.tripTint) private var tint
    @Environment(\.tripText) private var tripText
    let trip: Trip

    @State private var moments: [PhotoClusterer.Moment]?
    @State private var viewer: PhotoViewerContext?
    @State private var studioRequest: StudioRequest?
    private var library: PhotoLibrary { .shared }
    private var prefs: MemoryPrefs { .shared }

    var body: some View {
        // Tercihler body'de okunur; favori/gizle değişince görünüm yenilenir.
        let hidden = prefs.hidden(trip.id)
        let favorites = prefs.favorites(trip.id)
        ModuleCard(String(localized: "Anılar"), symbol: "photo.on.rectangle.angled") {
            if !library.canRead {
                permissionPrompt
            } else if let moments {
                if moments.isEmpty {
                    EmptyHint(symbol: "photo", text: String(localized: "Seyahat tarihlerinde çekilmiş fotoğraf bulunamadı.")).tray()
                } else {
                    content(moments, hidden: hidden, favorites: favorites)
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Fotoğraflar anlara ayrılıyor…").font(.tBody).foregroundStyle(Color.ink2)
                }
                .tray()
            }
            shareRow
            SharedAlbumCard(trip: trip)
            if CommunityService.shared.isConfigured && CommunityPlaces.canContribute(trip) {
                CommunityShareCard(trip: trip, verified: CommunityPlaces.verifiedStops(in: trip, moments: moments ?? []))
            }
        }
        .task(id: "\(trip.id)-\(library.status.rawValue)-\(trip.stops.count)") { await load() }
        // Albüm açıldıysa (ör. ekipten biri onay verdi) eksik fotoğrafları yükle; kullanılmayanları temizle.
        .task(id: "\(trip.id)-\(SharedAlbum.canView(store.me.id, in: trip))-\(library.status.rawValue)") {
            AlbumSync.shared.pruneOrphans(store: store)
            await AlbumSync.shared.sync(trip.id, store: store)
        }
        .fullScreenCover(item: $viewer) { context in
            PhotoViewer(items: context.items, index: context.index, tripID: trip.id)
                .environment(store)
        }
    }

    // MARK: İzin

    private var permissionPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seyahat tarihlerindeki fotoğraflarını yer ve zamana göre anlara ayırıp durak adlarıyla eşleştirelim. Fotoğraflar cihazdan çıkmaz.")
                .font(.tBody)
                .foregroundStyle(Color.ink2)
            if library.status == .denied || library.status == .restricted {
                Link("Ayarlar'dan fotoğraf erişimini aç", destination: URL(string: UIApplication.openSettingsURLString)!)
                    .font(.system(.subheadline, weight: .semibold))
            } else {
                Button {
                    Task { await library.requestAccess() }
                } label: {
                    Label("Fotoğraflara erişim ver", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.primary(tint))
            }
        }
        .tray()
    }

    // MARK: İçerik

    @ViewBuilder
    private func content(_ moments: [PhotoClusterer.Moment], hidden: Set<String>, favorites: Set<String>) -> some View {
        let visible = Self.visible(moments, hidden: hidden)
        let highlights = MemoryHighlights.pick(moments: moments, favorites: favorites, hidden: hidden)
        let allIDs = Set(moments.flatMap(\.photoIDs))
        let hiddenHere = hidden.intersection(allIDs)
        if !highlights.isEmpty {
            HighlightsStrip(trip: trip, highlights: highlights, onOpen: { viewer = $0 }, onCreateCard: openStudio)
        }
        MemoryJournal(trip: trip, moments: visible, onOpen: { viewer = $0 },
                      hiddenCount: hiddenHere.count) {
            // Onay sorulmaz; bu seyahatin gizlileri geri gelir.
            for id in hidden { prefs.setHidden(id, false, trip: trip.id) }
        }
    }

    /// Gizli fotoğraflar çıkarılır, boşalan anlar düşer.
    private static func visible(_ moments: [PhotoClusterer.Moment], hidden: Set<String>) -> [PhotoClusterer.Moment] {
        guard !hidden.isEmpty else { return moments }
        return moments.compactMap { moment in
            var moment = moment
            moment.photoIDs.removeAll(where: hidden.contains)
            return moment.photoIDs.isEmpty ? nil : moment
        }
    }

    // MARK: Paylaş

    private var shareRow: some View {
        Button {
            openStudio(lastTemplate ?? .postcard, [])
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(tripText)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Seyahatini paylaş").font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text("5 şablon · story, gönderi, kare").font(.caption).foregroundStyle(Color.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tray(padding: 16)
    }

    /// Son kullanılan şablon; stüdyo ayarları (Task 4, `gezzy.shareStudio.v1`) gelince oradan okunur.
    private var lastTemplate: ShareCardConfig.Template? { nil }

    /// Stüdyo kancası: şablon ve önceden seçili fotoğraflarla stüdyoyu açar.
    private func openStudio(_ template: ShareCardConfig.Template, _ photoIDs: [String]) {
        studioRequest = StudioRequest(template: template, photoIDs: photoIDs)
    }

    // MARK: Yükleme

    private func load() async {
        guard library.canRead else { return }
        let photos = await library.photos(for: trip)
        let grouped = PhotoClusterer.label(PhotoClusterer.moments(photos), stops: trip.stops)
        withAnimation { moments = grouped }
    }
}

/// Fotoğraf arşivinden küçük kare görsel.
struct PhotoThumb: View {
    let id: String
    let side: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.track
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .task(id: id) {
                image = await PhotoLibrary.shared.thumbnail(for: id, side: side * displayScale)
            }
            .accessibilityHidden(true)
    }
}

/// Paylaşılabilir seyahat kartpostalı (ImageRenderer ile görüntüye çevrilir).
struct PostcardView: View {
    let trip: Trip
    let photo: UIImage?
    let photoCount: Int
    let momentCount: Int
    let stamp: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        CoverArt(palette: trip.palette)
                    }
                }
                .frame(width: 360, height: 270)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.name)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("\(trip.countryCodes.map(Countries.flag).joined()) \(trip.cityTitle) · \(AppFormat.dateRange(trip.startDate, trip.endDate))")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(18)
            }
            .frame(width: 360, height: 270)

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    stat("\(trip.days().count)", String(localized: "gün"))
                    stat("\(photoCount)", String(localized: "fotoğraf"))
                    stat("\(momentCount)", "an")
                    stat("\(trip.stops.count)", String(localized: "durak"))
                }
                Spacer()
                StampImprint(subtitle: stamp, scale: 0.8)
            }
            .padding(20)
            .frame(width: 360, height: 180)
            .background(Color.tray)
        }
        .frame(width: 360, height: 450)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(12)
        .background(Color.canvas)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(Color.ink)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Color.ink2)
        }
    }
}
