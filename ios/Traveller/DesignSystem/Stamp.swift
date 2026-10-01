import SwiftUI
import TravellerKit

// Seyahat onayı: ahşap saplı lastik mühür ve bilete bastığı "PASSED" izi.

private enum Wood {
    static let light = Color(hex: 0xD49A5C)
    static let mid = Color(hex: 0xAD6E36)
    static let dark = Color(hex: 0x7A4A22)
    static let ink = Color(hex: 0xC2343F)
}

/// Ahşap saplı lastik mühür.
struct RubberStamp: View {
    var inkColor: Color = Wood.ink

    var body: some View {
        VStack(spacing: -2) {
            // Topuz
            Ellipse()
                .fill(LinearGradient(colors: [Wood.light, Wood.mid], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(WoodGrain(lines: 4).stroke(Wood.dark.opacity(0.25), lineWidth: 1).clipShape(Ellipse()))
                .overlay(Ellipse().fill(.white.opacity(0.25)).frame(width: 26, height: 10).offset(x: -12, y: -10).blur(radius: 2))
                .frame(width: 74, height: 50)
                .zIndex(2)
            // Boyun
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [Wood.dark, Wood.mid, Wood.light, Wood.mid], startPoint: .leading, endPoint: .trailing))
                .frame(width: 32, height: 42)
                .zIndex(1)
            // Yaka
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(LinearGradient(colors: [Wood.mid, Wood.dark], startPoint: .top, endPoint: .bottom))
                .overlay(WoodGrain(lines: 3).stroke(Color.black.opacity(0.15), lineWidth: 1)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous)))
                .frame(width: 122, height: 24)
            // Gövde
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [Wood.dark, Color(hex: 0x5A3418)], startPoint: .top, endPoint: .bottom))
                .frame(width: 140, height: 22)
            // Lastik
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(inkColor)
                .overlay(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.25)))
                .frame(width: 132, height: 8)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.25), radius: 10, y: 8)
        .accessibilityHidden(true)
    }

    static let height: CGFloat = 50 + 42 + 24 + 22 + 8 - 8
}

/// Ahşap damarları için birkaç yumuşak eğri.
private struct WoodGrain: Shape {
    let lines: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<lines {
            let y = rect.minY + rect.height * (CGFloat(index) + 0.5) / CGFloat(lines)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addCurve(to: CGPoint(x: rect.maxX, y: y + 3),
                          control1: CGPoint(x: rect.width * 0.3, y: y - 5),
                          control2: CGPoint(x: rect.width * 0.7, y: y + 6))
        }
        return path
    }
}

/// Mürekkep izi: çift çerçeve, "PASSED", tarih ve varış kodu; lastik baskısı gibi yer yer boş.
struct StampImprint: View {
    var title = "PASSED"
    let subtitle: String
    var color: Color = Wood.ink
    var scale: CGFloat = 1

    var body: some View {
        VStack(spacing: 2 * scale) {
            Text(title)
                .font(.system(size: 30 * scale, weight: .black, design: .rounded))
                .tracking(4 * scale)
            Text(subtitle)
                .font(.system(size: 10 * scale, weight: .bold, design: .monospaced))
                .tracking(1 * scale)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 16 * scale)
        .padding(.vertical, 8 * scale)
        .overlay(RoundedRectangle(cornerRadius: 9 * scale, style: .continuous).strokeBorder(color, lineWidth: 3 * scale))
        .overlay(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous).strokeBorder(color, lineWidth: 1 * scale)
            .padding(4.5 * scale))
        .mask(InkMask())
        .opacity(0.9)
        .rotationEffect(.degrees(-12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title) \(subtitle)"))
    }

    /// Damganın alt yazısı: "01 EKİ 2026 · LIS".
    static func subtitle(for trip: Trip, on date: Date = .now) -> String {
        let day = date.formatted(.dateTime.day(.twoDigits).month(.abbreviated).year().locale(AppFormat.locale))
            .uppercased(with: AppFormat.locale)
        let code = trip.primaryFlight?.toCode
            ?? String(trip.destination.city.prefix(3)).uppercased(with: AppFormat.locale)
        return "\(day) · \(code)"
    }
}

/// Lastik baskısındaki boşlukları taklit eden sabit desenli maske.
private struct InkMask: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .clear
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            for _ in 0..<140 {
                let x = next() * size.width
                let y = next() * size.height
                let r = 0.4 + next() * 1.6
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white))
            }
        }
    }
}

// MARK: - Ceremony

/// Yeni seyahat onayı: bilet ortaya gelir, mühür iner ve "PASSED" basar, bilet desteye uçar.
struct StampCeremony: View {
    let trip: Trip
    var coverImage: UIImage?
    let onFinished: () -> Void

    private enum Phase: Int, Comparable {
        case appearing, ready, descending, impact, lifting, flying

        static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    @State private var phase: Phase = .appearing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let side: CGFloat = 280
    private let imprintY: CGFloat = 52

    var body: some View {
        ZStack {
            Color.black
                .opacity(phase == .flying ? 0 : 0.35)
                .ignoresSafeArea()

            ZStack {
                TripTicketCard(trip: trip, side: side)
                    .environment(\.coverOverride, coverImage)
                    .overlay {
                        StampImprint(subtitle: StampImprint.subtitle(for: trip))
                            .scaleEffect(phase >= .impact ? 1 : 1.35)
                            .opacity(phase >= .impact ? 1 : 0)
                            .offset(y: imprintY)
                    }

                RubberStamp()
                    .scaleEffect(x: 1, y: phase == .impact ? 0.9 : 1, anchor: .bottom)
                    .rotationEffect(.degrees(stampRotation))
                    .offset(y: stampOffset)
                    .opacity(phase == .appearing || phase >= .lifting ? 0 : 1)
            }
            .scaleEffect(phase == .appearing ? 0.85 : (phase == .flying ? 0.45 : 1))
            .rotationEffect(.degrees(phase == .flying ? -8 : 0))
            .offset(y: phase == .flying ? -720 : 0)
            .opacity(phase == .appearing ? 0 : 1)
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 1), trigger: phase == .impact)
        .task { await run() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Seyahat oluşturuldu")
    }

    /// Mühür merkezinin dikey konumu: lastik, izin üst kısmına değecek şekilde.
    private var stampOffset: CGFloat {
        let touching = imprintY - RubberStamp.height / 2 + 6
        switch phase {
        case .appearing, .ready: return -360
        case .descending, .impact: return touching
        case .lifting, .flying: return -380
        }
    }

    private var stampRotation: Double {
        switch phase {
        case .appearing, .ready: -14
        case .descending, .impact: -4
        case .lifting, .flying: 8
        }
    }

    private func run() async {
        if reduceMotion {
            phase = .impact
            try? await Task.sleep(for: .milliseconds(900))
            onFinished()
            return
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { phase = .ready }
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(.easeIn(duration: 0.26)) { phase = .descending }
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { phase = .impact }
        try? await Task.sleep(for: .milliseconds(480))
        withAnimation(.easeOut(duration: 0.35)) { phase = .lifting }
        try? await Task.sleep(for: .milliseconds(420))
        withAnimation(.easeIn(duration: 0.42)) { phase = .flying }
        try? await Task.sleep(for: .milliseconds(360))
        onFinished()
    }
}
