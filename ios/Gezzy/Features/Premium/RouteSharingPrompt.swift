import SwiftUI

/// Rota paylaşım izni sorusu: başlık, açıklama ve eşit görünümlü iki seçenek. Hiçbiri önceden seçili değil.
struct RouteSharingPrompt: View {
    @Binding var choice: RouteReporter.Choice?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rotanı başkalarına ilham yap")
                .font(.tBodyStrong)
                .foregroundStyle(Color.ink)
            Text(RouteSharingPrompt.explanation)
                .font(.caption)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                option(.yes, title: "Evet, paylaş")
                option(.no, title: "Hayır")
            }
            .padding(.top, 2)
        }
    }

    /// Her yerde aynı açıklama (tek yerelleştirme anahtarı).
    static let explanation: LocalizedStringKey = "Seyahat bitince gittiğin yerler, sırası ve saatleri, kaç gece ve kaç kişi olduğun, harcama tutarların Gezzy'ye gider. Adın, otelin, uçuşun ve harcama başlıkların gitmez. Profil'den istediğin zaman değiştirebilirsin."

    private func option(_ value: RouteReporter.Choice, title: LocalizedStringKey) -> some View {
        let isOn = choice == value
        return Button {
            withAnimation(.spring(duration: 0.25)) { choice = value }
        } label: {
            HStack(spacing: 6) {
                if isOn { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)) }
                Text(title).font(.system(.subheadline, weight: .semibold))
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Color.tray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isOn ? Color.ink : Color.clear, lineWidth: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Mevcut ya da anketi atlayan kullanıcılara bir kez gösterilen izin sayfası.
struct RouteSharingPromptSheet: View {
    /// Kaydedilen seçim; sayfa kapanmadan önce çağrılır.
    let onSave: (RouteReporter.Choice) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: RouteReporter.Choice?

    var body: some View {
        VStack(spacing: 20) {
            ScrollView {
                RouteSharingPrompt(choice: $choice)
                    .padding(.horizontal, 20)
                    .padding(.top, 28)
            }
            Button("Kaydet") {
                guard let choice else { return }
                onSave(choice)
                dismiss()
            }
            .buttonStyle(.primary)
            .disabled(choice == nil)
            .opacity(choice == nil ? 0.5 : 1)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .background(Color.canvas)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
