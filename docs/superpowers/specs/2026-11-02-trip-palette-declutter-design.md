# Seyahat paleti ve sadeleştirme — tasarım

Tarih: 2026-11-02 · Durum: onay bekliyor

## Sorun

- **Renkler tutarsız ve tekdüze.** Seyahatin vurgu rengi (`Trip.tint`) 4 kategori renginden biri
  (`Accent.cycle(coverSeed)`). Kapak bantları ise ayrı 5 paletten geliyor (`CoverArt.palettes`). Kopenhag'ın kapağı
  mavi-mor, ekrandaki ışık turuncu. Durak pinleri her seyahatte aynı yeşil/mavi/turuncu/mor döngüsünde.
- **Ekranlar kalabalık.**
  - Plan'da her durağın solunda renkli numaralı pin, sağında aynı bilgiyi tekrarlayan büyük renkli tür kutusu var.
  - Gün başlığında üç ayrı çip var.
  - Fikirler kartında her satırda siyah "19 Per ekle" hapı var; kartta ayrıca siyah "Otomatik rota", kartın üstünde
    de siyah "Durak ekle" var. Tek ekranda beş ağır siyah düğme.
  - Sürükleme ipucu her gün kartında sürekli görünüyor.
  - "Haritaları internetsiz kaydet" bandı her zaman açık.

## Hedef

1. Her seyahatin kendi rengi olsun; kapak, vurgu, pinler ve düğmeler aynı paletten gelsin. Yeni seyahat rastgele
   palet alsın.
2. Seyahat ekranında aynı bilgi iki kez gösterilmesin, ağır siyah düğme sayısı en fazla bir olsun, kalıcı ipuçları
   kalksın.

Kapsam dışı: Seyahatler listesi dışındaki ana ekranlar (Profil, Onboarding) yalnızca palet değişikliğinden etkilenir;
yeniden düzenlenmez. Bütçe kategori renkleri (konaklama yeşil, ulaşım mavi, yemek turuncu, aktivite mor) anlam
taşıdığı için aynen kalır. Kişi renkleri (`Member.colorIndex`) aynen kalır.

## 1. TripPalette (GezzyKit, saf)

`ios/Packages/GezzyKit/Sources/GezzyKit/TripPalette.swift`. UI bilmez; renkler `UInt32` hex.

```swift
public struct TripPalette: Hashable, Sendable {
    public let id: String          // "fjord", "terracotta" …
    public let bands: [UInt32]     // kapak bantları, 5 renk, yukarıdan aşağı
    public let accent: UInt32      // ana vurgu: birincil düğme, seçili çip, ışık
    public let pins: [UInt32]      // durak pinleri, 4 renk; pins[0] == accent
    public let softLight: UInt32   // açık temada vurgu zemini (seçili satır, çip zemini)
    public let softDark: UInt32    // koyu temada vurgu zemini

    public static let all: [TripPalette]                    // 12 el seçimi palet
    public static func forSeed(_ seed: Int) -> TripPalette  // all[abs(seed) % all.count]
    public static func derived(from hex: UInt32, fallbackSeed: Int) -> TripPalette
}
```

### El seçimi paletler

On iki palet; her biri bir yer hissi taşır (fiyort, terrakota, zeytin, lavanta, mercan, okyanus, safran, orman,
erik, kum, buzul, gece). Değerler plan aşamasında sabitlenir ve testlerle kilitlenir.

Kurallar (testler denetler):

- `bands.count == 5`, `pins.count == 4`, `pins[0] == accent`.
- `accent` ve her `pins` rengi beyaz metinle en az **3:1** kontrast (WCAG göreli parlaklık). Pin numarası ve birincil
  düğme metni beyaz.
- Bir paletin `pins` renkleri birbirinden ayırt edilebilir: her çift arasında ton farkı ≥ 25° ya da parlaklık
  farkı ≥ 0,15.
- `softLight` beyaz zemine yakın (göreli parlaklık ≥ 0,8), `softDark` koyu (≤ 0,08).

### Fotoğraftan türetme

Kapak fotoğrafı olan seyahatte palet `CoverImageStore.dominantColor` renginden türetilir:

