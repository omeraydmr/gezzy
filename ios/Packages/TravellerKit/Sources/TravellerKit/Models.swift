import Foundation

// MARK: - Enums

/// Harcama ve bütçe kategorileri. Renkleri tasarım dilinde sabittir.
public enum SpendCategory: String, Codable, CaseIterable, Hashable, Sendable {
    case stays, transport, food, activities, other
}

public enum MemberRole: String, Codable, CaseIterable, Hashable, Sendable {
    case owner, editor, viewer
}

/// Türk pasaport türleri. Vize veri seti şimdilik yalnızca umuma mahsus (bordo) pasaportu kapsar.
public enum PassportType: String, Codable, CaseIterable, Hashable, Sendable {
    case ordinary, special, service
}

/// Kullanıcının elinde olabilecek ve başka ülkelere girişte de işe yarayan vize bölgeleri.
public enum VisaZone: String, Codable, CaseIterable, Hashable, Sendable {
    case schengen, uk, us, canada
}

public enum StopKind: String, Codable, CaseIterable, Hashable, Sendable {
    case sight, food, activity, transport, stay
}

public enum TripStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case draft, planned
}

// MARK: - People

public struct HeldVisa: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var zone: VisaZone
    public var validUntil: Date
    public var multipleEntry: Bool

    public init(id: UUID = UUID(), zone: VisaZone, validUntil: Date, multipleEntry: Bool = true) {
        self.id = id
        self.zone = zone
        self.validUntil = validUntil
        self.multipleEntry = multipleEntry
    }
}

public struct Passport: Codable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2, ör. "TR".
    public var nationality: String
    public var type: PassportType
    public var expiresOn: Date
    public var heldVisas: [HeldVisa]

    public init(nationality: String = "TR", type: PassportType = .ordinary, expiresOn: Date, heldVisas: [HeldVisa] = []) {
        self.nationality = nationality
        self.type = type
        self.expiresOn = expiresOn
        self.heldVisas = heldVisas
    }
}

public struct Member: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var role: MemberRole
    /// Avatar ve kişi bazlı grafiklerde kullanılan palet sırası.
    public var colorIndex: Int
    public var passport: Passport?

    public init(id: UUID = UUID(), name: String, role: MemberRole = .editor, colorIndex: Int = 0, passport: Passport? = nil) {
        self.id = id
        self.name = name
        self.role = role
        self.colorIndex = colorIndex
        self.passport = passport
    }

    public var initial: String {
        guard let first = name.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased(with: Locale(identifier: "tr_TR"))
    }
}

// MARK: - Plan

public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct Destination: Codable, Hashable, Sendable {
    /// ISO 3166-1 alpha-2, ör. "PT".
    public var countryCode: String
    public var city: String
    public var coordinate: Coordinate?

    public init(countryCode: String, city: String, coordinate: Coordinate? = nil) {
        self.countryCode = countryCode
        self.city = city
        self.coordinate = coordinate
    }
}

public struct FlightSegment: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var flightNumber: String
    public var fromCode: String
    public var fromCity: String
    public var toCode: String
    public var toCity: String
    public var departure: Date
    public var arrival: Date
    /// Kalkış ve varış saatleri havalimanının yerel saatinde gösterilir (IANA kimliği, ör. "Europe/Lisbon").
    public var departureTimeZone: String?
    public var arrivalTimeZone: String?
    public var gate: String?
    public var seat: String?

    public init(id: UUID = UUID(), flightNumber: String, fromCode: String, fromCity: String, toCode: String, toCity: String,
                departure: Date, arrival: Date, departureTimeZone: String? = nil, arrivalTimeZone: String? = nil,
                gate: String? = nil, seat: String? = nil) {
        self.id = id
        self.flightNumber = flightNumber
        self.fromCode = fromCode
        self.fromCity = fromCity
        self.toCode = toCode
        self.toCity = toCity
        self.departure = departure
        self.arrival = arrival
        self.departureTimeZone = departureTimeZone
        self.arrivalTimeZone = arrivalTimeZone
        self.gate = gate
        self.seat = seat
    }

    public var durationMinutes: Int {
        max(0, Int(arrival.timeIntervalSince(departure) / 60))
    }
}

