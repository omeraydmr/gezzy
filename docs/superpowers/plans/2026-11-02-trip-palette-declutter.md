# Seyahat paleti ve sadeleştirme Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Her seyahate kendi renk paletini vermek (kapak, vurgu, pinler, birincil düğmeler) ve seyahat ekranındaki tekrar eden/ağır öğeleri sadeleştirmek.

**Architecture:** Palet verisi ve fotoğraftan türetme GezzyKit'te saf `TripPalette` olarak durur (hex `UInt32`, XCTest). Uygulama `Trip.palette` ile paleti seçer, `tripPalette` ortam değeriyle alt ekranlara iner; mevcut `tripTint` palet vurgusuna eşitlenir. Sadeleştirme Plan sekmesi, Fikirler kartı ve diğer sekmelerde kurallarla yapılır.

**Tech Stack:** Swift 6, SwiftUI (iOS 17), MapKit, GezzyKit SwiftPM paketi, XCTest.

**Spec:** `docs/superpowers/specs/2026-11-02-trip-palette-declutter-design.md`

## Global Constraints

- Build: `cd ios && xcodebuild -project Gezzy.xcodeproj -scheme Gezzy -destination 'platform=iOS Simulator,name=iPhone Air' build` (`-quiet` kullanma; sahte hata satırı basıyor). Yeni dosya eklendiyse önce `cd ios && xcodegen generate`.
- Test: `cd ios/Packages/GezzyKit && swift test`.
- Bütçe kategori renkleri (`SpendCategory.accent`, `Color.stays/transport/food/activities`) ve kişi renkleri (`Accent.cycle(member.colorIndex)`) DEĞİŞMEZ.
- Seyahatler listesindeki "Seyahat planla" ve Onboarding düğmeleri siyah (`.ink`) kalır; yalnızca seyahat ekranı (`TripDetailView` altı) palet rengini kullanır.
- Yeni kullanıcı metinleri Türkçe; `ios/Gezzy/Resources/Localizable.xcstrings` içine `en` karşılığı elle eklenir. Derleme xcstrings'ten yüzlerce satır silerse o değişikliği geri al (`git checkout -- ios/Gezzy/Resources/Localizable.xcstrings`) ve yalnızca kendi anahtarlarını ekle.
- Kod yorumları Türkçe, kısa (mevcut dosyalardaki gibi).
- Commit mesajı sonu: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
- Simülatör: iPhone Air (UDID 28310D42-ED32-41D1-8841-CEFE37B7EBE9). Kopenhag test seyahati yüklü. Simülatörde başka bir uygulama öndeyse kullanıcının işi olabilir: Gezzy'yi `simctl launch` ile öne getirmeden önce raporda belirt, başka uygulamayı kapatma.

---

### Task 1: TripPalette (GezzyKit)

**Files:**
- Create: `ios/Packages/GezzyKit/Sources/GezzyKit/TripPalette.swift`
- Test: `ios/Packages/GezzyKit/Tests/GezzyKitTests/TripPaletteTests.swift`

