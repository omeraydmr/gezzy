# Anılar ve paylaşım stüdyosu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anılar sekmesine öne çıkanlar, harita üzerinde günlük ve favori/kapak/gizle; 5 şablonlu, özelleştirilebilir paylaşım stüdyosu ve "Gezzy ile planlandı" işareti.

**Architecture:** Saf kurallar GezzyKit'te (`MemoryHighlights`, `ShareCardConfig`). Uygulamada `MemoryPrefs` (cihazda favori/gizli), yeni Anılar düzeni (`HighlightsStrip`, `MemoryJournal`), `ShareStudioView` + `CardTemplates` + `CardRenderer`. Fotoğraflar cihazdan çıkmaz.

**Tech Stack:** Swift 6, SwiftUI iOS 17, MapKit (`Map`, `MKMapSnapshotter`), Photos, `ImageRenderer`, GezzyKit + XCTest.

**Spec:** `docs/superpowers/specs/2026-11-03-memories-share-studio-design.md`

## Global Constraints

- Build: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build` (no `-quiet`). Yeni dosya eklenince önce `cd ios && xcodegen generate`. GezzyKit test: `cd ios/Packages/GezzyKit && swift test`.
- Fotoğraf kimlikleri (`PHAsset.localIdentifier`) `Trip`'e yazılmaz; favori/gizli cihazda `UserDefaults` `gezzy.memories.v1`. Stüdyo ayarları `gezzy.shareStudio.v1`.
- Şablonlar: `postcard`, `stats`, `route`, `collage`, `ticket`. Biçimler: `story` 9:16, `post` 4:5, `square` 1:1. Çıktı genişliği 1080 px.
- Bilgiler: `days`, `stops`, `distance`, `travellers`, `spent`, `perPerson`; varsayılan açık: days, stops, distance, travellers. `spent` ve `perPerson` varsayılan kapalı.
- Metin sınırı: başlık ve alt yazı en çok 40 karakter.
- Kolaj: 2–9 fotoğraf; sütun sayısı `ShareCardConfig.collageColumns(count:format:)` (story 2, diğerleri 7+ fotoğrafta 3, aksi 2); satırlar fotoğraf sayısına göre.
- "Gezzy ile planlandı" (en "Planned with Gezzy"): ücretsizde açık ve kilitli (dokununca `PaywallSheet(reason: .branding)`, başlık "Kartlardan Gezzy işaretini kaldır"), Premium'da anahtar.
- Seyahat ekranında dolu düğmeler `.primary(tint)`; stüdyo tam ekran örtü olduğu için `.primary` (ink). Metinde palet rengi gerekiyorsa `tripText` ortam değeri (koyu modda okunur ton).
- Yeni metinler Türkçe, `en` elle `ios/Gezzy/Resources/Localizable.xcstrings`'e; derleme yüzlerce satır silerse dosyayı geri al, yalnız kendi anahtarlarını ekle.
- Kod yorumları Türkçe, kısa. Commit sonu: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Yalnızca değiştirdiğin dosyaları stage et.
- Simülatör: iPhone Air (28310D42-ED32-41D1-8841-CEFE37B7EBE9), Kopenhag test seyahati. Simülatöre dokunma; görsel doğrulamayı controller yapar.

---

### Task 1: MemoryHighlights ve ShareCardConfig (GezzyKit)

**Files:**
- Create: `ios/Packages/GezzyKit/Sources/GezzyKit/MemoryHighlights.swift`, `ios/Packages/GezzyKit/Sources/GezzyKit/ShareCardConfig.swift`
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/MemoryHighlightsTests.swift`, `ios/Packages/GezzyKit/Tests/GezzyKitTests/ShareCardConfigTests.swift`

