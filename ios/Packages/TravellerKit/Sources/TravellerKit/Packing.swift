import Foundation

/// Kural tabanlı (yapay zekâ kullanmayan) valiz önerileri.
public enum PackingAdvisor {
    /// Türkiye'de kullanılan priz tipleri.
    public static let homePlugTypes: Set<String> = ["C", "F"]

    /// Ülke → priz tipleri. Listede olmayan ülkeler için adaptör önerilmez.
    public static let plugTypes: [String: Set<String>] = [
        "GB": ["G"], "MT": ["G"], "MY": ["G"], "SG": ["G"], "IE": ["G"], "CY": ["G"],
        "US": ["A", "B"], "CA": ["A", "B"], "JP": ["A", "B"], "MX": ["A", "B"],
        "AR": ["C", "I"], "BR": ["C", "N"], "CH": ["C", "J"], "IT": ["C", "F", "L"],
    ]

    /// Gidilen ülkede Türkiye'deki fişler kullanılamıyorsa gereken adaptör tipleri.
    public static func adapterTypes(for countryCode: String) -> [String]? {
        guard let types = plugTypes[countryCode.uppercased()], types.isDisjoint(with: homePlugTypes) else { return nil }
        return types.sorted()
    }

    /// Seyahat için önerilen maddeler; listede zaten bulunanlar (büyük/küçük harf duyarsız) çıkarılır.
    public static func suggestions(for trip: Trip, weather: WeatherSummary? = nil, now: Date = Date(),
                                   calendar: Calendar = .current) -> [String] {
        let country = trip.destination.countryCode.uppercased()
        let entry = VisaRules.entry(for: country)
        var items = ["Pasaport", "Telefon şarj aleti", "Powerbank"]

        if entry?.idCardAccepted == true {
            items.append("Kimlik kartı")
        }
        if let adapters = adapterTypes(for: country) {
            items.append("Priz adaptörü · Tip \(adapters.joined(separator: "/"))")
        }
        if VisaRules.schengenCountries.contains(country) {
            items.append("Seyahat sağlık sigortası poliçesi")
        }
        if case .visaRequired = entry?.rule {
            items.append("Vize ve başvuru belgelerinin kopyası")
        }
        if trip.flights.isEmpty == false {
            items.append("Biniş kartları")
        }
        if trip.nights(calendar: calendar) >= 5 {
            items.append("Küçük çamaşır torbası")
        }
        if let weather {
            items += weatherItems(weather)
        } else {
            let month = calendar.component(.month, from: trip.startDate)
            if (5...9).contains(month) {
                items.append("Güneş kremi")
            } else if month == 12 || month <= 2 {
                items.append("Bere ve eldiven")
            }
        }

        let existing = Set(trip.packing.map { normalize($0.title) })
        return items.filter { !existing.contains(normalize($0)) }
    }

    /// Hava özetine göre giyim ve ekipman önerileri.
    public static func weatherItems(_ weather: WeatherSummary) -> [String] {
        var items: [String] = []
        if weather.maxTemperature >= 24 {
            items += ["Güneş kremi", "Şapka", "Güneş gözlüğü"]
        }
        if weather.maxTemperature >= 28 {
            items.append("Matara")
        }
        if weather.minTemperature <= 8 {
            items.append("Mont")
        }
        if weather.minTemperature <= 3 {
            items.append("Bere ve eldiven")
        }
        if weather.maxTemperature - weather.minTemperature >= 12 {
            items.append("İnce hırka (katmanlı giyim)")
        }
        if weather.rainyDays > 0 {
            items.append(weather.rainyDays * 3 >= weather.dayCount ? "Yağmurluk" : "Katlanır şemsiye")
            items.append("Su geçirmez ayakkabı")
        }
        return items
    }

    static func normalize(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "tr_TR")).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
