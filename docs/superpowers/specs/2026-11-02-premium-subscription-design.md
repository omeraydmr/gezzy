# Gezzy Premium (abonelik) — tasarım

Tarih: 2026-11-02 · Durum: onay bekliyor

## Hedef

Uygulamaya StoreKit 2 aboneliği eklemek. Premium şunları açar:

1. **Veri paylaşımı olmadan kullanım:** premium kullanıcının rotası sunucuya hiç gönderilmez (rota raporu spec'i:
   `2026-11-02-trip-route-reports-design.md`).
2. **Sınırsız seyahat:** ücretsiz kullanıcı ömrü boyunca en çok **2** seyahat oluşturabilir. Geçmiş seyahatler sayılır;
   seyahati silmek hakkı geri vermez.
3. **Çevrimdışı haritalar ve otomatik rota:** "Haritaları internetsiz kaydet" ve "Otomatik rota" premium olur.

İzin vermeyen kullanıcı survey'de premium teklifini görür ama uygulamayı ücretsiz kullanmaya devam eder (zorunlu duvar
yok).

Kapsam dışı: sunucu tarafı makbuz doğrulama, aile paylaşımı ayarı dışında özel davranış, promosyon kodları, kazanç
raporları.

## 1. Ürünler

App Store Connect'te bir abonelik grubu "Gezzy Premium":

| Ürün kimliği | Süre | Deneme | Örnek fiyat |
|---|---|---|---|
| `gezzy.premium.monthly` | 1 ay | yok | ~₺79 |
| `gezzy.premium.yearly` | 1 yıl | 7 gün ücretsiz | ~₺599 |

Fiyatlar App Store Connect'te belirlenir; uygulama `Product.displayPrice` gösterir. Yerel test için
`ios/Gezzy/Support/Gezzy.storekit` (StoreKit Configuration dosyası) ve scheme'de seçili.

## 2. Yetki (`Entitlements`)

- `Store/Entitlements.swift`, `@MainActor @Observable final class Entitlements` (tek örnek, ortam değeriyle iner).
  - `isPremium: Bool` — `Transaction.currentEntitlements` içinde iptal edilmemiş, süresi geçmemiş bir premium işlem
    varsa `true`.
  - `products: [Product]` — iki ürün, yıllık önce.
  - `purchase(_:) async throws -> Bool`, `restore() async` (`AppStore.sync()`).
  - Açılışta ve `Transaction.updates` dinlenerek güncellenir.
  - Son bilinen durum `UserDefaults`'a yazılır (çevrimdışı açılışta kısa süre doğru görünsün); asıl kaynak StoreKit.
- Saf kurallar GezzyKit'te `PremiumRules` (test edilir):
  - `canCreateTrip(created: Int, isPremium: Bool) -> Bool` — `isPremium || created < 2`.
  - `freeTripLimit = 2`.
  - `tripsCreated(stored: Int, owned: Int) -> Int` — `max(stored, owned)` (silinen seyahat hakkı geri vermez).

## 3. Seyahat hakkı sayacı

- "Oluşturulan seyahat" = kullanıcının `NewTripSheet` ile oluşturduğu seyahat. QR/bağlantıyla katıldığı (sahibi
  başkası olan) seyahatler sayılmaz.
- Sayaç silmeye ve yeniden kuruluma dayanıklı olmalı:
  - **Keychain** (`kSecClassGenericPassword`, `gezzy.tripsCreated`, `kSecAttrSynchronizable = true` → iCloud Anahtar
    Zinciri ile cihazlar arası) ana kaynak.
  - Sayaç = `max(keychain, sahibi olunan mevcut seyahat sayısı)`; ilk sürüm geçişinde mevcut seyahatler sayılır.
