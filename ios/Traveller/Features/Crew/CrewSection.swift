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

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(trip.members) { member in
                    Button {
                        editing = member
                    } label: {
                        MemberTile(member: member, trip: trip)
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
                Button {
                    isAdding = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 52, height: 52)
                            .background(Color.track, in: Circle())
                        Text("Kişi ekle").font(.system(.subheadline, weight: .semibold))
                    }
                    .foregroundStyle(Color.ink2)
                    .frame(maxWidth: .infinity, minHeight: 168)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.ink3.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    )
                }
                .buttonStyle(.plain)
            }

            InviteCard(trip: trip)

            if CloudSync.shared.sharedWithMe.contains(trip.id), !trip.members.contains(where: { $0.id == store.me.id }) {
                HStack(spacing: 12) {
                    AvatarView(member: store.me, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bu seyahate katıldın").font(.tBodyStrong).foregroundStyle(Color.ink)
                        Text("Harcama ve valizde görünmek için kendini ekle.").font(.caption).foregroundStyle(Color.ink2)
                    }
                    Spacer()
                    Button("Ekle") {
                        var me = store.me
                        me.role = .editor
                        me.colorIndex = trip.members.count
                        store.update(trip.id) { $0.members.append(me) }
                    }
                    .font(.system(.subheadline, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(Color.ink)
                }
                .tray(padding: 14)
            }
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

/// Ekip ızgarasındaki kişi kartı: büyük avatar, rol ve vize durumu.
struct MemberTile: View {
    let member: Member
    let trip: Trip

    var body: some View {
        let result = VisaAdvisor.assess(countryCode: trip.destination.countryCode, passport: member.passport,
                                        tripStart: trip.startDate, tripEnd: trip.endDate)
        let tag = VisaText.tag(result)
        VStack(spacing: 8) {
            AvatarView(member: member, size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if member.role == .owner {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.food, in: Circle())
                            .overlay(Circle().strokeBorder(Color.tray, lineWidth: 2))
                    }
                }
            VStack(spacing: 2) {
                Text(member.name).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(1)
                Text(member.role.title).font(.caption).foregroundStyle(Color.ink3)
            }
            HStack(spacing: 4) {
                Image(systemName: "person.text.rectangle")
                Text(tag.text)
            }
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(tag.accent == .gray ? Color.ink2 : tag.accent.base)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tag.accent.tint, in: Capsule())
        }
        .frame(maxWidth: .infinity, minHeight: 168)
        .background(Color.tray, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .softShadow()
        .accessibilityElement(children: .combine)
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

/// iCloud paylaşım davetini (Mesajlar, Mail, AirDrop…) gönderen kart.
struct InviteCard: View {
    let trip: Trip
    private var sync: CloudSync { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.transport)
                    .frame(width: 36, height: 36)
                    .background(Color.transportTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(subtitle).font(.caption).foregroundStyle(Color.ink2)
                }
            }

            if sync.isAvailable {
                ShareLink(item: TripShareItem(tripID: trip.id, title: trip.name),
                          preview: SharePreview("\(trip.name) · Traveller")) {
                    Label(sync.sharedByMe.contains(trip.id) ? "Paylaşımı yönet / yeni kişi davet et" : "Davet bağlantısı gönder",
                          systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.primary)
            }
        }
        .tray()
    }

    private var title: String {
        if sync.sharedWithMe.contains(trip.id) { return "Bu seyahat seninle paylaşıldı" }
        if sync.sharedByMe.contains(trip.id) { return "Ekip iCloud ile bağlı" }
        return "Ekibi davet et"
    }

    private var subtitle: String {
        switch sync.status {
        case let .unavailable(reason): return reason
        case .unknown: return "iCloud durumu kontrol ediliyor…"
        case .syncing: return "Eşitleniyor…"
        case let .synced(date): return "Değişiklikler herkesin telefonunda görünür · son eşitleme \(AppFormat.time(date))"
        case let .failed(message): return "Eşitleme sorunu: \(message)"
        }
    }
}
