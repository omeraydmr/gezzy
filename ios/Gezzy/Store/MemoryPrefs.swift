import Foundation
import Observation

/// Cihazda tutulan favori ve gizli fotoğraf tercihleri (kimlikler Trip'e yazılmaz).
@MainActor @Observable
final class MemoryPrefs {
    static let shared = MemoryPrefs()

    private struct Entry: Codable {
        var favorites: [String] = []
        var hidden: [String] = []
    }

    private static let key = "gezzy.memories.v1"
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

    func favorites(_ tripID: UUID) -> Set<String> { Set(entries[tripID]?.favorites ?? []) }
    func hidden(_ tripID: UUID) -> Set<String> { Set(entries[tripID]?.hidden ?? []) }

    func toggleFavorite(_ photoID: String, trip: UUID) {
        var entry = entries[trip] ?? Entry()
        if let i = entry.favorites.firstIndex(of: photoID) {
            entry.favorites.remove(at: i)
        } else {
            entry.favorites.append(photoID)
        }
        entries[trip] = entry
        save()
    }

    func setHidden(_ photoID: String, _ hidden: Bool, trip: UUID) {
        var entry = entries[trip] ?? Entry()
        entry.hidden.removeAll { $0 == photoID }
        if hidden { entry.hidden.append(photoID) }
        entries[trip] = entry
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
