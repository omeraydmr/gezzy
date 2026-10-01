import SwiftUI
import TravellerKit

struct MoneySection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var isAddingExpense = false
    @State private var isEditingBudget = false
    @State private var pendingTransfer: Transfer?

    private var summary: BudgetSummary { Budget.summary(for: trip) }
    private var transfers: [Transfer] { Settlement.transfers(for: trip) }

    var body: some View {
        VStack(spacing: 16) {
            budgetCard
            balancesCard
            expensesCard
        }
        .sheet(isPresented: $isAddingExpense) {
            AddExpenseSheet(trip: trip)
        }
        .sheet(isPresented: $isEditingBudget) {
            EditBudgetSheet(trip: trip)
        }
        .confirmationDialog("Ödeme yapıldı mı?", isPresented: Binding(
            get: { pendingTransfer != nil }, set: { if !$0 { pendingTransfer = nil } }
        ), presenting: pendingTransfer) { transfer in
            Button("Ödendi olarak işaretle") { settle(transfer) }
        } message: { transfer in
            Text("\(name(transfer.from)) → \(name(transfer.to)) · \(money(transfer.amount))")
        }
    }

    // MARK: Budget

    private var budgetCard: some View {
        ModuleCard("Bütçe", symbol: "chart.pie.fill", accessory: {
            Button("Düzenle") { isEditingBudget = true }
                .font(.system(.subheadline, weight: .medium))
                .foregroundStyle(Color.ink2)
        }) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(money(summary.spent)).foregroundStyle(Color.ink)
                    + Text(summary.limit > 0 ? " / \(money(summary.limit))" : "").foregroundStyle(Color.ink3))
                    .font(.tAmount)
                Text(paceText).font(.tBody).foregroundStyle(Color.ink2)
            }

            if summary.categories.isEmpty {
                EmptyHint(symbol: "chart.bar", text: "Kategori limitleri belirle, harcamalar burada dolsun.")
                    .tray()
            } else {
                VStack(spacing: 20) {
                    ForEach(summary.categories, id: \.category) { item in
                        CategoryBudgetRow(item: item, currency: trip.currency)
                    }
                }
                .tray()
            }
        }
    }

    private var paceText: String {
        switch summary.pace {
        case .notStarted: "Seyahat başlamadı · ön harcamalar"
        case let .under(day, total): "\(total) günün \(day). günü · tempo gerisinde"
        case let .onTrack(day, total): "\(total) günün \(day). günü · tam temposunda"
        case let .ahead(day, total): "\(total) günün \(day). günü · tempo biraz önde"
        case .finished: "Seyahat tamamlandı"
        }
    }

    // MARK: Balances

    private var balancesCard: some View {
        ModuleCard("Bakiyeler", symbol: "wallet.pass.fill") {
            StoryHeadline(text: balancesHeadline)
            VStack(spacing: 0) {
                ForEach(Array(transfers.enumerated()), id: \.offset) { index, transfer in
                    if index > 0 { Divider().overlay(Color.line) }
                    TransferRow(trip: trip, transfer: transfer) { pendingTransfer = transfer }
                }
                ForEach(Array(settledMembers.enumerated()), id: \.element.id) { index, member in
                    if index > 0 || !transfers.isEmpty { Divider().overlay(Color.line) }
                    HStack(spacing: 14) {
                        AvatarView(member: member, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                            Text("hesap kapalı").font(.tBody).foregroundStyle(Color.ink2)
                        }
                        Spacer()
                        Image(systemName: "checkmark").font(.headline).foregroundStyle(Color.success)
                    }
                    .padding(.vertical, 12)
                }
            }
            .tray(padding: 16)

            Button {
                isAddingExpense = true
            } label: {
                Label("Masraf ekle", systemImage: "plus")
            }
            .buttonStyle(.primary)
        }
    }

    private var settledMembers: [Member] {
        let involved = Set(transfers.flatMap { [$0.from, $0.to] })
        return trip.members.filter { !involved.contains($0.id) }
    }

    private var balancesHeadline: String {
        switch transfers.count {
        case 0: "Herkes dengede."
        case 1: "Tek transfer tüm seyahati kapatıyor."
        default: "\(Self.numberWord(transfers.count)) transfer tüm seyahati kapatıyor."
        }
    }

    private static func numberWord(_ n: Int) -> String {
        let words = ["Sıfır", "Bir", "İki", "Üç", "Dört", "Beş", "Altı", "Yedi", "Sekiz", "Dokuz", "On"]
        return n < words.count ? words[n] : "\(n)"
    }

    // MARK: Expenses

    private var expensesCard: some View {
        let expenses = trip.expenses.sorted { $0.date > $1.date }
        return ModuleCard("Harcamalar", symbol: "list.bullet.rectangle.fill") {
            if expenses.isEmpty {
                EmptyHint(symbol: "creditcard", text: "Henüz harcama yok.").tray()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                        if index > 0 { Divider().overlay(Color.line) }
                        ExpenseRow(trip: trip, expense: expense)
                            .contextMenu {
                                Button("Sil", systemImage: "trash", role: .destructive) {
                                    store.update(trip.id) { $0.expenses.removeAll { $0.id == expense.id } }
                                }
                            }
                    }
                }
                .tray(padding: 16)
            }
        }
    }

    // MARK: Helpers

    private func settle(_ transfer: Transfer) {
        let payment = Expense(title: "Hesaplaşma", amount: transfer.amount, category: .other, paidBy: transfer.from,
                              splitAmong: [transfer.to], date: .now, isTransfer: true)
        store.update(trip.id) { $0.expenses.append(payment) }
    }

    private func money(_ minor: Int) -> String { AppFormat.money(minor, trip.currency) }
    private func name(_ id: UUID) -> String { trip.member(id)?.name ?? "?" }
}

