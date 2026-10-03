import Foundation

/// Bir uçuş servisinden alınan son durum: aşama, kapı, tahmini saatler.
public struct FlightLiveStatus: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, CaseIterable, Sendable {
        case scheduled, checkIn, boarding, gateClosed, departed, enRoute, approaching, arrived, delayed, canceled, diverted, unknown

        public var title: String {
            switch self {
            case .scheduled: String(localized: "Zamanında")
            case .checkIn: String(localized: "Check-in açık")
            case .boarding: String(localized: "Biniş")
            case .gateClosed: String(localized: "Kapı kapandı")
            case .departed: String(localized: "Kalktı")
            case .enRoute: String(localized: "Havada")
            case .approaching: String(localized: "İnişe geçti")
            case .arrived: String(localized: "İndi")
            case .delayed: String(localized: "Rötarlı")
            case .canceled: String(localized: "İptal")
            case .diverted: String(localized: "Yönlendirildi")
            case .unknown: String(localized: "Bilinmiyor")
            }
        }

        /// Uçak kalktıysa ya da uçuş bittiyse true.
        public var isAirborneOrDone: Bool {
            switch self {
            case .departed, .enRoute, .approaching, .arrived, .diverted: true
            default: false
            }
        }
    }

    public var phase: Phase
    public var departureGate: String?
    public var departureTerminal: String?
    public var estimatedDeparture: Date?
    public var estimatedArrival: Date?
    public var baggageBelt: String?
    public var fetchedAt: Date

    public init(phase: Phase, departureGate: String? = nil, departureTerminal: String? = nil, estimatedDeparture: Date? = nil,
                estimatedArrival: Date? = nil, baggageBelt: String? = nil, fetchedAt: Date = Date()) {
        self.phase = phase
        self.departureGate = departureGate
        self.departureTerminal = departureTerminal
        self.estimatedDeparture = estimatedDeparture
        self.estimatedArrival = estimatedArrival
        self.baggageBelt = baggageBelt
        self.fetchedAt = fetchedAt
    }
}

/// 15 dakikadan azı rötar sayılmaz (havayollarının "zamanında" tanımı).
public let flightDelayThresholdMinutes = 15

extension FlightSegment {
    /// Tahmini kalkış planlanandan kaç dakika geç (erken kalkışta 0).
    public var delayMinutes: Int {
        guard let estimated = live?.estimatedDeparture else { return 0 }
        return max(0, Int((estimated.timeIntervalSince(departure) / 60).rounded()))
    }

    public var isDelayed: Bool { delayMinutes >= flightDelayThresholdMinutes }

    /// Geri sayım ve kartlar için geçerli kalkış saati (rötar varsa tahmini).
    public var effectiveDeparture: Date { isDelayed ? live?.estimatedDeparture ?? departure : departure }

    public var effectiveArrival: Date {
        guard let estimated = live?.estimatedArrival, isDelayed || live?.phase.isAirborneOrDone == true else { return arrival }
        return estimated
    }

    /// Kısa durum etiketi: "Rötarlı +40 dk", "Biniş", "Zamanında".
    public var statusText: String? {
        guard let live else { return nil }
        if live.phase == .canceled { return live.phase.title }
        if isDelayed && !live.phase.isAirborneOrDone && live.phase != .boarding {
            return String(localized: "Rötarlı +\(delayMinutes) dk")
        }
        return live.phase == .delayed ? String(localized: "Rötarlı") : live.phase.title
    }

    /// Servisten gelen durumu uygular; kapı bilgisi geldiyse elle girilen kapının yerini alır.
    public func applying(_ status: FlightLiveStatus) -> FlightSegment {
        var copy = self
        copy.live = status
        if let gate = status.departureGate, !gate.isEmpty { copy.gate = gate }
        return copy
    }
}

// MARK: - Değişiklik bildirimi

