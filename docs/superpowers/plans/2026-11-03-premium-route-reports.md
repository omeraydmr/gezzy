# Premium ve rota raporları Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** StoreKit 2 premium aboneliği (2 seyahat sınırı, kilitli özellikler, paywall) ve izin verilmişse biten seyahatin rota raporunun sunucuya otomatik gönderilmesi.

**Architecture:** Saf kurallar GezzyKit'te (`PremiumRules`, `RouteReport`). Uygulamada `Entitlements` (StoreKit), `TripAllowance` (Keychain sayaç), `PaywallSheet`, `RouteReporter` (ön plana gelişte gönderim). Sunucu Cloudflare Worker + D1: yeni `trip_reports` tablosu ve uç noktalar.

**Tech Stack:** Swift 6, SwiftUI iOS 17, StoreKit 2, Security (Keychain), GezzyKit SwiftPM + XCTest, TypeScript Worker + D1, `node --test`.

**Specs:** `docs/superpowers/specs/2026-11-02-premium-subscription-design.md`, `docs/superpowers/specs/2026-11-02-trip-route-reports-design.md`

## Global Constraints

- Build: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build` (no `-quiet`). Yeni dosya eklenince önce `cd ios && xcodegen generate`.
- GezzyKit test: `cd ios/Packages/GezzyKit && swift test`. Sunucu test: `cd server && npm test`.
- Ürün kimlikleri: `gezzy.premium.monthly` (P1M), `gezzy.premium.yearly` (P1Y, 7 gün ücretsiz deneme). Grup adı "Gezzy Premium".
- Ücretsiz seyahat sınırı: **2**, ömür boyu; silmek hakkı geri vermez; yalnızca kullanıcının `NewTripSheet` ile oluşturdukları sayılır.
- Rota tercihi `UserDefaults` anahtarı `gezzy.routeSharing.choice`: `"yes"` / `"no"` / yok. Yokken ve premium'da gönderim yok. İzin sorusunda varsayılan seçili değil.
- Reddetmek hiçbir özelliği kapatmaz; yalnızca `PaywallSheet(reason: .dataSharingDeclined)` gösterilir; paywall her zaman kapatılabilir.
- Rota raporunda gönderilmeyen: seyahat adı, gün tarihleri (yalnızca yıl+ay), kişi adları, harcama başlığı ve ödeyen, transferler, notlar (bilinen tür etiketleri hariç), konaklama/ulaşım durakları, otel, uçuş, fotoğraflar.
- Yeniden deneme: gönderilene kadar, denemeler arası ≥ 15 dk; 400/409/413 → `rejected`, tekrar yok.
- Yeni kullanıcı metinleri Türkçe; `ios/Gezzy/Resources/Localizable.xcstrings`'e `en` elle eklenir. Derleme yüzlerce satır silerse dosyayı geri al, yalnız kendi anahtarlarını ekle.
- Seyahat ekranında dolu düğmeler `.primary(tint)`; sheet'ler (paywall dahil) `.primary` (ink).
- Kod yorumları Türkçe, kısa. Commit sonu: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Yalnızca değiştirdiğin dosyaları stage et.
- Simülatör iPhone Air (28310D42-ED32-41D1-8841-CEFE37B7EBE9), Kopenhag test seyahati yüklü. Öne başka uygulama gelmişse kapatma, raporda belirt.

---

### Task 1: PremiumRules (GezzyKit)

**Files:**
- Create: `ios/Packages/GezzyKit/Sources/GezzyKit/PremiumRules.swift`
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/PremiumRulesTests.swift`

**Interfaces — Produces:** `PremiumRules.freeTripLimit`, `canCreateTrip(created:isPremium:)`, `tripsCreated(stored:owned:)`, `remainingFreeTrips(created:)`, `PremiumRules.Product` ids.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import GezzyKit

final class PremiumRulesTests: XCTestCase {
    func testFreeUserCanCreateTwoTrips() {
        XCTAssertTrue(PremiumRules.canCreateTrip(created: 0, isPremium: false))
        XCTAssertTrue(PremiumRules.canCreateTrip(created: 1, isPremium: false))
        XCTAssertFalse(PremiumRules.canCreateTrip(created: 2, isPremium: false))
        XCTAssertFalse(PremiumRules.canCreateTrip(created: 7, isPremium: false))
    }

    func testPremiumIsUnlimited() {
        XCTAssertTrue(PremiumRules.canCreateTrip(created: 50, isPremium: true))
    }

    func testDeletingDoesNotRefund() {
        // Keychain 2 diyor, cihazda 0 seyahat kaldı: hak geri gelmez.
        XCTAssertEqual(PremiumRules.tripsCreated(stored: 2, owned: 0), 2)
        // İlk geçiş: sayaç yok ama 3 sahipli seyahat var.
        XCTAssertEqual(PremiumRules.tripsCreated(stored: 0, owned: 3), 3)
    }

    func testRemaining() {
        XCTAssertEqual(PremiumRules.remainingFreeTrips(created: 0), 2)
        XCTAssertEqual(PremiumRules.remainingFreeTrips(created: 1), 1)
        XCTAssertEqual(PremiumRules.remainingFreeTrips(created: 5), 0)
    }

