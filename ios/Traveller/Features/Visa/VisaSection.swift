import SwiftUI
import TravellerKit

struct VisaSection: View {
    let trip: Trip
    @State private var selected: Member?

    private struct Row {
        let member: Member
        let result: VisaAssessment
    }

    private var assessments: [Row] {
        trip.members.map { member in
            Row(member: member,
                result: VisaAdvisor.assess(countryCode: trip.destination.countryCode, passport: member.passport,
                                           tripStart: trip.startDate, tripEnd: trip.endDate))
        }
    }

    var body: some View {
        let rows = assessments
        let readyCount = rows.filter { !$0.result.needsAction }.count
        ModuleCard("Vize", symbol: "person.text.rectangle.fill") {
            StoryHeadline(text: headline(ready: readyCount, total: rows.count))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(rows, id: \.member.id) { row in
                        Button {
                            selected = row.member
                        } label: {
                            PassportCard(member: row.member, result: row.result,
                                         countryCode: trip.destination.countryCode)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()

            VStack(alignment: .leading, spacing: 8) {
                Text("\(Countries.flag(trip.destination.countryCode)) \(Countries.name(trip.destination.countryCode))")
                    .font(.tBodyStrong)
                    .foregroundStyle(Color.ink)
                if let note = VisaRules.entry(for: trip.destination.countryCode)?.note {
                    Text(note).font(.tBody).foregroundStyle(Color.ink2)
                }
                SourceFootnote()
            }
            .tray()
        }
        .sheet(item: $selected) { member in
            VisaDetailSheet(trip: trip, member: member)
        }
    }

    private func headline(ready: Int, total: Int) -> String {
        if total == 0 { return "Ekipte kimse yok." }
        if ready == total { return total == 1 ? "Girişe hazırsın." : "Herkes girişe hazır." }
        let waiting = total - ready
        return ready == 0 ? "\(waiting) kişinin yapacakları var." : "\(ready) kişi hazır, \(waiting) kişinin yapacakları var."
    }
}

/// Bordo T.C. pasaportu görünümünde kart; üzerinde seyahatin vize durumu damga olarak basılı.
struct PassportCard: View {
    let member: Member
    let result: VisaAssessment
    let countryCode: String

    private static let burgundy = [Color(hex: 0x8A2433), Color(hex: 0x5A1420)]
    private static let gold = Color(hex: 0xE2C27A)

    var body: some View {
        let tag = VisaText.tag(result)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TÜRKİYE CUMHURİYETİ")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(1.2)
                    Text("PASAPORT")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(2.5)
                }
                .foregroundStyle(Self.gold)
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Self.gold.opacity(0.85))
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                AvatarView(member: member, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(passportLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(width: 250, height: 156)
        .background(
            LinearGradient(colors: Self.burgundy, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(Hatch(spacing: 7).stroke(Color.white.opacity(0.04), lineWidth: 1))
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(alignment: .topTrailing) {
            VisaStamp(text: tag.text, countryCode: countryCode, accent: tag.accent)
                .rotationEffect(.degrees(-12))
                .offset(x: -14, y: 46)
        }
        .shadow(color: Color(hex: 0x5A1420).opacity(0.3), radius: 12, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(member.name), \(VisaText.subtitle(result))"))
        .accessibilityAddTraits(.isButton)
    }

    private var passportLine: String {
        guard let passport = member.passport else { return "Pasaport bilgisi yok" }
        return "Geçerlilik \(AppFormat.longDate(passport.expiresOn))"
    }
}

/// Mürekkep damgası görünümünde durum etiketi.
struct VisaStamp: View {
    let text: String
    let countryCode: String
    let accent: Accent

    var body: some View {
        let color = accent == .gray ? Color.white.opacity(0.8) : accent.base
        VStack(spacing: 1) {
            Text(Countries.flag(countryCode)).font(.system(size: 14))
            Text(text.uppercased(with: AppFormat.locale))
                .font(.system(size: 11, weight: .heavy))
                .tracking(0.8)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [5, 2]))
                .padding(2)
        )
    }
}

/// Yeni seyahat formunda gösterilen kısa önizleme.
struct VisaPreview: View {
    let countryCode: String
    let passport: Passport?
    let start: Date
    let end: Date

    var body: some View {
        let result = VisaAdvisor.assess(countryCode: countryCode, passport: passport, tripStart: start, tripEnd: end)
        let tag = VisaText.tag(result)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(VisaText.subtitle(result)).font(.subheadline)
                Spacer()
                Tag(text: tag.text, accent: tag.accent)
            }
            ForEach(result.warnings, id: \.self) { warning in
                Label(VisaText.warning(warning), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.food)
            }
        }
    }
}

struct SourceFootnote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Bilgiler T.C. umuma mahsus (bordo) pasaport içindir; son gözden geçirme \(VisaRules.lastReviewed). Seyahatten önce resmî kaynaktan doğrula.")
                .font(.footnote)
                .foregroundStyle(Color.ink3)
            Link("konsolosluk.gov.tr", destination: VisaRules.officialSourceURL)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(Color.transport)
        }
    }
}

// MARK: - Detail

