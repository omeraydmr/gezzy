import SwiftUI
import TravellerKit

struct CrewSection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var editing: Member?
    @State private var isAdding = false
    @State private var blockedRemoval: Member?

    var body: some View {
        ModuleCard("Ekip", symbol: "person.2.fill") {
            StoryHeadline(text: "\(trip.members.count) kişi \(trip.destination.city) yolunda.")

            VStack(spacing: 0) {
                ForEach(Array(trip.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { Divider().overlay(Color.line) }
                    Button {
                        editing = member
                    } label: {
                        CrewRow(member: member)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if member.role != .owner {
                            Button("Ekipten çıkar", systemImage: "person.badge.minus", role: .destructive) {
                                remove(member)
                            }
                        }
                    }
                }
            }
            .tray(padding: 16)

            VStack(alignment: .leading, spacing: 8) {
                Label("Davet linki ve QR kod", systemImage: "link")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                Text("Ekip arkadaşlarının kendi telefonlarından katılması için hesap ve senkronizasyon gerekiyor; bir sonraki adımda eklenecek. Şimdilik kişileri buradan elle ekleyebilirsin.")
                    .font(.tBody)
                    .foregroundStyle(Color.ink2)
            }
            .tray()

            Button {
                isAdding = true
            } label: {
                Label("Kişi ekle", systemImage: "person.badge.plus")
            }
            .buttonStyle(.primary)
        }
        .sheet(item: $editing) { member in
            MemberEditor(member: member) { updated in
                store.update(trip.id) { trip in
                    if let index = trip.members.firstIndex(where: { $0.id == updated.id }) {
                        trip.members[index] = updated
                    }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            MemberEditor(member: Member(name: "", role: .editor, colorIndex: trip.members.count,
                                        passport: Passport(expiresOn: Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now)),
                         isNew: true) { member in
                store.update(trip.id) { $0.members.append(member) }
            }
        }
        .alert("Kişi çıkarılamıyor", isPresented: Binding(get: { blockedRemoval != nil },
                                                          set: { if !$0 { blockedRemoval = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("\(blockedRemoval?.name ?? "") harcamalarda yer alıyor. Önce ilgili harcamaları sil ya da düzenle.")
        }
    }

    private func remove(_ member: Member) {
        let involved = trip.expenses.contains { $0.paidBy == member.id || $0.splitAmong.contains(member.id) }
        guard !involved else {
            blockedRemoval = member
            return
        }
        store.update(trip.id) { trip in
            trip.members.removeAll { $0.id == member.id }
            for index in trip.packing.indices where trip.packing[index].assignee == member.id {
                trip.packing[index].assignee = nil
            }
        }
    }
}

struct CrewRow: View {
    let member: Member

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(member: member, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                Text(passportText).font(.tBody).foregroundStyle(Color.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Tag(text: member.role.title, accent: member.role == .viewer ? .gray : .green)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var passportText: String {
        guard let passport = member.passport else { return "Pasaport bilgisi yok" }
        var text = "Pasaport \(AppFormat.longDate(passport.expiresOn))"
        if !passport.heldVisas.isEmpty {
            text += " · " + passport.heldVisas.map { VisaText.zoneName($0.zone) }.joined(separator: ", ")
        }
        return text
    }
}

struct MemberEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var member: Member
    var isNew = false
    let onSave: (Member) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ad", text: $member.name)
                    if member.role != .owner {
                        Picker("Yetki", selection: $member.role) {
                            Text(MemberRole.editor.title).tag(MemberRole.editor)
                            Text(MemberRole.viewer.title).tag(MemberRole.viewer)
                        }
                    }
                }

                Section {
                    Toggle("Pasaport bilgisi", isOn: Binding(
                        get: { member.passport != nil },
                        set: { member.passport = $0 ? Passport(expiresOn: Calendar.current.date(byAdding: .year, value: 5, to: .now) ?? .now) : nil }
                    ))
                    if member.passport != nil {
                        DatePicker("Geçerlilik bitişi", selection: passportBinding(\.expiresOn), displayedComponents: .date)
                    }
                } header: {
                    Text("Pasaport (T.C.)")
                }

                if member.passport != nil {
                    Section {
                        ForEach(VisaZone.allCases, id: \.self) { zone in
                            heldVisaRow(zone)
                        }
                    } header: {
                        Text("Elindeki geçerli vizeler")
                    } footer: {
                        Text("Geçerli bir vize, aynı bölgeye yapılan seyahatlerde otomatik olarak dikkate alınır.")
                    }
                }
            }
            .navigationTitle(isNew ? "Kişi ekle" : member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        member.name = member.name.trimmingCharacters(in: .whitespaces)
                        onSave(member)
                        dismiss()
                    }
                    .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func heldVisaRow(_ zone: VisaZone) -> some View {
        let index = member.passport?.heldVisas.firstIndex { $0.zone == zone }
        Toggle(VisaText.zoneName(zone), isOn: Binding(
            get: { index != nil },
            set: { isOn in
                if isOn {
                    let until = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now
                    member.passport?.heldVisas.append(HeldVisa(zone: zone, validUntil: until))
                } else {
                    member.passport?.heldVisas.removeAll { $0.zone == zone }
                }
            }
        ))
        if let index {
            DatePicker("Bitiş", selection: Binding(
                get: { member.passport?.heldVisas[index].validUntil ?? .now },
                set: { member.passport?.heldVisas[index].validUntil = $0 }
            ), displayedComponents: .date)
            .padding(.leading, 16)
        }
    }

    private func passportBinding<Value>(_ keyPath: WritableKeyPath<Passport, Value>) -> Binding<Value> {
        Binding(
            get: { member.passport![keyPath: keyPath] },
            set: { member.passport?[keyPath: keyPath] = $0 }
        )
    }
}
