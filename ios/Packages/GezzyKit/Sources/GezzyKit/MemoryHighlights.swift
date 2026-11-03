import Foundation

/// Anılar'ın öne çıkanları: her günden bir fotoğraf. Favori varsa en erken favori, yoksa en kalabalık anın
/// ortadaki fotoğrafı. Gizlenenler hiç seçilmez.
public enum MemoryHighlights {
    public struct Highlight: Hashable, Sendable {
        public var day: Date
        public var photoID: String
        public var stopName: String?
    }

    public static func pick(moments: [PhotoClusterer.Moment], favorites: Set<String>, hidden: Set<String>,
                            calendar: Calendar = .current) -> [Highlight] {
        let byDay = Dictionary(grouping: moments) { calendar.startOfDay(for: $0.start) }
        return byDay.keys.sorted().compactMap { day in
            let dayMoments = byDay[day]!.sorted { $0.start < $1.start }
                .map { m -> PhotoClusterer.Moment in var m = m; m.photoIDs.removeAll(where: hidden.contains); return m }
                .filter { !$0.photoIDs.isEmpty }
            if let favorite = dayMoments.lazy.flatMap({ m in m.photoIDs.map { (m, $0) } }).first(where: { favorites.contains($0.1) }) {
                return Highlight(day: day, photoID: favorite.1, stopName: favorite.0.stopName)
            }
            guard let best = dayMoments.max(by: { a, b in
                if a.count != b.count { return a.count < b.count }
                if (a.stopName != nil) != (b.stopName != nil) { return a.stopName == nil }
                return a.start > b.start
            }) else { return nil }
            return Highlight(day: day, photoID: best.photoIDs[best.photoIDs.count / 2], stopName: best.stopName)
        }
    }
}
