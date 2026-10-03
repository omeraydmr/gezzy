import XCTest
@testable import TravellerKit

/// THY ve Pegasus Wallet kartlarının tipik düzeni (yolcu, PNR ve barkod sahte). Barkod IATA BCBP metnidir.
final class BoardingPassBarcodeTests: XCTestCase {
    let cal = TestCalendar.calendar
    let now = TestCalendar.date(2026, 9, 1)

    static let thyBarcode = "M1TEST/KISI           EABC123 ISTLISTK 1759 285Y014C00042100"
    static let pegasusBarcode = "M1TEST/KISI           EXYZ789 SAWKIXPC 1171 315Y021A00007100"
    static let connectionBarcode = "M2TEST/KISI           EABC123 SAWAMSPC 1251 285Y012A00003100ABC123 AMSLISKL 1691 285Y003F00011100"

    func local(_ date: Date, _ zone: String) -> [Int?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        return [parts.month, parts.day, parts.hour, parts.minute]
    }

    func testDecodesSingleLeg() throws {
        let leg = try XCTUnwrap(BoardingPassBarcode.parse(Self.thyBarcode).first)
        XCTAssertEqual(leg.pnr, "ABC123")
        XCTAssertEqual([leg.fromCode, leg.toCode], ["IST", "LIS"])
        XCTAssertEqual(leg.flightCode, "TK1759")
        XCTAssertEqual(leg.dayOfYear, 285)
        XCTAssertEqual(leg.seat, "14C")
        let day = try XCTUnwrap(leg.date(near: now, calendar: cal))
        XCTAssertEqual(cal.dateComponents([.year, .month, .day], from: day), DateComponents(year: 2026, month: 10, day: 12))
    }

    func testDecodesConnection() {
        let legs = BoardingPassBarcode.parse(Self.connectionBarcode)
        XCTAssertEqual(legs.map(\.flightCode), ["PC1251", "KL1691"])
        XCTAssertEqual(legs.map(\.toCode), ["AMS", "LIS"])
        XCTAssertEqual(legs.map(\.seat), ["12A", "3F"])
    }

    func testRejectsNonBCBP() {
        XCTAssertTrue(BoardingPassBarcode.parse("https://www.turkishairlines.com/checkin").isEmpty)
        XCTAssertTrue(BoardingPassBarcode.parse("M1SHORT").isEmpty)
    }

    /// THY: Türkçe etiketler, saatler yalnızca "07:40" olarak; anlamsal etiket yok.
    func testTurkishAirlinesStylePass() throws {
        let json = """
        {
          "organizationName": "Turkish Airlines",
          "description": "Turkish Airlines Boarding Pass",
          "relevantDate": "2026-10-12T07:00+03:00",
          "barcodes": [{ "format": "PKBarcodeFormatAztec", "message": "\(Self.thyBarcode)", "messageEncoding": "iso-8859-1" }],
          "boardingPass": {
            "transitType": "PKTransitTypeAir",
            "headerFields": [{ "key": "gate", "label": "KAPI", "value": "D5" }],
            "primaryFields": [
              { "key": "origin", "label": "İSTANBUL", "value": "IST" },
              { "key": "destination", "label": "LİZBON", "value": "LIS" }
            ],
            "auxiliaryFields": [
              { "key": "boardingTime", "label": "BİNİŞ", "value": "07:00" },
              { "key": "departureTime", "label": "KALKIŞ", "value": "07:40" },
              { "key": "arrivalTime", "label": "VARIŞ", "value": "10:15" },
              { "key": "seat", "label": "KOLTUK", "value": "14C" }
            ]
          }
        }
        """
        let flight = try XCTUnwrap(PassParser.parse(passJSON: Data(json.utf8), now: now, calendar: cal)?.flights.first)
        XCTAssertEqual(flight.flightNumber, "TK1759")
        XCTAssertEqual([flight.fromCode, flight.toCode], ["IST", "LIS"])
        XCTAssertEqual(local(flight.departure, "Europe/Istanbul"), [10, 12, 7, 40], "Biniş saati değil kalkış saati")
        XCTAssertEqual(local(flight.arrival, "Europe/Lisbon"), [10, 12, 10, 15])
        XCTAssertTrue(flight.hasTimes)
        XCTAssertEqual(flight.seat, "14C")
    }

    /// Pegasus: alanlarda havalimanı kodu ve uçuş numarası yok (şehir adları), tarih yok; bunlar barkoddan gelir.
    func testPegasusStylePassUsesBarcode() throws {
        let json = """
        {
          "organizationName": "Pegasus Airlines",
          "barcode": { "format": "PKBarcodeFormatQR", "message": "\(Self.pegasusBarcode)", "messageEncoding": "iso-8859-1" },
          "boardingPass": {
            "transitType": "PKTransitTypeAir",
            "primaryFields": [
              { "key": "from", "label": "Sabiha Gökçen", "value": "İstanbul" },
              { "key": "to", "label": "Kansai", "value": "Osaka" }
            ],
            "secondaryFields": [{ "key": "departure", "label": "DEPARTURE", "value": "9:55 AM" }]
          }
        }
        """
        let flight = try XCTUnwrap(PassParser.parse(passJSON: Data(json.utf8), now: now, calendar: cal)?.flights.first)
        XCTAssertEqual(flight.flightNumber, "PC1171")
        XCTAssertEqual([flight.fromCode, flight.toCode], ["SAW", "KIX"])
        XCTAssertEqual(local(flight.departure, "Europe/Istanbul"), [11, 11, 9, 55])
        XCTAssertFalse(flight.hasTimes, "Varış saati yok; kullanıcıya kontrol ettirilir")
        XCTAssertEqual(flight.seat, "21A")
    }

    func testConnectionPassListsBothFlights() throws {
        let json = """
        { "relevantDate": "2026-10-12T08:30+03:00",
          "barcodes": [{ "format": "PKBarcodeFormatPDF417", "message": "\(Self.connectionBarcode)" }],
          "boardingPass": { "transitType": "PKTransitTypeAir" } }
        """
        let flights = try XCTUnwrap(PassParser.parse(passJSON: Data(json.utf8), now: now, calendar: cal)?.flights)
        XCTAssertEqual(flights.map(\.flightNumber), ["PC1251", "KL1691"])
        XCTAssertEqual(flights.last.map { local($0.departure, "Europe/Amsterdam") }?.prefix(2).map { $0 }, [10, 12])
        XCTAssertEqual(flights.last?.hasTimes, false)
    }
}