**Interfaces — Produces:** `MemoryHighlights.Highlight { day: Date; photoID: String; stopName: String? }`, `MemoryHighlights.pick(moments:favorites:hidden:calendar:)`; `ShareCardConfig` (Codable: `template`, `format`, `photoIDs`, `paletteID: String?` (nil = seyahat paleti, "photo" = fotoğraftan, aksi `TripPalette.id`), `title: String?`, `subtitle: String?`, `stats: Set<Stat>`, `showsBrand: Bool`), `ShareCardConfig.Template`, `.Format` (`aspect: Double` = genişlik/yükseklik), `.Stat`, `ShareCardConfig.default(for:)`, `photoLimit(_:)`, `collageColumns(count:format:)`, `clampedText(_:)`.

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import GezzyKit

final class MemoryHighlightsTests: XCTestCase {
    let cal = TestCalendar.calendar

    func moment(_ ids: [String], day: Int, hour: Int, stop: String? = nil) -> PhotoClusterer.Moment {
        let start = TestCalendar.date(2026, 11, day).addingTimeInterval(Double(hour) * 3600)
        return PhotoClusterer.Moment(photoIDs: ids, start: start, end: start.addingTimeInterval(1800), center: nil, stopName: stop)
    }

    func testOnePerDayFromBiggestMomentMiddlePhoto() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1", "a2"], day: 19, hour: 10),
            moment(["b1", "b2", "b3"], day: 19, hour: 14, stop: "Nyhavn"),
            moment(["c1"], day: 20, hour: 9),
        ], favorites: [], hidden: [], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["b2", "c1"])
        XCTAssertEqual(picks[0].stopName, "Nyhavn")
        XCTAssertEqual(picks.map(\.day), [TestCalendar.date(2026, 11, 19), TestCalendar.date(2026, 11, 20)])
    }

    func testFavoriteWinsEarliestFirst() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1", "a2"], day: 19, hour: 10),
            moment(["b1", "b2", "b3"], day: 19, hour: 14),
        ], favorites: ["b3", "a2"], hidden: [], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["a2"])
    }

    func testHiddenNeverPickedAndEmptyDaySkipped() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1"], day: 19, hour: 10),
            moment(["b1", "b2", "b3"], day: 20, hour: 14),
        ], favorites: ["a1"], hidden: ["a1", "b2"], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["b3"])
    }

    func testTieBreaksOnStopNameThenEarlier() {
        let picks = MemoryHighlights.pick(moments: [
            moment(["a1", "a2"], day: 19, hour: 9),
            moment(["b1", "b2"], day: 19, hour: 12, stop: "Tivoli"),
        ], favorites: [], hidden: [], calendar: cal)
        XCTAssertEqual(picks.map(\.photoID), ["b2"])
    }
}

final class ShareCardConfigTests: XCTestCase {
    func testDefaultsKeepMoneyPrivate() {
        let c = ShareCardConfig.default(for: .stats)
        XCTAssertEqual(c.stats, [.days, .stops, .distance, .travellers])
        XCTAssertEqual(c.format, .story)
        XCTAssertTrue(c.showsBrand)
        XCTAssertNil(c.paletteID)
    }

