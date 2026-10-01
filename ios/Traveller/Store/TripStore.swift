import Foundation
import Observation
import TravellerKit

/// Uygulama durumu. Şimdilik cihazda JSON olarak saklanır; ileride senkronize bir backend'e taşınacak.
@MainActor
@Observable
final class TripStore {
    private(set) var trips: [Trip] = []
    /// Cihaz sahibinin profili (pasaport bilgileri yeni seyahatlere kopyalanır).
    private(set) var me: Member

    private let fileURL: URL
    private static let meKey = "traveller.me"

    init(fileURL: URL = TripStore.defaultFileURL, seedIfEmpty: Bool = true) {
        self.fileURL = fileURL
        if let data = UserDefaults.standard.data(forKey: Self.meKey),
           let me = try? JSONDecoder().decode(Member.self, from: data) {
            self.me = me
        } else {
            self.me = Member(name: "Ben", role: .owner, colorIndex: 3,
                             passport: Passport(expiresOn: Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now))
        }
        load()
        if trips.isEmpty && seedIfEmpty {
            trips = SampleData.trips(me: me)
            save()
        }
    }

    nonisolated static var defaultFileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent("trips.json")
    }

    // MARK: Queries

    func trip(_ id: Trip.ID) -> Trip? {
        trips.first { $0.id == id }
    }

    var upcoming: [Trip] {
        trips.filter { !$0.isPast() }.sorted { $0.startDate < $1.startDate }
    }

    var past: [Trip] {
        trips.filter { $0.isPast() }.sorted { $0.startDate > $1.startDate }
    }

    // MARK: Mutations

    func add(_ trip: Trip) {
        trips.append(trip)
        save()
    }

    func delete(_ id: Trip.ID) {
        if let photo = trip(id)?.coverPhoto {
            CoverImageStore.shared.delete(named: photo)
        }
        for receipt in trip(id)?.expenses.compactMap(\.receiptPhoto) ?? [] {
            CoverImageStore.receipts.delete(named: receipt)
        }
        trips.removeAll { $0.id == id }
        save()
    }

    /// Kapak fotoğrafını değiştirir; eski dosya silinir.
    func setCoverPhoto(_ data: Data, for id: Trip.ID) throws {
        let name = try CoverImageStore.shared.save(data)
        let old = trip(id)?.coverPhoto
        update(id) { $0.coverPhoto = name }
        if let old { CoverImageStore.shared.delete(named: old) }
    }

    func removeCoverPhoto(for id: Trip.ID) {
        guard let old = trip(id)?.coverPhoto else { return }
        update(id) { $0.coverPhoto = nil }
        CoverImageStore.shared.delete(named: old)
    }

    /// Bir seyahati yerinde değiştirir ve kaydeder.
    func update(_ id: Trip.ID, _ change: (inout Trip) -> Void) {
        guard let index = trips.firstIndex(where: { $0.id == id }) else { return }
        change(&trips[index])
        save()
    }

    func updateMe(_ change: (inout Member) -> Void) {
        change(&me)
        if let data = try? JSONEncoder().encode(me) {
            UserDefaults.standard.set(data, forKey: Self.meKey)
        }
    }

    func resetToSamples() {
        trips = SampleData.trips(me: me)
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            trips = try Self.decoder.decode([Trip].self, from: data)
        } catch {
            // Bozuk dosyayı silmek yerine kenara al; kullanıcı verisi kaybolmasın.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(trips)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("Seyahatler kaydedilemedi: \(error)")
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