**Interfaces:**
- Produces: `TripPalette` (`id`, `bands`, `accent`, `pins`, `softLight`, `softDark`), `TripPalette.all`, `TripPalette.forSeed(_:)`, `TripPalette.derived(from:fallbackSeed:)`, `TripPalette.contrastWithWhite(_:)`, `TripPalette.luminance(_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import GezzyKit

final class TripPaletteTests: XCTestCase {
    func testTwelvePalettesWithUniqueIDs() {
        XCTAssertEqual(TripPalette.all.count, 12)
        XCTAssertEqual(Set(TripPalette.all.map(\.id)).count, 12)
    }

    func testStructure() {
        for palette in TripPalette.all {
            XCTAssertEqual(palette.bands.count, 5, palette.id)
            XCTAssertEqual(palette.pins.count, 4, palette.id)
            XCTAssertEqual(palette.pins[0], palette.accent, palette.id)
        }
    }

    func testWhiteTextContrastOnPins() {
        for palette in TripPalette.all {
            for pin in palette.pins {
                XCTAssertGreaterThanOrEqual(TripPalette.contrastWithWhite(pin), 3, "\(palette.id) \(String(pin, radix: 16))")
            }
        }
    }

    func testPinsAreDistinguishable() {
        for palette in TripPalette.all {
            assertDistinct(palette.pins, palette.id)
        }
    }

    func testSoftTones() {
        for palette in TripPalette.all {
            XCTAssertGreaterThanOrEqual(TripPalette.luminance(palette.softLight), 0.8, palette.id)
            XCTAssertLessThanOrEqual(TripPalette.luminance(palette.softDark), 0.08, palette.id)
        }
    }

    func testForSeedWrapsAndHandlesNegative() {
        XCTAssertEqual(TripPalette.forSeed(0), TripPalette.all[0])
        XCTAssertEqual(TripPalette.forSeed(13), TripPalette.all[1])
        XCTAssertEqual(TripPalette.forSeed(-1), TripPalette.all[11])
        XCTAssertTrue(TripPalette.all.contains(TripPalette.forSeed(Int.min)))
    }

    func testDerivedKeepsContrastForVariousHues() {
        for hex: UInt32 in [0xD03A2F, 0x2F6FD0, 0xF2D33A, 0x3AD07A, 0x8A2FD0, 0xFFFFE0] {
            let palette = TripPalette.derived(from: hex, fallbackSeed: 0)
            XCTAssertEqual(palette.pins.count, 4)
            XCTAssertEqual(palette.bands.count, 5)
            XCTAssertEqual(palette.pins[0], palette.accent)
            for pin in palette.pins {
                XCTAssertGreaterThanOrEqual(TripPalette.contrastWithWhite(pin), 3, String(hex, radix: 16))
            }
            assertDistinct(palette.pins, String(hex, radix: 16))
            XCTAssertGreaterThanOrEqual(TripPalette.luminance(palette.softLight), 0.8)
            XCTAssertLessThanOrEqual(TripPalette.luminance(palette.softDark), 0.08)
        }
    }

    func testDerivedKeepsHueOfPhoto() {
        let palette = TripPalette.derived(from: 0x2F6FD0, fallbackSeed: 0)
        let (h, _, _) = TripPalette.hsb(palette.accent)
        XCTAssertEqual(h * 360, TripPalette.hsb(0x2F6FD0).h * 360, accuracy: 3)
    }

    func testDerivedFallsBackForGray() {
        XCTAssertEqual(TripPalette.derived(from: 0x808080, fallbackSeed: 5), TripPalette.forSeed(5))
        XCTAssertEqual(TripPalette.derived(from: 0x7A7D80, fallbackSeed: 2), TripPalette.forSeed(2))
    }

    private func assertDistinct(_ colors: [UInt32], _ label: String) {
        for i in colors.indices {
            for j in colors.indices where j > i {
                let a = TripPalette.hsb(colors[i]), b = TripPalette.hsb(colors[j])
                var hueGap = abs(a.h - b.h) * 360
                hueGap = min(hueGap, 360 - hueGap)
                XCTAssertTrue(hueGap >= 25 || abs(a.b - b.b) >= 0.15, "\(label): \(i) ~ \(j)")
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ios/Packages/GezzyKit && swift test --filter TripPaletteTests`
Expected: FAIL — `cannot find 'TripPalette' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Seyahatin renk paleti: kapak bantları, vurgu, durak pinleri ve yumuşak zemin tonları.
/// Renkler 0xRRGGBB; UI katmanı `Color(hex:)` ile çevirir.
public struct TripPalette: Hashable, Sendable {
    public let id: String
    /// Kapak bantları, yukarıdan aşağı 5 renk.
    public let bands: [UInt32]
    /// Ana vurgu: birincil düğme, seçili çip, arka plan ışığı.
    public let accent: UInt32
    /// Durak pinleri; `pins[0] == accent`. Hepsi beyaz metinle en az 3:1 kontrast.
    public let pins: [UInt32]
    /// Açık temada vurgu zemini.
    public let softLight: UInt32
    /// Koyu temada vurgu zemini.
    public let softDark: UInt32

    public init(id: String, bands: [UInt32], pins: [UInt32], softLight: UInt32, softDark: UInt32) {
        self.id = id
        self.bands = bands
        self.accent = pins[0]
        self.pins = pins
        self.softLight = softLight
        self.softDark = softDark
    }

    public static let all: [TripPalette] = [
        .init(id: "fjord", bands: [0x9DB7E8, 0xBFD3EE, 0x6E9F7E, 0xC8B6E8, 0x3F5FA8],
              pins: [0x3F62B8, 0x2F7D6B, 0x8A55B8, 0xC0573E], softLight: 0xE8EEFA, softDark: 0x1A2238),
        .init(id: "terracotta", bands: [0xF2B9A6, 0xE58C6B, 0xD9644C, 0xA7B98A, 0x7A9A6B],
              pins: [0xB8502F, 0x4F7A45, 0x2F6A9A, 0x9A4A7A], softLight: 0xFBECE6, softDark: 0x34201A),
        .init(id: "olive", bands: [0xD9DDB0, 0xB9C48A, 0x8FA35E, 0xE8CFA0, 0x6B7A45],
              pins: [0x5F7330, 0xA85A2A, 0x3A6A8A, 0x8A4A6A], softLight: 0xF0F2E2, softDark: 0x24281A),
        .init(id: "lavender", bands: [0xE9D9F7, 0xC8B6E8, 0xA48FD6, 0xF4D7E3, 0x6E5AAE],
              pins: [0x6E55B8, 0xB8467A, 0x2F7A8A, 0x7A6A2A], softLight: 0xF1ECFA, softDark: 0x261F36),
        .init(id: "coral", bands: [0xFAD4C8, 0xF5A893, 0xE8735A, 0xF6E1A8, 0x4FA3A0],
              pins: [0xC4472F, 0x1F7A78, 0x5A55B0, 0x8A6A1F], softLight: 0xFDEDE8, softDark: 0x381E1A),
        .init(id: "ocean", bands: [0xB8E0EE, 0x7CC3DE, 0x3E8FC0, 0xE6F2C8, 0x1F5A8A],
              pins: [0x1F6A9E, 0x2A7F5F, 0xB0503A, 0x6A4AA8], softLight: 0xE6F3FA, softDark: 0x172632),
        .init(id: "saffron", bands: [0xF4D04E, 0xF0B54A, 0xE3A23B, 0xB6CDEB, 0x8FB3E8],
              pins: [0x9A6A0A, 0x2F5FA8, 0xA8443A, 0x3F7A4A], softLight: 0xFBF3DD, softDark: 0x2E2614),
        .init(id: "forest", bands: [0xC8DDB8, 0x9AB89A, 0x5F8F6A, 0xE6D6B0, 0x2F5F45],
              pins: [0x2F6F4A, 0x8A5A2A, 0x3F5A9A, 0xA0405A], softLight: 0xE8F2EA, softDark: 0x18281E),
        .init(id: "plum", bands: [0xEAC8D8, 0xD49AB8, 0xA8628A, 0xF0DCC0, 0x5A3A6A],
              pins: [0x8A3A6E, 0x2F6F7A, 0xA8602A, 0x4A55A8], softLight: 0xF6E8EF, softDark: 0x2C1A26),
        .init(id: "sand", bands: [0xF5E6CC, 0xE6CDA0, 0xC9A27A, 0xB9CFA8, 0x8A6A4A],
              pins: [0x8A5F35, 0x3F6A7A, 0x7A4A8A, 0x4F7A3A], softLight: 0xF7F0E4, softDark: 0x2A2219),
        .init(id: "glacier", bands: [0xDDEFF2, 0xB0DCE3, 0x7FBFCC, 0xD8E0F0, 0x4A7F9A],
              pins: [0x2A6F85, 0x5A4FA8, 0xA8503A, 0x3A7A4F], softLight: 0xE8F5F7, softDark: 0x16272C),
        .init(id: "midnight", bands: [0x2B3A67, 0x4A5A8A, 0x8A7FB8, 0xE8B88A, 0x1A2140],
              pins: [0x3A4A9A, 0xB0603A, 0x2F7A70, 0x8A3F7A], softLight: 0xE9EBF6, softDark: 0x161A2E),
    ]

    public static func forSeed(_ seed: Int) -> TripPalette {
        let count = all.count
        // Int.min'in mutlak değeri taşar; kalanı önce alıp sonra pozitife çevir.
        return all[((seed % count) + count) % count]
    }

    /// Kapak fotoğrafının ortalama renginden palet. Gri fotoğrafta seed paletine düşer.
    public static func derived(from hex: UInt32, fallbackSeed: Int) -> TripPalette {
        let (h, s, _) = hsb(hex)
        guard s >= 0.08 else { return forSeed(fallbackSeed) }
        let saturation = min(0.75, max(0.45, s))
        let pins = [0.0, 40.0, 160.0, 220.0].map { offset in
            readable(hue: (h + offset / 360).truncatingRemainder(dividingBy: 1), saturation: saturation)
        }
        let bands = [0.2, 0.35, 0.5, 0.25, 0.65].map { sat in
            rgb(h: h, s: sat * saturation / 0.75, b: 0.92 - sat * 0.3)
        }
        return TripPalette(id: "photo", bands: bands, pins: pins,
                           softLight: rgb(h: h, s: 0.08, b: 0.99), softDark: rgb(h: h, s: 0.35, b: 0.16))
    }

    /// Beyaz metnin okunacağı en parlak ton: 0,62'den başlayıp 3:1 sağlanana kadar koyulaşır.
    private static func readable(hue: Double, saturation: Double) -> UInt32 {
        var brightness = 0.62
        var color = rgb(h: hue, s: saturation, b: brightness)
        while contrastWithWhite(color) < 3, brightness > 0.2 {
            brightness -= 0.05
            color = rgb(h: hue, s: saturation, b: brightness)
        }
        return color
    }

    // MARK: Renk matematiği

    /// WCAG göreli parlaklık.
    public static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    public static func contrastWithWhite(_ hex: UInt32) -> Double {
        1.05 / (luminance(hex) + 0.05)
    }

    /// Ton, doygunluk, parlaklık; hepsi 0…1.
    public static func hsb(_ hex: UInt32) -> (h: Double, s: Double, b: Double) {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    static func rgb(h: Double, s: Double, b: Double) -> UInt32 {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        let (r, g, bl): (Double, Double, Double) = switch i {
        case 0: (b, t, p)
        case 1: (q, b, p)
        case 2: (p, b, t)
        case 3: (p, q, b)
        case 4: (t, p, b)
        default: (b, p, q)
        }
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(r) << 16 | byte(g) << 8 | byte(bl)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd ios/Packages/GezzyKit && swift test`
Expected: tüm testler PASS (mevcut 237 + yeni 9). `testDerivedKeepsContrastForVariousHues` sarı girişte düşerse `readable` döngüsünün sınırını değil, ayırt edilebilirlik kuralını kontrol et: 160° ve 220° kaymaları en az 60° ton farkı verir; ton aynıysa sorun `rgb` dönüşümündedir.