    func testCodableRoundTrip() throws {
        var c = ShareCardConfig.default(for: .collage)
        c.photoIDs = ["x", "y"]; c.title = "Kopenhag"; c.stats.insert(.spent); c.format = .square
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(ShareCardConfig.self, from: data), c)
    }

    func testPhotoLimits() {
        XCTAssertEqual(ShareCardConfig.photoLimit(.postcard), 1...1)
        XCTAssertEqual(ShareCardConfig.photoLimit(.collage), 2...9)
        XCTAssertEqual(ShareCardConfig.photoLimit(.stats), 0...0)
        XCTAssertEqual(ShareCardConfig.photoLimit(.route), 0...0)
        XCTAssertEqual(ShareCardConfig.photoLimit(.ticket), 0...0)
    }

    func testAspects() {
        XCTAssertEqual(ShareCardConfig.Format.story.aspect, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(ShareCardConfig.Format.post.aspect, 4.0 / 5.0, accuracy: 0.0001)
        XCTAssertEqual(ShareCardConfig.Format.square.aspect, 1, accuracy: 0.0001)
    }

    func testCollageColumns() {
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 4, format: .square), 2)
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 6, format: .post), 2)
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 9, format: .square), 3)
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 9, format: .story), 2)
    }

    func testTextClamped() {
        XCTAssertEqual(ShareCardConfig.clampedText(String(repeating: "a", count: 50)).count, 40)
        XCTAssertEqual(ShareCardConfig.clampedText("  Kopenhag  "), "Kopenhag")
    }
}
```

- [ ] **Step 2: Run** → FAIL. `PhotoClusterer.Moment` memberwise init `@testable` ile erişilir; gerekirse `Moment`'a `public init(photoIDs:start:end:center:stopName:)` ekle.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Anılar'ın öne çıkanları: her günden bir fotoğraf. Favori varsa en erken favori, yoksa en kalabalık anın
/// ortadaki fotoğrafı. Gizlenenler hiç seçilmez.
public enum MemoryHighlights {
    public struct Highlight: Hashable, Sendable {
        public var day: Date
        public var photoID: String
        public var stopName: String?
    }

    public static func pick(moments: [PhotoClusterer.Moment], favorites: Set<String>, hidden: Set<String>,
                            calendar: Calendar = .current) -> [Highlight] {
        let byDay = Dictionary(grouping: moments) { calendar.startOfDay(for: $0.start) }
        return byDay.keys.sorted().compactMap { day in
            let dayMoments = byDay[day]!.sorted { $0.start < $1.start }
                .map { m -> PhotoClusterer.Moment in var m = m; m.photoIDs.removeAll(where: hidden.contains); return m }
                .filter { !$0.photoIDs.isEmpty }
            if let favorite = dayMoments.lazy.flatMap({ m in m.photoIDs.map { (m, $0) } }).first(where: { favorites.contains($0.1) }) {
                return Highlight(day: day, photoID: favorite.1, stopName: favorite.0.stopName)
            }
            guard let best = dayMoments.max(by: { a, b in
                if a.count != b.count { return a.count < b.count }
                if (a.stopName != nil) != (b.stopName != nil) { return a.stopName == nil }
                return a.start > b.start
            }) else { return nil }
            return Highlight(day: day, photoID: best.photoIDs[best.photoIDs.count / 2], stopName: best.stopName)
        }
    }
}
```

```swift
import Foundation

/// Paylaşım kartı ayarları; seyahat başına cihazda saklanır.
public struct ShareCardConfig: Codable, Hashable, Sendable {
    public enum Template: String, Codable, CaseIterable, Sendable { case postcard, stats, route, collage, ticket }
    public enum Format: String, Codable, CaseIterable, Sendable {
        case story, post, square
        /// Genişlik / yükseklik.
        public var aspect: Double {
            switch self {
            case .story: 9.0 / 16.0
            case .post: 4.0 / 5.0
            case .square: 1
            }
        }
    }
    public enum Stat: String, Codable, CaseIterable, Sendable { case days, stops, distance, travellers, spent, perPerson }

    public var template: Template
    public var format: Format
    public var photoIDs: [String]
    /// nil: seyahatin paleti; "photo": seçili fotoğraftan; diğer: `TripPalette.id`.
    public var paletteID: String?
    public var title: String?
    public var subtitle: String?
    public var stats: Set<Stat>
    public var showsBrand: Bool

    public static let maxTextLength = 40

    public static func `default`(for template: Template) -> ShareCardConfig {
        ShareCardConfig(template: template, format: .story, photoIDs: [], paletteID: nil, title: nil, subtitle: nil,
                        stats: [.days, .stops, .distance, .travellers], showsBrand: true)
    }

    public static func photoLimit(_ template: Template) -> ClosedRange<Int> {
        switch template {
        case .postcard: 1...1
        case .collage: 2...9
        case .stats, .route, .ticket: 0...0
        }
    }

    /// Kolaj sütun sayısı: story'de hep 2; diğerlerinde 7+ fotoğrafta 3.
    public static func collageColumns(count: Int, format: Format) -> Int {
        format == .story ? 2 : (count >= 7 ? 3 : 2)
    }

    public static func clampedText(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
    }
}
```

