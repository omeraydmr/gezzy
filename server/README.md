# Traveller · canlı uçuş kartı sunucusu

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
