import Foundation
import Observation
import StoreKit
import GezzyKit

/// StoreKit 2 premium durumu: ürünler, satın alma, geri yükleme.
@MainActor @Observable
final class Entitlements {
    static let shared = Entitlements()

    private static let cacheKey = "gezzy.premium.cached"

    private(set) var isPremium: Bool {
        didSet { UserDefaults.standard.set(isPremium, forKey: Self.cacheKey) }
    }
    private(set) var products: [Product] = []
    /// StoreKit bu açılışta en az bir kez cevap verdi mi; o zamana kadar rota raporu gönderilmez.
    private(set) var hasLoaded = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    enum PurchaseError: Error { case unverified }

    private init() {
        // Son bilinen değer; StoreKit cevabı gelene kadar kullanılır.
        isPremium = UserDefaults.standard.bool(forKey: Self.cacheKey)
        // Başka cihazda ya da App Store'da yapılan işlemleri dinle.
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.refresh()
            }
        }
    }

    func load() async {
        await loadProducts()
        await refresh()
    }

    func loadProducts() async {
        do {
            let fetched = try await Product.products(for: PremiumRules.productIDs)
            products = fetched.sorted { lhs, rhs in
                (PremiumRules.productIDs.firstIndex(of: lhs.id) ?? .max) < (PremiumRules.productIDs.firstIndex(of: rhs.id) ?? .max)
            }
        } catch {
            // Boş liste paywall'da hata durumu olarak gösterilir.
        }
    }

    /// Satın alma tamamlandıysa `true`; iptal ya da beklemede `false`.
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(.verified(let transaction)):
            await transaction.finish()
            await refresh()
            return true
        case .success(.unverified):
            throw PurchaseError.unverified
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Geri yüklemeden sonra premium etkinse `true`.
    @discardableResult
    func restore() async -> Bool {
        try? await AppStore.sync()
        await refresh()
        return isPremium
    }

    /// Geçerli haklardan premium durumunu yeniden hesaplar.
    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  PremiumRules.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration <= .now { continue }
            active = true
        }
        if isPremium != active { isPremium = active }
        hasLoaded = true
    }
}