- [ ] **Step 4: Run** `swift test` → all PASS.
- [ ] **Step 5: Commit** `"Add memory highlights and share card config"`.

---

### Task 2: Favori, kapak, gizle

**Files:**
- Create: `ios/Gezzy/Store/MemoryPrefs.swift`
- Modify: `ios/Gezzy/Features/Memories/SharedAlbumViews.swift` (`PhotoViewer`), `Localizable.xcstrings`

**Interfaces — Produces:** `@MainActor @Observable final class MemoryPrefs { static let shared; func favorites(_ tripID: UUID) -> Set<String>; func hidden(_ tripID: UUID) -> Set<String>; func toggleFavorite(_ photoID: String, trip: UUID); func setHidden(_ photoID: String, _ hidden: Bool, trip: UUID) }` (UserDefaults `gezzy.memories.v1`, JSON `[tripID: {favorites: [String], hidden: [String]}]`). `PhotoViewer(items:index:tripID: UUID? = nil)` — `tripID` verilince alt çubukta favori/kapak/gizle.

- [ ] **Step 1: `MemoryPrefs`** — yukarıdaki API; her değişiklikte kaydet; okuma hatasında boş.
- [ ] **Step 2: `PhotoViewer` alt çubuğu** — yalnızca `tripID != nil` ve öğe `.library(id)` ise: alt kenarda yarı saydam kapsül içinde üç düğme: `heart` / `heart.fill` ("Favori"), `photo.badge.checkmark` ("Kapak yap"), `eye.slash` ("Gizle"). Kapak: `PhotoLibrary.shared.albumJPEG(for:)` ile veri → `store.setCoverPhoto(data, for: tripID)` (`@Environment(TripStore.self)`), başarıda kısa "Kapak yapıldı" yazısı (1,5 sn). Gizle: `setHidden(true)` ve görüntüleyiciyi kapat. `.album(_)` öğelerinde çubuk yok.
- [ ] **Step 3: Build, commit** `"Let travellers favourite, hide and set cover photos"`.

---

### Task 3: Anılar yeni düzen

