import SwiftUI
import TravellerKit

struct VisaSection: View {
    let trip: Trip
    @Environment(TripStore.self) private var store
    @State private var focusedID: Member.ID?
    @State private var checkedDocuments: [Member.ID: Set<String>] = [:]

    private struct Row {
        let member: Member
        let result: VisaAssessment
    }

    private var assessments: [Row] {
        trip.members.map { member in
            Row(member: member, result: store.visaAssessment(for: member, in: trip))
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
                            withAnimation(.spring(duration: 0.35)) { focusedID = row.member.id }
                        } label: {
                            PassportCard(member: row.member, result: row.result,
                                         countryCode: trip.destination.countryCode)
                                .scaleEffect(row.member.id == focusedRow(rows)?.member.id ? 1 : 0.94)
                                .opacity(row.member.id == focusedRow(rows)?.member.id ? 1 : 0.7)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focusedID)
            .scrollClipDisabled()
            .animation(.spring(duration: 0.35), value: focusedID)

            if rows.count > 1 {
                HStack(spacing: 6) {
                    ForEach(rows, id: \.member.id) { row in
                        let isFocused = row.member.id == focusedRow(rows)?.member.id
                        Capsule()
                            .fill(isFocused ? Color.ink : Color.ink3.opacity(0.4))
                            .frame(width: isFocused ? 18 : 6, height: 6)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.spring(duration: 0.3), value: focusedID)
                .accessibilityHidden(true)
            }

            if let row = focusedRow(rows) {
                VisaDetailPanel(member: row.member, result: row.result,
                                checked: Binding(get: { checkedDocuments[row.member.id] ?? [] },
                                                 set: { checkedDocuments[row.member.id] = $0 }))
                    .id(row.member.id)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                if Schengen.isSchengen(trip.destination.countryCode) {
                    SchengenCard(member: row.member, trip: trip)
                        .id("schengen-\(row.member.id)")
                        .transition(.opacity)
                }
            }

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
    }

    private func focusedRow(_ rows: [Row]) -> Row? {
        rows.first { $0.member.id == focusedID } ?? rows.first
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
    var otherSchengenStays: [Schengen.Stay] = []

    var body: some View {
        let result = VisaAdvisor.assess(countryCode: countryCode, passport: passport, tripStart: start, tripEnd: end,
                                        otherSchengenStays: otherSchengenStays)
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

/// Odaktaki pasaportun detayı: pasaport bitişi, uyarılar ve gerekiyorsa belge listesi.
struct VisaDetailPanel: View {
    let member: Member
    let result: VisaAssessment
    @Binding var checked: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(member: member, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name).font(.tBodyStrong).foregroundStyle(Color.ink)
                    Text(VisaText.subtitle(result)).font(.tBody).foregroundStyle(Color.ink2)
                }
                Spacer(minLength: 8)
                let tag = VisaText.tag(result)
                Tag(text: tag.text, accent: tag.accent)
            }

            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(VisaText.warning(warning), systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.food)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.foodTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if case let .required(zone) = result.status {
                let documents = VisaText.documents(for: zone)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Belge listesi").font(.tCaption).foregroundStyle(Color.ink3)
                        Spacer()
                        Text("\(checked.intersection(documents).count)/\(documents.count)")
                            .font(.tCaption)
                            .foregroundStyle(Color.ink3)
                    }
                    ForEach(documents, id: \.self) { document in
                        let isDone = checked.contains(document)
                        Button {
                            withAnimation(.spring(duration: 0.2)) {
                                if isDone { checked.remove(document) } else { checked.insert(document) }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 20))
                                    .foregroundStyle(isDone ? Color.success : Color.ink3)
                                Text(document)
                                    .font(.subheadline)
                                    .foregroundStyle(isDone ? Color.ink3 : Color.ink)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Konsolosluğa ve başvuru amacına göre değişir; randevu ve güncel liste için yetkili aracı kurumu kontrol et.")
                        .font(.caption)
                        .foregroundStyle(Color.ink3)
                        .padding(.top, 4)
                }
            }
        }
        .tray()
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
        case let .schengenOverstay(firstDay, latestExit, days):
            let exit = latestExit.map { " En geç \(AppFormat.shortDate($0)) günü çıkmalısın." } ?? ""
            return "Schengen 90/180 sınırı \(AppFormat.shortDate(firstDay)) günü aşılıyor (\(days) gün fazla).\(exit)"
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