struct VisaDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    let member: Member

    @State private var checked: Set<String> = []

    var body: some View {
        let result = VisaAdvisor.assess(countryCode: trip.destination.countryCode, passport: member.passport,
                                        tripStart: trip.startDate, tripEnd: trip.endDate)
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        AvatarView(member: member, size: 44)
                        VStack(alignment: .leading) {
                            Text(member.name).font(.headline)
                            Text(VisaText.subtitle(result)).font(.subheadline).foregroundStyle(Color.ink2)
                        }
                        Spacer()
                        let tag = VisaText.tag(result)
                        Tag(text: tag.text, accent: tag.accent)
                    }
                    if let passport = member.passport {
                        LabeledContent("Pasaport bitişi", value: AppFormat.longDate(passport.expiresOn))
                    }
                }

                if !result.warnings.isEmpty {
                    Section("Uyarılar") {
                        ForEach(result.warnings, id: \.self) { warning in
                            Label(VisaText.warning(warning), systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.food)
                        }
                    }
                }

                if case let .required(zone) = result.status {
                    Section {
                        ForEach(VisaText.documents(for: zone), id: \.self) { document in
                            Button {
                                if checked.contains(document) { checked.remove(document) } else { checked.insert(document) }
                            } label: {
                                Label {
                                    Text(document).foregroundStyle(checked.contains(document) ? Color.ink3 : Color.ink)
                                } icon: {
                                    Image(systemName: checked.contains(document) ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(checked.contains(document) ? Color.success : Color.ink3)
                                }
                            }
                        }
                    } header: {
                        Text("Genel belge listesi")
                    } footer: {
                        Text("Konsolosluğa ve başvuru amacına göre değişir. Randevu ve güncel liste için yetkili aracı kurumu kontrol et.")
                    }
                }

                Section {
                    SourceFootnote()
                }
            }
            .navigationTitle("Vize durumu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Tamam") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Texts

enum VisaText {
    static func zoneName(_ zone: VisaZone?) -> String {
        switch zone {
        case .schengen: "Schengen"
        case .uk: "Birleşik Krallık"
        case .us: "ABD"
        case .canada: "Kanada"
        case nil: ""
        }
    }

    static func subtitle(_ result: VisaAssessment) -> String {
        switch result.status {
        case .domestic: return "Yurt içi seyahat"
        case let .notRequired(days): return "Vizesiz · \(days) güne kadar"
        case .eVisa: return "Önceden e-vize alınmalı"
        case let .onArrival(days): return days.map { "Kapıda vize · \($0) gün" } ?? "Kapıda vize"
        case let .required(zone): return "\(zoneName(zone)) vizesi gerekli".trimmingCharacters(in: .whitespaces)
        case let .coveredByHeldVisa(zone, until):
            return "\(zoneName(zone)) vizesi · bitiş \(AppFormat.longDate(until))"
        case .noPassport: return "Pasaport bilgisi eklenmedi"
        case .unknown: return "Bu ülke için veri yok"
        }
    }

    static func tag(_ result: VisaAssessment) -> (text: String, accent: Accent) {
        if result.warnings.contains(where: {
            if case .passportExpiresDuringTrip = $0 { return true }
            return false
        }) {
            return ("Pasaport", .orange)
        }
        switch result.status {
        case .domestic, .notRequired: return result.needsAction ? ("Uyarı", .orange) : ("Gerekmez", .green)
        case .coveredByHeldVisa: return result.needsAction ? ("Uyarı", .orange) : ("Geçerli ✓", .green)
        case .onArrival: return ("Kapıda", .blue)
        case .eVisa: return ("e-Vize", .blue)
        case .required: return ("Başvuru", .orange)
        case .noPassport: return ("Eksik", .orange)
        case .unknown: return ("Kontrol et", .gray)
        }
    }

    static func warning(_ warning: VisaWarning) -> String {
        switch warning {
        case let .passportExpiresDuringTrip(date):
            return "Pasaport seyahat bitmeden sona eriyor (\(AppFormat.shortDate(date))). Yenilemen gerekiyor."
        case let .passportValidityShort(months, mandatory, _):
            return mandatory
                ? "Pasaport dönüşten sonra en az \(months) ay geçerli olmalı."
                : "Pasaportun dönüşten sonra \(months) aydan az geçerli; bazı havayolları ve sınır kapıları sorun çıkarabilir."
        case let .stayExceedsLimit(maxDays, tripDays):
            return "Seyahat \(tripDays) gün; vizesiz kalış sınırı \(maxDays) gün."
        case let .heldVisaExpiresDuringTrip(zone, until):
            return "\(zoneName(zone)) vizen seyahat bitmeden sona eriyor (\(AppFormat.shortDate(until)))."
        }
    }

    static func documents(for zone: VisaZone?) -> [String] {
        var list = [
            "Başvuru formu",
            "Biyometrik fotoğraf",
            "Pasaport ve eski vizelerin fotokopisi",
            "Uçak rezervasyonu",
            "Konaklama rezervasyonu",
            "Son 3 ayın banka hesap dökümü",
            "İşveren yazısı / SGK dökümü veya öğrenci belgesi",
        ]
        if zone == .schengen {
            list.insert("En az 30.000 € teminatlı seyahat sağlık sigortası", at: 4)
        }
        return list
    }
}
