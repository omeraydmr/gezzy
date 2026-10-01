import Foundation

/// Bir ülkeye giriş kuralı (Türkiye Cumhuriyeti umuma mahsus pasaportu için).
public enum EntryRule: Hashable, Sendable {
    case visaFree(maxDays: Int)
    case eVisa
    case visaOnArrival(maxDays: Int?)
    case visaRequired(zone: VisaZone?)
}

public struct CountryEntry: Hashable, Sendable {
    public var code: String
    public var rule: EntryRule
    /// Dönüş tarihinden sonra pasaportun geçerli olması gereken/önerilen ay sayısı.
    public var passportValidityMonths: Int
    /// Değer yasal zorunluluk mu, yoksa genel tavsiye mi.
    public var validityIsMandatory: Bool
    /// Pasaport yerine yeni çipli kimlik kartıyla giriş mümkün mü.
    public var idCardAccepted: Bool
    public var note: String?

    public init(code: String, rule: EntryRule, passportValidityMonths: Int = 6, validityIsMandatory: Bool = false,
                idCardAccepted: Bool = false, note: String? = nil) {
        self.code = code
        self.rule = rule
        self.passportValidityMonths = passportValidityMonths
        self.validityIsMandatory = validityIsMandatory
        self.idCardAccepted = idCardAccepted
        self.note = note
    }
}

/// Türk vatandaşları için derlenmiş giriş kuralları.
///
/// ÖNEMLİ: Bu veri seti elle derlenmiştir ve yayından önce ve düzenli aralıklarla
/// https://www.konsolosluk.gov.tr üzerinden doğrulanmalıdır. Uygulama her zaman resmî
/// kaynağa yönlendirir ve son gözden geçirme tarihini gösterir.
public enum VisaRules {
    public static let lastReviewed = "2026-10"
    public static let officialSourceURL = URL(string: "https://www.konsolosluk.gov.tr")!

    /// Schengen bölgesi (29 ülke; Bulgaristan ve Romanya 2025'ten itibaren tam üye).
    public static let schengenCountries: Set<String> = [
        "AT", "BE", "BG", "HR", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IS", "IT", "LV",
        "LI", "LT", "LU", "MT", "NL", "NO", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "CH",
    ]

    public static let entries: [String: CountryEntry] = {
        var map: [String: CountryEntry] = [:]
        for code in schengenCountries {
            map[code] = CountryEntry(
                code: code, rule: .visaRequired(zone: .schengen), passportValidityMonths: 3, validityIsMandatory: true,
                note: "Schengen: 180 gün içinde en fazla 90 gün. Pasaport son 10 yıl içinde verilmiş olmalı.")
        }
        let others: [CountryEntry] = [
            CountryEntry(code: "GB", rule: .visaRequired(zone: .uk)),
            CountryEntry(code: "US", rule: .visaRequired(zone: .us)),
            CountryEntry(code: "CA", rule: .visaRequired(zone: .canada)),
            CountryEntry(code: "JP", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "GE", rule: .visaFree(maxDays: 365), idCardAccepted: true),
            CountryEntry(code: "AZ", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "RS", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "BA", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "ME", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "MK", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "AL", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "XK", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "MA", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "TN", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "BR", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "AR", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "MY", rule: .visaFree(maxDays: 90)),
            CountryEntry(code: "SG", rule: .visaFree(maxDays: 30)),
            CountryEntry(code: "ID", rule: .visaOnArrival(maxDays: 30), note: "Kapıda vize veya önceden e-VOA alınabilir."),
            CountryEntry(code: "AM", rule: .eVisa, note: "Başvuru öncesi güncel kuralları kontrol edin."),
        ]
        for entry in others { map[entry.code] = entry }
        return map
    }()

    public static func entry(for countryCode: String) -> CountryEntry? {
        entries[countryCode.uppercased()]
    }
}

// MARK: - Assessment

public enum VisaStatus: Hashable, Sendable {
    case domestic
    case notRequired(maxDays: Int)
    case eVisa
    case onArrival(maxDays: Int?)
    case required(zone: VisaZone?)
    case coveredByHeldVisa(zone: VisaZone, until: Date)
    case noPassport
    case unknown
}

