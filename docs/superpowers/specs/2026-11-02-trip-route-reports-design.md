# Biten seyahatin rotasını otomatik gönderme — tasarım

Tarih: 2026-11-02 · Durum: onay bekliyor

## Sorun

Bugün seyahat bitince Anılar'da `CommunityShareCard` çıkıyor; kullanıcı "Paylaş"a basarsa yalnızca yer adı, konum,
oy ve aynı gün art arda gidilen yer çiftleri `POST /places/contribute`'a gidiyor. Basmayan kullanıcıdan veri gelmiyor;
gelen veri de rota analizi için zayıf (gün sırası, saat, süre, seyahat özeti yok).

## Hedef

Seyahat bitince rota, seyahat özeti ve harcamalar, kullanıcı survey adımında izin verdiyse kendiliğinden Gezzy
sunucusuna gitsin. Sunucuda hem topluluk önerileri beslensin hem de analiz için ayrı bir rota raporu saklansın.

Kapsam dışı: sunucuda analiz/rapor ekranları, veri ambarına aktarım, toplu veri silme aracı (kullanıcı başına geri alma
var).

## Kararlar (kullanıcıyla)

- **İzin:** onboarding'in survey adımında açık bir soruyla istenir; önceden işaretli değildir ("Evet, paylaş" /
  "Hayır"). Cevap verilmeden hiçbir şey gönderilmez. "Hayır" diyen kullanıcıya premium teklifi gösterilir
  (kapatılabilir; uygulama ücretsiz kullanılmaya devam eder). Profil'de aynı tercih değiştirilebilir.
- **Premium:** abonesi olan kullanıcının rotası hiç gönderilmez (tercih premium'da kapalı kilitlenir). Abonelik ayrı
  spec'te: `2026-11-02-premium-subscription-design.md`.
- **Veri:** rota + seyahat özeti (yıl dahil) + durak saatleri + harcama tutarları.
- **Yeniden deneme:** gönderilene kadar sınırsız.

### Hukuki not

KVKK/GDPR'da zorunlu olmayan işleme için açık rıza gerekir. App Store 5.1.1 toplanan verinin açıklanmasını ister;
3.2.2 bir özelliği veri paylaşımı iznine bağlamayı yasaklar. Bu yüzden:

- İzin survey'de, ne gönderildiğini söyleyen metinle ve iki eşit düğmeyle istenir; varsayılan seçili değildir.
- Reddetmek hiçbir özelliği kapatmaz; yalnızca premium teklifi gösterilir.
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
  year: Int                // başlangıç yılı
  month: Int               // 1…12, başlangıç ayı
  nights: Int
  travellers: Int          // ekip sayısı (en az 1)
  places: [Place]          // CommunityPlaces.Place ile aynı: ref, name, lat/lon (5 basamak), kind, category
  days: [Day]              // gün sırasıyla
  currency: String         // seyahat para birimi, "DKK"
  budget: [String: Int]    // kategori → limit (kuruş)
  expenses: [Spend]        // her harcama: başlık ve kişi gönderilmez
}
Spend { day: Int?, category: String, amount: Int, originalAmount: Int?, originalCurrency: String?, splitCount: Int }
                          // day: seyahatin kaçıncı günü (dışındaysa nil); tutarlar kuruş