// MARK: - Rows

struct CategoryBudgetRow: View {
    let item: CategorySpend
    let currency: String

    var body: some View {
        let accent = item.category.accent
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: item.category.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent.base)
                    .frame(width: 36, height: 36)
                    .background(accent.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(item.category.title).font(.tBodyStrong).foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                Text(AppFormat.money(item.spent, currency))
                    .font(.tBodyStrong)
                    .foregroundStyle(item.isOver ? Color.food : accent.base)
                if item.limit > 0 {
                    Text("/ \(AppFormat.money(item.limit, currency))")
                        .font(.tBody)
                        .foregroundStyle(Color.ink3)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            HatchedBar(progress: item.progress, color: accent.base)
        }
        .accessibilityElement(children: .combine)
    }
}

struct TransferRow: View {
    let trip: Trip
    let transfer: Transfer
    let onSettle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            if let from = trip.member(transfer.from) {
                AvatarView(member: from, size: 44)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.member(transfer.from)?.name ?? "?").font(.tBodyStrong).foregroundStyle(Color.ink)
                HStack(spacing: 6) {
                    Text("öder").foregroundStyle(Color.ink2)
                    if let to = trip.member(transfer.to) {
                        AvatarView(member: to, size: 20)
                        Text(to.name).foregroundStyle(Color.ink2)
                    }
                }
                .font(.tBody)
            }
            Spacer()
            Button(action: onSettle) {
                Text(AppFormat.money(transfer.amount, trip.currency))
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Color.food)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Ödendi olarak işaretle")
        }
        .padding(.vertical, 12)
    }
}

struct ExpenseRow: View {
    let trip: Trip
    let expense: Expense

    var body: some View {
        let accent = expense.isTransfer ? Accent.gray : expense.category.accent
        HStack(spacing: 12) {
            Image(systemName: expense.isTransfer ? "arrow.left.arrow.right" : expense.category.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent.base)
                .frame(width: 36, height: 36)
                .background(accent.tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tBodyStrong).foregroundStyle(Color.ink).lineLimit(1)
                Text(subtitle).font(.tBody).foregroundStyle(Color.ink2).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(AppFormat.money(expense.amount, trip.currency))
                .font(.tBodyStrong)
                .foregroundStyle(expense.isTransfer ? Color.ink2 : Color.ink)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        guard expense.isTransfer else { return expense.title }
        let to = expense.splitAmong.first.flatMap { trip.member($0)?.name } ?? "?"
        return "\(trip.member(expense.paidBy)?.name ?? "?") → \(to)"
    }

    private var subtitle: String {
        let payer = trip.member(expense.paidBy)?.name ?? "?"
        if expense.isTransfer { return "Hesaplaşma · \(AppFormat.shortDate(expense.date))" }
        return "\(payer) ödedi · \(expense.splitAmong.count) kişi · \(AppFormat.shortDate(expense.date))"
    }
}
