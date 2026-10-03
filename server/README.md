# Traveller sunucusu

Cloudflare Worker + D1: topluluk öneri havuzu ve App Attest doğrulaması. Uçuş durumu takibi yok (güncel kapı,
rötar ve iptal bilgisi için havayolunun uygulaması kullanılır); kilit ekranındaki uçuş kartı cihazda, planlanmış
saatlerle çalışır.

## Kurulum

```bash
cd server
npm install
npx wrangler kv namespace create KV               # çıkan id'yi wrangler.toml'a yaz
npx wrangler d1 create traveller-community        # çıkan database_id'yi wrangler.toml'a yaz
npx wrangler d1 migrations apply traveller-community --remote
npx wrangler secret put CLIENT_KEY                # rastgele uzun bir değer
npx wrangler secret put CONTRIBUTOR_SALT          # rastgele uzun bir değer; değişirse katkı sayımları sıfırlanır
npx wrangler deploy
```

Uygulamada `ios/Config/Secrets.xcconfig` (git'e girmez):
```
TRAVELLER_SERVER_HOST = traveller-live.<hesabın>.workers.dev
TRAVELLER_SERVER_KEY = <CLIENT_KEY ile aynı>
```
Adreste `https://` yazma: xcconfig'te `//` yorum başlatır; uygulama şemayı kendisi ekler. Adres boşsa topluluk
önerileri kapalıdır, uygulamanın geri kalanı çalışır.

## Topluluk öneri havuzu

Seyahati biten kullanıcı Anılar'daki kartla onay verirse gittiği yerler ve aynı gün art arda gidilen yer çiftleri D1'e yazılır.
Veritabanı gizlidir (yalnızca Worker erişir); uç noktalar `X-Traveller-Key` ister.

| Uç nokta | İş |
|---|---|
| `POST /places/contribute` | `X-Traveller-Contributor: <cihaz UUID'si>`; gövde `{country, places[], transitions[[ref, ref]]}`. Günde 300 yer sınırı (429) |
| `GET /places/nearby?lat&lon` | 8 km içinde en az 3 farklı gezginin gittiği, beğenisi beğenmemesinden az olmayan yerler |
| `GET /places/next?lat&lon` | Bu yerden sonra aynı gün en az 3 gezginin gittiği yerler |

- Saklanan: yer adı, konum (5 basamak), tür, oy, fotoğrafla doğrulandı mı ve yer çiftleri. Kişi adı, tarih, not, ekip, tam rota saklanmaz.
- Cihaz kimliği `SHA-256(CONTRIBUTOR_SALT + UUID)` olarak tutulur; yalnızca "aynı kişi iki kez sayılmasın" ve kota için.
- Aynı yer farklı dillerde/küçük konum farkıyla gelirse 60 m içinde ve adı örtüşüyorsa (ya da 15 m içindeyse) birleştirilir.
- Yerelde denemek: `npx wrangler d1 migrations apply traveller-community --local` ve `npx wrangler dev`; uygulamayı
  `TRAVELLER_SERVER_HOST='http:/$()/localhost:8787'` ile derle.
- Yanlış/spam yer bildirimi: `POST /places/report {placeId, reason}` (wrong, closed, spam, offensive). En az 3 farklı
  kişi bildirdiğinde ya da bildirenler katkı verenlerin yarısına ulaştığında yer önerilerden düşer. Bağlantı, e-posta,
  telefon numarası içeren yer adları katkıda reddedilir.

### App Attest

Uygulama gerçek cihazda bir kez anahtar üretip Apple'a onaylatır (`POST /attest/challenge`, `POST /attest/register`),
sonra katkı ve bildirim gövdelerini bu anahtarla imzalar (`X-Traveller-Attest-Key`, `X-Traveller-Assertion`). Sunucu
sertifika zincirini Apple App Attestation kök sertifikasına kadar, challenge'ı, uygulama kimliğini (`APP_ID`) ve artan
sayacı doğrular (`src/appattest.ts`). Kimlik, anahtar kimliğinin tuzlanmış özetidir.

- `REQUIRE_APP_ATTEST = "false"`: geçiş dönemi; simülatör ve eski sürümler cihaz kimliğiyle katkı verebilir. App
  Attest'li sürüm App Store'a çıkınca `"true"` yapıp `npx wrangler deploy`.
- `ALLOW_DEV_ATTEST = "true"`: Xcode'dan kurulan geliştirme sürümleri kabul edilir. App Store sürümü için uygulamaya
  `com.apple.developer.devicecheck.appattest-environment = production` hakkı eklenmeli; eklenmezse cihaz geliştirme
  ortamını kullanır.

## Test

```bash
npm test   # node --test (Node 22.6+; TypeScript doğrudan çalışır)
```
