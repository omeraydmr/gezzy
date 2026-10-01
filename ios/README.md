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
