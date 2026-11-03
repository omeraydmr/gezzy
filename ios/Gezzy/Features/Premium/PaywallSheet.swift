import SwiftUI
import StoreKit
import GezzyKit

/// Premium satın alma ekranı; her zaman kapatılabilir.
struct PaywallSheet: View {
    enum Reason { case dataSharingDeclined, tripLimit, offlineMaps, autoPlan, profile, branding }

    let reason: Reason
    let onPurchased: () -> Void

    @Environment(Entitlements.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID = PremiumRules.yearlyID
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var isLoading = false
    @State private var showsError = false
    @State private var restoreFoundNothing = false
    /// Ücretsiz deneme hakkı olan ürünler (deneme kullanıldıysa rozet gösterilmez).
    @State private var trialEligible: Set<String> = []

    init(reason: Reason, onPurchased: @escaping () -> Void = {}) {
        self.reason = reason
        self.onPurchased = onPurchased
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(title)
                        .font(.tTitle)
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 14) {
                        benefit("infinity", String(localized: "Sınırsız seyahat"))
                        benefit("map", String(localized: "Çevrimdışı haritalar ve otomatik rota"))
                        benefit("lock.shield", String(localized: "Rotan hiç paylaşılmaz"))
                    }

                    plans

                    footer
                }
                .padding(16)
            }
            .background(Color.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ink)
                    }
                    .accessibilityLabel(Text("Kapat"))
                }
            }
            .alert("Satın alma tamamlanamadı", isPresented: $showsError) {
                Button("Tamam", role: .cancel) {}
            }
            .task {
                if entitlements.products.isEmpty { await reload() }
            }
            .task(id: entitlements.products.map(\.id)) {
                var eligible: Set<String> = []
                for product in entitlements.products where product.subscription?.introductoryOffer != nil {
                    if await product.subscription?.isEligibleForIntroOffer == true { eligible.insert(product.id) }
                }
                trialEligible = eligible
            }
        }
    }

    private var title: String {
        switch reason {
        case .dataSharingDeclined: String(localized: "Verini paylaşmadan Gezzy'yi destekle")
        case .tripLimit: String(localized: "2 ücretsiz seyahatini kullandın")
        case .offlineMaps, .autoPlan: String(localized: "Bu bir Premium özelliği")
        case .profile: String(localized: "Gezzy Premium")
        case .branding: String(localized: "Kartlardan Gezzy işaretini kaldır")
        }
    }

    private func benefit(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 28)
            Text(text).font(.tBodyStrong).foregroundStyle(Color.ink)
        }
    }

    @ViewBuilder private var plans: some View {
        if entitlements.products.isEmpty {
            VStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Abonelikler şu an yüklenemedi.")
                        .font(.tBody)
                        .foregroundStyle(Color.ink2)
                    Button("Tekrar dene") { Task { await reload() } }
                        .font(.tBodyStrong)
                        .foregroundStyle(Color.ink)
                }
            }
            .frame(maxWidth: .infinity)
            .tray()
        } else {
            VStack(spacing: 12) {
                ForEach(entitlements.products, id: \.id) { product in
                    planCard(product)
                }
            }
            Button {
                Task { await buy() }
            } label: {
                if isPurchasing {
                    ProgressView().tint(Color.onInk)
                } else {
                    Text("Devam et")
                }
            }
            .buttonStyle(.primary)
            .disabled(isPurchasing || selectedProduct == nil)
        }
    }

    private func planCard(_ product: Product) -> some View {
        let isSelected = product.id == selectedID
        let isYearly = product.id == PremiumRules.yearlyID
        return Button {
            selectedID = product.id
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.ink : Color.ink3)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName).font(.tBodyStrong).foregroundStyle(Color.ink)
                        if isYearly, trialEligible.contains(product.id) {
                            Tag(text: String(localized: "7 gün ücretsiz"), accent: .green)
                        }
                    }
                    Text(verbatim: product.displayPrice + (isYearly ? String(localized: "/yıl") : String(localized: "/ay")))
                        .font(.tBody)
                        .foregroundStyle(Color.ink2)
                    if isYearly {
                        let monthly = (product.price / 12).formatted(product.priceFormatStyle)
                        Text("Aylık \(monthly)")
                            .font(.tCaption)
                            .foregroundStyle(Color.ink3)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.tray, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? Color.ink : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    isRestoring = true
                    restoreFoundNothing = false
                    let restored = await entitlements.restore()
                    isRestoring = false
                    if restored {
                        onPurchased()
                        dismiss()
                    } else {
                        withAnimation { restoreFoundNothing = true }
                    }
                }
            } label: {
                if isRestoring { ProgressView() } else { Text("Satın alımları geri yükle") }
            }
            .font(.tBodyStrong)
            .foregroundStyle(Color.ink)
            .disabled(isRestoring)

            if restoreFoundNothing {
                Text("Geri yüklenecek satın alma bulunamadı.")
                    .font(.tCaption)
                    .foregroundStyle(Color.ink2)
            }

            HStack(spacing: 16) {
                Link("Kullanım koşulları", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Gizlilik", destination: URL(string: "https://gezzy.app/privacy")!)
            }
            .font(.tCaption)
            .foregroundStyle(Color.ink2)

            Text("Abonelik, dönem bitmeden 24 saat önce iptal edilmezse otomatik yenilenir. App Store ayarlarından yönetebilirsin.")
                .font(.tCaption)
                .foregroundStyle(Color.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var selectedProduct: Product? {
        entitlements.products.first { $0.id == selectedID } ?? entitlements.products.first
    }

    private func reload() async {
        isLoading = true
        await entitlements.loadProducts()
        isLoading = false
    }

    private func buy() async {
        guard let product = selectedProduct else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if try await entitlements.purchase(product) {
                onPurchased()
                dismiss()
            }
        } catch {
            showsError = true
        }
    }
}
