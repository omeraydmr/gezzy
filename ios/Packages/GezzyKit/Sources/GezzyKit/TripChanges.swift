import Foundation

/// Buluttan gelen bir seyahat güncellemesinde nelerin değiştiğini kısa Türkçe cümlelerle özetler
/// ("Elif bir harcama ekledi: Akşam yemeği · €86").
public enum TripChanges {
    public struct Summary: Hashable, Sendable {
        public var title: String
        public var lines: [String]
        /// Dokununca açılacak seyahat ve ilk değişikliğin sekmesi.
        public var link: TripLink
        /// Değişikliği yapan kişinin adı (biliniyorsa).
        public var editor: String?

        public init(title: String, lines: [String], link: TripLink, editor: String? = nil) {
            self.title = title
            self.lines = lines
            self.link = link
            self.editor = editor
        }

        public var body: String { lines.joined(separator: "\n") }
    }

    /// - Parameters:
    ///   - old: cihazdaki önceki kopya (yoksa yeni paylaşılan seyahat).
    ///   - new: birleşmiş yeni kopya.
    ///   - me: bu cihazın kullanıcısı; kendi yaptığı değişiklikler bildirilmez.
    ///   - money: tutar biçimlendirici (kuruş, para birimi).
    public static func summarize(old: Trip?, new: Trip, me: UUID?, money: (Int, String) -> String) -> Summary? {
        guard let old else {
            return Summary(title: new.name, lines: [String(localized: "Seyahat seninle paylaşıldı.")], link: TripLink(tripID: new.id, section: "plan"))
        }
        // Kendi (başka cihazdan) yaptığın değişiklik bildirilmez.
        if let editorID = new.updatedBy, editorID == me { return nil }
        var lines: [String] = []
        var sections: [String] = []
        let name = { (id: UUID) in new.member(id)?.name ?? String(localized: "Biri") }
        let editor = new.updatedBy.flatMap { new.member($0)?.name }

        let oldExpenses = Set(old.expenses.map(\.id))
        for expense in new.expenses where !oldExpenses.contains(expense.id) && !expense.isTransfer && expense.paidBy != me {
            sections.append("money")
            lines.append("\(name(expense.paidBy)) bir harcama ekledi: \(expense.title) · \(money(expense.amount, new.currency))")
        }
        for expense in new.expenses where !oldExpenses.contains(expense.id) && expense.isTransfer && expense.paidBy != me {
            let to = expense.splitAmong.first.map(name) ?? String(localized: "Biri")
            sections.append("money")
            lines.append(String(localized: "\(name(expense.paidBy)) → \(to) ödemesi yapıldı · \(money(expense.amount, new.currency))"))
        }

        let newExpenses = Set(new.expenses.map(\.id))
        for expense in old.expenses where !newExpenses.contains(expense.id) && !expense.isTransfer {
            sections.append("money")
            lines.append(editor.map { String(localized: "\($0) bir harcamayı sildi: \(expense.title)") }
                         ?? String(localized: "Harcama silindi: \(expense.title)"))
        }

        let oldStops = Set(old.stops.map(\.id))
        let addedStops = new.stops.filter { !oldStops.contains($0.id) }
        if !addedStops.isEmpty { sections.append("plan") }
        if addedStops.count == 1 {
            lines.append(editor.map { String(localized: "\($0) plana ekledi: \(addedStops[0].name)") }
                         ?? String(localized: "Plana eklendi: \(addedStops[0].name)"))
        } else if addedStops.count > 1 {
            lines.append(editor.map { String(localized: "\($0) plana \(addedStops.count) durak ekledi") }
                         ?? String(localized: "Plana \(addedStops.count) durak eklendi"))
        }

        let newStopIDs = Set(new.stops.map(\.id))
        let removedStops = old.stops.filter { !newStopIDs.contains($0.id) }
        if !removedStops.isEmpty { sections.append("plan") }
        if removedStops.count == 1 {
            lines.append(editor.map { String(localized: "\($0) plandan çıkardı: \(removedStops[0].name)") }
                         ?? String(localized: "Plandan çıkarıldı: \(removedStops[0].name)"))
        } else if removedStops.count > 1 {
            lines.append(editor.map { String(localized: "\($0) plandan \(removedStops.count) durak çıkardı") }
                         ?? String(localized: "Plandan \(removedStops.count) durak çıkarıldı"))
        }

        // Başka güne taşınan duraklar tek tek; aynı gün içinde sırası değişenler tek satırda.
        let oldByID = Dictionary(old.stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var reordered = false
        for stop in new.stops {
            guard let before = oldByID[stop.id] else { continue }
            if !Calendar.current.isDate(before.day, inSameDayAs: stop.day) {
                sections.append("plan")
                let day = stop.day.formatted(.dateTime.day().month(.abbreviated).weekday(.abbreviated))
                lines.append(editor.map { String(localized: "\($0), \(stop.name) durağını \(day) gününe taşıdı") }
                             ?? String(localized: "\(stop.name) \(day) gününe taşındı"))
            } else if before.order != stop.order {
                reordered = true
            }
        }
        if reordered {
            sections.append("plan")
            lines.append(editor.map { String(localized: "\($0) planın sırasını değiştirdi") }
                         ?? String(localized: "Planın sırası değişti"))
        }

        let oldLodgings = Set(old.lodgingList.map(\.id))
        for lodging in new.lodgingList where !oldLodgings.contains(lodging.id) {
            sections.append("reservations")
            lines.append(editor.map { String(localized: "\($0) konaklama ekledi: \(lodging.name)") }
                         ?? String(localized: "Konaklama eklendi: \(lodging.name)"))
        }
        let oldFlights = Set(old.flights.map(\.id))
        for flight in new.flights where !oldFlights.contains(flight.id) {
            sections.append("reservations")
            lines.append(editor.map { String(localized: "\($0) uçuş ekledi: \(flight.fromCode) → \(flight.toCode)") }
                         ?? String(localized: "Uçuş eklendi: \(flight.fromCode) → \(flight.toCode)"))
        }

        let oldMembers = Set(old.members.map(\.id))
        for member in new.members where !oldMembers.contains(member.id) && member.id != me {
            sections.append("crew")
            lines.append(String(localized: "\(member.name) ekibe katıldı"))
        }

        let oldPacked = Set(old.packing.filter(\.isPacked).map(\.id))
        let newlyPacked = new.packing.filter { $0.isPacked && !oldPacked.contains($0.id) && $0.assignee != me }
        if !newlyPacked.isEmpty {
            sections.append("packing")
            let titles = newlyPacked.prefix(2).map(\.title).joined(separator: ", ")
            let more = newlyPacked.count > 2 ? String(localized: " ve \(newlyPacked.count - 2) madde daha") : ""
            lines.append(String(localized: "Valize konuldu: \(titles)\(more)"))
        }

        if old.startDate != new.startDate || old.endDate != new.endDate {
            sections.append("plan")
            lines.append(editor.map { String(localized: "\($0) seyahat tarihlerini değiştirdi") }
                         ?? String(localized: "Seyahat tarihleri değişti"))
        }

        guard !lines.isEmpty else { return nil }
        return Summary(title: new.name, lines: lines, link: TripLink(tripID: new.id, section: sections.first), editor: editor)
    }
}
