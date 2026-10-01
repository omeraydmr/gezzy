import SwiftUI
import TravellerKit

struct AddExpenseSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var title = ""
    @State private var amountText = ""
    @State private var category: SpendCategory = .food
    @State private var paidBy: UUID?
    @State private var splitAmong: Set<UUID> = []
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ne için? (ör. Akşam yemeği)", text: $title)
                    HStack {
                        TextField("Tutar", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text(trip.currency).foregroundStyle(Color.ink2)
                    }
                    Picker("Kategori", selection: $category) {
                        ForEach(SpendCategory.allCases, id: \.self) { category in
                            Label(category.title, systemImage: category.symbol).tag(category)
                        }
                    }
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                }

                Section("Kim ödedi?") {
                    Picker("Ödeyen", selection: $paidBy) {
                        ForEach(trip.members) { member in
                            Text(member.name).tag(Optional(member.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    ForEach(trip.members) { member in
                        Button {
                            if splitAmong.contains(member.id) {
                                splitAmong.remove(member.id)
                            } else {
                                splitAmong.insert(member.id)
                            }
                        } label: {
                            HStack {
                                AvatarView(member: member, size: 28)
                                Text(member.name).foregroundStyle(Color.ink)
                                Spacer()
                                if splitAmong.contains(member.id) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
                                } else {
                                    Image(systemName: "circle").foregroundStyle(Color.ink3)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Kimler arasında bölünsün?")
                } footer: {
                    if let share {
                        Text("Kişi başı \(share)")
                    }
                }
            }
            .navigationTitle("Masraf ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save).disabled(!isValid)
                }
            }
            .onAppear {
                if paidBy == nil { paidBy = trip.members.first?.id }
                if splitAmong.isEmpty { splitAmong = Set(trip.members.map(\.id)) }
            }
        }
    }

    private var amount: Int? { AppFormat.parseMinor(amountText) }

    private var share: String? {
        guard let amount, amount > 0, !splitAmong.isEmpty else { return nil }
        return AppFormat.money(Settlement.split(amount, into: splitAmong.count).first ?? 0, trip.currency)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (amount ?? 0) > 0 && paidBy != nil && !splitAmong.isEmpty
    }

    private func save() {
        guard let amount, let paidBy else { return }
        // Üye sırasını koru ki artan kuruşların kime düştüğü tutarlı olsun.
        let split = trip.members.map(\.id).filter { splitAmong.contains($0) }
        let expense = Expense(title: title.trimmingCharacters(in: .whitespaces), amount: amount, category: category,
                              paidBy: paidBy, splitAmong: split, date: date)
        store.update(trip.id) { $0.expenses.append(expense) }
        dismiss()
    }
}

struct EditBudgetSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var limits: [SpendCategory: String] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SpendCategory.allCases, id: \.self) { category in
                        HStack {
                            Label(category.title, systemImage: category.symbol)
                                .foregroundStyle(category.accent.base)
                            Spacer()
                            TextField("0", text: Binding(
                                get: { limits[category] ?? "" },
                                set: { limits[category] = $0 }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                            Text(trip.currency).foregroundStyle(Color.ink2)
                        }
                    }
                } footer: {
                    Text("Boş bırakılan kategoriler bütçede gösterilmez (harcama olmadıkça).")
                }
            }
            .navigationTitle("Bütçe limitleri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                }
            }
            .onAppear {
                for line in trip.budget {
                    limits[line.category] = String(line.limit / 100)
                }
            }
        }
    }

    private func save() {
        let lines = SpendCategory.allCases.compactMap { category -> BudgetLine? in
            guard let text = limits[category], let minor = AppFormat.parseMinor(text), minor > 0 else { return nil }
            return BudgetLine(category: category, limit: minor)
        }
        store.update(trip.id) { $0.budget = lines }
        dismiss()
    }
}
