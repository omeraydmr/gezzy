import XCTest
@testable import TravellerKit

final class BookingParserTests: XCTestCase {
    let cal = TestCalendar.calendar
    let now = TestCalendar.date(2026, 9, 1)

    func components(_ date: Date, _ zone: String) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    func testTurkishAirlinesTicketWithTwoSegments() {
        let text = """
        Turkish Airlines e-Bilet
        PNR: XK7Q2M
        TK 1759  İstanbul (IST) → Lizbon (LIS)
        12 Eki 2026  07:40 - 10:15
        Koltuk: 14C
        TK 1760  Lizbon (LIS) → İstanbul (IST)
        18 Eki 2026  11:20 - 17:05
        """
        let result = BookingParser.parse(text, now: now, calendar: cal)
        XCTAssertEqual(result.flights.count, 2)
        let outbound = result.flights[0]
        XCTAssertEqual(outbound.flightNumber, "TK1759")
        XCTAssertEqual(outbound.fromCode, "IST")
        XCTAssertEqual(outbound.toCode, "LIS")
        XCTAssertEqual(outbound.seat, "14C")
        XCTAssertTrue(outbound.hasTimes)
        let dep = components(outbound.departure, "Europe/Istanbul")
        XCTAssertEqual([dep.month, dep.day, dep.hour, dep.minute], [10, 12, 7, 40])
        let arr = components(outbound.arrival, "Europe/Lisbon")
        XCTAssertEqual([arr.hour, arr.minute], [10, 15])

        let segment = outbound.segment()
        XCTAssertEqual(segment.fromCity, "İstanbul")
        XCTAssertEqual(segment.toCity, "Lizbon")
        XCTAssertEqual(segment.arrivalTimeZone, "Europe/Lisbon")

        let inbound = result.flights[1]
        XCTAssertEqual(inbound.flightNumber, "TK1760")
        XCTAssertEqual(inbound.fromCode, "LIS")
        XCTAssertNil(inbound.seat)
        XCTAssertEqual(components(inbound.departure, "Europe/Lisbon").day, 18)
        XCTAssertTrue(result.lodgings.isEmpty)
    }

    func testCompactLineAndDateBeforeNumber() {
        let pegasus = BookingParser.parse("Pegasus\nPC 1201 SAW-BCN 12.10.2026 06:30 09:15", now: now, calendar: cal)
        XCTAssertEqual(pegasus.flights.map(\.flightNumber), ["PC1201"])
        XCTAssertEqual(pegasus.flights.first?.toCode, "BCN")

        let dateFirst = BookingParser.parse("12 October 2026\nLH1301 IST-AMS 08:00 10:05", now: now, calendar: cal)
        XCTAssertEqual(dateFirst.flights.first?.flightNumber, "LH1301")
        XCTAssertEqual(components(dateFirst.flights.first!.departure, "Europe/Istanbul").day, 12)
    }

    func testBookingConfirmationInEnglish() {
        let text = """
        Booking confirmation
        Hotel Alfama Lisbon
        Address: Rua dos Remédios 12, Lisbon
        Check-in: Monday, 12 October 2026 (from 15:00)
        Check-out: Sunday, 18 October 2026 (until 11:00)
        Confirmation number: 4583920175
        """
        let result = BookingParser.parse(text, now: now, calendar: cal)
        XCTAssertTrue(result.flights.isEmpty)
        let lodging = try? XCTUnwrap(result.lodgings.first)
        XCTAssertEqual(lodging?.name, "Hotel Alfama Lisbon")
        XCTAssertEqual(lodging?.address, "Rua dos Remédios 12, Lisbon")
        XCTAssertEqual(lodging?.confirmation, "4583920175")
        XCTAssertEqual(lodging.map { cal.dateComponents([.day, .hour], from: $0.checkIn) }?.day, 12)
        XCTAssertEqual(lodging.map { cal.dateComponents([.day, .hour], from: $0.checkIn) }?.hour, 15)
        XCTAssertEqual(lodging.map { cal.dateComponents([.day, .hour], from: $0.checkOut) }?.day, 18)
        XCTAssertEqual(lodging?.lodging().nights(calendar: cal), 6)
    }

    func testTurkishHotelConfirmation() {
        let text = """
        Otel Rezervasyon Onayı
        Pera Palace Otel
        Giriş: 3 Kas 2026 14:00
        Çıkış: 6 Kas 2026 12:00
        Rezervasyon No: AB12345
        """
        let lodging = BookingParser.parse(text, now: now, calendar: cal).lodgings.first
        XCTAssertEqual(lodging?.name, "Pera Palace Otel")
        XCTAssertEqual(lodging?.confirmation, "AB12345")
        XCTAssertEqual(lodging.map { cal.component(.hour, from: $0.checkOut) }, 12)
    }

    func testDatesWithoutYearRollForward() {
        // Eylül'de okunan "5 Mar" geçmişte kaldığı için gelecek yıl sayılır.
        let tokens = BookingParser.findDates(in: "5 Mar · 20 Eki", now: now, calendar: cal)
        XCTAssertEqual(tokens.map(\.year), [2027, 2026])
        XCTAssertEqual(tokens.map(\.month), [3, 10])
    }

    func testIgnoresTextWithoutBookings() {
        XCTAssertTrue(BookingParser.parse("Merhaba, 7 gece kalacağız. 10 kişiyiz.", now: now, calendar: cal).isEmpty)
    }
}