**Files:**
- Create: `ios/Gezzy/Features/Memories/HighlightsStrip.swift`, `ios/Gezzy/Features/Memories/MemoryJournal.swift`
- Modify: `ios/Gezzy/Features/Memories/MemoriesSection.swift`, `Localizable.xcstrings`
- Delete: `ios/Gezzy/Features/Memories/TripSummaryCard.swift` (Task 4 `TripSummaryPoster` içeriğini `CardTemplates`'e taşıyacak; bu taskta dosyayı silme, yalnızca `MemoriesSection`'dan `TripSummaryCard` kullanımını kaldır), `MemoriesSection` içindeki kartpostal düğmesi ve `PostcardView` kullanımı (görünüm türü Task 5'te taşınır; bu taskta kullanımı kaldır)

**Interfaces — Consumes:** `MemoryHighlights.pick`, `MemoryPrefs`, `PhotoViewer(items:index:tripID:)`, `DayChips` (DesignSystem/TripTheme.swift), `MapFraming`, `NumberedPin(number:color:)`, `palette.pin(_:)`. **Produces:** `MemoriesSection` içinde `onOpenStudio: (ShareCardConfig.Template, [String]) -> Void` hook'u — Task 4 stüdyoyu bağlar; bu taskta `@State var studioRequest: StudioRequest?` (`struct StudioRequest: Identifiable { let id = UUID(); let template: ShareCardConfig.Template; let photoIDs: [String] }`) üret ve sheet'i Task 4'e bırak (geçici olarak `EmptyView` değil, hiçbir şey gösterme).

- [ ] **Step 1: Veri** — `MemoriesSection.load()` mevcut anları yükler; görünümde `visibleMoments` = anlardan `MemoryPrefs.hidden` fotoğrafları çıkarılmış, boşalan anlar düşmüş hali.
- [ ] **Step 2: `HighlightsStrip(trip:highlights:onOpen:onCreateCard:)`** — başlık satırı "Öne çıkanlar" + sağda "Kart oluştur" (palet metin rengi). Yatay `ScrollView`, 150×190 köşeli karolar (`PhotoThumb` ile küçük resim), altında "1. gün · Nyhavn" (durak yoksa "1. gün"). Dokununca görüntüleyici (o günün fotoğrafları değil, tüm öne çıkanlar dizisi). "Kart oluştur" → `onCreateCard(.collage, highlights.map(\.photoID).prefix(9))`.
- [ ] **Step 3: `MemoryJournal(trip:moments:onOpen:)`** — `DayChips` (seyahat günleri; `stopCount` yerine o günün fotoğraf sayısı), altında 220 pt yüksek `Map`: o günün konumlu anları 44 pt yuvarlak küçük resim pin (beyaz 2 pt kenar, sayı rozeti), planın durakları soluk `NumberedPin` (opacity 0.45) + rota `MapPolyline` (palet accent, opacity 0.5). Kamera `MapFraming` ile pinleri çerçeveler; gün değişince yeniden. Altında o günün anları (mevcut `momentRow` görünümünü bu dosyaya taşı). Pine dokununca `ScrollViewReader` ile satıra kay ve 1 sn vurgula; satıra dokununca kamera o ana gider. O gün foto yoksa "Bu günde fotoğraf yok." Günlüğün sonunda gizli fotoğraf varsa "N gizli fotoğraf · Göster" → o seyahatin gizlilerini temizler (`setHidden(false)` hepsi için, onay sorma).
- [ ] **Step 4: Paylaş kartı** — tray içinde satır: `square.and.arrow.up` + "Seyahatini paylaş" + alt yazı "5 şablon · story, gönderi, kare" + chevron; dokununca `studioRequest = .init(template: lastTemplate ?? .postcard, photoIDs: [])`.
- [ ] **Step 5: Düzen** — `ModuleCard("Anılar")` içinde sırayla: (izin varsa ve an varsa) öne çıkanlar, günlük; Paylaş kartı; ortak albüm; topluluk kartı. İzin yoksa bugünkü izin istemi + Paylaş kartı + albüm + topluluk.
- [ ] **Step 6: Build, commit** `"Rework the memories tab with highlights and a map journal"`.

---

### Task 4: Paylaşım stüdyosu iskeleti ve kontroller

**Files:**
- Create: `ios/Gezzy/Features/Memories/Studio/ShareStudioView.swift`, `ios/Gezzy/Features/Memories/Studio/StudioControls.swift`, `ios/Gezzy/Features/Memories/Studio/GezzyMark.swift`, `ios/Gezzy/Store/ShareStudioStore.swift`
- Modify: `ios/Gezzy/Features/Memories/MemoriesSection.swift` (stüdyoyu bağla), `ios/Gezzy/Features/Premium/PaywallSheet.swift` (`Reason.branding`), `Localizable.xcstrings`

**Interfaces — Produces:** `ShareStudioView(trip: Trip, request: StudioRequest)`; `ShareStudioStore.shared.config(for: UUID, template:) -> ShareCardConfig`, `save(_:for:)`, `lastTemplate(for:)` (`gezzy.shareStudio.v1`, seyahat başına şablon → config ve son şablon); `GezzyMark(onDark: Bool)`; `protocol CardContent: View` yok — şablon görünümleri Task 5'te `CardTemplateView(trip:summary:config:photos:mapImage:palette:)` olarak gelir; bu taskta önizleme yerine yer tutucu `RoundedRectangle` + şablon adı göster.

- [ ] **Step 1: `ShareStudioStore`** — yukarıdaki API; Codable JSON.
- [ ] **Step 2: `ShareStudioView`** — `NavigationStack`, başlık "Paylaş", solda "Kapat". Üstte önizleme alanı: kart `aspectRatio(config.format.aspect)` ile ekrana sığar, gölgeli. Altında `ScrollView`:
  1. Şablon şeridi: 5 kapsül (ikon + ad: Kartpostal `envelope`, İstatistik `chart.bar`, Rota `map`, Kolaj `square.grid.2x2`, Bilet `ticket`); seçili `Color.ink` dolgu.
  2. Biçim: `PillPicker` "Story" / "Gönderi" / "Kare".
  3. `StudioControls(config: $config, trip:, highlights:, moments:, isPremium:)` bölümleri:
     - Fotoğraf (yalnızca `photoLimit` üst sınırı > 0): 4 sütun ızgara; sıra favoriler, öne çıkanlar, diğer anlar (gizliler hariç). Dokununca seç/bırak; sınır dolunca en eski seçim düşer (kartpostalda tek seçim). Seçili olanlarda sıra numarası rozeti. Fotoğraf izni yoksa "Fotoğraf seçmek için Anılar'dan erişim ver."
     - Renk: yatay daireler: "Seyahat" (seyahat paleti), "Fotoğraf" (yalnızca seçili fotoğraf varken; `CoverImageStore`'daki ortalama renk hesabının fotoğraf verisi için olanını kullan — gerekirse `CoverImageStore`'a `averageHex(of image: UIImage)` ekle), sonra `TripPalette.all`.
     - Metin: iki `TextField` (başlık, alt yazı), placeholder varsayılanlar (seyahat adı; "Şehir · tarih aralığı"), `ShareCardConfig.clampedText` ile 40 karakter.
     - Bilgiler (yalnızca stats/postcard/ticket): 6 `Toggle` ("Gün", "Durak", "Km", "Kişi", "Harcama", "Kişi başı").
     - Gezzy işareti: `Toggle("Gezzy ile planlandı")`; premium değilse kapatma denemesinde değer geri açılır ve `PaywallSheet(reason: .branding)` açılır; yanında kilit ikonu.
  4. Alt sabit çubuk: "Kaydet" (ikincil) ve "Paylaş" (`.primary`) — bu taskta pasif; Task 5 bağlar.
  Config her değişiklikte `ShareStudioStore.save`. `request.photoIDs` boş değilse açılışta config'e yazılır.
- [ ] **Step 3: `GezzyMark`** — `Image("AppIcon")` uygulamada okunamıyorsa küçük `airplane` sembollü yuvarlak rozet + "Gezzy ile planlandı" (`.caption2` semibold), `onDark`'a göre beyaz/ink, %70 opaklık.
- [ ] **Step 4: Paywall** — `Reason.branding` başlık "Kartlardan Gezzy işaretini kaldır".
- [ ] **Step 5: Bağla** — `MemoriesSection`'da `.fullScreenCover(item: $studioRequest) { ShareStudioView(trip:, request:) }` (+ `tripPalette`/`tripTint`/`tripText` ortam değerlerini ilet, `Entitlements` ortamı zaten global).
- [ ] **Step 6: Build, commit** `"Add the share studio with templates, formats and controls"`.

---

### Task 5: Şablonlar ve görsel üretimi

**Files:**
- Create: `ios/Gezzy/Features/Memories/Studio/CardTemplates.swift`, `ios/Gezzy/Features/Memories/Studio/CardRenderer.swift`
- Modify: `ShareStudioView.swift` (önizleme + Kaydet/Paylaş), `Localizable.xcstrings`, `ios/Gezzy/Support/Info.plist` ya da `project.yml` info (`NSPhotoLibraryAddUsageDescription` yoksa ekle: "Paylaşım kartını Fotoğraflar'a kaydetmek için.")
- Delete: `ios/Gezzy/Features/Memories/TripSummaryCard.swift`; `MemoriesSection.swift` içindeki `PostcardView` (içerikleri şablonlara taşınır)

**Interfaces — Produces:** `CardTemplateView(trip: Trip, summary: TripSummary, config: ShareCardConfig, photos: [UIImage], mapImage: UIImage?, palette: TripPalette)` (genişlik dışarıdan; yükseklik `width / aspect`); `CardRenderer.render(trip:config:palette:width: CGFloat = 1080) async -> UIImage?` (fotoğrafları `PhotoLibrary.fullImage(for:maxPixelSize: 1600)` ile, rota haritasını `MKMapSnapshotter` ile yükler, `ImageRenderer` `scale = 1`, `proposedSize` = 1080 × 1080/aspect); `CardRenderer.mapSnapshot(trip:palette:size:) async -> UIImage?`.

- [ ] **Step 1: Ortak** — kart içinde tüm boyutlar genişliğe oranlı (`let u = width / 360`; yazı boyutları `u` ile çarpılır) ki önizleme ve 1080 px çıktı aynı görünsün. Başlık `config.title ?? trip.name`, alt yazı `config.subtitle ?? "\(trip.cityTitle) · \(AppFormat.dateRange(...))"`. Bilgi değerleri `TripSummary`'den (mevcut `TripSummaryPoster`'daki biçimlemeler). `config.showsBrand` → altta `GezzyMark`.
- [ ] **Step 2: Şablonlar** (spec tablosu):
  - **Kartpostal:** tam kaplayan fotoğraf (`scaledToFill`, kırpılır), alttan karartma gradyanı, sol altta başlık/alt yazı (beyaz), sağ altta pul: tırtıklı kenarlı beyaz kare (kenarı küçük yarım dairelerle `Shape`), içinde bayrak emojisi, şehir, tarih; pulun üstüne hafif döndürülmüş `StampImprint` (opacity 0.35). Fotoğraf yoksa palet gradyanı.
  - **İstatistik:** palet `accent` → `bands[0]` gradyanı; başlık büyük; seçili bilgiler `Grid` (story/post 2 sütun, kare 3 sütun) büyük rakam + küçük etiket; "Öne çıkanlar: …" (`summary.highlights`).
  - **Rota:** üst %70 `mapImage` (yoksa palet zemini + "Rota için konumlu durak gerekli"), alt bant palet `softLight` zeminde başlık, alt yazı ve gün renk lejantı (gün başına küçük daire + "1. gün"…).
  - **Kolaj:** `LazyVGrid` `collageColumns` sütun, 4·u aralık, kare hücreler (story'de hücre oranı yükseklikten hesaplanır ki alan dolsun); altta başlık ve tarih bandı.
  - **Bilet:** `TicketShape` içinde: üstte havayolu yerine "GEZZY" ve başlık; ortada kalkış/varış kodları (birincil uçuş varsa `fromCode`/`toCode` + şehirler, yoksa ilk ve son şehir adı) ve `FlightArc`; altta tarih, gece, kişi, koltuk (varsa) alanları; delikli ayraç; koçanda `GezzyMark` (QR yok).
- [ ] **Step 3: Harita görüntüsü** — `MKMapSnapshotter` (`region` = tüm konumlu durakları kapsayan, %20 pay), görüntü üzerine `UIGraphicsImageRenderer` ile her gün için palet `pin(dayIndex)` renginde 4·u kalın çizgi ve numaralı daireler çiz (snapshot `point(for:)` ile). Sonuç önbelleğe alınır (seyahat id + palet id + boyut).
- [ ] **Step 4: Önizleme ve eylemler** — önizleme `CardTemplateView`'i küçük boyutta canlı gösterir (fotoğraflar `thumbnail(for:side: 600)`). "Paylaş": `CardRenderer.render` → `ShareLink` yerine `UIActivityViewController` (sheet) ile `UIImage`; "Kaydet": `PHPhotoLibrary.requestAuthorization(for: .addOnly)` → `PHAssetChangeRequest.creationRequestForAsset(from:)`; başarıda "Fotoğraflar'a kaydedildi". Üretim sırasında düğmede `ProgressView`.
- [ ] **Step 5: Temizlik** — `TripSummaryCard.swift` ve `PostcardView` silinir; başka kullanım kalmadığını `grep` ile doğrula; `xcodegen generate`.
- [ ] **Step 6: Build, commit** `"Render five share card templates in three formats"`.