- Ton `h` korunur. `accent` = HSB(h, doygunluk 0,45…0,75 aralığına kısılmış, parlaklık 0,62). Kontrast 3:1'in altında
  kalırsa parlaklık 0,05 adımlarla düşürülür.
- `pins` = accent, h+40°, h+160°, h+220° (aynı doygunluk/parlaklık, aynı kontrast düzeltmesi).
- `bands` kullanılmaz (fotoğraf gösterilir) ama dolu döner: accent'in açık tonları.
- `softLight` = HSB(h, 0,08, 0,99), `softDark` = HSB(h, 0,35, 0,16).
- Gri fotoğraf (doygunluk < 0,08): `forSeed(fallbackSeed)` döner.

`dominantColor` bugün `Color` döndürüyor; `rgbHex` (WidgetBridge'deki mevcut yardımcı) ile hex'e çevrilir.

## 2. Uygulamada kullanım

- `Trip.palette` (`@MainActor`, `TripCover.swift`): fotoğraf varsa `derived`, yoksa `forSeed(coverSeed)`.
- `Trip.tint` = `Color(hex: palette.accent)`. Mevcut `tripTint` ortam değeri aynen kalır, yanına `tripPalette` ortam
  değeri eklenir (`TripDetailView`'de ikisi birlikte verilir).
- `Color(soft:)` yardımcısı: `Color(light: palette.softLight, dark: palette.softDark)`.
- **Kapak**: `CoverArt(seed:)` → `CoverArt(palette:)`; bantlar paletten. Ağırlıklar aynen.
- **Pinler**: `NumberedPin(number:accent:)` yerine `NumberedPin(number:color:)`. Plan, harita ve Yer ekle ekranındaki
  pinler `palette.pins[index % 4]`. `Accent.cycle` yalnızca kişi renkleri ve paylaşım görseli (`DeviceServices`) için
  kalır.
- **Birincil düğme**: `PrimaryButtonStyle` bir `fill: Color` alır (varsayılan `.ink`). Seyahat ekranındaki birincil
  düğmeler `tint` kullanır; Seyahatler listesindeki "Seyahat planla" siyah kalır.
- **Seçili çipler**: sekme çubuğu ve gün seçicideki seçili öğe siyah yerine `tint` zemin + beyaz metin.
- **Işık**: `TintGlow` zaten `tint` alıyor; değişiklik gerekmez.
- **Widget**: `WidgetBridge` `tint.rgbHex` gönderiyor; `Trip.tint` paletten geldiği için kendiliğinden doğru renk.
- **Yeni seyahat**: `NewTripSheet` zaten `coverSeed = Int.random(in: 0..<100)`; önizleme ışığı `forSeed` accent'ini
  kullanır.
- **Düzenle**: `TripEditSheet`'teki renk düğmesi `coverSeed`'i bir sonraki palete geçirir (`(seed + 1) % 100` aynı
  kalır, `% 12` ile her basışta farklı palet). Düğmedeki daire paletin 4 pin rengini çeyrek dilim olarak gösterir.

Mevcut seyahatlerin rengi değişir (seed artık 12 palete eşlenir); veri göçü gerekmez.

## 3. Sadeleştirme

### Plan sekmesi

- **Durak satırı**: sağdaki 52 pt tür kutusu kalkar. Tür, alt satırın başında küçük gri SF Symbol olur:
  "🔭 Manzara · 1 sa". Saat etiketi (ör. 18:30) sağda kalır; zemini `soft`, metni `tint`.
- **Gün başlığı**: üç çip tek satır ikincil metin olur: "3 durak · 2,2 km · 35 dk yürüyüş". Durak yoksa satır
  gösterilmez.
- **Sürükleme ipucu**: `@AppStorage("gezzy.hint.dragStops")` sayacı; ipucu en çok 3 kez (3 farklı açılış) gösterilir,
  kullanıcı bir durağı sürüklediğinde sayaç doğrudan biter.
- **"Durak ekle"** birincil düğme kalır (`tint` dolgu). Yanındaki rota düğmesi aynen.
- **"Haritaları internetsiz kaydet" bandı**: yalnızca seyahat başlangıcına 7 gün ya da daha az kaldığında ve seyahat
  bitmemişken görünür. Diğer zamanlarda `•••` menüsünde "Haritaları internetsiz kaydet" öğesi olarak durur (aynı
  eylem).

### Fikirler kartı

- "Yer ekle" kartın başlığındaki tinted **+** olur (Uçuşlar/Konaklama kartlarındaki `ModuleCard` accessory deseni).
  Fikir yokken `AddPlaceholder` satırı ("＋ Yer ekle") görünür.
- "Otomatik rota" ikincil stil: `soft` zemin, `tint` metin, kapsül. Kartın başlık altında tek başına durur.
- Satırdaki siyah "19 Per ekle" hapı → 32 pt `tint` renkli daire içinde **+**. Dokununca seçili güne ekler (bugünkü
  davranış). Uzun basınca `Menu` ile gün seçilir ("20 Cum'e ekle" …). Erişilebilirlik etiketi:
  "19 Per gününe ekle".
- Satırdaki tür kutusu (gri dürbün) aynen kalır ama 36 pt yerine 28 pt; durak satırıyla aynı ikon dili.

### Diğer sekmeler — tarama kuralları

Bütçe, Valiz, Vize, Ekip ve Anılar sekmeleri aşağıdaki kurallarla taranır; uygulayıcı her sekmenin önce/sonra
ekran görüntüsünü alır ve bulguları rapora yazar.

1. Sekme başına en fazla bir dolu (siyah ya da tint) düğme. Diğerleri ikincil stil (`soft` zemin + `tint` metin) ya
   da başlıktaki **+**.
2. Kart içinde ekleme eylemi varsa başlıktaki **+** ile yapılır; ayrı büyük "… ekle" düğmesi kalkar. Boş durumda
   `AddPlaceholder`.
3. Aynı bilgiyi gösteren ikinci öğe (ikon + aynı anlamda etiket, tekrarlanan başlık) kalkar.
4. Her zaman görünen açıklama/ipucu metni (`.caption` gri paragraflar) yalnızca boş durumda ya da ilk kullanımda
   görünür; dolu durumda kalkar. Yasal/kaynak notları (vize kaynağı gibi) bu kuralın dışındadır, kısaltılarak kalır.
5. Seçili durum ve vurgular `tint`; kategori renkleri yalnızca bütçe kategorilerinde.

Bilinen adaylar (koddan): Ekip'te "QR ile katılanlar · şimdilik sadece görür" notu, Valiz'de "Öneriler mevsime göre
yapılacak." notu, Vize'de "Ekipte kimse yok." başlığının boş durum yerine büyük başlık olması, Bütçe ve Belgeler
kartlarındaki ekleme düğmeleri.

## 4. Kod düzeni

- Yeni: `GezzyKit/TripPalette.swift`, `GezzyKitTests/TripPaletteTests.swift`.
- Değişir: `DesignSystem/Theme.swift` (`Color(hex:)` zaten var; `Color.soft(_:)` yardımcısı),
  `DesignSystem/Components.swift` (`CoverArt`, `NumberedPin`, `PrimaryButtonStyle`),
  `DesignSystem/TripTheme.swift` (`tripPalette` ortam değeri), `Features/Trips/TripCover.swift` (`Trip.palette`,
  `Trip.tint`), `TripEditSheet`, `NewTripSheet`, `TripDetailView`, `PlanSection`, `IdeasCard`,
  `PlacePicker/PlacePickerMap`, `PlacePicker/PlacePickerList`, diğer sekme dosyaları (tarama sonucuna göre),
  `Localizable.xcstrings`.

## 5. Test

- `TripPaletteTests`: 12 palet; yapı kuralları; beyaz metin kontrastı ≥ 3:1; pin ayırt edilebilirliği; `forSeed`
  negatif ve büyük seed'de çökmez; `derived` kırmızı/mavi/sarı/gri girişlerde kontrast kuralını sağlar ve gri girişte
  `forSeed(fallbackSeed)` döner.
- Elle doğrulama (simülatör, Kopenhag test seyahati): açık ve koyu tema; Plan, Fikirler, Rezervasyon, Bütçe, Valiz,
  Vize, Ekip, Anılar; Düzenle'de renk karıştırma; kapak fotoğraflı seyahat.
