import SwiftUI
import TravellerKit

/// Yanlarında bilet çentikleri olan yuvarlatılmış kart şekli.
/// Yol doğrudan çizilir; boolean yol işlemi (subtracting) her karede pahalı olduğu için kullanılmaz.
struct TicketShape: Shape {
    /// Çentiklerin dikey konumu (üstten, pt).
    var notchY: CGFloat
    var notchRadius: CGFloat = 11
    var cornerRadius: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        let r = min(cornerRadius, rect.width / 2, rect.height / 2)
        let n = notchRadius
        let notch = min(max(rect.minY + notchY, rect.minY + r + n), rect.maxY - r - n)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r), radius: r)
        path.addLine(to: CGPoint(x: rect.maxX, y: notch - n))
        // Sağ çentik: kartın içine doğru yarım daire.
        path.addArc(center: CGPoint(x: rect.maxX, y: notch), radius: n,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - r, y: rect.maxY), radius: r)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - r), radius: r)
        path.addLine(to: CGPoint(x: rect.minX, y: notch + n))
        // Sol çentik.
        path.addArc(center: CGPoint(x: rect.minX, y: notch), radius: n,
                    startAngle: .degrees(90), endAngle: .degrees(-90), clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + r, y: rect.minY), radius: r)
        path.closeSubpath()
        return path
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
