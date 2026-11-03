import SwiftUI
import GezzyKit

/// Anılar sekmesinde ortak albüm: karşılıklı onay, yükleme durumu, kişi filtresi ve fotoğraf ızgarası.
struct SharedAlbumCard: View {
    @Environment(TripStore.self) private var store
    @Environment(\.tripTint) private var tint
    @Environment(\.tripText) private var tintText
    @Environment(\.tripPalette) private var palette
    let trip: Trip
    @State private var owner: UUID?
    @State private var viewer: PhotoViewerContext?
    @State private var confirmWithdraw = false
    private var sync: AlbumSync { .shared }

    var body: some View {
        let me = store.me.id
        let isMember = trip.members.contains { $0.id == me }
        let consenting = SharedAlbum.consentingMembers(of: trip)
        let iConsented = consenting.contains(me)
        let others = trip.members.filter { $0.id != me && consenting.contains($0.id) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ortak albüm", systemImage: "photo.stack")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Spacer()
                if iConsented {
                    Menu {
                        Button("Paylaşımı kapat", systemImage: "eye.slash", role: .destructive) { confirmWithdraw = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.circleIcon(size: 32))
                    .accessibilityLabel("Albüm seçenekleri")
                }
            }

            if !isMember {
                Text("Ortak albüm için önce Ekip sekmesinden kendini seyahate ekle.")
                    .font(.tBody).foregroundStyle(Color.ink2)
            } else if !iConsented {
                Text(others.isEmpty
                     ? String(localized: "Seyahat günlerinde çektiğin fotoğraflar ekiple paylaşılır. Albüm, en az iki kişi onay verince açılır; yalnızca onay verenler görür.")
                     : String(localized: "\(others.map(\.name).joined(separator: ", ")) fotoğraflarını paylaşmaya hazır. Sen de onay verince albüm açılır."))
                    .font(.tBody).foregroundStyle(Color.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    sync.consent(trip.id, store: store)
                } label: {
                    Label("Fotoğraflarımı paylaş", systemImage: "person.2.badge.plus")
                }
                .buttonStyle(PillButtonStyle(tint: tintText, soft: .soft(palette)))
                .disabled(!store.canEdit(trip))
                Text("Ekran görüntüleri hariç; 2048 px'e küçültülmüş kopya iCloud'a yüklenir. İstediğin fotoğrafı sonra çıkarabilirsin.")
                    .font(.caption).foregroundStyle(Color.ink3)
            } else if !SharedAlbum.isActive(trip) {
                Label("Onayın alındı. Ekipten biri de onay verince albüm açılacak.", systemImage: "hourglass")
                    .font(.tBody).foregroundStyle(Color.ink2)
            } else {
                activeAlbum(me: me, consenting: consenting)
            }
        }
        .tray()
        .fullScreenCover(item: $viewer) { context in
            PhotoViewer(items: context.items, index: context.index)
                .environment(store)
        }
        .confirmationDialog("Paylaşım kapatılsın mı?", isPresented: $confirmWithdraw, titleVisibility: .visible) {
            Button("Paylaşımı kapat", role: .destructive) { sync.withdraw(trip.id, store: store) }
        } message: {
            Text("Fotoğrafların albümden ve ekibin cihazlarından kalkar; sen de başkalarının fotoğraflarını göremezsin.")
        }
    }

