# Traveller · iOS

SwiftUI, iOS 17+. Türkiye'den yurt dışına giden gruplar için ilk sürüm.

## Kurulum

```bash
brew install xcodegen
cd ios
xcodegen generate
open Traveller.xcodeproj
```

`Traveller.xcodeproj` üretilen bir dosyadır ve repoya eklenmez; yapı `project.yml` içinde tanımlıdır.
Yeni dosya eklediğinde `xcodegen generate` komutunu tekrar çalıştır.

## iCloud paylaşımı (CloudKit)

Ekip paylaşımı ve eşitleme Apple'ın iCloud altyapısını kullanır; ayrı bir sunucu yoktur.
Gerçek cihazda çalıştırmak için bir kez:

1. Xcode → Traveller hedefi → *Signing & Capabilities* → kendi geliştirici ekibini seç.
2. *iCloud* yeteneğinde **CloudKit** işaretli olmalı; konteyner `iCloud.app.traveller.ios`
   (farklı bir kimlik kullanırsan `CloudConfig.containerIdentifier` ve `project.yml`'i güncelle).
3. İlk çalıştırmada CloudKit geliştirme şeması kendiliğinden oluşur (`Trip` kaydı: `payload`, `name`, `updatedAt`).
   Yayından önce CloudKit Console'da şemayı **Production**'a taşı.

iCloud'a giriş yapılmamış cihazda uygulama yalnızca yerel çalışır. Eşitleme iki kopyayı öğe bazında birleştirir;
silinen öğeler `tombstones` ile işaretlenir ve geri gelmez. Kapak fotoğrafı `Trip` kaydında `cover` varlığı,
makbuzlar ise seyahate bağlı `Photo` kayıtları (`name`, `kind`, `asset`) olarak eşitlenir.

Anlık güncelleme için *Push Notifications* yeteneği (`aps-environment`) ve *Background Modes → Remote notifications*
gerekir; ikisi de `project.yml`'de tanımlı. Uygulama CloudKit veritabanı aboneliklerini ilk açılışta kurar.

## Canlı uçuş kartı (Live Activity)

`TravellerWidgets` uzantısı (`Widgets/`) kilit ekranı ve Dynamic Island görünümünü çizer; ortak
`FlightActivityAttributes` tipi `Shared/` klasöründedir. Uzantının paket kimliği `app.traveller.ios.widgets`;
imzalarken uygulamayla aynı ekibi seç. Kart push'suz, uygulama içinden güncellenir.

`Support/Info.plist` ve `Support/Traveller.entitlements` `xcodegen generate` ile üretilir.

## Yapı

```
ios/
├── project.yml                 XcodeGen proje tanımı
├── Packages/TravellerKit       Saf Swift domain katmanı (UI yok, testli)
│   ├── Models                  Trip, Member, Stop, Expense, PackingItem…
│   ├── Settlement              Masraf bölme + borç sadeleştirme
│   ├── Budget                  Kategori bütçesi ve harcama temposu
│   ├── VisaRules               TC pasaportu için giriş kuralları + değerlendirme
│   ├── Packing                 Kural tabanlı valiz önerileri (priz tipi vb.)
│   ├── Geo                     Mesafe, yürüme süresi, rota sıralama
│   └── MoneyParser, TurkishGrammar, Countdown
└── Traveller                   Uygulama
    ├── DesignSystem            Kartpostal token'ları ve bileşenleri
    ├── Store                   TripStore (cihazda JSON) + örnek veri
    └── Features                Trips, TripDetail, Plan, Money, Packing, Visa, Crew
```

## Test

```bash
swift test --package-path ios/Packages/TravellerKit
```

CI (`.github/workflows/ios.yml`) her PR'da paket testlerini çalıştırır ve uygulamayı simülatör için derler.

## Vize verisi

`VisaRules.swift` elle derlenmiş bir veri setidir. Yayından önce ve düzenli aralıklarla
[konsolosluk.gov.tr](https://www.konsolosluk.gov.tr) üzerinden doğrulanmalı; doğrulandıkça `lastReviewed` güncellenmeli.
