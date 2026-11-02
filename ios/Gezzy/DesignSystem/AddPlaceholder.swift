import SwiftUI

/// Boş kartta tek ekleme yolu: kesik çizgili satır; dokununca verilen menü açılır.
struct AddPlaceholder<MenuContent: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let menu: () -> MenuContent
    @Environment(\.tripTint) private var tint

    var body: some View {
        Menu {
            menu()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Color.ink2)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.ink3, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Kart başlığındaki ekleme düğmesinin görünümü: palet renginde dolu daire, beyaz artı.
struct HeaderPlusLabel: View {
    @Environment(\.tripTint) private var tint

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(tint, in: Circle())
    }
}
