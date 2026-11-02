import SwiftUI

/// Boş kartta tek ekleme yolu: kesik çizgili satır; dokununca verilen menü açılır
/// ya da tek seçenek varsa doğrudan eylem çalışır.
struct AddPlaceholder<MenuContent: View>: View {
    let title: String
    let subtitle: String
    var action: (() -> Void)?
    @ViewBuilder let menu: () -> MenuContent
    @Environment(\.tripTint) private var tint
    @Environment(\.tripText) private var tintText

    init(title: String, subtitle: String, @ViewBuilder menu: @escaping () -> MenuContent) {
        self.title = title
        self.subtitle = subtitle
        self.menu = menu
    }

    var body: some View {
        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
        } else {
            Menu {
                menu()
            } label: {
                label
            }
            .buttonStyle(.plain)
        }
    }

    private var label: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tintText)
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
}

extension AddPlaceholder where MenuContent == EmptyView {
    /// Tek seçenekli boş durum: dokununca doğrudan eylem.
    @_disfavoredOverload
    init(title: String, subtitle: String, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.menu = { EmptyView() }
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
            // Görünüm 32 pt, dokunma alanı 44 pt.
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}
