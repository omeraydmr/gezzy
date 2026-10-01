import SwiftUI
import TravellerKit

struct AddExpenseSheet: View {
    @Environment(TripStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let trip: Trip

    @State private var entry = AmountEntry()
    @State private var title = ""
    @State private var category: SpendCategory = .food
    @State private var paidBy: UUID?
    @State private var splitAmong: Set<UUID> = []
    @State private var date = Date.now
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                amountDisplay
                    .padding(.top, 4)

                TextField("Ne için? (ör. Akşam yemeği)", text: $title)
                    .focused($isTitleFocused)
                    .submitLabel(.done)
                    .multilineTextAlignment(.center)
                    .font(.system(.body, weight: .medium))
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color.tray, in: Capsule())
                    .softShadow()
                    .padding(.horizontal, 16)

                categoryChips

                VStack(spacing: 10) {
                    peopleRow("Ödeyen", selected: { paidBy == $0 }) { paidBy = $0 }
                    peopleRow("Bölünecek", selected: { splitAmong.contains($0) }) { id in
                        if splitAmong.contains(id) {
                            if splitAmong.count > 1 { splitAmong.remove(id) }
                        } else {
                            splitAmong.insert(id)
                        }
                    }
                }
                .padding(.horizontal, 16)

                Spacer(minLength: 0)

                if !isTitleFocused {
                    Keypad(entry: $entry)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button(action: save) {
                    Label("Kaydet", systemImage: "checkmark")
                }
                .buttonStyle(.primary)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
            .animation(.spring(duration: 0.3), value: isTitleFocused)
            .background(TintGlow(tint: category.accent.base, offsetY: -260))
            .navigationTitle("Masraf ekle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    DatePicker("Tarih", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            .onAppear {
                if paidBy == nil { paidBy = trip.members.first?.id }
                if splitAmong.isEmpty { splitAmong = Set(trip.members.map(\.id)) }
            }
        }
    }

    // MARK: Parts

    private var amountDisplay: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(AppFormat.currencySymbol(trip.currency))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.ink3)
                Text(entry.display)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(entry.isEmpty ? Color.ink3 : Color.ink)
                    .contentTransition(.numericText())
                    .animation(.spring(duration: 0.2), value: entry.display)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Tutar \(AppFormat.money(entry.minorUnits, trip.currency))"))

            Text(shareText)
                .font(.system(.footnote, weight: .medium))
                .foregroundStyle(Color.ink2)
        }
    }

    private var shareText: String {
        let count = splitAmong.count
        guard entry.minorUnits > 0, count > 0 else { return "\(count) kişi arasında bölünecek" }
        let share = Settlement.split(entry.minorUnits, into: count).first ?? 0
        return count == 1 ? "Tek kişiye ait" : "Kişi başı \(AppFormat.money(share, trip.currency)) · \(count) kişi"
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SpendCategory.allCases, id: \.self) { item in
                    let isSelected = item == category
                    Button {
                        withAnimation(.spring(duration: 0.25)) { category = item }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(isSelected ? Color.white : item.accent.base)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(isSelected ? item.accent.base : item.accent.tint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func peopleRow(_ label: String, selected: @escaping (UUID) -> Bool,
                           toggle: @escaping (UUID) -> Void) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.tCaption)
                .foregroundStyle(Color.ink3)
                .frame(width: 72, alignment: .leading)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(trip.members) { member in
                        let isOn = selected(member.id)
                        Button {
                            withAnimation(.spring(duration: 0.2)) { toggle(member.id) }
                        } label: {
                            AvatarView(member: member, size: 38)
                                .overlay(Circle().strokeBorder(isOn ? Color.ink : .clear, lineWidth: 2.5).padding(-4))
                                .opacity(isOn ? 1 : 0.35)
                                .saturation(isOn ? 1 : 0)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(member.name))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        entry.minorUnits > 0 && paidBy != nil && !splitAmong.isEmpty
    }

    private func save() {
        guard let paidBy, isValid else { return }
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        // Üye sırasını koru ki artan kuruşların kime düştüğü tutarlı olsun.
        let split = trip.members.map(\.id).filter { splitAmong.contains($0) }
        let expense = Expense(title: trimmed.isEmpty ? category.title : trimmed, amount: entry.minorUnits,
                              category: category, paidBy: paidBy, splitAmong: split, date: date)
        store.update(trip.id) { $0.expenses.append(expense) }
        dismiss()
    }
}

/// Hesap makinesi tarzı rakam tuşları.
struct Keypad: View {
    @Binding var entry: AmountEntry

    private enum Key: Hashable {
        case digit(Int), decimal, backspace
    }

    private let rows: [[Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.decimal, .digit(0), .backspace],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            press(key)
                        } label: {
                            label(for: key)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.tray, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .softShadow()
                        }
                        .buttonStyle(KeyPressStyle())
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: entry)
    }

    @ViewBuilder
    private func label(for key: Key) -> some View {
        switch key {
        case let .digit(value):
            Text("\(value)").font(.system(size: 24, weight: .medium)).foregroundStyle(Color.ink)
        case .decimal:
            Text(",").font(.system(size: 26, weight: .semibold)).foregroundStyle(Color.ink)
                .accessibilityLabel("Virgül")
        case .backspace:
            Image(systemName: "delete.left").font(.system(size: 20, weight: .medium)).foregroundStyle(Color.ink)
                .accessibilityLabel("Sil")
        }
    }

    private func press(_ key: Key) {
        switch key {
        case let .digit(value): entry.append(digit: value)
        case .decimal: entry.appendDecimalSeparator()
        case .backspace: entry.backspace()
        }
    }
}

private struct KeyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
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
