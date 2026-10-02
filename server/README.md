# Traveller sunucusu

İki iş yapar: canlı uçuş kartı push'ları ve topluluk öneri havuzu (aşağıda).

## Canlı uçuş kartı

Kilit ekranı / Dynamic Island'daki canlı uçuş kartını uygulama kapalıyken de günceller.
Cloudflare Worker: KV'de kayıtlı kartları 5 dakikada bir AeroDataBox'tan sorgular, durum değişince
APNs'e Live Activity push'u gönderir; uçak inince kartı kapatır.

```
uygulama ──POST /activities (push token + uçuş)──▶ Worker ──KV
                                                    │ cron */5
                                                    ├──▶ AeroDataBox (RapidAPI)
                                                    └──▶ APNs (liveactivity push) ──▶ kart
```

## Kurulum

1. Apple Developer > Certificates, IDs & Profiles > **Keys**: "Apple Push Notifications service (APNs)" yetkili bir anahtar
   oluştur, `.p8` dosyasını indir ve Key ID'yi not al.
2. Cloudflare hesabında:
   ```bash
   cd server
   npm install
   npx wrangler kv namespace create ACTIVITIES   # çıkan id'yi wrangler.toml'a yaz
   npx wrangler d1 create traveller-community    # çıkan database_id'yi wrangler.toml'a yaz
   npx wrangler d1 migrations apply traveller-community --remote
   npx wrangler secret put CONTRIBUTOR_SALT      # rastgele uzun bir değer; değişirse katkı sayımları sıfırlanır
   npx wrangler secret put CLIENT_KEY            # rastgele uzun bir değer
   npx wrangler secret put RAPIDAPI_KEY
   npx wrangler secret put APNS_KEY_ID
   npx wrangler secret put APNS_TEAM_ID          # 4BAD86T55H
   npx wrangler secret put APNS_PRIVATE_KEY      # .p8 dosyasının tüm içeriği
   npx wrangler deploy
   ```
3. Uygulamada `ios/Config/Secrets.xcconfig`:
   ```
   LIVE_ACTIVITY_SERVER_HOST = traveller-live.<hesabın>.workers.dev
   LIVE_ACTIVITY_SERVER_KEY = <CLIENT_KEY ile aynı>
   ```
   Adreste `https://` yazma: xcconfig'te `//` yorum başlatır; uygulama şemayı kendisi ekler.

Sunucu adresi boşsa uygulama eskisi gibi çalışır: kart yalnızca uygulama açıkken ve arka plan yenilemesinde güncellenir.

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
  `LIVE_ACTIVITY_SERVER_HOST='http:/$()/localhost:8787'` ile derle.
- Sonraki adım: App Attest ile yalnızca gerçek uygulamanın katkı gönderebilmesi (şimdilik ortak `CLIENT_KEY` + kota).

## Notlar

- Xcode'dan kurulan sürüm `development` (sandbox APNs), TestFlight/App Store sürümü `production` ortamını kullanır.
- Kart içeriği uygulamadaki `FlightActivityAttributes.ContentState` ile aynı anahtarlara sahiptir; tarihler Apple referans
  tarihinden (2001-01-01) saniye olarak gönderilir. Durum metni mantığı `ios/Packages/TravellerKit/.../FlightStatus.swift`
  ile `src/flight.ts`'te ikizdir; birini değiştirirken diğerini de güncelle.
- Kayıtlar varıştan 12 saat sonra KV'den kendiliğinden silinir.

## Test

```bash
npm test   # node --test (Node 22.6+; TypeScript doğrudan çalışır)
```