    @ViewBuilder
    private func activeAlbum(me: UUID, consenting: Set<UUID>) -> some View {
        let all = SharedAlbum.visiblePhotos(in: trip)
        let photos = owner.map { id in all.filter { $0.ownerID == id } } ?? all
        if let progress = sync.progress[trip.id] {
            HStack(spacing: 10) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                Text("\(progress.done)/\(progress.total)").font(.caption.monospacedDigit()).foregroundStyle(Color.ink2)
            }
            Text("Fotoğrafların hazırlanıyor…").font(.caption).foregroundStyle(Color.ink3)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ownerChip(nil, title: String(localized: "Herkes · \(all.count)"))
                ForEach(trip.members.filter { consenting.contains($0.id) }) { member in
                    ownerChip(member.id, title: "\(member.name) · \(all.filter { $0.ownerID == member.id }.count)", member: member)
                }
            }
        }
        if photos.isEmpty {
            EmptyHint(symbol: "photo", text: String(localized: "Henüz fotoğraf yok. Yüklemeler eşitlendikçe burada görünür."))
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 4)], spacing: 4) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        viewer = PhotoViewerContext(items: photos.map { .album($0.fileName) }, index: index)
                    } label: {
                        AlbumThumb(fileName: photo.fileName, side: 96)
                            .overlay(alignment: .bottomTrailing) {
                                if let member = trip.member(photo.ownerID) {
                                    AvatarView(member: member, size: 20).padding(4)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if photo.ownerID == me {
                            Button("Albümden çıkar", systemImage: "minus.circle", role: .destructive) {
                                withAnimation { sync.remove(photo, from: trip.id, store: store) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func ownerChip(_ id: UUID?, title: String, member: Member? = nil) -> some View {
        let isOn = owner == id
        return Button {
            withAnimation(.spring(duration: 0.25)) { owner = id }
        } label: {
            HStack(spacing: 6) {
                if let member { AvatarView(member: member, size: 20) }
                Text(title)
            }
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(isOn ? Color.white : Color.ink2)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(isOn ? tint : Color.track, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Albüm dosyasından kare küçük görsel; dosya henüz iCloud'dan gelmediyse yer tutucu.
struct AlbumThumb: View {
    let fileName: String
    let side: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.track
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityLabel("Fotoğraf")
            .task(id: fileName) {
                let pixels = side * displayScale
                // Dosya ekipten iCloud ile gelecekse bir süre bekle.
                for attempt in 0..<30 {
                    if let url = CoverImageStore.album.fileURL(named: fileName) {
                        image = await Task.detached(priority: .userInitiated) {
                            CoverImageStore.downsample(at: url, maxPixelSize: pixels)
                        }.value
                        return
                    }
                    try? await Task.sleep(for: .seconds(attempt < 5 ? 2 : 10))
                }
            }
    }
}

/// Tam ekran görüntüleyicinin açılış bilgisi.
struct PhotoViewerContext: Identifiable {
    let id = UUID()
    let items: [PhotoViewer.Item]
    let index: Int
}

/// Fotoğrafları tam ekran açar: kaydırarak gezilir, iki parmakla yakınlaştırılır.
struct PhotoViewer: View {
    enum Item: Hashable {
        /// Bu cihazın fotoğraf arşivinden.
        case library(String)
        /// Ortak albüm dosyası.
        case album(String)
    }

    let items: [Item]
    @State var index: Int
    /// Verilirse (ve öğe cihaz arşivindense) alt çubukta favori/kapak/gizle çıkar.
    var tripID: UUID?
    @Environment(\.dismiss) private var dismiss
    @Environment(TripStore.self) private var store
    @State private var toast: LocalizedStringKey?
    @State private var toastTask: Task<Void, Never>?
    private var prefs: MemoryPrefs { .shared }

    init(items: [Item], index: Int, tripID: UUID? = nil) {
        self.items = items
        self._index = State(initialValue: index)
        self.tripID = tripID
    }

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                PhotoPage(item: item).tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black)
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            HStack {
                Text("\(index + 1) / \(items.count)")
                    .font(.system(.footnote, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.4), in: Circle())
                }
                .accessibilityLabel("Kapat")
            }
            .padding(16)
        }
        .overlay(alignment: .bottom) { actionBar }
        .statusBarHidden()
    }

    @ViewBuilder
    private var actionBar: some View {
        if let tripID, items.indices.contains(index), case let .library(id) = items[index] {
            VStack(spacing: 10) {
                if let toast {
                    Text(toast)
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.black.opacity(0.5), in: Capsule())
                        .transition(.opacity)
                }
                HStack(spacing: 28) {
                    let isFavorite = prefs.favorites(tripID).contains(id)
                    barButton(isFavorite ? "heart.fill" : "heart", "Favori") {
                        prefs.toggleFavorite(id, trip: tripID)
                    }
                    if store.trip(tripID).map(store.canEdit) == true {
                        barButton("photo.badge.checkmark", "Kapak yap") { setCover(id, tripID) }
                    }
                    barButton("eye.slash", "Gizle") {
                        prefs.setHidden(id, true, trip: tripID)
                        dismiss()
                    }
                }
                .padding(.horizontal, 24).padding(.vertical, 10)
                .background(.black.opacity(0.45), in: Capsule())
            }
            .padding(.bottom, 24)
        }
    }

    private func barButton(_ symbol: String, _ label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(label)
    }

    private func setCover(_ photoID: String, _ tripID: UUID) {
        toastTask?.cancel()
        toastTask = Task {
            var ok = false
            if let data = await PhotoLibrary.shared.albumJPEG(for: photoID) {
                ok = (try? store.setCoverPhoto(data, for: tripID)) != nil
            }
            guard !Task.isCancelled else { return }
            withAnimation { toast = ok ? "Kapak yapıldı" : "Kapak değiştirilemedi" }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}

private struct PhotoPage: View {
    let item: PhotoViewer.Item
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                ZoomableImage(image: image)
            } else {
                ProgressView().tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item) {
            switch item {
            case let .library(id): image = await PhotoLibrary.shared.fullImage(for: id)
            case let .album(name): image = CoverImageStore.album.image(named: name)
            }
        }
    }
}