- [ ] **Step 5: Commit**

```bash
git add ios/Packages/GezzyKit/Sources/GezzyKit/TripPalette.swift ios/Packages/GezzyKit/Tests/GezzyKitTests/TripPaletteTests.swift
git commit -m "Add TripPalette with twelve curated palettes and photo-derived palettes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Paleti uygulamaya bağla

**Files:**
- Modify: `ios/Gezzy/DesignSystem/Theme.swift` (Color yardımcıları)
- Modify: `ios/Gezzy/DesignSystem/TripTheme.swift` (`tripPalette` ortam değeri, `DayChips` seçili zemin)
- Modify: `ios/Gezzy/DesignSystem/Components.swift` (`CoverArt`, `NumberedPin`, `PrimaryButtonStyle`, `Tag`)
- Modify: `ios/Gezzy/Store/CoverImageStore.swift` (`averageHex(named:)`)
- Modify: `ios/Gezzy/Features/Trips/TripCover.swift` (`Trip.palette`, `Trip.tint`, `CoverArt` çağrısı)
- Modify: `ios/Gezzy/Features/TripDetail/TripDetailView.swift` (ortam değeri, `TripStub` kilit ekranı düğmesi)
- Modify: `ios/Gezzy/Features/Plan/PlanSection.swift` (pinler, şehir renkleri, "Durak ekle")
- Modify: `ios/Gezzy/Features/Plan/PlacePicker/PlacePickerMap.swift`, `PlacePickerList.swift` (pinler)
- Modify: `ios/Gezzy/Store/DeviceServices.swift` (çevrimdışı harita pinleri)
- Modify: `ios/Gezzy/Features/Trips/TripEditSheet.swift`, `NewTripSheet.swift`, `ios/Gezzy/Features/Memories/MemoriesSection.swift`
- Modify: seyahat ekranındaki diğer `.buttonStyle(.primary)` kullanımları: `Money/MoneySection.swift:165`, `Packing/PackingSection.swift:88`, `Crew/CrewSection.swift:318`, `Memories/MemoriesSection.swift:71,184,195`

**Interfaces:**
- Consumes: `TripPalette` (Task 1).
- Produces:
  - `extension EnvironmentValues { var tripPalette: TripPalette }` (varsayılan `TripPalette.all[0]`).
  - `extension Color { static func soft(_ palette: TripPalette) -> Color }` = `Color(light: palette.softLight, dark: palette.softDark)`.
  - `extension TripPalette { func pin(_ index: Int) -> Color }` = `Color(hex: pins[((index % 4) + 4) % 4])`.
  - `@MainActor extension Trip { var palette: TripPalette }`; `Trip.tint` = `Color(hex: palette.accent)`.
  - `CoverArt(palette: TripPalette)` (`seed:` init kalkar).
  - `NumberedPin(number: Int, color: Color, size: CGFloat = 30)` (`accent:` kalkar).
  - `PrimaryButtonStyle(fill: Color = .ink)`; `static func primary(_ fill: Color) -> PrimaryButtonStyle`.
  - `Tag(text:color:soft:)` init'i (mevcut `Tag(text:accent:)` kalır).
  - `CoverImageStore.averageHex(named:) -> UInt32?` (doygunlaştırılmamış ortalama, önbellekli).

- [ ] **Step 1: Yardımcılar**

`Theme.swift` sonuna:

```swift
extension Color {
    /// Paletin yumuşak zemini; açık/koyu temaya göre.
    static func soft(_ palette: TripPalette) -> Color {
        Color(light: palette.softLight, dark: palette.softDark)
    }
}

