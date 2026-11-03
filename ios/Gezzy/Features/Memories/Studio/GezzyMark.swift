import SwiftUI
import UIKit

/// Kartların altındaki "Gezzy ile planlandı" işareti; kart rengine göre beyaz ya da mürekkep, %70 opak.
struct GezzyMark: View {
    let onDark: Bool

    private var color: Color { onDark ? .white : .ink }

    var body: some View {
        HStack(spacing: 6) {
            badge
            Text("Gezzy ile planlandı")
                .font(.system(.caption2, weight: .semibold))
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
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            Image(systemName: "airplane")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(onDark ? Color.black : Color.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(color))
        }
    }
}