Day { index: Int, stops: [Visit] }
Visit { ref: String, startMinutes: Int?, durationMinutes: Int }   // startMinutes 15 dk'ya yuvarlanır
```

Gönderilmeyen: seyahat adı, kesin gün tarihleri (yalnızca yıl ve ay), kişi adları, harcama başlıkları ve ödeyen kişi,
notlar (bilinen tür etiketleri hariç — mevcut `CommunityPlaces.category` kuralı), konaklama ve ulaşım durakları, otel ve
uçuş bilgisi, makbuz ve diğer fotoğraflar. Hesaplaşma ödemeleri (`isTransfer`) gönderilmez.

`make` şunlarda `nil` döner: seyahat bitmemiş (`CommunityPlaces` içindeki "bitti" kuralı), konumlu ve uygun durak
sayısı < 2, kullanıcı seyahatin sahibi değil (aşağıda).

Topluluk havuzu için aynı seyahatten mevcut `CommunityPlaces.contribution(...)` de (oysuz) üretilir.

## 2. Ne zaman ve hangi cihazdan

- **Tetik:** uygulama ön plana geldiğinde (`GezzyApp` içindeki `scenePhase == .active`) `RouteReporter.run()`.
  Arka plan görevi yok.
- **Uygun seyahat:** bitiş gününden en az 1 gün geçmiş, durumu `planned`, gönderilmemiş, kullanıcı bu seyahat için
  Anılar kartında "Paylaşma" dememiş, tercih "evet", kullanıcı premium değil.
- **Tek gönderici:** ekipli seyahatte her cihaz göndermesin diye yalnızca sahibin cihazı gönderir
  (`trip.members` içinde `role == .owner` olan üyenin `id`'si `store.me.id` ise; üye listesi boşsa da gönderilir).
- **Durum** (cihazda, `UserDefaults` `gezzy.routeReports.v1`): seyahat id → `{reportID, state: pending | sent | withdrawn, lastAttempt}`.
  Başarısız gönderim gönderilene kadar her ön plana gelişte tekrar denenir; ardışık denemeler arasında en az 15 dakika
  (sunucuyu boğmamak için). 4xx doğrulama hatası (400/413) alan rapor `rejected` olur ve yeniden denenmez; sebep
  günlüğe yazılır.
- **Sıra:** önce `POST /places/contribute` (oysuz), sonra `POST /trips/report`. İkincisi başarısızsa ilki yeniden
  gönderilebilir (sunucu kişi başına upsert ediyor, çift sayım olmaz).

## 3. Arayüz

- **Tercih:** `@AppStorage("gezzy.routeSharing.choice")`: `"yes"`, `"no"` ya da boş (sorulmadı). Boşken gönderim yok.
- **Survey adımı (`OnboardingView.survey`):** mevcut soruların sonuna "Rotanı başkalarına ilham yap" kartı:
  açıklama ("Seyahat bitince gittiğin yerler, sırası ve saatleri, kaç gece ve kaç kişi olduğun, harcama tutarların
  Gezzy'ye gider. Adın, otelin, uçuşun ve harcama başlıkların gitmez. Profil'den istediğin zaman değiştirebilirsin.")
  ve iki eşit görünümlü düğme "Evet, paylaş" / "Hayır". Biri seçilmeden "Devam" pasif. "Hayır" seçilince premium
  teklif ekranı (`PaywallSheet`, premium spec'i) açılır; kapatınca onboarding sürer.
- **Mevcut kullanıcılar** (onboarding'i geçmiş, tercih boş): ilk açılışta aynı kart tek başına bir sheet olarak sorulur.
- **Profil:** "Gizlilik" bölümünde tercih (anahtar) + "Ne gönderiliyor?" (aynı metin). Premium kullanıcıda anahtar
  kapalı ve pasif, altında "Premium'da rotan paylaşılmaz.".
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
  year INTEGER NOT NULL,
  month INTEGER NOT NULL,
  currency TEXT NOT NULL,
  nights INTEGER NOT NULL,
  travellers INTEGER NOT NULL,
  payload TEXT NOT NULL,          -- RouteReport JSON (places, days, cities, budget, expenses)
  created_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS trip_reports_country_city ON trip_reports (country, city);
```

- **`POST /trips/report`** (`X-Gezzy-Key`, `X-Gezzy-Contributor` ya da App Attest — mevcut kimlik akışı): doğrula
  (alan tipleri, `year` 2000–2100, `month` 1–12, `currency` 3 harf, en çok 500 harcama, tutarlar 0…10⁹, `nights` 0–90, `travellers` 1–30, en çok 200 yer / 60 gün / gün başına 30 ziyaret,
  `payload` ≤ 64 KB, yer adlarında bağlantı/e-posta/telefon yok — mevcut `validate` kuralları). Aynı `id` gelirse üzerine
  yazar (aynı contributor ise), başkasınınsa 409. Günlük kota: kişi başına 20 rapor.
- **`POST /trips/report/withdraw`** (gövde `{id}`; imzalı gövde gerektiği için DELETE değil): yalnızca aynı contributor silebilir; satırı siler. 404/403 ayrımı yapmaz (bilgi
  sızdırmasın): her durumda 200.
- **`POST /places/withdraw`** (gövde `Contribution` ile aynı): yerleri mevcut eşleştirme kuralıyla bulur, bu
  contributor'ın o yerlerdeki `votes` ve `transitions` satırlarını siler. Yeri silmez.
- **Saklama:** `trip_reports` 24 aydan eski satırlar her `contribute` çağrısında silinir (ucuz, ayrı cron yok).
- Testler `server/src/*.test.ts` deseniyle (vitest, D1 sahte).

## 5. Kod düzeni

- GezzyKit: `RouteReport.swift` + `RouteReportTests.swift` (yapı, yuvarlama, dışlanan alanlar, sahip kuralı,
  bitmemiş seyahat, < 2 durak, harcamalarda başlık/kişi/transfer sızmaması, gün indeksi, kişisel not sızmaması);
  `RouteReportRetry` (yeniden deneme zamanı) testleri.
- Bağımlılık: premium spec'indeki `Entitlements.isPremium` ve `PaywallSheet`. Premium önce uygulanır.
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
