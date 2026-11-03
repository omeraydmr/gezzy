import Foundation
import GezzyKit

/// Paylaşım stüdyosu ayarları: seyahat başına her şablonun son config'i ve son kullanılan şablon.
/// Cihazda `UserDefaults` (`gezzy.shareStudio.v1`) içinde JSON olarak tutulur.
@MainActor
final class ShareStudioStore {
    static let shared = ShareStudioStore()

    private struct Entry: Codable {
        var lastTemplate: ShareCardConfig.Template?
        /// Şablonun ham değeri → config.
        var configs: [String: ShareCardConfig] = [:]
    }

    private static let key = "gezzy.shareStudio.v1"
    private let defaults: UserDefaults
    private var entries: [UUID: Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Okuma hatasında boş başla.
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([UUID: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    /// Şablonun kayıtlı config'i; yoksa varsayılan.
    func config(for tripID: UUID, template: ShareCardConfig.Template) -> ShareCardConfig {
        guard var saved = entries[tripID]?.configs[template.rawValue] else { return .default(for: template) }
        saved.template = template
        return saved
    }

    func lastTemplate(for tripID: UUID) -> ShareCardConfig.Template? {
        entries[tripID]?.lastTemplate
    }

    /// Config'i şablonunun altına yazar ve son şablon olarak işaretler; metinler kırpılır.
    func save(_ config: ShareCardConfig, for tripID: UUID) {
        var config = config
        config.title = config.title.map(ShareCardConfig.clampedText).flatMap { $0.isEmpty ? nil : $0 }
        config.subtitle = config.subtitle.map(ShareCardConfig.clampedText).flatMap { $0.isEmpty ? nil : $0 }
        var entry = entries[tripID] ?? Entry()
        entry.configs[config.template.rawValue] = config
        entry.lastTemplate = config.template
        entries[tripID] = entry
        persist()
    }

    /// Seyahat silinince kart ayarları (fotoğraf kimlikleri, metinler) de silinir.
    func remove(trip tripID: UUID) {
        guard entries.removeValue(forKey: tripID) != nil else { return }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