- `TripStore.add(_:)` çağrılmadan önce (`TripsView`'deki "Seyahat planla") kontrol: hak yoksa `PaywallSheet(reason:
  .tripLimit)` açılır, `NewTripSheet` açılmaz. Başarılı eklemeden sonra sayaç +1.
- Kalan hak "Seyahat planla" düğmesinin altında küçük metin: "Ücretsiz: 1 seyahat hakkın kaldı" (premium'da yok).

## 4. Kilitlenen özellikler

- **Çevrimdışı haritalar:** `OfflineMapRow`'daki "Kaydet/Güncelle" ve `•••` menüsündeki öğe ücretsizde
  `PaywallSheet(reason: .offlineMaps)` açar; daha önce kaydedilmiş haritalar gösterilmeye devam eder.
- **Otomatik rota:** Fikirler kartındaki "Otomatik rota" ücretsizde `PaywallSheet(reason: .autoPlan)` açar. Düğmede
  küçük kilit ikonu. Plan'daki tek gün "rota sırala" düğmesi (`optimize`) ücretsiz kalır.
- **Rota paylaşımı:** premium'da Profil'deki tercih kapalı ve pasif; `RouteReporter` premium'da hiçbir şey göndermez.

## 5. Paywall (`Features/Premium/PaywallSheet.swift`)

- `PaywallSheet(reason: Reason)`, `Reason = .dataSharingDeclined | .tripLimit | .offlineMaps | .autoPlan | .profile`.
- Üstte nedene göre başlık:
  - `.dataSharingDeclined`: "Verini paylaşmadan Gezzy'yi destekle"
  - `.tripLimit`: "2 ücretsiz seyahatini kullandın"
  - `.offlineMaps` / `.autoPlan`: "Bu bir Premium özelliği"
  - `.profile`: "Gezzy Premium"
- Üç madde (ikon + kısa metin): sınırsız seyahat, çevrimdışı harita ve otomatik rota, rotan paylaşılmaz.
- İki plan kartı (yıllık önce, "7 gün ücretsiz" rozeti, aylık karşılığı), seçili olan palet/ink vurgulu.
- Birincil düğme "Devam et" (`.primary`), altında "Satın alımları geri yükle", "Kullanım koşulları", "Gizlilik"
  bağlantıları ve Apple'ın gerektirdiği yenileme açıklaması.
- Kapatma düğmesi her zaman görünür (sağ üst ×).
- Satın alma başarılı → sheet kapanır, tetikleyen eylem (ör. seyahat oluşturma) devam eder.
- Hata → alert; kullanıcı iptal → sessiz.

## 6. Profil

"Premium" bölümü: premium ise "Gezzy Premium · aktif" + "Aboneliği yönet" (`manageSubscriptionsSheet`); değilse
"Premium'a geç" (`PaywallSheet(reason: .profile)`) ve "Satın alımları geri yükle".

## 7. Kod düzeni

- GezzyKit: `PremiumRules.swift` + testler.
- Uygulama: `Store/Entitlements.swift`, `Store/TripAllowance.swift` (Keychain sayaç), `Features/Premium/PaywallSheet.swift`,
  `Support/Gezzy.storekit`; değişen: `GezzyApp` (ortam), `TripsView`, `PlanSection` (`OfflineMapRow`),
  `TripDetailView` (menü), `IdeasCard`, `ProfileView`, `project.yml` (storekit dosyası, scheme), `Localizable.xcstrings`.

## 8. Test ve doğrulama

- `PremiumRulesTests`; `TripAllowance` için Keychain'i soyutlayan küçük protokol ve uygulama içi birim testi yerine
  GezzyKit'te saf sayaç birleştirme testi (`max` kuralı).
- Simülatör (StoreKit Configuration ile): 2 seyahat sınırı (Kopenhag + 1 yeni → 3.'de paywall), silip yeniden deneme,
  yıllık deneme satın alma, geri yükleme, çevrimdışı harita ve otomatik rota kilitleri, survey'de "Hayır" → paywall.

## 9. Yayın notları (bu spec'in dışında)

- App Store Connect'te abonelik grubu, ürünler, yerelleştirilmiş ad/açıklama, inceleme ekran görüntüsü.
- Kullanım koşulları ve gizlilik politikası bağlantıları (paywall'da zorunlu).
- Gizlilik politikası ve App Store gizlilik etiketi rota raporlarına göre güncellenir.