public enum FlightStatusChange {
    /// Önceki ve yeni durum arasındaki önemli farklar: kapı, rötar, iptal, biniş.
    /// - Parameter time: kalkış saatini havalimanının saatiyle biçimlendirir.
    public static func describe(old: FlightSegment, new: FlightSegment, time: (Date) -> String) -> [String] {
        guard let status = new.live else { return [] }
        var lines: [String] = []
        let oldPhase = old.live?.phase

        if status.phase == .canceled {
            return oldPhase == .canceled ? [] : [String(localized: "Uçuş iptal edildi. Havayolunun bildirimini kontrol et.")]
        }
        if status.phase == .diverted && oldPhase != .diverted {
            lines.append(String(localized: "Uçuş başka bir havalimanına yönlendirildi."))
        }

        if let gate = new.gate, gate != old.gate {
            if let previous = old.gate {
                lines.append(String(localized: "Kapı değişti: \(previous) → \(gate)"))
            } else {
                lines.append(String(localized: "Kapı belli oldu: \(gate)"))
            }
        }

        let before = old.isDelayed ? old.delayMinutes : 0
        let after = new.isDelayed ? new.delayMinutes : 0
        if after > 0, abs(after - before) >= 10 {
            lines.append(String(localized: "Rötar: kalkış \(time(new.effectiveDeparture)) (+\(after) dk)"))
        } else if after == 0, before > 0, !status.phase.isAirborneOrDone {
            lines.append(String(localized: "Rötar kalktı, kalkış \(time(new.departure))"))
        }

        if status.phase == .boarding, oldPhase != .boarding {
            lines.append(new.gate.map { String(localized: "Biniş başladı · Kapı \($0)") } ?? String(localized: "Biniş başladı"))
        }
        return lines
    }
}

// MARK: - AeroDataBox

/// AeroDataBox `/flights/number/{numara}/{tarih}` yanıtını çözer.
public enum FlightStatusParser {
    public enum ParseError: Error { case invalid }

    /// Birden çok kayıt dönerse planlanan kalkışı bizimkine en yakın olanı seçer.
    public static func parseAeroDataBox(_ data: Data, scheduledDeparture: Date, now: Date = Date()) throws -> FlightLiveStatus? {
        guard let entries = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            if (try? JSONSerialization.jsonObject(with: data)) is [String: Any] { return nil }
            throw ParseError.invalid
        }
        let candidates = entries.compactMap { entry -> (entry: [String: Any], distance: TimeInterval)? in
            let departure = entry["departure"] as? [String: Any]
            guard let scheduled = time(departure?["scheduledTime"]) else { return (entry, .infinity) }
            return (entry, abs(scheduled.timeIntervalSince(scheduledDeparture)))
        }
        guard let best = candidates.min(by: { $0.distance < $1.distance }),
              best.distance < 18 * 3600 || candidates.count == 1 else { return nil }

        let entry = best.entry
        let departure = entry["departure"] as? [String: Any] ?? [:]
        let arrival = entry["arrival"] as? [String: Any] ?? [:]
        let estimatedDeparture = time(departure["revisedTime"]) ?? time(departure["predictedTime"]) ?? time(departure["runwayTime"])
        let estimatedArrival = time(arrival["revisedTime"]) ?? time(arrival["predictedTime"]) ?? time(arrival["runwayTime"])

        var current = phase(from: entry["status"] as? String)
        if current == .scheduled, let estimatedDeparture,
           estimatedDeparture.timeIntervalSince(scheduledDeparture) >= Double(flightDelayThresholdMinutes * 60) {
            current = .delayed
        }
        return FlightLiveStatus(phase: current,
                                departureGate: nonEmpty(departure["gate"]),
                                departureTerminal: nonEmpty(departure["terminal"]),
                                estimatedDeparture: estimatedDeparture,
                                estimatedArrival: estimatedArrival,
                                baggageBelt: nonEmpty(arrival["baggageBelt"]),
                                fetchedAt: now)
    }

    static func phase(from status: String?) -> FlightLiveStatus.Phase {
        switch (status ?? "").lowercased() {
        case "expected": .scheduled
        case "checkin": .checkIn
        case "boarding": .boarding
        case "gateclosed": .gateClosed
        case "departed": .departed
        case "enroute": .enRoute
        case "approaching": .approaching
        case "arrived": .arrived
        case "delayed": .delayed
        case "canceled", "cancelled", "canceleduncertain": .canceled
        case "diverted": .diverted
        default: .unknown
        }
    }

    /// `{"utc": "2026-10-03 06:45Z", "local": "..."}` biçimindeki zamanı çözer.
    static func time(_ value: Any?) -> Date? {
        guard let object = value as? [String: Any], var raw = object["utc"] as? String else { return nil }
        raw = raw.trimmingCharacters(in: .whitespaces)
        if raw.hasSuffix("Z") { raw.removeLast() }
        raw = raw.replacingOccurrences(of: "T", with: " ")
        for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        return text
    }

    /// Servise gönderilecek numara: boşluksuz, büyük harf ("TK 1759" → "TK1759").
    public static func normalizedNumber(_ flightNumber: String) -> String {
        flightNumber.uppercased().filter { $0.isLetter || $0.isNumber }
    }
}