extension TripPalette {
    /// Sıradaki durak pini rengi.
    func pin(_ index: Int) -> Color {
        Color(hex: pins[((index % pins.count) + pins.count) % pins.count])
    }
}
```

`TripTheme.swift`'te `TripTintKey`'in yanına:

```swift
private struct TripPaletteKey: EnvironmentKey {
    static let defaultValue: TripPalette = TripPalette.all[0]
}

extension EnvironmentValues {
    var tripPalette: TripPalette {
        get { self[TripPaletteKey.self] }
        set { self[TripPaletteKey.self] = newValue }
    }
}
```

- [ ] **Step 2: Fotoğraf ortalaması ve `Trip.palette`**

`CoverImageStore`'a `dominantColor`'un yanına (aynı CIAreaAverage kodunu tek yardımcıya çıkar, iki fonksiyon onu kullansın):

```swift
    @ObservationIgnored private var averages: [String: UInt32] = [:]

    /// Fotoğrafın doygunlaştırılmamış ortalama rengi (0xRRGGBB); palet türetmek için.
    func averageHex(named name: String) -> UInt32? {
        if let cached = averages[name] { return cached }
        guard let average = averageColor(named: name) else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        average.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        let hex = byte(r) << 16 | byte(g) << 8 | byte(b)
        averages[name] = hex
        return hex
    }
