import Foundation

/// E-bilet ve otel onaylarının metninden (PDF metni ya da cihazda okunan ekran görüntüsü) uçuş ve
/// konaklama adayları çıkarır. Sezgiseldir: kullanıcı sonucu eklemeden önce görür ve düzeltir.
public enum BookingParser {
    public struct FlightCandidate: Hashable, Sendable {
        public var flightNumber: String
        public var fromCode: String
        public var toCode: String
        public var departure: Date
        public var arrival: Date
        /// Saat metinde bulunamadıysa false; kullanıcıya "saati kontrol et" denir.
        public var hasTimes: Bool
        public var seat: String?

        public func segment() -> FlightSegment {
            let from = Airports.airport(fromCode)
            let to = Airports.airport(toCode)
            return FlightSegment(flightNumber: flightNumber, fromCode: fromCode, fromCity: from?.city ?? fromCode,
                                 toCode: toCode, toCity: to?.city ?? toCode, departure: departure, arrival: arrival,
                                 departureTimeZone: from?.timeZone, arrivalTimeZone: to?.timeZone, seat: seat)
        }
    }

    public struct LodgingCandidate: Hashable, Sendable {
        public var name: String
        public var address: String
        public var checkIn: Date
        public var checkOut: Date
        public var confirmation: String

        public func lodging() -> Lodging {
            Lodging(name: name, address: address, checkIn: checkIn, checkOut: checkOut, confirmation: confirmation)
        }
    }

    public struct Result: Hashable, Sendable {
        public var flights: [FlightCandidate]
        public var lodgings: [LodgingCandidate]
        public var isEmpty: Bool { flights.isEmpty && lodgings.isEmpty }
    }

