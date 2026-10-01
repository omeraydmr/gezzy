import Foundation

/// Wallet biniş kartından (`.pkpass`) uçuş adayı çıkarır. Önce `pass.json`'daki anlamsal etiketlere
/// (iOS 15+ `semantics`), sonra kart alanlarına bakar; ikisi de yetmezse alan metinlerini `BookingParser`'a verir.
public enum PassParser {
    /// `.pkpass` arşivini okur; arşiv ya da `pass.json` açılamazsa nil.
    public static func parse(pkpass data: Data, now: Date = Date(), calendar: Calendar = .current) -> BookingParser.Result? {
        guard let archive = ZipArchive(data: data), let json = archive.contents(of: "pass.json") else { return nil }
        return parse(passJSON: json, now: now, calendar: calendar)
    }

    public static func parse(passJSON data: Data, now: Date = Date(), calendar: Calendar = .current) -> BookingParser.Result? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let style = ["boardingPass", "eventTicket", "generic", "storeCard", "coupon"]
            .lazy.compactMap { root[$0] as? [String: Any] }.first ?? [:]
        let fields = ["headerFields", "primaryFields", "secondaryFields", "auxiliaryFields", "backFields"]
            .flatMap { (style[$0] as? [[String: Any]] ?? []).map(Field.init) }
        let semantics = root["semantics"] as? [String: Any] ?? [:]

        if let flight = flight(semantics: semantics, fields: fields, relevantDate: date(root["relevantDate"])) {
            return BookingParser.Result(flights: [flight], lodgings: [])
        }
        // Yapı tanınmadı: alanları metne çevirip genel ayrıştırıcıya ver.
        var lines = fields.map { [$0.label, $0.value].filter { !$0.isEmpty }.joined(separator: ": ") }
        if let relevant = root["relevantDate"] as? String { lines.append(relevant) }
        if let description = root["description"] as? String { lines.insert(description, at: 0) }
        return BookingParser.parse(lines.joined(separator: "\n"), now: now, calendar: calendar)
    }

    struct Field {
        var key: String
        var label: String
        var value: String
        var rawValue: Any?

        init(_ dictionary: [String: Any]) {
            key = (dictionary["key"] as? String ?? "").lowercased()
            label = dictionary["label"] as? String ?? ""
            rawValue = dictionary["value"]
            switch dictionary["value"] {
            case let text as String: value = text
            case let number as NSNumber: value = number.stringValue
            default: value = ""
            }
        }

        func mentions(_ words: [String]) -> Bool {
            let haystack = (key + " " + label).lowercased(with: Locale(identifier: "tr_TR"))
            return words.contains { haystack.contains($0) }
        }
    }

    static func flight(semantics: [String: Any], fields: [Field], relevantDate: Date?) -> BookingParser.FlightCandidate? {
        // Havalimanı kodları
        var from = (semantics["departureAirportCode"] as? String)?.uppercased()
        var to = (semantics["destinationAirportCode"] as? String)?.uppercased()
        if from == nil || to == nil {
            let codes = fields.filter { isAirportCode($0.value) }
            let origin = codes.first { $0.mentions(["origin", "depart", "from", "kalkış", "nereden"]) }
            let destination = codes.first { $0.mentions(["dest", "arriv", "to", "varış", "nereye"]) && $0.key != origin?.key }
            if let origin, let destination {
                from = origin.value.uppercased()
                to = destination.value.uppercased()
            } else if codes.count >= 2 {
                from = codes[0].value.uppercased()
                to = codes[1].value.uppercased()
            }
        }
        guard let from, let to, from != to else { return nil }

        // Uçuş numarası
        var number = (semantics["flightCode"] as? String).map(normalizedFlightNumber)
        if number == nil, let airline = semantics["airlineCode"] as? String, let digits = semantics["flightNumber"] {
            number = normalizedFlightNumber("\(airline)\(digits)")
        }
        if number == nil {
            let ordered = fields.filter { $0.mentions(["flight", "uçuş", "sefer", "vol"]) } + fields
            number = ordered.lazy.compactMap { flightNumber(in: $0.value) }.first
        }
        guard let number else { return nil }

        // Saatler
        let semanticDeparture = date(semantics["currentDepartureDate"]) ?? date(semantics["originalDepartureDate"])
        let semanticArrival = date(semantics["currentArrivalDate"]) ?? date(semantics["originalArrivalDate"])
        let fieldDeparture = fields.first { $0.mentions(["depart", "kalkış"]) && date($0.rawValue) != nil }.flatMap { date($0.rawValue) }
        let fieldArrival = fields.first { $0.mentions(["arriv", "varış", "iniş"]) && date($0.rawValue) != nil }.flatMap { date($0.rawValue) }
        guard let departure = semanticDeparture ?? fieldDeparture ?? relevantDate else { return nil }
        var arrival = semanticArrival ?? fieldArrival
        if let value = arrival, value <= departure { arrival = nil }

        return BookingParser.FlightCandidate(flightNumber: number, fromCode: from, toCode: to, departure: departure,
                                             arrival: arrival ?? departure.addingTimeInterval(3 * 3600),
                                             hasTimes: (semanticDeparture ?? fieldDeparture) != nil && arrival != nil,
                                             seat: seat(semantics: semantics, fields: fields))
    }

    static func seat(semantics: [String: Any], fields: [Field]) -> String? {
        if let seats = semantics["seats"] as? [[String: Any]], let first = seats.first {
            if let identifier = first["seatIdentifier"] as? String, !identifier.isEmpty { return identifier.uppercased() }
            let row = first["seatRow"].map { "\($0)" } ?? ""
            let number = first["seatNumber"].map { "\($0)" } ?? ""
            if !(row + number).isEmpty { return (row + number).uppercased() }
        }
        let value = fields.first { $0.mentions(["seat", "koltuk"]) }?.value.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? nil : value.uppercased()
    }

    static func isAirportCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.count == 3 && trimmed.allSatisfy { $0.isASCII && $0.isUppercase }
    }

    static func normalizedFlightNumber(_ text: String) -> String {
        text.uppercased().filter { !$0.isWhitespace }
    }

    static func flightNumber(in text: String) -> String? {
        let upper = text.uppercased()
        for match in BookingParser.matches(#"\b([A-Z0-9]{2})\s?(\d{1,4})\b"#, in: upper) {
            guard let airline = BookingParser.group(match, 1, in: upper), BookingParser.airlines.contains(airline),
                  let digits = BookingParser.group(match, 2, in: upper) else { continue }
            return airline + digits
        }
        return nil
    }

    /// Pass dosyalarındaki W3C tarihleri: saniyeli ya da saniyesiz, saat dilimli.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, text.count >= 16, text.contains("T") else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        // 2026-10-12T07:40+03:00 → saniye ekle
        let index = text.index(text.startIndex, offsetBy: 16)
        return ISO8601DateFormatter().date(from: String(text[..<index]) + ":00" + String(text[index...]))
    }
}
