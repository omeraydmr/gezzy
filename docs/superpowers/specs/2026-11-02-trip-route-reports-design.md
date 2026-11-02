# Biten seyahatin rotasını otomatik gönderme — tasarım

Tarih: 2026-11-02 · Durum: onay bekliyor

## Sorun

Bugün seyahat bitince Anılar'da `CommunityShareCard` çıkıyor; kullanıcı "Paylaş"a basarsa yalnızca yer adı, konum,
oy ve aynı gün art arda gidilen yer çiftleri `POST /places/contribute`'a gidiyor. Basmayan kullanıcıdan veri gelmiyor;
gelen veri de rota analizi için zayıf (gün sırası, saat, süre, seyahat özeti yok).

## Hedef

Seyahat bitince rota ve seyahat özeti, kullanıcı bir kez izin verdiyse (varsayılan açık) kendiliğinden Gezzy
sunucusuna gitsin. Sunucuda hem topluluk önerileri beslensin hem de analiz için ayrı bir rota raporu saklansın.

Kapsam dışı: sunucuda analiz/rapor ekranları, veri ambarına aktarım, toplu veri silme aracı (kullanıcı başına geri alma
var).

## Kararlar (kullanıcıyla)

- **İzin:** bir kez sorulur, **varsayılan açık**. Onboarding'de görünür bir anahtar ve Profil'de aynı anahtar.
  Kapatmak tek dokunuş.
- **Veri:** rota + seyahat özeti + durak saatleri.

### Hukuki not

KVKK/GDPR'da zorunlu olmayan işleme için açık rıza gerekir; önceden işaretli kutu geçerli rıza sayılmayabilir. App Store
5.1.1 toplanan verinin açıklanmasını ister. Riski azaltmak için:

- Anahtar onboarding'de ayrı bir adımda, ne gönderildiğini söyleyen metinle gösterilir (gizli ayar değil).
- Profil'de "Ne gönderiliyor?" açıklaması ve anahtar.
- Her gönderim Anılar'da görünür ve geri alınabilir.
- Gizlilik politikası ve App Store gizlilik etiketi güncellenir (bu spec'in dışında, yayından önce yapılmalı;
  etiket: "Other Data / Usage Data — Not linked to you, Analytics + App Functionality").

## 1. Gönderilen veri

GezzyKit'te saf `RouteReport` (Codable) ve `RouteReport.make(trip:me:now:calendar:) -> RouteReport?`.

```
RouteReport {
  reportID: String         // cihazda seyahat başına üretilen rastgele UUID; geri almada kullanılır
  country: String          // "DK"
  city: String             // "Kopenhag" (çok şehirde ilk şehir)
  cities: [String]         // çok şehirde sırayla şehirler; tek şehirde [city]
  month: Int               // 1…12, başlangıç ayı (yıl yok)
  nights: Int
  travellers: Int          // ekip sayısı (en az 1)
  places: [Place]          // CommunityPlaces.Place ile aynı: ref, name, lat/lon (5 basamak), kind, category
  days: [Day]              // gün sırasıyla
  budgetShares: [String: Double]  // kategori → harcama payı (0…1, 2 basamak); tutar ve para birimi yok
}
Day { index: Int, stops: [Visit] }
Visit { ref: String, startMinutes: Int?, durationMinutes: Int }   // startMinutes 15 dk'ya yuvarlanır
```

Gönderilmeyen: seyahat adı, kesin tarihler, yıl, kişi adları, notlar (bilinen tür etiketleri hariç — mevcut
`CommunityPlaces.category` kuralı), konaklama ve ulaşım durakları, otel ve uçuş bilgisi, tutarlar, fotoğraflar.

`make` şunlarda `nil` döner: seyahat bitmemiş (`CommunityPlaces` içindeki "bitti" kuralı), konumlu ve uygun durak
sayısı < 2, kullanıcı seyahatin sahibi değil (aşağıda).

Topluluk havuzu için aynı seyahatten mevcut `CommunityPlaces.contribution(...)` de (oysuz) üretilir.

## 2. Ne zaman ve hangi cihazdan

- **Tetik:** uygulama ön plana geldiğinde (`GezzyApp` içindeki `scenePhase == .active`) `RouteReporter.run()`.
  Arka plan görevi yok.
- **Uygun seyahat:** bitiş gününden en az 1 gün geçmiş, durumu `planned`, gönderilmemiş, kullanıcı bu seyahat için
  Anılar kartında "Paylaşma" dememiş, ayar açık.
