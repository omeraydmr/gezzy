import Foundation

/// Türkiye'den sık uçulan havalimanları: IATA kodu → şehir, ülke, saat dilimi.
/// Rezervasyon içe aktarmada uçuşun şehir ve yerel saatlerini doldurmak için.
public enum Airports {
    public struct Airport: Hashable, Sendable {
        public var code: String
        public var city: String
        public var countryCode: String
        public var timeZone: String
    }

    public static func airport(_ code: String) -> Airport? {
        table[code.uppercased()]
    }

    static let table: [String: Airport] = {
        let rows: [(String, String, String, String)] = [
            ("IST", "İstanbul", "TR", "Europe/Istanbul"), ("SAW", "İstanbul", "TR", "Europe/Istanbul"),
            ("ESB", "Ankara", "TR", "Europe/Istanbul"), ("ADB", "İzmir", "TR", "Europe/Istanbul"),
            ("AYT", "Antalya", "TR", "Europe/Istanbul"), ("DLM", "Dalaman", "TR", "Europe/Istanbul"),
            ("BJV", "Bodrum", "TR", "Europe/Istanbul"), ("TZX", "Trabzon", "TR", "Europe/Istanbul"),
            ("LIS", "Lizbon", "PT", "Europe/Lisbon"), ("OPO", "Porto", "PT", "Europe/Lisbon"),
            ("CDG", "Paris", "FR", "Europe/Paris"), ("ORY", "Paris", "FR", "Europe/Paris"), ("NCE", "Nice", "FR", "Europe/Paris"),
            ("LYS", "Lyon", "FR", "Europe/Paris"),
            ("FCO", "Roma", "IT", "Europe/Rome"), ("CIA", "Roma", "IT", "Europe/Rome"), ("MXP", "Milano", "IT", "Europe/Rome"),
            ("LIN", "Milano", "IT", "Europe/Rome"), ("BGY", "Bergamo", "IT", "Europe/Rome"), ("VCE", "Venedik", "IT", "Europe/Rome"),
            ("NAP", "Napoli", "IT", "Europe/Rome"), ("BLQ", "Bologna", "IT", "Europe/Rome"), ("FLR", "Floransa", "IT", "Europe/Rome"),
            ("BCN", "Barselona", "ES", "Europe/Madrid"), ("MAD", "Madrid", "ES", "Europe/Madrid"),
            ("VLC", "Valensiya", "ES", "Europe/Madrid"), ("AGP", "Malaga", "ES", "Europe/Madrid"),
            ("PMI", "Palma", "ES", "Europe/Madrid"), ("SVQ", "Sevilla", "ES", "Europe/Madrid"),
            ("LHR", "Londra", "GB", "Europe/London"), ("LGW", "Londra", "GB", "Europe/London"),
            ("STN", "Londra", "GB", "Europe/London"), ("LTN", "Londra", "GB", "Europe/London"),
            ("MAN", "Manchester", "GB", "Europe/London"), ("EDI", "Edinburgh", "GB", "Europe/London"),
            ("AMS", "Amsterdam", "NL", "Europe/Amsterdam"), ("EIN", "Eindhoven", "NL", "Europe/Amsterdam"),
            ("BRU", "Brüksel", "BE", "Europe/Brussels"), ("CRL", "Brüksel", "BE", "Europe/Brussels"),
            ("FRA", "Frankfurt", "DE", "Europe/Berlin"), ("MUC", "Münih", "DE", "Europe/Berlin"),
            ("BER", "Berlin", "DE", "Europe/Berlin"), ("HAM", "Hamburg", "DE", "Europe/Berlin"),
            ("DUS", "Düsseldorf", "DE", "Europe/Berlin"), ("CGN", "Köln", "DE", "Europe/Berlin"),
            ("STR", "Stuttgart", "DE", "Europe/Berlin"),
            ("VIE", "Viyana", "AT", "Europe/Vienna"), ("ZRH", "Zürih", "CH", "Europe/Zurich"),
            ("GVA", "Cenevre", "CH", "Europe/Zurich"), ("BSL", "Basel", "CH", "Europe/Zurich"),
            ("PRG", "Prag", "CZ", "Europe/Prague"), ("BUD", "Budapeşte", "HU", "Europe/Budapest"),
            ("WAW", "Varşova", "PL", "Europe/Warsaw"), ("KRK", "Krakov", "PL", "Europe/Warsaw"),
            ("ATH", "Atina", "GR", "Europe/Athens"), ("SKG", "Selanik", "GR", "Europe/Athens"),
            ("CPH", "Kopenhag", "DK", "Europe/Copenhagen"), ("ARN", "Stockholm", "SE", "Europe/Stockholm"),
            ("OSL", "Oslo", "NO", "Europe/Oslo"), ("HEL", "Helsinki", "FI", "Europe/Helsinki"),
            ("DUB", "Dublin", "IE", "Europe/Dublin"), ("KEF", "Reykjavik", "IS", "Atlantic/Reykjavik"),
            ("OTP", "Bükreş", "RO", "Europe/Bucharest"), ("SOF", "Sofya", "BG", "Europe/Sofia"),
            ("BEG", "Belgrad", "RS", "Europe/Belgrade"), ("SJJ", "Saraybosna", "BA", "Europe/Sarajevo"),
            ("SKP", "Üsküp", "MK", "Europe/Skopje"), ("TIA", "Tiran", "AL", "Europe/Tirane"),
            ("PRN", "Priştine", "XK", "Europe/Belgrade"), ("TGD", "Podgorica", "ME", "Europe/Podgorica"),
            ("ZAG", "Zagreb", "HR", "Europe/Zagreb"), ("DBV", "Dubrovnik", "HR", "Europe/Zagreb"),
            ("SPU", "Split", "HR", "Europe/Zagreb"), ("LJU", "Ljubljana", "SI", "Europe/Ljubljana"),
            ("TBS", "Tiflis", "GE", "Asia/Tbilisi"), ("BUS", "Batum", "GE", "Asia/Tbilisi"),
            ("GYD", "Bakü", "AZ", "Asia/Baku"), ("EVN", "Erivan", "AM", "Asia/Yerevan"),
            ("RAK", "Marakeş", "MA", "Africa/Casablanca"), ("CMN", "Kazablanka", "MA", "Africa/Casablanca"),
            ("TUN", "Tunus", "TN", "Africa/Tunis"), ("CAI", "Kahire", "EG", "Africa/Cairo"),
            ("DXB", "Dubai", "AE", "Asia/Dubai"), ("DOH", "Doha", "QA", "Asia/Qatar"),
            ("JFK", "New York", "US", "America/New_York"), ("EWR", "New York", "US", "America/New_York"),
            ("ORD", "Chicago", "US", "America/Chicago"), ("LAX", "Los Angeles", "US", "America/Los_Angeles"),
            ("MIA", "Miami", "US", "America/New_York"), ("YYZ", "Toronto", "CA", "America/Toronto"),
            ("NRT", "Tokyo", "JP", "Asia/Tokyo"), ("HND", "Tokyo", "JP", "Asia/Tokyo"), ("KIX", "Osaka", "JP", "Asia/Tokyo"),
            ("ICN", "Seul", "KR", "Asia/Seoul"), ("BKK", "Bangkok", "TH", "Asia/Bangkok"),
            ("SIN", "Singapur", "SG", "Asia/Singapore"), ("KUL", "Kuala Lumpur", "MY", "Asia/Kuala_Lumpur"),
            ("DPS", "Bali", "ID", "Asia/Makassar"), ("GRU", "São Paulo", "BR", "America/Sao_Paulo"),
            ("EZE", "Buenos Aires", "AR", "America/Argentina/Buenos_Aires"),
        ]
        var map: [String: Airport] = [:]
        for (code, city, country, zone) in rows {
            map[code] = Airport(code: code, city: city, countryCode: country, timeZone: zone)
        }
        return map
    }()
}