public enum VisaWarning: Hashable, Sendable {
    /// Pasaport seyahat bitmeden sona eriyor.
    case passportExpiresDuringTrip(expiresOn: Date)
    /// Pasaport, dönüşten sonra gereken/önerilen süre kadar geçerli değil.
    case passportValidityShort(months: Int, mandatory: Bool, expiresOn: Date)
    /// Seyahat süresi vizesiz kalış limitini aşıyor.
    case stayExceedsLimit(maxDays: Int, tripDays: Int)
    /// Eldeki vize seyahat bitmeden sona eriyor.
    case heldVisaExpiresDuringTrip(zone: VisaZone, until: Date)
}

public struct VisaAssessment: Hashable, Sendable {
    public var status: VisaStatus
    public var warnings: [VisaWarning]
    public var entry: CountryEntry?

    /// Yolcunun harekete geçmesi gerekiyor mu (vize başvurusu, e-vize, pasaport yenileme).
    public var needsAction: Bool {
        switch status {
        case .required, .eVisa, .noPassport: return true
        default: return warnings.contains { warning in
            switch warning {
            case .passportExpiresDuringTrip, .stayExceedsLimit, .heldVisaExpiresDuringTrip: return true
            case let .passportValidityShort(_, mandatory, _): return mandatory
            }
        }
        }
    }
}

public enum VisaAdvisor {
    public static func assess(countryCode: String, passport: Passport?, tripStart: Date, tripEnd: Date,
                              calendar: Calendar = .current) -> VisaAssessment {
        let code = countryCode.uppercased()
        guard let passport else { return VisaAssessment(status: .noPassport, warnings: [], entry: nil) }
        if passport.nationality.uppercased() == code {
            return VisaAssessment(status: .domestic, warnings: [], entry: nil)
        }
        // Veri seti şimdilik yalnızca TC umuma mahsus pasaportu kapsıyor.
        guard passport.nationality.uppercased() == "TR", passport.type == .ordinary,
              let entry = VisaRules.entry(for: code)
        else {
            return VisaAssessment(status: .unknown, warnings: passportWarnings(passport: passport, entry: nil,
                                                                               tripEnd: tripEnd, calendar: calendar),
                                  entry: nil)
        }

        var warnings: [VisaWarning] = []
        let status: VisaStatus
        switch entry.rule {
        case let .visaFree(maxDays):
            status = .notRequired(maxDays: maxDays)
            let tripDays = (calendar.dateComponents([.day], from: calendar.startOfDay(for: tripStart),
                                                    to: calendar.startOfDay(for: tripEnd)).day ?? 0) + 1
            if tripDays > maxDays {
                warnings.append(.stayExceedsLimit(maxDays: maxDays, tripDays: tripDays))
            }
        case .eVisa:
            status = .eVisa
        case let .visaOnArrival(maxDays):
            status = .onArrival(maxDays: maxDays)
        case let .visaRequired(zone):
            let held = passport.heldVisas
                .filter { $0.zone == zone && $0.validUntil >= tripStart }
                .max { $0.validUntil < $1.validUntil }
            if let zone, let held {
                status = .coveredByHeldVisa(zone: zone, until: held.validUntil)
                if calendar.startOfDay(for: held.validUntil) < calendar.startOfDay(for: tripEnd) {
                    warnings.append(.heldVisaExpiresDuringTrip(zone: zone, until: held.validUntil))
                }
            } else {
                status = .required(zone: zone)
            }
        }

        warnings += passportWarnings(passport: passport, entry: entry, tripEnd: tripEnd, calendar: calendar)
        return VisaAssessment(status: status, warnings: warnings, entry: entry)
    }

    static func passportWarnings(passport: Passport, entry: CountryEntry?, tripEnd: Date,
                                 calendar: Calendar) -> [VisaWarning] {
        if calendar.startOfDay(for: passport.expiresOn) < calendar.startOfDay(for: tripEnd) {
            return [.passportExpiresDuringTrip(expiresOn: passport.expiresOn)]
        }
        let months = entry?.passportValidityMonths ?? 6
        let mandatory = entry?.validityIsMandatory ?? false
        if let required = calendar.date(byAdding: .month, value: months, to: tripEnd), passport.expiresOn < required {
            return [.passportValidityShort(months: months, mandatory: mandatory, expiresOn: passport.expiresOn)]
        }
        return []
    }
}
