import Foundation

/// Paylaşım kartı ayarları; seyahat başına cihazda saklanır.
public struct ShareCardConfig: Codable, Hashable, Sendable {
    public enum Template: String, Codable, CaseIterable, Sendable { case postcard, stats, route, collage, ticket }
    public enum Format: String, Codable, CaseIterable, Sendable {
        case story, post, square
        /// Genişlik / yükseklik.
        public var aspect: Double {
            switch self {
            case .story: 9.0 / 16.0
            case .post: 4.0 / 5.0
            case .square: 1
            }
        }
    }
    public enum Stat: String, Codable, CaseIterable, Sendable { case days, stops, distance, travellers, spent, perPerson }

    public var template: Template
    public var format: Format
    public var photoIDs: [String]
    /// nil: seyahatin paleti; "photo": seçili fotoğraftan; diğer: `TripPalette.id`.
    public var paletteID: String?
    public var title: String?
    public var subtitle: String?
    public var stats: Set<Stat>
    public var showsBrand: Bool

    public static let maxTextLength = 40

    public static func `default`(for template: Template) -> ShareCardConfig {
        ShareCardConfig(template: template, format: .story, photoIDs: [], paletteID: nil, title: nil, subtitle: nil,
                        stats: [.days, .stops, .distance, .travellers], showsBrand: true)
    }

    public static func photoLimit(_ template: Template) -> ClosedRange<Int> {
        switch template {
        case .postcard: 1...1
        case .collage: 2...9
        case .stats, .route, .ticket: 0...0
        }
    }

    /// Kolaj sütun sayısı: story'de hep 2; diğerlerinde 7+ fotoğrafta 3.
    public static func collageColumns(count: Int, format: Format) -> Int {
        format == .story ? 2 : (count >= 7 ? 3 : 2)
    }

    public static func clampedText(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
    }
}
