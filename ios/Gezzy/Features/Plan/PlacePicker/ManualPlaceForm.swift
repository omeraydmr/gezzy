import SwiftUI
import GezzyKit

/// Listede olmayan yeri elle ekleme: ad, tür, süre ve konum (adres ya da haritadan). Konumsuz durak haritada görünmediği
/// ve yol tarifi alınamadığı için konum zorunludur. Saat ve not sonradan "Düzenle" ile verilir.
struct ManualPlaceForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Stop
    let onAdd: (Stop) -> Void
    let center: Coordinate?

    init(initialName: String, day: Date, center: Coordinate?, onAdd: @escaping (Stop) -> Void) {
        self.center = center
        _draft = State(initialValue: Stop(day: day, order: 0, name: initialName.trimmingCharacters(in: .whitespaces),
                                          kind: .sight))
        self.onAdd = onAdd
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { StopFormFields(stop: $draft, showsTime: false) }
                StopLocationSection(stop: $draft, center: center, isRequired: true)
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
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.coordinate == nil)
                }
            }
        }
        .presentationDetents([.large])
    }
}
