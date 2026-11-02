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