    func testProductIDs() {
        XCTAssertEqual(PremiumRules.productIDs, ["gezzy.premium.yearly", "gezzy.premium.monthly"])
    }
}
```

- [ ] **Step 2: Run** `swift test --filter PremiumRulesTests` → FAIL (`cannot find 'PremiumRules'`).

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Premium kuralları: ücretsiz kullanıcı ömür boyu 2 seyahat oluşturabilir; silmek hakkı geri vermez.
public enum PremiumRules {
    public static let freeTripLimit = 2
    public static let yearlyID = "gezzy.premium.yearly"
    public static let monthlyID = "gezzy.premium.monthly"
    /// Paywall sırası: yıllık önce.
    public static let productIDs = [yearlyID, monthlyID]

    public static func canCreateTrip(created: Int, isPremium: Bool) -> Bool {
        isPremium || created < freeTripLimit
    }

    /// Kalıcı sayaç ile cihazdaki sahipli seyahatlerin büyüğü.
    public static func tripsCreated(stored: Int, owned: Int) -> Int {
        max(stored, owned)
    }

    public static func remainingFreeTrips(created: Int) -> Int {
        max(0, freeTripLimit - created)
    }
}
```

- [ ] **Step 4: Run** `swift test` → all PASS.
- [ ] **Step 5: Commit** `git commit -m "Add premium rules for the free trip limit"` (+ trailer).

---

### Task 2: StoreKit, sayaç ve paywall

**Files:**
- Create: `ios/Gezzy/Store/Entitlements.swift`, `ios/Gezzy/Store/TripAllowance.swift`, `ios/Gezzy/Features/Premium/PaywallSheet.swift`, `ios/Gezzy/Support/Gezzy.storekit`
- Modify: `ios/project.yml` (scheme `run.storeKitConfiguration`), `ios/Gezzy/App/GezzyApp.swift`, `ios/Gezzy/Features/Profile/ProfileView.swift`, `Localizable.xcstrings`

**Interfaces — Produces:**
- `@MainActor @Observable final class Entitlements { static let shared; var isPremium: Bool; var products: [Product]; func load() async; func purchase(_ product: Product) async throws -> Bool; func restore() async }` — `GezzyApp`'te `.environment(Entitlements.shared)`.
- `enum TripAllowance { @MainActor static func created(store: TripStore) -> Int; @MainActor static func recordCreation(store: TripStore) }` — Keychain `service "gezzy"`, `account "tripsCreated"`, `kSecAttrSynchronizable = true`; `created` = `PremiumRules.tripsCreated(stored:owned:)`, `owned` = sahibi `store.me.id` olan ya da üyesiz seyahat sayısı; ilk okumada değer keychain'e yazılır.
- `struct PaywallSheet: View { enum Reason { case dataSharingDeclined, tripLimit, offlineMaps, autoPlan, profile }; init(reason: Reason, onPurchased: () -> Void = {}) }`

- [ ] **Step 1: StoreKit Configuration** — `ios/Gezzy/Support/Gezzy.storekit` (Xcode StoreKit config JSON, `version` 3.0): bir `subscriptionGroups` öğesi "Gezzy Premium"; iki `RecurringSubscription`: `gezzy.premium.monthly` `recurringSubscriptionPeriod: "P1M"` `displayPrice: "79.99"`; `gezzy.premium.yearly` `"P1Y"` `"599.99"` `introductoryOffer: { paymentMode: "free", subscriptionPeriod: "P1W" }`; `localizations` `tr` ve `en` (ad: "Premium (Aylık/Yıllık)" / "Premium (Monthly/Yearly)"). Dosya kaynak olarak bundle'a girmemeli (yalnızca scheme referansı). `project.yml`'de:

