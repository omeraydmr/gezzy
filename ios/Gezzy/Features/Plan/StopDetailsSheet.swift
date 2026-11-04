import SwiftUI
import GezzyKit

/// Durağın ad, tür, saat, süre ve not alanları; düzenleme ve elle ekleme formları paylaşır.
struct StopFormFields: View {
    @Binding var stop: Stop
    var showsTime = true

    var body: some View {
        TextField("Durak adı", text: $stop.name)
        Picker("Tür", selection: $stop.kind) {
            ForEach(StopKind.allCases, id: \.self) { kind in
                Label(kind.title, systemImage: kind.symbol).tag(kind)
            }
        }
        if showsTime {
            Toggle("Saat belirle", isOn: Binding(
                get: { stop.startMinutes != nil },
                set: { stop.startMinutes = $0 ? (stop.startMinutes ?? 10 * 60) : nil }))
            .tint(Color.success)
            if let minutes = stop.startMinutes {
                DatePicker("Başlangıç", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        stop.startMinutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    }), displayedComponents: .hourAndMinute)
            }
        }
        Stepper("Süre: \(AppFormat.duration(minutes: stop.durationMinutes))", value: $stop.durationMinutes, in: 15...600, step: 15)
        TextField("Not (ör. Rezervasyon gerekli)", text: $stop.note)
    }
}

/// Plandaki bir durağın ayrıntılarını düzenler.
struct StopDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Stop
    @State private var isPickingOnMap = false
    let center: Coordinate?
    let onSave: (Stop) -> Void

    init(stop: Stop, center: Coordinate?, onSave: @escaping (Stop) -> Void) {
        _draft = State(initialValue: stop)
        self.center = center
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { StopFormFields(stop: $draft) }
                StopLocationSection(stop: $draft, center: draft.coordinate ?? center, isPickingOnMap: $isPickingOnMap)
            }
            .stopMapPicker(isPresented: $isPickingOnMap, stop: $draft, center: center)
            .navigationTitle("Durağı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Vazgeç") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        var saved = draft
                        saved.name = saved.name.trimmingCharacters(in: .whitespaces)
                        saved.note = saved.note.trimmingCharacters(in: .whitespaces)
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
