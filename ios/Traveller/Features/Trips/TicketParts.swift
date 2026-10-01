import SwiftUI
import TravellerKit

/// Yanlarında bilet çentikleri olan yuvarlatılmış kart şekli.
struct TicketShape: Shape {
    /// Çentiklerin dikey konumu (üstten, pt).
    var notchY: CGFloat
    var notchRadius: CGFloat = 11
    var cornerRadius: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        let body = Path(roundedRect: rect, cornerRadius: cornerRadius, style: .continuous)
        var notches = Path()
        for x in [rect.minX, rect.maxX] {
            notches.addEllipse(in: CGRect(x: x - notchRadius, y: rect.minY + notchY - notchRadius,
                                          width: notchRadius * 2, height: notchRadius * 2))
        }
        return body.subtracting(notches)
    }
}

/// Kalkış ve varış arasındaki kesikli yay + uçak.
struct FlightArc: View {
    var accent: Color = .success

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 4, y: h - 4))
                    path.addQuadCurve(to: CGPoint(x: w - 4, y: h - 4), control: CGPoint(x: w / 2, y: -h * 0.4))
                }
                .stroke(Color.ink3, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 4]))
                Circle().fill(Color.ink3).frame(width: 6, height: 6).position(x: 4, y: h - 4)
                Circle().fill(accent).frame(width: 6, height: 6).position(x: w - 4, y: h - 4)
                Image(systemName: "airplane")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .position(x: w / 2, y: h * 0.16)
            }
        }
        .accessibilityHidden(true)
    }
}

struct Barcode: View {
    private static let widths: [CGFloat] = [2, 1, 3, 1, 1, 2, 1, 3, 2, 1, 1, 2, 3, 1, 2, 1, 1, 3]

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Self.widths.indices, id: \.self) { index in
                Rectangle().fill(Color.ink).frame(width: Self.widths[index])
            }
        }
        .accessibilityHidden(true)
    }
}
