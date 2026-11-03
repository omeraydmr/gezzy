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

    func testDarkTextContrastOnDarkSurfaces() {
        var palettes = TripPalette.all
        for hue in stride(from: 0, to: 360, by: 15) {
            let seed = TripPalette.rgb(h: Double(hue) / 360, s: 0.6, b: 0.7)
            palettes.append(TripPalette.derived(from: seed, fallbackSeed: 0))
        }
        for palette in palettes {
            for hex in palette.pins {
                let text = TripPalette.textOnDark(hex)
                XCTAssertGreaterThanOrEqual(contrast(text, 0x24262A), 4.5, "\(palette.id) \(String(hex, radix: 16))")
                XCTAssertGreaterThanOrEqual(contrast(text, 0x1A1B1E), 4.5, "\(palette.id) \(String(hex, radix: 16))")
                XCTAssertGreaterThanOrEqual(contrast(text, palette.softDark), 4.5, "\(palette.id) soft")
            }
            XCTAssertEqual(palette.accentTextDark, TripPalette.textOnDark(palette.accent))
        }
    }

    func testDarkTextKeepsHue() {
        for palette in TripPalette.all {
            let a = TripPalette.hsb(palette.accent).h, t = TripPalette.hsb(palette.accentTextDark).h
            var gap = abs(a - t) * 360
            gap = min(gap, 360 - gap)
            XCTAssertLessThanOrEqual(gap, 4, palette.id)
        }
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = TripPalette.luminance(a), lb = TripPalette.luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
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