```

`averageColor(named:) -> UIColor?` mevcut `dominantColor` gövdesinin `average`'a kadar olan kısmıdır; `dominantColor` onu çağırıp doygunlaştırmaya devam eder. `remove` fonksiyonunda `colors[name] = nil`'in yanına `averages[name] = nil` ekle. Sınıf `@Observable` değilse `@ObservationIgnored` yazma — dosyadaki `colors` sözlüğünün nasıl tanımlandığına uy.

`TripCover.swift`'te `Trip.tint`'i değiştir:

```swift
extension Trip {
    /// Seyahatin paleti: kapak fotoğrafı varsa ondan türetilir, yoksa seed'e göre el seçimi palet.
    @MainActor
    var palette: TripPalette {
        if let name = coverPhoto, let hex = CoverImageStore.shared.averageHex(named: name) {
            return TripPalette.derived(from: hex, fallbackSeed: coverSeed)
        }
        return TripPalette.forSeed(coverSeed)
    }

    /// Kartların dinamik vurgu rengi.
    @MainActor
    var tint: Color { Color(hex: palette.accent) }
```

`dominantColor` başka yerde kullanılmıyorsa (`grep -rn dominantColor ios/Gezzy`) kaldır; `CoverImageStore.swift:67`'deki ön ısıtma çağrısını `averageHex` yap.

- [ ] **Step 3: Bileşenler**

`Components.swift`:
- `CoverArt`: `let seed: Int` → `let palette: TripPalette`; `palettes` statik dizisi silinir; `let colors = palette.bands` ile aynı çizim. Çağrılar: `TripCover.swift:28` → `CoverArt(palette: trip.palette)`, `MemoriesSection.swift:283` → `CoverArt(palette: trip.palette)`.
- `NumberedPin`: `let accent: Accent` → `let color: Color`; `.fill(accent.base)` → `.fill(color)`.
- `PrimaryButtonStyle`:

```swift
struct PrimaryButtonStyle: ButtonStyle {
    var fill: Color = .ink
    var label: Color = .onInk

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .medium))
            .foregroundStyle(label)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .cardBackground(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
    /// Seyahat ekranı: palet rengi zemin, beyaz metin.
    static func primary(_ fill: Color) -> PrimaryButtonStyle { PrimaryButtonStyle(fill: fill, label: .white) }
}
```

- `Tag`:

```swift
struct Tag: View {
    let text: String
    let foreground: Color
    let background: Color

    init(text: String, accent: Accent = .gray) {
        self.text = text
        self.foreground = accent.base
        self.background = accent.tint
    }

    init(text: String, color: Color, soft: Color) {
        self.text = text
        self.foreground = color
        self.background = soft
    }