```yaml
    run:
      config: Debug
      storeKitConfiguration: Gezzy/Support/Gezzy.storekit
```

  ve `Gezzy` target'ının `sources`'unda `.storekit` dosyasını `excludes` ile hariç tut (bundle'a girmesin) — mevcut `sources` yapısına uy. `xcodegen generate`.

- [ ] **Step 2: `Entitlements`** — `Product.products(for: PremiumRules.productIDs)` (yıllık önce sıralı); `isPremium` = `Transaction.currentEntitlements` içinde `productID` premium kimliklerinden biri, `revocationDate == nil`, `expirationDate` nil ya da gelecekte. `init`'te `Transaction.updates` dinleyen `Task` (her doğrulanmış işlemde `finish()` ve yeniden hesap). Son değer `UserDefaults` `gezzy.premium.cached`'e yazılır ve `init`'te başlangıç değeri olarak okunur. `purchase`: `.success(.verified(t))` → `finish`, yenile, `true`; `.userCancelled` / `.pending` → `false`; doğrulanmamış → hata fırlat. `restore`: `try? await AppStore.sync()` + yenile. `GezzyApp`'te `.environment(Entitlements.shared)` ve ilk `.task`'ta `await Entitlements.shared.load()`.

- [ ] **Step 3: `TripAllowance`** — `SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate` ile `Int` (UTF-8 string) okuma/yazma; `kSecAttrSynchronizable: kCFBooleanTrue`, `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock`. Okuma hatasında 0.

- [ ] **Step 4: `PaywallSheet`** — `NavigationStack` içinde `ScrollView`:
  - Sağ üst kapatma (`xmark`, `dismiss()`), her zaman görünür.
  - Nedene göre başlık: `.dataSharingDeclined` "Verini paylaşmadan Gezzy'yi destekle", `.tripLimit` "2 ücretsiz seyahatini kullandın", `.offlineMaps`/`.autoPlan` "Bu bir Premium özelliği", `.profile` "Gezzy Premium".
  - Üç madde (ikon + metin): "Sınırsız seyahat" (`infinity`), "Çevrimdışı haritalar ve otomatik rota" (`map`), "Rotan hiç paylaşılmaz" (`lock.shield`).
  - Plan kartları `entitlements.products` üzerinden: ad (`displayName`), `displayPrice` + dönem ("/ay", "/yıl"); yıllıkta `subscription?.introductoryOffer` varsa "7 gün ücretsiz" rozeti ve aylık karşılığı (`price / 12`, `priceFormatStyle`). Seçili kart `Color.ink` kenarlık; varsayılan seçim yıllık.
  - "Devam et" `.buttonStyle(.primary)`; satın alırken `ProgressView`. Başarı → `onPurchased()`, `dismiss()`. Hata → alert "Satın alma tamamlanamadı".
  - Altta "Satın alımları geri yükle" (restore, premium olursa kapan), "Kullanım koşulları" (`https://www.apple.com/legal/internet-services/itunes/dev/stdeula/`), "Gizlilik" (`https://gezzy.app/privacy`) bağlantıları ve yenileme notu: "Abonelik, dönem bitmeden 24 saat önce iptal edilmezse otomatik yenilenir. App Store ayarlarından yönetebilirsin."
  - Ürünler yüklenemezse: "Abonelikler şu an yüklenemedi." + "Tekrar dene".

- [ ] **Step 5: Profil** — `ProfileView` listesine "Premium" bölümü: premium → "Gezzy Premium · aktif" satırı + "Aboneliği yönet" (`.manageSubscriptionsSheet(isPresented:)`); değil → "Premium'a geç" (`PaywallSheet(reason: .profile)` sheet) + "Satın alımları geri yükle".

- [ ] **Step 6: Build + simülatör** — build; uygulamayı Xcode scheme'i ile değil `simctl` ile kurarsan StoreKit config etkin olmaz: StoreKit testini raporda "Xcode Run gerektirir" diye not et; paywall'ın açıldığını Profil'den ekran görüntüsüyle doğrula (ürün yüklenmiyorsa hata durumu görünür, bu kabul).
- [ ] **Step 7: Commit** `"Add premium subscription with paywall and trip allowance"`.

---

### Task 3: Premium kilitleri

**Files:**
- Modify: `ios/Gezzy/Features/Trips/TripsView.swift`, `ios/Gezzy/Features/Plan/PlanSection.swift` (`OfflineMapRow`), `ios/Gezzy/Features/TripDetail/TripDetailView.swift` (`coverMenu`), `ios/Gezzy/Features/Plan/IdeasCard.swift`, `Localizable.xcstrings`

**Interfaces — Consumes:** `Entitlements`, `TripAllowance`, `PaywallSheet`, `PremiumRules` (Task 1–2).

- [ ] **Step 1: Seyahat sınırı** — `TripsView`'de "Seyahat planla" eylemi: `PremiumRules.canCreateTrip(created: TripAllowance.created(store: store), isPremium: entitlements.isPremium)` ise `isCreating = true`, değilse `PaywallSheet(reason: .tripLimit) { isCreating = true }` sheet'i (satın alınca oluşturma açılır). `NewTripSheet`'in `onCreate` kapanışında `store.add(trip)` sonrası `TripAllowance.recordCreation(store: store)`. Onboarding'deki "İlk seyahatimi planla" aynı kontrolden geçer (aynı fonksiyonu kullan). Premium değilse düğmenin altında `.caption` `Color.ink2`: kalan 1 ise "Ücretsiz: 1 seyahat hakkın kaldı", 0 ise "Ücretsiz seyahat hakkın doldu"; 2 ise metin yok.
- [ ] **Step 2: Çevrimdışı haritalar** — `OfflineMapRow`'daki "Kaydet/Güncelle" ve `TripDetailView.coverMenu`'deki "Haritaları internetsiz kaydet": premium değilse `PaywallSheet(reason: .offlineMaps)` açar (satın alınca kaydı başlatır). Kayıtlı haritaları gösterme (`eye`) ücretsiz kalır. Menü öğesine premium değilken `lock` ikonu.
- [ ] **Step 3: Otomatik rota** — `IdeasCard`'daki "Otomatik rota": premium değilse `PaywallSheet(reason: .autoPlan) { isPlanning = true }`; etiketin sonunda küçük `lock.fill` ikonu (premium değilken). Plan'daki tek gün sıralama düğmesi (`optimize`) değişmez.
- [ ] **Step 4: Build, simülatör, commit** — Kopenhag'a ek olarak 1 seyahat oluştur → 2 oldu → "Seyahat planla" paywall açmalı; oluşturduğun seyahati sil → yine paywall. (Simülatör verisini değiştirdiysen raporda belirt.) Commit `"Gate trip creation, offline maps and auto plan behind premium"`.

---

### Task 4: Sunucu — rota raporları ve geri çekme

**Files:**
- Create: `server/migrations/0003_trip_reports.sql`, `server/src/reports.ts`, `server/src/reports.test.ts`
- Modify: `server/src/community.ts` (`findPlace` ayrımı, `withdraw`), `server/src/community.test.ts` (withdraw testi, migration listesi), `server/src/index.ts`, `server/README.md`

**Interfaces — Produces:** `POST /trips/report` (gövde `RouteReport` JSON) → 200 `{ok}` / 400 / 409 / 413 / 429; `POST /trips/report/withdraw` (gövde `{id}`) → 200 her durumda (sahiplik sızdırmaz); `POST /places/withdraw` (gövde `Contribution`) → 200. Hepsi mevcut `sender()` kimlik akışıyla (imzalı gövde gerektiği için DELETE yerine POST — spec'teki `DELETE /trips/report/:id` bu nedenle `POST /trips/report/withdraw` oldu).

- [ ] **Step 1: Migration**

```sql
-- Biten seyahatlerin rota raporları (kullanıcı izin verdiyse). Kişi adı, gün tarihi, not, otel, uçuş tutulmaz.
CREATE TABLE IF NOT EXISTS trip_reports (
  id TEXT PRIMARY KEY,
  contributor TEXT NOT NULL,
  country TEXT NOT NULL,
  city TEXT NOT NULL,
  year INTEGER NOT NULL,
  month INTEGER NOT NULL,
  nights INTEGER NOT NULL,
  travellers INTEGER NOT NULL,
  currency TEXT NOT NULL,
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS trip_reports_country_city ON trip_reports (country, city);
CREATE INDEX IF NOT EXISTS trip_reports_created ON trip_reports (created_at);
```

- [ ] **Step 2: Failing tests** (`reports.test.ts`, `community.test.ts`'teki `d1()` adaptörünü kopyala; migration listesine `0003_trip_reports.sql` ekle):

```ts
const report = (o: Record<string, unknown> = {}) => ({
  reportID: "8F0C2A4E-1B2C-4D5E-8F90-123456789ABC", country: "DK", city: "Kopenhag", cities: ["Kopenhag"],
  year: 2026, month: 11, nights: 4, travellers: 3, currency: "DKK",
  places: [{ ref: "p0", name: "Nyhavn", lat: 55.6798, lon: 12.5907, kind: "sight", category: "", liked: 0, verified: false }],
  days: [{ index: 0, stops: [{ ref: "p0", startMinutes: 600, durationMinutes: 60 }] }],
  budget: { food: 450000 }, expenses: [{ day: 0, category: "food", amount: 62000, splitCount: 3 }], ...o,
});

test("valid report is stored once per id", async () => {
  const db = d1();
  assert.equal(await submitReport(db, "u1", validateReport(report()) as RouteReport), "ok");
  assert.equal(await submitReport(db, "u1", validateReport(report({ nights: 5 })) as RouteReport), "ok"); // aynı kişi: üzerine yazar
  const row = await db.prepare("SELECT nights, year FROM trip_reports").first<{ nights: number; year: number }>();
  assert.deepEqual(row, { nights: 5, year: 2026 });
});

test("another contributor cannot overwrite a report", async () => {
  const db = d1();
  await submitReport(db, "u1", validateReport(report()) as RouteReport);
  assert.equal(await submitReport(db, "u2", validateReport(report()) as RouteReport), "conflict");
});

test("validation rejects bad fields", () => {
  assert.equal(typeof validateReport(report({ month: 13 })), "string");
  assert.equal(typeof validateReport(report({ year: 1990 })), "string");
  assert.equal(typeof validateReport(report({ currency: "EURO" })), "string");
  assert.equal(typeof validateReport(report({ reportID: "x" })), "string");
  assert.equal(typeof validateReport(report({ days: [{ index: 0, stops: [{ ref: "zz", durationMinutes: 60 }] }] })), "string");
  assert.equal(typeof validateReport(report({ places: [{ ref: "p0", name: "www.spam.com", lat: 1, lon: 1, kind: "sight" }] })), "string");
});

test("withdraw deletes only own report", async () => {
  const db = d1();
  await submitReport(db, "u1", validateReport(report()) as RouteReport);
  await withdrawReport(db, "u2", report().reportID as string);
  assert.ok(await db.prepare("SELECT id FROM trip_reports").first());
  await withdrawReport(db, "u1", report().reportID as string);
  assert.equal(await db.prepare("SELECT id FROM trip_reports").first(), null);
});

test("daily quota of 20 reports", async () => {
  const db = d1();
  for (let i = 0; i < REPORT_DAILY_QUOTA; i++) {
    const id = `8F0C2A4E-1B2C-4D5E-8F90-${String(i).padStart(12, "0")}`;
    assert.equal(await submitReport(db, "u1", validateReport(report({ reportID: id })) as RouteReport), "ok");
  }
  assert.equal(await submitReport(db, "u1", validateReport(report({ reportID: "8F0C2A4E-1B2C-4D5E-8F90-999999999999" })) as RouteReport), "quota");
});

test("reports older than 24 months are pruned on submit", async () => {
  const db = d1();
  const old = Date.now() - RETENTION_MS - 1000;
  await submitReport(db, "u1", validateReport(report()) as RouteReport, old);
  await submitReport(db, "u2", validateReport(report({ reportID: "8F0C2A4E-1B2C-4D5E-8F90-000000000777" })) as RouteReport);
  const { results } = await db.prepare("SELECT id FROM trip_reports").all<{ id: string }>();
  assert.equal(results.length, 1);
});
```

  `community.test.ts`'e: `withdraw` sonrası aynı contributor'ın `votes` ve `transitions` satırlarının silindiği, `places` satırının ve başka contributor'ın oylarının kaldığı test.

- [ ] **Step 3: Implement `reports.ts`** — `export interface RouteReport`; `export const REPORT_DAILY_QUOTA = 20`, `RETENTION_MS = 730 * 24 * 3600 * 1000`, `MAX_PAYLOAD_BYTES = 64 * 1024`; `validateReport(x): RouteReport | string` kurallar: `reportID` UUID regex, `country` 2 harf, `city` 1–80 karakter, `cities` ≤ 20, `year` 2000–2100, `month` 1–12, `nights` 0–90, `travellers` 1–30, `currency` `/^[A-Z]{3}$/`, `places` 1–200 (her biri `isPlausibleName` + lat/lon aralık + kind string), `days` ≤ 60, gün başına ≤ 30 ziyaret, her `ref` places içinde, `startMinutes` 0–1439 ya da yok, `durationMinutes` 0–1440, `budget` değerleri 0…1e9 tamsayı, `expenses` ≤ 500 (amount 0…1e9 tamsayı, `splitCount` 1–30, `day` tamsayı ya da null), JSON uzunluğu ≤ `MAX_PAYLOAD_BYTES`. `submitReport(db, contributor, r, now)`: önce `DELETE FROM trip_reports WHERE created_at < now - RETENTION_MS`; mevcut satır başkasınınsa `"conflict"`; kota (`quotas` tablosu, `day` = `"r:" + YYYY-MM-DD`) aşıldıysa `"quota"`; `INSERT ... ON CONFLICT(id) DO UPDATE` (payload = places/days/cities/budget/expenses JSON). `withdrawReport(db, contributor, id)`: `DELETE ... WHERE id = ? AND contributor = ?`.
- [ ] **Step 4: `community.ts`** — `findOrCreatePlace`'i `findPlace` (eşleşme, yoksa null) + oluşturmaya ayır; `export async function withdraw(db, contributor, c: Contribution)`: her yer için `findPlace`; bulunan id'lerde `DELETE FROM votes WHERE place_id = ? AND contributor = ?` ve `DELETE FROM transitions WHERE contributor = ? AND (from_id = ? OR to_id = ?)`.
- [ ] **Step 5: `index.ts`** — `POST /trips/report`, `/trips/report/withdraw`, `/places/withdraw` yolları; gövde baytları `sender()`'a, sonra JSON. `/trips/report`: gövde > 64 KB → 413; `validateReport` string → 400; `"conflict"` → 409; `"quota"` → 429; ok → 200. Withdraw yolları her zaman 200 `{ok:true}` (geçersiz gövde 400).
- [ ] **Step 6: README** — uç nokta tablosuna üç satır; "Rota raporları" alt bölümü: ne saklanır (tablo sütunları + payload içeriği), ne saklanmaz, 24 ay saklama, geri çekme.
- [ ] **Step 7: Run** `cd server && npm test` → all PASS. Commit `"Store trip route reports and allow withdrawing contributions"`.

---

### Task 5: RouteReport (GezzyKit)

**Files:**
- Create: `ios/Packages/GezzyKit/Sources/GezzyKit/RouteReport.swift`
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/RouteReportTests.swift`

**Interfaces — Produces:** `RouteReport` (Codable; alan adları sunucudaki JSON ile birebir), `RouteReport.make(trip:me:reportID:now:calendar:) -> RouteReport?`, `RouteReport.isSender(_:me:)`, `RouteReport.contribution(trip:calendar:)` (oysuz topluluk katkısı), `RouteReportRetry.shouldAttempt(lastAttempt:now:)`, `RouteReportRetry.minimumGap` (15 dk), `RouteReportRetry.isFinal(status:)` (400/409/413 → true).

- [ ] **Step 1: Failing tests** (`CommunityPlacesTests` deseni; `TestCalendar` mevcut):

```swift
import XCTest
@testable import GezzyKit

final class RouteReportTests: XCTestCase {
    let cal = TestCalendar.calendar
    let me = UUID(), other = UUID()
    let now = TestCalendar.date(2026, 11, 30)

    func trip() -> Trip {
        let d1 = TestCalendar.date(2026, 11, 19), d2 = TestCalendar.date(2026, 11, 20)
        var trip = Trip(name: "Kopenhag · Ayşe'nin doğum günü", destination: Destination(countryCode: "dk", city: "Kopenhag"),
                        startDate: d1, endDate: TestCalendar.date(2026, 11, 23), currency: "DKK",
                        members: [Member(id: me, name: "Ömer", role: .owner), Member(id: other, name: "Ayşe")])
        trip.stops = [
            Stop(day: d1, order: 1, name: "Strøget", kind: .sight, startMinutes: 607, durationMinutes: 60,
                 coordinate: .init(latitude: 55.678612, longitude: 12.574712), note: "Kapı kodu 4512"),
            Stop(day: d1, order: 0, name: "Nyhavn", kind: .sight, durationMinutes: 45,
                 coordinate: .init(latitude: 55.6798, longitude: 12.5907), note: "Meydan"),
            Stop(day: d1, order: 2, name: "Hotel SP34", kind: .stay, coordinate: .init(latitude: 55.6787, longitude: 12.5685)),
            Stop(day: d2, order: 0, name: "Tivoli", kind: .activity, startMinutes: 1088, durationMinutes: 150,
                 coordinate: .init(latitude: 55.6737, longitude: 12.5681)),
        ]
        trip.budget = [BudgetLine(category: .food, limit: 450_000)]
        trip.expenses = [
            Expense(title: "Ayşe'ye hediye", amount: 62_000, category: .food, paidBy: other, splitAmong: [me, other],
                    date: TestCalendar.date(2026, 11, 20), originalAmount: 8_300, originalCurrency: "EUR"),
            Expense(title: "Hesaplaşma", amount: 10_000, category: .other, paidBy: me, splitAmong: [other],
                    date: TestCalendar.date(2026, 11, 21), isTransfer: true),
            Expense(title: "Ön ödeme", amount: 5_000, category: .stays, paidBy: me, splitAmong: [me],
                    date: TestCalendar.date(2026, 10, 1)),
        ]
        return trip
    }

    func make(_ t: Trip? = nil, me id: UUID? = nil, now n: Date? = nil) -> RouteReport? {
        RouteReport.make(trip: t ?? trip(), me: id ?? me, reportID: "R1", now: n ?? now, calendar: cal)
    }

    func testSummaryFields() throws {
        let r = try XCTUnwrap(make())
        XCTAssertEqual(r.reportID, "R1")
        XCTAssertEqual(r.country, "DK")
        XCTAssertEqual(r.city, "Kopenhag")
        XCTAssertEqual(r.cities, ["Kopenhag"])
        XCTAssertEqual(r.year, 2026)
        XCTAssertEqual(r.month, 11)
        XCTAssertEqual(r.nights, 4)
        XCTAssertEqual(r.travellers, 2)
        XCTAssertEqual(r.currency, "DKK")
        XCTAssertEqual(r.budget, ["food": 450_000])
    }

    func testDaysKeepOrderRoundTimesAndSkipStays() throws {
        let r = try XCTUnwrap(make())
        XCTAssertEqual(r.places.map(\.name), ["Nyhavn", "Strøget", "Tivoli"])
        XCTAssertEqual(r.days.map(\.index), [0, 1])
        XCTAssertEqual(r.days[0].stops.map(\.ref), ["p0", "p1"])
        XCTAssertEqual(r.days[0].stops[1].startMinutes, 600)   // 607 → 600
        XCTAssertNil(r.days[0].stops[0].startMinutes)
        XCTAssertEqual(r.days[1].stops[0].startMinutes, 1095)  // 1088 → 1095
        XCTAssertEqual(r.days[1].stops[0].durationMinutes, 150)
        XCTAssertEqual(r.places[1].lat, 55.67861)
    }

    func testExpensesWithoutTitlesPayersOrTransfers() throws {
        let r = try XCTUnwrap(make())
        XCTAssertEqual(r.expenses.count, 2)
        // Tarihe göre sıralı: önce seyahat öncesi ön ödeme.
        XCTAssertNil(r.expenses[0].day) // seyahat dışı tarih
        XCTAssertEqual(r.expenses[0].category, "stays")
        XCTAssertEqual(r.expenses[1], .init(day: 1, category: "food", amount: 62_000, originalAmount: 8_300,
                                            originalCurrency: "EUR", splitCount: 2))
    }

    func testNoPersonalTextLeaks() throws {
        let json = String(data: try JSONEncoder().encode(try XCTUnwrap(make())), encoding: .utf8)!
        for secret in ["Ayşe", "Ömer", "doğum günü", "4512", "hediye", "Hesaplaşma", "Hotel SP34", "2026-11-19"] {
            XCTAssertFalse(json.contains(secret), secret)
        }
        XCTAssertTrue(json.contains("Meydan")) // bilinen tür etiketi kalır
    }

    func testOnlyOwnerSends() {
        XCTAssertNil(make(me: other))
        var solo = trip(); solo.members = []
        XCTAssertNotNil(make(solo, me: other))
    }

    func testNotBeforeTripEndsAndNeedsTwoPlaces() {
        XCTAssertNil(make(now: TestCalendar.date(2026, 11, 23)))
        var few = trip(); few.stops = [few.stops[0]]
        XCTAssertNil(make(few))
    }

    func testContributionHasNoVotes() throws {
        let c = try XCTUnwrap(RouteReport.contribution(trip: trip(), calendar: cal))
        XCTAssertTrue(c.places.allSatisfy { $0.liked == 0 && !$0.verified })
    }

    func testRetryGap() {
        XCTAssertTrue(RouteReportRetry.shouldAttempt(lastAttempt: nil, now: now))
        XCTAssertFalse(RouteReportRetry.shouldAttempt(lastAttempt: now.addingTimeInterval(-14 * 60), now: now))
        XCTAssertTrue(RouteReportRetry.shouldAttempt(lastAttempt: now.addingTimeInterval(-15 * 60), now: now))
        XCTAssertTrue(RouteReportRetry.isFinal(status: 400))
        XCTAssertTrue(RouteReportRetry.isFinal(status: 409))
        XCTAssertFalse(RouteReportRetry.isFinal(status: 429))
        XCTAssertFalse(RouteReportRetry.isFinal(status: 500))
    }
}
```

  `Expense` init'inde `isTransfer`/`originalAmount` parametre sırası mevcut init'e göre (`Models.swift:231`); gerekirse testteki argüman sırasını init'e uydur, değerleri değiştirme. `Trip` init'inde `members` var; `currency:` sırası init'e uyar.

- [ ] **Step 2: Run** → FAIL.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Biten seyahatin rota raporu (kullanıcı izin verdiyse sunucuya gider). Kişi adı, gün tarihi, not, otel, uçuş,
/// harcama başlığı ve ödeyen kişi gönderilmez; yalnızca yıl ve ay.
public struct RouteReport: Codable, Hashable, Sendable {
    public struct Visit: Codable, Hashable, Sendable {
        public var ref: String
        public var startMinutes: Int?
        public var durationMinutes: Int
    }
    public struct Day: Codable, Hashable, Sendable {
        public var index: Int
        public var stops: [Visit]
    }
    public struct Spend: Codable, Hashable, Sendable {
        public var day: Int?
        public var category: String
        public var amount: Int
        public var originalAmount: Int?
        public var originalCurrency: String?
        public var splitCount: Int
    }

    public var reportID: String
    public var country: String
    public var city: String
    public var cities: [String]
    public var year: Int
    public var month: Int
    public var nights: Int
    public var travellers: Int
    public var currency: String
    public var places: [CommunityPlaces.Place]
    public var days: [Day]
    public var budget: [String: Int]
    public var expenses: [Spend]

    /// Ekipli seyahatte yalnızca sahibin cihazı gönderir; üye yoksa herkes (tek kişi).
    public static func isSender(_ trip: Trip, me: UUID) -> Bool {
        guard let owner = trip.members.first(where: { $0.role == .owner }) else { return true }
        return owner.id == me
    }

    /// Topluluk havuzu için oysuz katkı.
    public static func contribution(trip: Trip, calendar: Calendar = .current) -> CommunityPlaces.Contribution? {
        CommunityPlaces.contribution(for: trip, ratings: [:], verified: [], calendar: calendar)
    }

    public static func make(trip: Trip, me: UUID, reportID: String, now: Date = Date(),
                            calendar: Calendar = .current) -> RouteReport? {
        guard CommunityPlaces.canContribute(trip, now: now, calendar: calendar), isSender(trip, me: me),
              let contribution = contribution(trip: trip, calendar: calendar) else { return nil }
        // Katkıdaki ref'ler uygun durakların sırasıyla eşleşir ("p0", "p1"…).
        let eligible = CommunityPlaces.eligibleStops(in: trip)
        let start = calendar.startOfDay(for: trip.startDate)
        func dayIndex(_ date: Date) -> Int {
            calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? 0
        }
        var byDay: [Int: [Visit]] = [:]
        for (index, stop) in eligible.enumerated() {
            let rounded = stop.startMinutes.map { min(1425, (($0 + 7) / 15) * 15) }
            byDay[dayIndex(stop.day), default: []]
                .append(Visit(ref: "p\(index)", startMinutes: rounded, durationMinutes: stop.durationMinutes))
        }
        let dayCount = trip.days(calendar: calendar).count
        let spends = trip.expenses.filter { !$0.isTransfer }.sorted { $0.date < $1.date }.map { expense in
            let index = dayIndex(expense.date)
            return Spend(day: (0..<dayCount).contains(index) ? index : nil, category: expense.category.rawValue,
                         amount: expense.amount, originalAmount: expense.originalAmount,
                         originalCurrency: expense.originalCurrency, splitCount: max(1, expense.splitAmong.count))
        }
        let parts = calendar.dateComponents([.year, .month], from: trip.startDate)
        let cities = trip.isMultiCity ? trip.cityLegs.map(\.destination.city) : [trip.destination.city]
        return RouteReport(
            reportID: reportID, country: trip.destination.countryCode.uppercased(), city: cities.first ?? trip.destination.city,
            cities: cities, year: parts.year ?? 0, month: parts.month ?? 0, nights: trip.nights(calendar: calendar),
            travellers: max(1, trip.members.count), currency: trip.currency.uppercased(), places: contribution.places,
            days: byDay.keys.sorted().map { Day(index: $0, stops: byDay[$0]!) },
            budget: Dictionary(trip.budget.map { ($0.category.rawValue, $0.limit) }, uniquingKeysWith: max),
            expenses: spends)
    }
}

/// Gönderilemeyen rapor her ön plana gelişte yeniden denenir; denemeler arası en az 15 dk.
public enum RouteReportRetry {
    public static let minimumGap: TimeInterval = 15 * 60

    public static func shouldAttempt(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= minimumGap
    }

    /// Sunucu veriyi kalıcı olarak reddetti; yeniden denenmez.
    public static func isFinal(status: Int) -> Bool {
        [400, 409, 413].contains(status)
    }
}
```

  Not: `contribution` sırası (`eligibleStops`) gün+sıraya göre; testte Nyhavn `order 0` olduğu için `p0`. Ref eşlemesi `CommunityPlaces.contribution`'daki `"p\(index)"` ile aynı olmalı — kod oradaki dışlama (`excluded`) boşken birebir aynı sıra.

- [ ] **Step 4: Run** `swift test` → all PASS.
- [ ] **Step 5: Commit** `"Build anonymised route reports from finished trips"`.

---

### Task 6: RouteReporter (gönderici)

**Files:**
- Create: `ios/Gezzy/Store/RouteReporter.swift`
- Modify: `ios/Gezzy/Store/CommunityService.swift`, `ios/Gezzy/App/GezzyApp.swift`

**Interfaces:**
- Consumes: `RouteReport`, `RouteReportRetry` (Task 5), `Entitlements.isPremium` (Task 2), sunucu uç noktaları (Task 4).
- Produces:
  - `CommunityService.sendReport(_ report: RouteReport) async throws`, `withdrawReport(id: String) async throws`, `withdraw(_ c: CommunityPlaces.Contribution) async throws` — mevcut `send(_:body:)` ile (`trips/report`, `trips/report/withdraw` gövde `{"id": …}`, `places/withdraw`). `send` 200 dışı durumda `Failure.rejected(status)` fırlatıyor; değişmez.
  - `@MainActor @Observable final class RouteReporter { static let shared; enum Choice: String { case yes, no }; var choice: Choice?; func setChoice(_:); enum State: Codable, Equatable { case pending(lastAttempt: Date?), sent, rejected, withdrawn }; func state(for tripID: UUID) -> State?; func run(store: TripStore, isPremium: Bool) async; func withdraw(_ trip: Trip) async throws; func exclude(_ trip: Trip) }`

- [ ] **Step 1: Durum saklama** — `UserDefaults` `gezzy.routeSharing.choice` (String) ve `gezzy.routeReports.v1` (JSON `[String(tripID): Entry]`, `Entry { reportID: String; state: State }`). `reportID` ilk kez `UUID().uuidString` üretilir ve kaydedilir; aynı seyahatte hep aynı kalır.
- [ ] **Step 2: `run`** — `isPremium` ya da `choice != .yes` ise çık. Aynı anda tek çalışma (`isRunning` bayrağı). Her seyahat için: `CommunityService.shared.choice(for:) == .declined` ise ya da durum `sent/rejected/withdrawn` ise atla; `pending(lastAttempt)` için `RouteReportRetry.shouldAttempt` değilse atla; `RouteReport.make(trip:me:reportID:now:)` nil ise atla (henüz bitmemiş, sahibi değil, < 2 yer). Önce `contribution` gönder (`contribute`), sonra `sendReport`. Başarı → `sent` ve `CommunityService.shared.setChoice(.shared, for:)`. `Failure.rejected(s)` ve `RouteReportRetry.isFinal(status: s)` → `rejected` (+ `print` ile sebep); diğer hata → `pending(lastAttempt: now)`. `notConfigured` → durumu değiştirme.
- [ ] **Step 3: `withdraw(trip)`** — `withdrawReport(id:)` + `withdraw(contribution)` (contribution `RouteReport.contribution(trip:)`); başarı → `withdrawn` ve topluluk tercihini `.declined` yap. `exclude(trip)` (henüz gönderilmemişken "Bu seyahati gönderme") → `CommunityService.setChoice(.declined)` + durum `withdrawn`.
- [ ] **Step 4: Tetik** — `GezzyApp`: ilk `.task` sonunda ve `scenePhase == .active` dalında `Task { await RouteReporter.shared.run(store: store, isPremium: Entitlements.shared.isPremium) }`.
- [ ] **Step 5: Build** → BUILD SUCCEEDED. Sunucuya gerçek gönderim testi isteğe bağlı (staging yapılandırılmamışsa `notConfigured`; raporda belirt). Commit `"Send finished trips' route reports when sharing is allowed"`.

---

### Task 7: İzin arayüzü

**Files:**
- Modify: `ios/Gezzy/Features/Onboarding/OnboardingView.swift`, `ios/Gezzy/Features/Trips/TripsView.swift`, `ios/Gezzy/Features/Profile/ProfileView.swift`, `ios/Gezzy/Features/Memories/CommunityShareCard.swift`, `Localizable.xcstrings`
- Create: `ios/Gezzy/Features/Premium/RouteSharingPrompt.swift`

**Interfaces — Consumes:** `RouteReporter` (Task 6), `PaywallSheet`, `Entitlements` (Task 2).

Metin (her yerde aynı, tek anahtar): "Seyahat bitince gittiğin yerler, sırası ve saatleri, kaç gece ve kaç kişi olduğun, harcama tutarların Gezzy'ye gider. Adın, otelin, uçuşun ve harcama başlıkların gitmez. Profil'den istediğin zaman değiştirebilirsin."

- [ ] **Step 1: `RouteSharingPrompt`** — yeniden kullanılır kart: başlık "Rotanı başkalarına ilham yap", yukarıdaki metin, iki eşit görünümlü düğme yan yana "Evet, paylaş" / "Hayır" (ikisi de aynı stil: `Color.tray` zemin, seçili olan `Color.ink` kenarlık + onay ikonu; hiçbiri önceden seçili değil). `@Binding var choice: RouteReporter.Choice?`.
- [ ] **Step 2: Onboarding survey** — survey'in en sonuna `RouteSharingPrompt`; seçim `RouteReporter.shared.setChoice` ile kaydedilir. Survey "Devam" düğmesi, seçim yapılmadan pasif (`.disabled` + opacity 0.5). "Hayır" seçilince (seçim anında) `PaywallSheet(reason: .dataSharingDeclined)` sheet açılır; kapanınca survey'de kalınır. "Şimdilik geç" tercihi boş bırakır (gönderim yok; Step 3 sonra sorar).
- [ ] **Step 3: Mevcut / atlayan kullanıcılar** — `TripsView`'de onboarding tamamlanmış ve `RouteReporter.shared.choice == nil` ve premium değilse, açılışta bir kez (`@AppStorage("gezzy.routeSharing.prompted")` false iken) sheet: `RouteSharingPrompt` + "Kaydet" (seçim yoksa pasif). Kaydedince `prompted = true`; "Hayır" ise kapanınca `PaywallSheet(reason: .dataSharingDeclined)`. Sheet aşağı kaydırılarak kapatılırsa `prompted = true` (tekrar sorma) ve tercih boş kalır.
- [ ] **Step 4: Profil** — "Gizlilik" bölümü: `Toggle("Rotamı Gezzy ile paylaş", isOn:)` (`choice == .yes`; kapatınca `.no`, açınca `.yes`), altında metin (footer). Premium'da toggle kapalı ve `.disabled(true)`, footer "Premium'da rotan paylaşılmaz.".
- [ ] **Step 5: `CommunityShareCard`** — `RouteReporter.shared.state(for: trip.id)` ve `choice`'a göre:
  - `choice != .yes` ya da premium: bugünkü kart aynen.
  - `sent`: tek satır "Rotan Gezzy'ye gönderildi" + "Geri al" (`withdraw`, sırasında `ProgressView`, hata → kısa hata metni); mevcut oylama bölümü kalır (oylar `contribute` ile upsert).
  - `pending` ya da durum yok (seyahat bitti, henüz gönderilmedi): "Gönderilecek" + "Bu seyahati gönderme" (`exclude`).
  - `withdrawn` / `rejected`: bugünkü "Paylaş"/"Paylaşma" kartı.
- [ ] **Step 6: Build + simülatör** — build; onboarding'i simülatörde yeniden görmek için `xcrun simctl spawn <udid> defaults delete com.omeraydemir.gezzy gezzy.onboarding.completed.v1` (sandbox kapalı) — sonra geri `defaults write ... -bool true`. Survey kartı, "Hayır" → paywall, Profil toggle ekran görüntüleri (`.superpowers/sdd/<plan>/shots/`). Commit `"Ask for route sharing consent in the survey and show report status"`.