- **Tek gönderici:** ekipli seyahatte her cihaz göndermesin diye yalnızca sahibin cihazı gönderir
  (`trip.members` içinde `role == .owner` olan üyenin `id`'si `store.me.id` ise; üye listesi boşsa da gönderilir).
- **Durum** (cihazda, `UserDefaults` `gezzy.routeReports.v1`): seyahat id → `{reportID, state: sent | failed(attempts) | withdrawn}`.
  Başarısız gönderim sonraki ön plana gelişte tekrar denenir, en çok 5 kez.
- **Sıra:** önce `POST /places/contribute` (oysuz), sonra `POST /trips/report`. İkincisi başarısızsa ilki yeniden
  gönderilebilir (sunucu kişi başına upsert ediyor, çift sayım olmaz).

## 3. Arayüz

- **Ayar anahtarı:** `@AppStorage("gezzy.routeSharing.enabled")`, varsayılan `true`.
- **Onboarding:** `cloud` ile `done` arasına yeni `sharing` adımı. Başlık "Rotanı başkalarına ilham yap", kısa
  açıklama (ne gider, ne gitmez: "Gittiğin yerler, sırası ve saatleri, kaç gece ve kaç kişi olduğu. Adın, tarihlerin,
  notların, otelin ve harcama tutarların gitmez."), anahtar açık gelir, "Devam".
- **Profil:** "Gizlilik" bölümünde anahtar + "Ne gönderiliyor?" (aynı metin, açılır).
- **Anılar kartı (`CommunityShareCard`):**
  - Ayar kapalıysa: bugünkü kart aynen.
  - Ayar açık ve gönderildiyse: tek satır "Rotan Gezzy'ye gönderildi" + "Geri al" ve mevcut "Beğendiklerini oyla"
    (oylar `/places/contribute` ile upsert edilir).
  - Ayar açık ama henüz gönderilmediyse (ör. ağ yok): "Gönderilecek" satırı + "Bu seyahati gönderme".
  - Geri alınmışsa: "Gönderilmedi" ve bugünkü "Paylaş" düğmesi.

## 4. Sunucu (Cloudflare Worker + D1)

- **Göç `0003_trip_reports.sql`:**

```sql
CREATE TABLE IF NOT EXISTS trip_reports (
  id TEXT PRIMARY KEY,            -- reportID
  contributor TEXT NOT NULL,      -- mevcut tuzlu özet
  country TEXT NOT NULL,
  city TEXT NOT NULL,
  month INTEGER NOT NULL,
  nights INTEGER NOT NULL,
  travellers INTEGER NOT NULL,
  payload TEXT NOT NULL,          -- RouteReport JSON (places, days, cities, budgetShares)
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS trip_reports_country_city ON trip_reports (country, city);
```

- **`POST /trips/report`** (`X-Gezzy-Key`, `X-Gezzy-Contributor` ya da App Attest — mevcut kimlik akışı): doğrula
  (alan tipleri, `month` 1–12, `nights` 0–90, `travellers` 1–30, en çok 200 yer / 60 gün / gün başına 30 ziyaret,
  `payload` ≤ 64 KB, yer adlarında bağlantı/e-posta/telefon yok — mevcut `validate` kuralları). Aynı `id` gelirse üzerine
  yazar (aynı contributor ise), başkasınınsa 409. Günlük kota: kişi başına 20 rapor.
- **`DELETE /trips/report/:id`**: yalnızca aynı contributor silebilir; satırı siler. 404/403 ayrımı yapmaz (bilgi
  sızdırmasın): her durumda 204.
- **`POST /places/withdraw`** (gövde `Contribution` ile aynı): yerleri mevcut eşleştirme kuralıyla bulur, bu
  contributor'ın o yerlerdeki `votes` ve `transitions` satırlarını siler. Yeri silmez.
- **Saklama:** `trip_reports` 24 aydan eski satırlar her `contribute` çağrısında silinir (ucuz, ayrı cron yok).
- Testler `server/src/*.test.ts` deseniyle (vitest, D1 sahte).

## 5. Kod düzeni

- GezzyKit: `RouteReport.swift` + `RouteReportTests.swift` (yapı, yuvarlama, dışlanan alanlar, sahip kuralı,
  bitmemiş seyahat, < 2 durak, bütçe payları toplamı ≈ 1, kişisel not sızmaması).
- Uygulama: `Store/RouteReporter.swift` (durum, tetik, ağ çağrıları — `CommunityService` ile aynı istek kurulumu),
  `CommunityService`'e `report(_:)`, `withdrawReport(id:)`, `withdraw(_ contribution:)`; `GezzyApp` tetik;
  `OnboardingView` yeni adım; `ProfileView` bölüm; `CommunityShareCard` durumları; `Localizable.xcstrings`.
- Sunucu: `migrations/0003_trip_reports.sql`, `src/reports.ts`, `src/reports.test.ts`, `src/community.ts`
  (`withdraw`), `src/index.ts` (yollar), `README.md` (uç noktalar ve saklanan veri tablosu).

## 6. Test ve doğrulama

- `swift test` (GezzyKit), `npm test` (server).
- Simülatör: Kopenhag test seyahatinin bitiş tarihini geçmişe çekerek (seed) staging'e gönderim; Anılar'da
  "gönderildi" satırı; "Geri al" sonrası sunucuda satırın silindiği (`wrangler d1 execute --local`).
- Yerel sunucu: `npx wrangler dev --env staging` ve uygulama `GEZZY_SERVER_HOST` ile.
