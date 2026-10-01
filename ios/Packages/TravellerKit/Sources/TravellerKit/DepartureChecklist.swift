import Foundation

/// Gidiş öncesi yapılacak bir iş (valizden farklı: eşya değil, görev).
public struct ChecklistItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var note: String
    /// Gidişten kaç gün önce yapılmalı; nil ise tarihsiz.
    public var daysBefore: Int?
    public var isDone: Bool
    /// Öneriden eklendiyse önerinin anahtarı (aynı öneri tekrar gösterilmez).
    public var key: String?

    public init(id: UUID = UUID(), title: String, note: String = "", daysBefore: Int? = nil, isDone: Bool = false,
                key: String? = nil) {
        self.id = id
        self.title = title
        self.note = note
        self.daysBefore = daysBefore
        self.isDone = isDone
        self.key = key
    }
}

/// Kural tabanlı gidiş öncesi öneriler (yapay zekâ kullanmaz).
public enum DepartureChecklist {
    public struct Suggestion: Hashable, Sendable {
        public var key: String
        public var title: String
        public var note: String
        public var daysBefore: Int

        public func item() -> ChecklistItem {
            ChecklistItem(title: title, note: note, daysBefore: daysBefore, key: key)
        }
    }

    /// Seyahate göre önerilenler; listede zaten olanlar (anahtara göre) çıkarılır. Yakın tarihliler önce.
    public static func suggestions(for trip: Trip) -> [Suggestion] {
        let country = trip.destination.countryCode.uppercased()
        let entry = VisaRules.entry(for: country)
        var result: [Suggestion] = []

        if country != "TR" {
            result.append(Suggestion(key: "exit-fee", title: "Yurt dışı çıkış harç pulu",
                                     note: "Türkiye'den çıkışta gerekir; e-Devlet, banka ya da vergi dairesinden pasaport numarasıyla alınır.",
                                     daysBefore: 7))
            result.append(Suggestion(key: "roaming", title: "Yurt dışı internet paketi ya da eSIM",
                                     note: "Operatörün yurt dışı paketi ya da varış ülkesi için eSIM; hat yurt dışı aramaya açık olsun.",
                                     daysBefore: 3))
            result.append(Suggestion(key: "cards", title: "Kartları yurt dışı kullanıma aç",
                                     note: "İnternet ve yurt dışı harcama izni, temassız ödeme ve kart limitleri.",
                                     daysBefore: 3))
        }
        if trip.currency.uppercased() != "TRY" {
            result.append(Suggestion(key: "cash", title: "Biraz nakit \(trip.currency.uppercased())",
                                     note: "Ulaşım, bahşiş ve kart geçmeyen yerler için küçük miktar.", daysBefore: 2))
        }
        let isSchengen = VisaRules.schengenCountries.contains(country)
        var needsVisa = false
        if case .visaRequired = entry?.rule { needsVisa = true }
        if isSchengen || needsVisa {
            result.append(Suggestion(key: "insurance", title: "Seyahat sağlık sigortası",
                                     note: needsVisa ? "Vize başvurusunda da istenir; seyahatin tüm günlerini kapsamalı."
                                                     : "Seyahatin tüm günlerini kapsamalı; poliçeyi Belge kasasına ekle.",
                                     daysBefore: needsVisa ? 30 : 7))
        }
        if needsVisa, (trip.visaApplications ?? []).allSatisfy({ $0.status != .approved }) {
            result.append(Suggestion(key: "visa", title: "Vize başvurusu",
                                     note: "Randevular dolabilir; Vize sekmesinden başvuruyu takip et.", daysBefore: 45))
        }
        if !trip.flights.isEmpty {
            result.append(Suggestion(key: "check-in", title: "Online check-in",
                                     note: "Çoğu havayolunda kalkıştan 24–48 saat önce açılır; biniş kartını Wallet'a ekle.",
                                     daysBefore: 1))
        }
        if trip.stops.contains(where: { $0.coordinate != nil }) {
            result.append(Suggestion(key: "offline-maps", title: "Haritaları çevrimdışı kaydet",
                                     note: "Plan sekmesinde \"Kaydet\"; varışta internet olmasa da rota açılır.", daysBefore: 1))
        }
        result.append(Suggestion(key: "documents", title: "Pasaport ve belgelerin kopyası",
                                 note: "Pasaport, bilet ve sigortanın fotoğrafını Belge kasasına ekle.", daysBefore: 7))
        result.append(Suggestion(key: "home", title: "Evden çıkmadan son kontrol",
                                 note: "Ocak, su, priz, pencereler, çöp ve anahtar.", daysBefore: 0))

        let existing = Set(trip.checklistItems.compactMap(\.key))
        return result.filter { !existing.contains($0.key) }.sorted { $0.daysBefore > $1.daysBefore }
    }

    /// Maddenin son günü (gidiş gününden `daysBefore` gün önce).
    public static func dueDate(of item: ChecklistItem, in trip: Trip, calendar: Calendar = .current) -> Date? {
        guard let days = item.daysBefore else { return nil }
        return calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: trip.startDate))
    }

    /// Süresi geçmiş ve yapılmamış mı.
    public static func isOverdue(_ item: ChecklistItem, in trip: Trip, now: Date = Date(),
                                 calendar: Calendar = .current) -> Bool {
        guard !item.isDone, let due = dueDate(of: item, in: trip, calendar: calendar) else { return false }
        return calendar.startOfDay(for: now) > due
    }

    /// Yapılmamışlar önce (son günü yakın olan önce), yapılanlar sonda.
    public static func sorted(_ items: [ChecklistItem], in trip: Trip, calendar: Calendar = .current) -> [ChecklistItem] {
        items.sorted { lhs, rhs in
            if lhs.isDone != rhs.isDone { return !lhs.isDone }
            let l = dueDate(of: lhs, in: trip, calendar: calendar) ?? .distantFuture
            let r = dueDate(of: rhs, in: trip, calendar: calendar) ?? .distantFuture
            return l != r ? l < r : lhs.title < rhs.title
        }
    }
}
