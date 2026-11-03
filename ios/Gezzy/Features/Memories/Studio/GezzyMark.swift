import SwiftUI
import UIKit

/// Kartların altındaki "Gezzy ile planlandı" işareti; kart rengine göre beyaz ya da mürekkep, %70 opak.
struct GezzyMark: View {
    let onDark: Bool
    /// Kart içinde genişliğe oranlı boyut; nil ise sistem yazı boyutu.
    var scale: CGFloat?

    private var color: Color { onDark ? .white : .ink }
    private var s: CGFloat { scale ?? 1 }

    var body: some View {
        HStack(spacing: 6 * s) {
            badge
            Text("Gezzy ile planlandı")
                .font(scale.map { .system(size: 11 * $0, weight: .semibold) } ?? .system(.caption2, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .opacity(0.7)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var badge: some View {
        // Uygulama simgesi okunamıyorsa (asset kataloğunda simge setleri genelde okunmaz) uçak rozeti.
        if let icon = UIImage(named: "AppIcon") {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 16 * s, height: 16 * s)
                .clipShape(RoundedRectangle(cornerRadius: 4 * s, style: .continuous))
        } else {
            Image(systemName: "airplane")
                .font(.system(size: 8 * s, weight: .bold))
                .foregroundStyle(onDark ? Color.black : Color.white)
                .frame(width: 16 * s, height: 16 * s)
                .background(Circle().fill(color))
        }
    }
}