public struct Stop: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Durağın ait olduğu gün (gün başlangıcı).
    public var day: Date
    public var order: Int
    public var name: String
    public var kind: StopKind
    /// Gece yarısından itibaren dakika; nil ise saat belirlenmemiş.
    public var startMinutes: Int?
    public var durationMinutes: Int
    public var coordinate: Coordinate?
    public var note: String

    public init(id: UUID = UUID(), day: Date, order: Int, name: String, kind: StopKind, startMinutes: Int? = nil,
                durationMinutes: Int = 60, coordinate: Coordinate? = nil, note: String = "") {
        self.id = id
        self.day = day
        self.order = order
        self.name = name
        self.kind = kind
        self.startMinutes = startMinutes
        self.durationMinutes = durationMinutes
        self.coordinate = coordinate
        self.note = note
    }
}

// MARK: - Money

public struct Expense: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    /// Seyahat para biriminde, kuruş/cent cinsinden.
    public var amount: Int
    public var category: SpendCategory
    public var paidBy: UUID
    public var splitAmong: [UUID]
    public var date: Date
    /// Hesaplaşma ödemesi; bütçeye sayılmaz, sadece bakiyeleri etkiler.
    public var isTransfer: Bool

    public init(id: UUID = UUID(), title: String, amount: Int, category: SpendCategory, paidBy: UUID, splitAmong: [UUID],
                date: Date, isTransfer: Bool = false) {
        self.id = id
        self.title = title
        self.amount = amount
        self.category = category
        self.paidBy = paidBy
        self.splitAmong = splitAmong
        self.date = date
        self.isTransfer = isTransfer
    }
}

public struct BudgetLine: Codable, Hashable, Sendable {
    public var category: SpendCategory
    /// Kuruş/cent cinsinden limit.
    public var limit: Int

    public init(category: SpendCategory, limit: Int) {
        self.category = category
        self.limit = limit
    }
}

// MARK: - Packing

public struct PackingItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var assignee: UUID?
    public var isPacked: Bool

    public init(id: UUID = UUID(), title: String, assignee: UUID? = nil, isPacked: Bool = false) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.isPacked = isPacked
    }
}

// MARK: - Trip

public struct Trip: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var destination: Destination
    public var startDate: Date
    public var endDate: Date
    public var status: TripStatus
    /// ISO 4217, ör. "EUR".
    public var currency: String
    /// Kapak illüstrasyonu yer tutucusu için tohum.
    public var coverSeed: Int
    /// Kullanıcının seçtiği kapak fotoğrafının dosya adı (uygulama klasöründe). Eski kayıtlarda yoktur.
    public var coverPhoto: String?
    public var members: [Member]
    public var flights: [FlightSegment]
    public var stops: [Stop]
    public var budget: [BudgetLine]
    public var expenses: [Expense]
    public var packing: [PackingItem]

    public init(id: UUID = UUID(), name: String, destination: Destination, startDate: Date, endDate: Date,
                status: TripStatus = .planned, currency: String = "EUR", coverSeed: Int = 0, coverPhoto: String? = nil,
                members: [Member] = [],
                flights: [FlightSegment] = [], stops: [Stop] = [], budget: [BudgetLine] = [], expenses: [Expense] = [],
                packing: [PackingItem] = []) {
        self.id = id
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
        self.status = status
        self.currency = currency
        self.coverSeed = coverSeed
        self.coverPhoto = coverPhoto
        self.members = members
        self.flights = flights
        self.stops = stops
        self.budget = budget
        self.expenses = expenses
        self.packing = packing
    }

    /// Seyahatin her günü (gün başlangıçları), başlangıç ve bitiş dahil.
    public func days(calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return [start] }
        var result: [Date] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    public func nights(calendar: Calendar = .current) -> Int {
        max(0, days(calendar: calendar).count - 1)
    }

    public func stops(on day: Date, calendar: Calendar = .current) -> [Stop] {
        stops
            .filter { calendar.isDate($0.day, inSameDayAs: day) }
            .sorted { $0.order < $1.order }
    }

    public func member(_ id: UUID?) -> Member? {
        guard let id else { return nil }
        return members.first { $0.id == id }
    }

    /// İlk uçuş; ana ekrandaki biniş kartı için.
    public var primaryFlight: FlightSegment? {
        flights.min { $0.departure < $1.departure }
    }

    public func isPast(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: endDate) < calendar.startOfDay(for: now)
    }
}