    var body: some View {
        Text(text)
            .font(.system(.subheadline, weight: .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(background, in: Capsule())
    }
}
```


- [ ] **Step 4: Seyahat ekranına ver**

`TripDetailView.body`: `let tint = trip.tint` yanına `let palette = trip.palette`; `.environment(\.tripTint, tint)` altına `.environment(\.tripPalette, palette)`. `TripStub`'daki "Kilit ekranında göster" düğmesi çalışmıyorken `Color.ink` zemini → `tint`, metin `.white`.

Seyahat ekranındaki birincil düğmeler `.buttonStyle(.primary)` → `.buttonStyle(.primary(tint))` (her dosyada `@Environment(\.tripTint) private var tint` zaten var; yoksa ekle): `PlanSection.swift:134`, `MoneySection.swift:165`, `PackingSection.swift:88`, `CrewSection.swift:318`, `MemoriesSection.swift:71,184,195`. Sheet içindeki (`ExpenseSheets`, `InviteQRSheet`, `SharedAlbumViews`, `TripSummaryCard`, `EmergencyViews`) düğmelere dokunma: sheet'ler ortamı ayrı alır, siyah kalırlar.

`DayChips.chip`: seçili zemin `Color.ink` → `tint`; seçili gün adı `Color.onInk.opacity(0.7)` → `.white.opacity(0.75)`, gün numarası `Color.onInk` → `.white`, seçili nokta `tint` → `.white`.

- [ ] **Step 5: Pinler ve şehir renkleri**

- `PlanSection.swift:367` → `NumberedPin(number: item.number, color: palette.pin(item.number - 1), size: 28)`.
- `PlanSection.swift:113` şehir rengi → `palette.pin(index + 1)`.
- `StopRow` (`PlanSection.swift:544`): `@Environment(\.tripPalette) private var palette`; `NumberedPin(number: number, color: palette.pin(number - 1))`; saat etiketi `Tag(text: …, color: palette.pin(number - 1), soft: .soft(palette))`. (Sağdaki tür kutusu Task 3'te kalkar; bu adımda rengini `palette.pin(number - 1)` ve `.soft(palette)` yap ki derleme geçsin.)
- `PlacePickerMap.swift:86` → `NumberedPin(number: number, color: palette.pin(number - 1), size: 30)`; `PlacePickerList.swift:195` → `palette.pin(number - 1)`. PlacePicker `fullScreenCover` içinde açıldığı için ortam değeri inmeyebilir: `PlanSection` ve `IdeasCard`'daki `.fullScreenCover { PlacePickerSheet(...) }` çağrılarına `.environment(\.tripPalette, palette).environment(\.tripTint, tint)` ekle.
- `DeviceServices.swift:244` çevrimdışı harita: `OfflineMapStore.render(stops:)` → `render(stops:palette:)`; `save(_ trip:)` içinde `trip.palette` geçir (`save` `@MainActor`, `Trip.palette` da). `UIColor(Accent.cycle(index).base)` → `UIColor(palette.pin(index))`.

- [ ] **Step 6: Yeni seyahat ve düzenle**

- `NewTripSheet.swift:106` → `TintGlow(tint: Color(hex: TripPalette.forSeed(coverSeed).accent), offsetY: -200)`.
- `TripEditSheet.swift:92-97`: düğme davranışı aynı (`(coverSeed + 1) % 100` → 12'ye bölünmeyen 100 yüzünden 99→0 geçişinde aynı palet gelebilir; bunu `coverSeed = (coverSeed + 1) % 120` yap). Daire yerine 4 çeyrek dilim:

```swift
let palette = TripPalette.forSeed(coverSeed)
ZStack {
    ForEach(0..<4, id: \.self) { index in
        Circle()
            .trim(from: Double(index) / 4, to: Double(index + 1) / 4)
            .stroke(palette.pin(index), lineWidth: 11)
    }
}
.frame(width: 22, height: 22)
.rotationEffect(.degrees(-90))
```

  Fotoğraflı seyahatte bu düğmenin kapağa etkisi yok; footer metni aynen kalır.

- [ ] **Step 7: Build ve simülatör**

Run: build komutu (Global Constraints). Expected: `** BUILD SUCCEEDED **`.
`grep -rn "Accent.cycle" ios/Gezzy` çıktısında yalnızca kişi renkleri (`PackingSection` üyeler, `MoneySection` para birimi dilimleri, `TripTheme`/`Theme` tanımı) kalmalı. `MoneySection.swift:503,520` para birimi renkleridir; dokunma.
Simülatörde Kopenhag seyahatini aç; ekran görüntüsü al: kapak bantları ile pinler, gün çipi ve "Durak ekle" aynı paletten mi? Düzenle → "Kart rengini değiştir"e 2 kez bas, rengin değiştiğini gör. Koyu temada (`simctl ui <udid> appearance dark`) tekrar bak, sonra `light`'a geri al.

- [ ] **Step 8: Commit**

```bash
git add -A ios/Gezzy
git commit -m "Color each trip from its own palette

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Plan sekmesini sadeleştir

**Files:**
- Modify: `ios/Gezzy/Features/Plan/PlanSection.swift` (`stopList`, `StopRow`, `OfflineMapRow` görünürlüğü)
- Modify: `ios/Gezzy/Features/TripDetail/TripDetailView.swift` (`coverMenu`'ye çevrimdışı harita öğesi)
- Modify: `ios/Gezzy/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `tripPalette`, `Tag(text:color:soft:)` (Task 2).
- Produces: `PlanSection.showsOfflineRow(trip:now:) -> Bool` (static, `internal`).

- [ ] **Step 1: Gün başlığı tek satır**

`stopList`'teki yatay `ScrollView` + `StatChip` grubunu sil, yerine:

```swift
if !stops.isEmpty {
    Text(summary(stops: stops.count, meters: totalMeters))
        .font(.system(.footnote, weight: .medium))
        .foregroundStyle(Color.ink2)
}
if plan.warningCount > 0 {
    Label(String(localized: "\(plan.warningCount) saat uyarısı"), systemImage: "clock.badge.exclamationmark")
        .font(.system(.footnote, weight: .semibold))
        .foregroundStyle(HoursLabel.conflictColor)
}
```

```swift
    private func summary(stops: Int, meters: Double) -> String {
        var parts = [String(localized: "\(stops) durak")]
        if meters > 0 {
            parts.append(AppFormat.distance(meters: meters))
            parts.append(String(localized: "\(Geo.walkingMinutes(meters: meters)) dk yürüyüş"))
        }
        return parts.joined(separator: " · ")
    }
```

`totalMeters`'ın tipi `Double` değilse imzayı ona uydur. `StatChip` başka yerde kullanılmıyorsa (`grep -rn StatChip ios/Gezzy`) `TripTheme.swift`'ten sil. Yeni anahtar: `"%lld dk yürüyüş"` → en `"%lld min walk"`.

- [ ] **Step 2: Durak satırı**

`StopRow`'da sağdaki `Image(systemName: stop.kind.symbol)…frame(width: 48, height: 48)` bloğunu sil. `Text(detail)` satırını:

```swift
Label {
    Text(detail)
} icon: {
    Image(systemName: stop.kind.symbol).font(.system(size: 12, weight: .semibold))
}
.font(.tBody)
.foregroundStyle(Color.ink2)
.labelStyle(.titleAndIcon)
```

Saat etiketi sağda kalır (Task 2'deki `Tag(text:color:soft:)`).

- [ ] **Step 3: Sürükleme ipucu en çok 3 açılış**

`PlanSection`'a:

```swift
    /// Sürükleme ipucunun gösterildiği açılış sayısı; 3'e ulaşınca ya da kullanıcı bir durak sürükleyince gizlenir.
    @AppStorage("gezzy.hint.dragStops") private var dragHintViews = 0
    @State private var countedDragHint = false
```

İpucu koşulu `stops.count > 1 && dragHintViews < 3`. İpucu `Text`'ine:

```swift
.onAppear {
    guard !countedDragHint else { return }
    countedDragHint = true
    dragHintViews += 1
}
```

`moveStop(_:before:on:)` gövdesinin başına `dragHintViews = 3`.

- [ ] **Step 4: Çevrimdışı harita bandı**

`PlanSection`'a:

```swift
    /// Band: kayıt sürerken, kayıtlıyken ya da hata varken hep; boşta yalnızca yolculuğa 7 gün kala ve bitmeden.
    static func showsOfflineRow(state: OfflineMapStore.State, start: Date, end: Date, now: Date = .now) -> Bool {
        if case .idle = state {
            let calendar = Calendar.current
            let daysLeft = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                                   to: calendar.startOfDay(for: start)).day ?? 0
            return daysLeft <= 7 && calendar.startOfDay(for: now) <= calendar.startOfDay(for: end)
        }
        return true
    }
```

`OfflineMapRow(trip: trip, day: plan.day)` çağrısını `if Self.showsOfflineRow(state: OfflineMapStore.shared.state(for: trip.id), start: trip.startDate, end: trip.endDate) { … }` ile sar.

`TripDetailView.coverMenu`'de "Takvime aktar"ın altına:

```swift
Button("Haritaları internetsiz kaydet", systemImage: "arrow.down.circle") {
    Task { await OfflineMapStore.shared.save(trip) }
}
```

(Metin zaten xcstrings'te var: `"Haritaları internetsiz kullanım için kaydet"` değil — bu kısa hali yeni anahtar: en `"Save maps for offline use"`.) Kullanıcı menüden kaydedince durum `.saving`'e geçer, band Plan'da görünür.

- [ ] **Step 5: Build, simülatör, commit**

Build. Simülatörde Kopenhag Plan sekmesi (yolculuğa 17 gün var → band görünmemeli; `•••` menüsünde öğe görünmeli). Gün başlığı tek satır, durak satırında sağ kutu yok, ipucu görünüyor. Uygulamayı 3 kez yeniden başlatınca (`simctl terminate`/`launch`) ipucu kaybolmalı. Ekran görüntüsünü rapora ekle (dosya yolu).

```bash
git add -A ios/Gezzy
git commit -m "Simplify plan day header, stop rows and persistent hints

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Fikirler kartını sadeleştir

**Files:**
- Modify: `ios/Gezzy/Features/Plan/IdeasCard.swift`
- Modify: `ios/Gezzy/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `tripTint`, `tripPalette`, `Color.soft(_:)`, `AddPlaceholder` (mevcut).
- Produces: `PillButtonStyle(tint: Color?, soft: Color?)` — `isProminent` kalkar.

- [ ] **Step 1: Başlık + ve boş durum**

Başlık `HStack`'te `Spacer()`'dan sonra (Uçuşlar kartındaki desen, `FlightViews.swift:21-32`):

```swift
Button {
    isPicking = true
} label: {
    Image(systemName: "plus")
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(tint, in: Circle())
}
.buttonStyle(.plain)
.accessibilityLabel("Yer ekle")
```

`ideas.isEmpty` iken `EmptyHint` yerine:

```swift
AddPlaceholder(title: String(localized: "Yer ekle"),
               subtitle: String(localized: "Gitmek istediğin yerleri ekle; sonra otomatik rota günlere dağıtsın.")) {
    Button("Haritada ara", systemImage: "map") { isPicking = true }
}
```

`AddPlaceholder` bir `Menu`; tek öğeli menü yerine doğrudan açılsın istiyorsan `AddPlaceholder`'a `action:` init'i ekleme — tek öğe kabul. Yeni anahtar `"Haritada ara"` → en `"Search the map"`.

Alttaki düğme sırasından "Yer ekle" düğmesini sil.

- [ ] **Step 2: Otomatik rota ikincil**

`PillButtonStyle`:

```swift
/// Kart içi küçük hap düğme; `tint` verilirse yumuşak zemin + renkli metin.
struct PillButtonStyle: ButtonStyle {
    var tint: Color?
    var soft: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.footnote, weight: .semibold))
            .foregroundStyle(tint ?? Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(soft ?? Color.track, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
```

"Otomatik rota": `.buttonStyle(PillButtonStyle(tint: tint, soft: .soft(palette)))`. `grep -rn "isProminent" ios/Gezzy` başka kullanım gösterirse onları `PillButtonStyle(tint: tint, soft: .soft(palette))` yap.

- [ ] **Step 3: Satırdaki ekleme düğmesi**

Siyah `"\(AppFormat.dayPill(day)) ekle"` kapsülünü sil, yerine:

```swift
Menu {
    ForEach(trip.days(), id: \.self) { target in
        Button("\(AppFormat.dayPill(target)) ekle") {
            withAnimation(.spring(duration: 0.3)) { schedule(idea, on: target) }
        }
    }
} label: {
    Image(systemName: "plus")
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(tint)
        .frame(width: 32, height: 32)
        .background(Color.soft(palette), in: Circle())
} primaryAction: {
    withAnimation(.spring(duration: 0.3)) { schedule(idea, on: day) }
}
.accessibilityLabel(Text("\(AppFormat.dayPill(day)) gününe ekle"))
```

`schedule(_:)` → `schedule(_ idea: Stop, on target: Date)`; gövdede `day` yerine `target`. `trip.days()` adı farklıysa (`grep -n "func days" ios/Packages/GezzyKit/Sources/GezzyKit/*.swift`) uydur. Yeni anahtar `"%@ gününe ekle"` → en `"Add to %@"`.

Satırdaki tür kutusu `frame(width: 34, height: 34)` → `28, 28`, köşe 8.

- [ ] **Step 4: Build, simülatör, commit**

Build. Kopenhag Plan → Fikirler: başlıkta tinted +, "Otomatik rota" yumuşak, satırlarda küçük + daireler; + dokununca seçili güne ekler, basılı tutunca gün menüsü açılır. Bir fikri ekleyip geri almak için durağı bağlam menüsünden silebilirsin; test verisini bozduysan seed'i yeniden yükleme talimatı raporda dursun (seed dosyası: scratchpad `trips-cph.json`, controller yükler).

```bash
git add -A ios/Gezzy
git commit -m "Lighten the ideas card actions

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Diğer sekmeleri tara ve sadeleştir

**Files:**
- Modify (bulguya göre): `Features/Money/MoneySection.swift`, `Features/Money/TaxFreeCard.swift`, `Features/Packing/PackingSection.swift`, `Features/Packing/DepartureChecklistCard.swift`, `Features/Visa/VisaSection.swift`, `Features/Visa/SchengenCard.swift`, `Features/Visa/DocumentsCard.swift`, `Features/Crew/CrewSection.swift`, `Features/Memories/MemoriesSection.swift`, `Features/Plan/ReservationsSection.swift`, `Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `tripTint`, `tripPalette`, `Color.soft(_:)`, `PrimaryButtonStyle.primary(_:)`, `PillButtonStyle(tint:soft:)`, `AddPlaceholder`.

Kurallar (spec §3, aynen):

1. Sekme başına en fazla bir dolu (siyah ya da tint) düğme. Diğerleri ikincil stil (`soft` zemin + `tint` metin) ya da başlıktaki **+**.
2. Kart içinde ekleme eylemi varsa başlıktaki **+** ile yapılır; ayrı büyük "… ekle" düğmesi kalkar. Boş durumda `AddPlaceholder`.
3. Aynı bilgiyi gösteren ikinci öğe (ikon + aynı anlamda etiket, tekrarlanan başlık) kalkar.
4. Her zaman görünen açıklama/ipucu metni (`.caption` gri paragraflar) yalnızca boş durumda ya da ilk kullanımda görünür; dolu durumda kalkar. Yasal/kaynak notları (vize kaynağı gibi) bu kuralın dışındadır, kısaltılarak kalır.
5. Seçili durum ve vurgular `tint`; kategori renkleri yalnızca bütçe kategorilerinde.

Bilinen adaylar: Ekip'teki "QR ile katılanlar · şimdilik sadece görür" notu; Valiz'deki "Öneriler mevsime göre yapılacak." notu; Vize'de üye yokken "Ekipte kimse yok." büyük başlığı (boş durum `EmptyHint`'e dönsün); Bütçe ve Belgeler kartlarındaki ekleme düğmeleri.

- [ ] **Step 1: Önce görüntüler**

Simülatörde Kopenhag seyahatinin Rezervasyon, Bütçe, Valiz, Vize, Ekip, Anılar sekmelerinin tam sayfa ekran görüntülerini al (her sekmede kaydırarak). Yolları rapora yaz.

- [ ] **Step 2: Bulgu tablosu**

Rapora sekme başına tablo yaz: `dosya:satır | kural no | ne var | ne yapılacak`. Bir kural ihlali bir davranışı kaldırıyorsa (eylem erişilemez hale geliyorsa) yapma; eylem her zaman başlıktaki + ya da `•••`/bağlam menüsünde erişilebilir kalmalı.

- [ ] **Step 3: Uygula**

Tablodaki satırları uygula. Her dosyada `@Environment(\.tripTint)`/`@Environment(\.tripPalette)` gerekirse ekle. Silinen metinlerin xcstrings anahtarlarını silme (derleyici "stale" işaretler, sorun değil); yeni metinlerin `en` değerini ekle.

- [ ] **Step 4: Build, sonra görüntüler, commit**

Build. Aynı sekmelerin sonra görüntülerini al, rapora yolları yaz. Her sekmede dolu düğme sayısını say (≤1).

```bash
git add -A ios/Gezzy
git commit -m "Declutter budget, packing, visa, crew and memories tabs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