    /// - Parameters:
    ///   - now: yılı yazılmamış tarihler için referans (geçmişte kalıyorsa sonraki yıl alınır).
    ///   - calendar: saat dilimi bilinmeyen tarihler için.
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        let source = text.replacingOccurrences(of: "\r", with: "\n")
        let dates = findDates(in: source, now: now, calendar: calendar)
        let times = findTimes(in: source, excluding: dates.map(\.range))
        return Result(flights: flights(in: source, dates: dates, times: times, calendar: calendar),
                      lodgings: lodgings(in: source, dates: dates, times: times, calendar: calendar))
    }

    // MARK: - Tokens

    struct DayToken: Hashable {
        var year: Int
        var month: Int
        var day: Int
        var range: NSRange
    }

    struct TimeToken: Hashable {
        var hour: Int
        var minute: Int
        var range: NSRange
    }

    static let monthNames: [String: Int] = [
        "oca": 1, "ocak": 1, "sub": 2, "subat": 2, "mar": 3, "mart": 3, "nis": 4, "nisan": 4, "may": 5, "mayis": 5,
        "haz": 6, "haziran": 6, "tem": 7, "temmuz": 7, "agu": 8, "agustos": 8, "eyl": 9, "eylul": 9, "eki": 10, "ekim": 10,
        "kas": 11, "kasim": 11, "ara": 12, "aralik": 12,
        "jan": 1, "january": 1, "feb": 2, "february": 2, "march": 3, "apr": 4, "april": 4, "jun": 6, "june": 6,
        "jul": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    static func month(_ word: String) -> Int? {
        let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
        return monthNames[folded]
    }

    static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    static func findDates(in text: String, now: Date, calendar: Calendar) -> [DayToken] {
        var tokens: [DayToken] = []
        let currentYear = calendar.component(.year, from: now)

        func add(day: Int, month: Int, year: Int?, range: NSRange) {
            guard (1...12).contains(month), (1...31).contains(day) else { return }
            var resolvedYear = year.map { $0 < 100 ? 2000 + $0 : $0 } ?? currentYear
            if year == nil, let candidate = calendar.date(from: DateComponents(year: resolvedYear, month: month, day: day)),
               candidate < calendar.date(byAdding: .day, value: -30, to: now) ?? now {
                resolvedYear += 1
            }
            guard calendar.date(from: DateComponents(year: resolvedYear, month: month, day: day)) != nil else { return }
            if tokens.contains(where: { NSIntersectionRange($0.range, range).length > 0 }) { return }
            tokens.append(DayToken(year: resolvedYear, month: month, day: day, range: range))
        }

        // 2026-10-12
        for m in matches(#"\b(\d{4})-(\d{2})-(\d{2})\b"#, in: text) {
            add(day: Int(group(m, 3, in: text)!)!, month: Int(group(m, 2, in: text)!)!, year: Int(group(m, 1, in: text)!), range: m.range)
        }
        // 12.10.2026, 12/10/26, 12-10-2026
        for m in matches(#"\b(\d{1,2})[./-](\d{1,2})[./-](\d{4}|\d{2})\b"#, in: text) {
            add(day: Int(group(m, 1, in: text)!)!, month: Int(group(m, 2, in: text)!)!, year: Int(group(m, 3, in: text)!), range: m.range)
        }
        // 12 Eki 2026, 12OCT26, 12 October
        let word = "([A-Za-zÇĞİÖŞÜçğıöşü]{3,9})"
        for m in matches(#"\b(\d{1,2})\s?"# + word + #"\.?,?\s?(\d{4}|\d{2}(?![:.\d]))?"#, in: text) {
            guard let monthValue = month(group(m, 2, in: text) ?? "") else { continue }
            add(day: Int(group(m, 1, in: text)!)!, month: monthValue, year: group(m, 3, in: text).flatMap { Int($0) }, range: m.range)
        }
        // Oct 12, 2026
        for m in matches(word + #"\.?\s(\d{1,2}),?\s(\d{4})\b"#, in: text) {
            guard let monthValue = month(group(m, 1, in: text) ?? "") else { continue }
            add(day: Int(group(m, 2, in: text)!)!, month: monthValue, year: Int(group(m, 3, in: text)!), range: m.range)
        }
        return tokens.sorted { $0.range.location < $1.range.location }
    }

    static func findTimes(in text: String, excluding excluded: [NSRange]) -> [TimeToken] {
        matches(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#, in: text).compactMap { m in
            guard !excluded.contains(where: { NSIntersectionRange($0, m.range).length > 0 }) else { return nil }
            return TimeToken(hour: Int(group(m, 1, in: text)!)!, minute: Int(group(m, 2, in: text)!)!, range: m.range)
        }
    }

    static func date(_ day: DayToken, hour: Int, minute: Int, timeZone: String?, calendar: Calendar) -> Date? {
        var cal = calendar
        if let zone = timeZone.flatMap(TimeZone.init(identifier:)) { cal.timeZone = zone }
        return cal.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))
    }

    // MARK: - Flights

    /// Bilinen havayolu kodları (yanlış eşleşmeleri azaltmak için).
    static let airlines: Set<String> = [
        "TK", "PC", "VF", "XQ", "AJ", "KK", "FR", "U2", "W6", "W4", "LH", "AF", "KL", "BA", "IB", "VY", "TP", "LX", "OS",
        "SN", "AZ", "A3", "LO", "SK", "AY", "EI", "EK", "QR", "EY", "KC", "J2", "PS", "B2", "FZ", "G9", "UA", "DL", "AA",
        "AC", "JL", "NH", "TG", "SQ", "EW", "HV", "DY", "LS", "OU", "JU", "RO", "FB", "4U", "8Q", "ZF", "WK", "BT", "OK",
    ]

    static func flights(in text: String, dates: [DayToken], times: [TimeToken], calendar: Calendar) -> [FlightCandidate] {
        let upper = text.uppercased(with: Locale(identifier: "en_US"))
        let numbers = matches(#"\b([A-Z0-9]{2})\s?(\d{2,4})\b"#, in: upper).compactMap { m -> (code: String, range: NSRange)? in
            guard let airline = group(m, 1, in: upper), airlines.contains(airline),
                  airline.contains(where: \.isLetter), let digits = group(m, 2, in: upper) else { return nil }
            return (airline + digits, m.range)
        }
        let routes = routes(in: upper)
        guard !numbers.isEmpty, !routes.isEmpty else { return [] }

        var result: [FlightCandidate] = []
        for (index, number) in numbers.enumerated() {
            let blockEnd = index + 1 < numbers.count ? numbers[index + 1].range.location : (upper as NSString).length
            let previousEnd = index > 0 ? numbers[index - 1].range.location + numbers[index - 1].range.length : 0
            let blockStart = max(previousEnd, number.range.location - 160)

            // Önce uçuş numarasından sonrasına bakılır (genelde rota/tarih/saat onu izler), yoksa öncesine.
            func pick<T>(_ items: [T], location: (T) -> Int) -> T? {
                items.first { location($0) >= number.range.location && location($0) < blockEnd }
                    ?? items.last { location($0) >= blockStart && location($0) < number.range.location }
            }
            guard let route = pick(routes, location: { $0.range.location }),
                  let day = pick(dates, location: { $0.range.location }) else { continue }

            var blockTimes = times.filter { $0.range.location >= number.range.location && $0.range.location < blockEnd }
            if blockTimes.count < 2 {
                let anchor = min(number.range.location, route.range.location, day.range.location)
                blockTimes = times.filter { $0.range.location >= anchor && $0.range.location < blockEnd }
            }
            let from = Airports.airport(route.from)
            let to = Airports.airport(route.to)
            let hasTimes = blockTimes.count >= 2
            let depTime = blockTimes.first.map { ($0.hour, $0.minute) } ?? (12, 0)
            guard let departure = date(day, hour: depTime.0, minute: depTime.1, timeZone: from?.timeZone, calendar: calendar)
            else { continue }
            let arrival: Date
            if hasTimes, var arr = date(day, hour: blockTimes[1].hour, minute: blockTimes[1].minute,
                                        timeZone: to?.timeZone, calendar: calendar) {
                if arr <= departure { arr = arr.addingTimeInterval(24 * 3600) }
                arrival = arr
            } else {
                arrival = departure.addingTimeInterval(3 * 3600)
            }
            let blockText = (upper as NSString).substring(with: NSRange(location: number.range.location,
                                                                        length: blockEnd - number.range.location))
            let seat = matches(#"(?:SEAT|KOLTUK)\s*(?:NO\.?)?\s*[:#]?\s*(\d{1,2}[A-K])\b"#, in: blockText)
                .first.flatMap { group($0, 1, in: blockText) }

            let candidate = FlightCandidate(flightNumber: number.code, fromCode: route.from, toCode: route.to,
                                            departure: departure, arrival: arrival, hasTimes: hasTimes, seat: seat)
            if !result.contains(where: { $0.flightNumber == candidate.flightNumber
                && calendar.isDate($0.departure, inSameDayAs: candidate.departure) }) {
                result.append(candidate)
            }
        }
        return result
    }

    struct Route {
        var from: String
        var to: String
        var range: NSRange
    }

    static func routes(in upper: String) -> [Route] {
        var routes: [Route] = []
        // IST - LIS, SAW→BCN, IST/LIS
        for m in matches(#"\b([A-Z]{3})\s?(?:-|–|—|→|>|/|TO)\s?([A-Z]{3})\b"#, in: upper) {
            guard let a = group(m, 1, in: upper), let b = group(m, 2, in: upper),
                  Airports.airport(a) != nil || Airports.airport(b) != nil, a != b else { continue }
            routes.append(Route(from: a, to: b, range: m.range))
        }
        // İstanbul (IST) ... Lizbon (LIS): aynı satırda ya da art arda iki parantezli kod
        let codes = matches(#"\(([A-Z]{3})\)"#, in: upper).compactMap { m -> (String, NSRange)? in
            group(m, 1, in: upper).map { ($0, m.range) }
        }
        for pair in zip(codes, codes.dropFirst()) where pair.0.0 != pair.1.0 {
            let gap = pair.1.1.location - (pair.0.1.location + pair.0.1.length)
            guard gap < 80, Airports.airport(pair.0.0) != nil || Airports.airport(pair.1.0) != nil,
                  !routes.contains(where: { NSIntersectionRange($0.range, pair.0.1).length > 0 }) else { continue }
            routes.append(Route(from: pair.0.0, to: pair.1.0, range: pair.0.1))
        }
        return routes.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Lodging

    static func lodgings(in text: String, dates: [DayToken], times: [TimeToken], calendar: Calendar) -> [LodgingCandidate] {
        let checkInWords = #"(?:check[\s-]?in|giriş tarihi|giriş|arrival|varış tarihi)"#
        let checkOutWords = #"(?:check[\s-]?out|çıkış tarihi|çıkış|ayrılış)"#
        guard let checkInKey = matches(checkInWords, in: text, options: .caseInsensitive).first,
              let checkOutKey = matches(checkOutWords, in: text, options: .caseInsensitive).first else { return [] }

        func dateAfter(_ key: NSTextCheckingResult) -> DayToken? {
            let end = key.range.location + key.range.length
            return dates.first { $0.range.location >= end && $0.range.location - end < 80 }
        }
        func timeAfter(_ day: DayToken) -> TimeToken? {
            let end = day.range.location + day.range.length
            return times.first { $0.range.location >= end && $0.range.location - end < 40 }
        }
        guard let inDay = dateAfter(checkInKey), let outDay = dateAfter(checkOutKey) else { return [] }
        let inTime = timeAfter(inDay).map { ($0.hour, $0.minute) } ?? (14, 0)
        let outTime = timeAfter(outDay).map { ($0.hour, $0.minute) } ?? (11, 0)
        guard let checkIn = date(inDay, hour: inTime.0, minute: inTime.1, timeZone: nil, calendar: calendar),
              let checkOut = date(outDay, hour: outTime.0, minute: outTime.1, timeZone: nil, calendar: calendar),
              checkOut > checkIn else { return [] }

        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let lodgingPattern = #"\b(hotel|otel|hostel|apart|apartments?|residence|suites?|inn|resort|pansiyon|guesthouse|lodge|palace)\b"#
        let skipWords = ["booking.com", "airbnb", "check", "giriş", "çıkış", "confirmation", "rezervasyon"]
        let name = lines.first { line in
            let lower = line.lowercased()
            return line.count <= 60 && !matches(lodgingPattern, in: line, options: .caseInsensitive).isEmpty
                && !skipWords.contains { lower.contains($0) }
        } ?? "Konaklama"

        let address = lines.first { $0.lowercased().hasPrefix("adres") || $0.lowercased().hasPrefix("address") }
            .map { line in
                line.split(separator: ":", maxSplits: 1).dropFirst().first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
            } ?? ""

        let confirmationPattern = #"(?:confirmation|booking|reservation|rezervasyon|onay|pnr)\s*(?:number|no\.?|numarası|kodu|code|id)?\s*[:#]?\s*([A-Z0-9]{5,14})\b"#
        let confirmation = matches(confirmationPattern, in: text, options: .caseInsensitive)
            .compactMap { group($0, 1, in: text) }
            .first { $0.contains(where: \.isNumber) } ?? ""

        return [LodgingCandidate(name: name, address: address, checkIn: checkIn, checkOut: checkOut, confirmation: confirmation)]
    }
}
