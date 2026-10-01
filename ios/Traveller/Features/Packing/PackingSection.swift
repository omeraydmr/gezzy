import SwiftUI
import TravellerKit

struct PackingSection: View {
    @Environment(TripStore.self) private var store
    let trip: Trip

    @State private var newTitle = ""
    @State private var newAssignee: UUID?
    @FocusState private var isAddFieldFocused: Bool
    @State private var suggestions: [String] = []

    private var items: [PackingItem] { trip.packing }
    private var packedCount: Int { items.filter(\.isPacked).count }

    var body: some View {
        ModuleCard("Valiz", symbol: "bag.fill") {
            StoryHeadline(text: headline)

            VStack(alignment: .leading, spacing: 0) {
                if !items.isEmpty {
                    progress
                        .padding(.bottom, 16)
                    Divider().overlay(Color.line)
                }

                ForEach(items) { item in
                    PackingRow(trip: trip, item: item) {
                        store.update(trip.id) { trip in
                            if let index = trip.packing.firstIndex(where: { $0.id == item.id }) {
                                trip.packing[index].isPacked.toggle()
                            }
                        }
                    }
                    .contextMenu { menu(for: item) }
                }

                addRow
                    .padding(.top, 8)
            }
            .tray()

            if !suggestions.isEmpty {
                suggestionList
            }

            Button(action: suggest) {
                Label("Madde öner", systemImage: "sparkles")
            }
            .buttonStyle(.primary)
        }
    }

    private var headline: String {
        guard !items.isEmpty else { return "Valiz listesi boş. Önerilerle başla." }
        let remaining = items.count - packedCount
        let countdown = Countdown.make(start: trip.startDate, end: trip.endDate)
        let when: String = switch countdown {
        case let .days(n) where n == 1: " Yarın yola çıkıyorsunuz."
        case let .days(n): " \(n) gün kaldı."
        case .today: " Bugün yola çıkıyorsunuz."
        default: ""
        }
        if remaining == 0 { return "Her şey hazır ✓" }
        return "\(items.count) maddenin \(TurkishGrammar.withPossessive(packedCount)) hazır.\(when)"
    }

    // MARK: Progress

    private var progress: some View {
        let groups = packedByMember
        let remaining = items.count - packedCount
        return VStack(alignment: .leading, spacing: 12) {
            GeometryReader { proxy in
                let spacing: CGFloat = 6
                let segments = groups.count + (remaining > 0 ? 1 : 0)
                let usable = proxy.size.width - spacing * CGFloat(max(segments - 1, 0))
                HStack(spacing: spacing) {
                    ForEach(groups, id: \.member.id) { group in
                        HatchedBar(progress: 1, color: Accent.cycle(group.member.colorIndex).base)
                            .frame(width: usable * CGFloat(group.count) / CGFloat(items.count))
                    }
                    if remaining > 0 {
                        HatchedBar(progress: 0, color: .clear)
                            .frame(width: usable * CGFloat(remaining) / CGFloat(items.count))
                    }
                }
            }
            .frame(height: 14)

            HStack(spacing: 14) {
                ForEach(groups, id: \.member.id) { group in
                    HStack(spacing: 6) {
                        AvatarView(member: group.member, size: 26)
                        Text("\(group.count)")
                            .font(.tBodyStrong)
                            .foregroundStyle(Accent.cycle(group.member.colorIndex).base)
                    }
                }
                Spacer()
                Text("\(remaining) kaldı").font(.tBody).foregroundStyle(Color.ink3)
            }
        }
    }

    private struct MemberCount {
        let member: Member
        let count: Int
    }

    /// Paketlenen maddelerin kişilere dağılımı (atanmamışlar kalanlarla birlikte sayılmaz).
    private var packedByMember: [MemberCount] {
        trip.members.compactMap { member in
            let count = items.filter { $0.isPacked && $0.assignee == member.id }.count
            return count > 0 ? MemberCount(member: member, count: count) : nil
        } + unassignedPacked
    }

    private var unassignedPacked: [MemberCount] {
        let count = items.filter { $0.isPacked && trip.member($0.assignee) == nil }.count
        guard count > 0 else { return [] }
        return [MemberCount(member: Member(id: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, name: "?",
                                           colorIndex: 4), count: count)]
    }

    // MARK: Add & suggest

    private var addRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.ink2)
                .frame(width: 28, height: 28)
                .background(Color.track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            TextField("Madde ekle", text: $newTitle)
                .focused($isAddFieldFocused)
                .submitLabel(.done)
                .onSubmit(addItem)
            Menu {
                Picker("Kime", selection: $newAssignee) {
                    Text("Atanmadı").tag(UUID?.none)
                    ForEach(trip.members) { member in
                        Text(member.name).tag(Optional(member.id))
                    }
                }
            } label: {
                if let member = trip.member(newAssignee) {
                    AvatarView(member: member, size: 28)
                } else {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title3)
                        .foregroundStyle(Color.ink3)
                }
            }
            .accessibilityLabel("Kişiye ata")
        }
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Öneriler").font(.tCaption).foregroundStyle(Color.ink3)
            FlowLayout(spacing: 8) {
                ForEach(suggestions, id: \.self) { title in
                    Button {
                        store.update(trip.id) { $0.packing.append(PackingItem(title: title)) }
                        suggestions.removeAll { $0 == title }
                    } label: {
                        Label(title, systemImage: "plus")
                            .font(.system(.subheadline, weight: .medium))
                            .foregroundStyle(Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.tray, in: Capsule())
                            .softShadow()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func suggest() {
        withAnimation(.spring(duration: 0.3)) {
            suggestions = PackingAdvisor.suggestions(for: trip)
        }
    }

    private func addItem() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        store.update(trip.id) { $0.packing.append(PackingItem(title: title, assignee: newAssignee)) }
        newTitle = ""
        isAddFieldFocused = true
    }

    @ViewBuilder
    private func menu(for item: PackingItem) -> some View {
        Menu("Kime", systemImage: "person") {
            Button("Atanmadı") { assign(item, to: nil) }
            ForEach(trip.members) { member in
                Button(member.name) { assign(item, to: member.id) }
            }
        }
        Button("Sil", systemImage: "trash", role: .destructive) {
            store.update(trip.id) { $0.packing.removeAll { $0.id == item.id } }
        }
    }

    private func assign(_ item: PackingItem, to member: UUID?) {
        store.update(trip.id) { trip in
            if let index = trip.packing.firstIndex(where: { $0.id == item.id }) {
                trip.packing[index].assignee = member
            }
        }
    }
}

struct PackingRow: View {
    let trip: Trip
    let item: PackingItem
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onToggle) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(item.isPacked ? Color.success : Color.line, lineWidth: 2)
                        .background(item.isPacked ? Color.success : .clear,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    if item.isPacked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 28, height: 28)
                .animation(.spring(duration: 0.25, bounce: 0.4), value: item.isPacked)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isPacked ? "Paketlendi" : "Paketlenmedi")

            Text(item.title)
                .font(.body)
                .foregroundStyle(item.isPacked ? Color.ink3 : Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let member = trip.member(item.assignee) {
                AvatarView(member: member, size: 28)
            } else {
                Tag(text: "Atanmadı", accent: .orange)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Satır sonuna gelince alta kayan basit yerleşim (öneri hapları için).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
