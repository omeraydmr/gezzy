import Foundation
import Security
import GezzyKit

/// Ömür boyu oluşturulan seyahat sayacı; iCloud Anahtar Zinciri'nde tutulur, uygulama silinse de kalır.
enum TripAllowance {
    private static let service = "gezzy"
    private static let account = "tripsCreated"

    /// Kalıcı sayaç ile sahip olunan seyahatlerin büyüğü; ilk okumada değer anahtar zincirine yazılır.
    @MainActor static func created(store: TripStore) -> Int {
        let stored = read()
        let value = PremiumRules.tripsCreated(stored: stored.value, owned: owned(store: store))
        // Okuma hatasında yazma; geçici hata kalıcı sayacı ezmesin.
        if stored.readable, stored.value != value || !stored.exists { write(value) }
        return value
    }

    /// `NewTripSheet` ile yeni seyahat oluşturuldu; `store.add` çağrısından SONRA çağrılmalı.
    /// Okuma hatasında yazmaz; `owned` yeni seyahati zaten içerir.
    @MainActor static func recordCreation(store: TripStore) {
        let stored = read()
        guard stored.readable else { return }
        write(max(stored.value + 1, owned(store: store)))
    }

    /// Sahibi ben olan ya da üyesi olmayan seyahatler.
    @MainActor private static func owned(store: TripStore) -> Int {
        let me = store.me.id
        return store.trips.filter { trip in
            trip.members.isEmpty || trip.members.contains { $0.id == me && $0.role == .owner }
        }.count
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
        ]
    }

    /// Okuma hatasında 0.
    private static func read() -> (value: Int, exists: Bool, readable: Bool) {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return (0, false, true) }
        guard status == errSecSuccess else { return (0, false, false) }
        guard let data = item as? Data, let text = String(data: data, encoding: .utf8),
              let value = Int(text) else { return (0, true, true) }
        return (value, true, true)
    }

    private static func write(_ value: Int) {
        let data = Data(String(value).utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(update) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            if addStatus != errSecSuccess { print("TripAllowance: sayaç eklenemedi (\(addStatus))") }
        } else if status != errSecSuccess {
            print("TripAllowance: sayaç güncellenemedi (\(status))")
        }
    }
}
