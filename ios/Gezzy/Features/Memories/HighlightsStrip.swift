import SwiftUI
import GezzyKit

/// Öne çıkanlar şeridi: her günden bir fotoğraf; başlıktan kolaj kartı oluşturulur.
struct HighlightsStrip: View {
    let trip: Trip
    let highlights: [MemoryHighlights.Highlight]
    let onOpen: (PhotoViewerContext) -> Void
    let onCreateCard: (ShareCardConfig.Template, [String]) -> Void
    @Environment(\.tripText) private var tripText

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Öne çıkanlar").font(.tBodyStrong).foregroundStyle(Color.ink)
                Spacer()
                Button {
                    onCreateCard(.collage, Array(highlights.map(\.photoID).prefix(9)))
                } label: {
                    Text("Kart oluştur").font(.system(.subheadline, weight: .semibold)).foregroundStyle(tripText)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(highlights.enumerated()), id: \.element) { index, highlight in
                        tile(highlight, index: index)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, 12)
            }
            // Kart gölgeleri kaydırma alanının kenarında kesilmesin.
            .scrollClipDisabled()
        }
    }

    private func tile(_ highlight: MemoryHighlights.Highlight, index: Int) -> some View {
        Button {
            // Görüntüleyici tüm öne çıkanlarla açılır.
            onOpen(PhotoViewerContext(items: highlights.map { .library($0.photoID) }, index: index))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                PhotoTile(id: highlight.photoID, width: 150, height: 190)
                Text(label(highlight))
                    .font(.tCaption)
                    .foregroundStyle(Color.ink2)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label(highlight)))
    }

    private func label(_ highlight: MemoryHighlights.Highlight) -> String {
        let number = (trip.days().firstIndex { Calendar.current.isDate($0, inSameDayAs: highlight.day) } ?? 0) + 1
        if let stop = highlight.stopName { return String(localized: "\(number). gün · \(stop)") }
        return String(localized: "\(number). gün")
    }
}

/// Fotoğraf arşivinden dikdörtgen görsel (öne çıkanlar karosu).
private struct PhotoTile: View {
    let id: String
    let width: CGFloat
    let height: CGFloat
    @State private var image: UIImage?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Color.track
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
            .cardBackground(Color.tray, in: RoundedRectangle(cornerRadius: Radius.thumb, style: .continuous))
            .task(id: id) {
                image = await PhotoLibrary.shared.thumbnail(for: id, side: max(width, height) * displayScale)
            }
            .accessibilityHidden(true)
    }
}
