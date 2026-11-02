import SwiftUI
import GezzyKit

/// Listede olmayan yeri elle ekleme: ad, tür, süre. Saat ve not sonradan "Düzenle" ile verilir.
struct ManualPlaceForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Stop
    let onAdd: (Stop) -> Void

    init(initialName: String, day: Date, onAdd: @escaping (Stop) -> Void) {
        _draft = State(initialValue: Stop(day: day, order: 0, name: initialName.trimmingCharacters(in: .whitespaces),
                                          kind: .sight))
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { StopFormFields(stop: $draft, showsTime: false) }
            }
            .navigationTitle("Elle ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle") {
                        var stop = draft
                        stop.name = stop.name.trimmingCharacters(in: .whitespaces)
                        stop.note = stop.note.trimmingCharacters(in: .whitespaces)
                        onAdd(stop)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
