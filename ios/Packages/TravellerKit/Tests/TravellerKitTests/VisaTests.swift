import XCTest
@testable import TravellerKit

final class VisaTests: XCTestCase {
    let cal = TestCalendar.calendar
    let start = TestCalendar.date(2026, 10, 12)
    let end = TestCalendar.date(2026, 10, 17)

    func passport(expires: Date = TestCalendar.date(2031, 1, 1), visas: [HeldVisa] = []) -> Passport {
        Passport(nationality: "TR", type: .ordinary, expiresOn: expires, heldVisas: visas)
    }

    func testSchengenRequiresVisa() {
        let result = VisaAdvisor.assess(countryCode: "PT", passport: passport(), tripStart: start, tripEnd: end, calendar: cal)
        XCTAssertEqual(result.status, .required(zone: .schengen))
        XCTAssertTrue(result.needsAction)
    }

    func testHeldSchengenVisaCoversTrip() {
        let visa = HeldVisa(zone: .schengen, validUntil: TestCalendar.date(2027, 6, 1))
        let result = VisaAdvisor.assess(countryCode: "DE", passport: passport(visas: [visa]), tripStart: start, tripEnd: end,
                                        calendar: cal)
        XCTAssertEqual(result.status, .coveredByHeldVisa(zone: .schengen, until: visa.validUntil))
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertFalse(result.needsAction)
    }

    func testHeldVisaExpiringMidTripWarns() {
        let visa = HeldVisa(zone: .schengen, validUntil: TestCalendar.date(2026, 10, 14))
        let result = VisaAdvisor.assess(countryCode: "FR", passport: passport(visas: [visa]), tripStart: start, tripEnd: end,
                                        calendar: cal)
        XCTAssertTrue(result.warnings.contains(.heldVisaExpiresDuringTrip(zone: .schengen, until: visa.validUntil)))
        XCTAssertTrue(result.needsAction)
    }

    func testVisaFreeAndStayLimit() {
        let short = VisaAdvisor.assess(countryCode: "JP", passport: passport(), tripStart: start, tripEnd: end, calendar: cal)
        XCTAssertEqual(short.status, .notRequired(maxDays: 90))
        XCTAssertFalse(short.needsAction)

        let long = VisaAdvisor.assess(countryCode: "SG", passport: passport(), tripStart: start,
                                      tripEnd: TestCalendar.date(2026, 12, 1), calendar: cal)
        XCTAssertTrue(long.warnings.contains(.stayExceedsLimit(maxDays: 30, tripDays: 51)))
    }

    func testPassportValidity() {
        let soon = TestCalendar.date(2026, 12, 1)
        let schengen = VisaAdvisor.assess(countryCode: "IT", passport: passport(expires: soon), tripStart: start,
                                          tripEnd: end, calendar: cal)
        XCTAssertTrue(schengen.warnings.contains(.passportValidityShort(months: 3, mandatory: true, expiresOn: soon)))

        let expired = VisaAdvisor.assess(countryCode: "JP", passport: passport(expires: TestCalendar.date(2026, 10, 14)),
                                         tripStart: start, tripEnd: end, calendar: cal)
        XCTAssertEqual(expired.warnings, [.passportExpiresDuringTrip(expiresOn: TestCalendar.date(2026, 10, 14))])
        XCTAssertTrue(expired.needsAction)
    }

    func testUnknownDomesticAndMissingPassport() {
        XCTAssertEqual(VisaAdvisor.assess(countryCode: "TR", passport: passport(), tripStart: start, tripEnd: end,
                                          calendar: cal).status, .domestic)
        XCTAssertEqual(VisaAdvisor.assess(countryCode: "AQ", passport: passport(), tripStart: start, tripEnd: end,
                                          calendar: cal).status, .unknown)
        XCTAssertEqual(VisaAdvisor.assess(countryCode: "PT", passport: nil, tripStart: start, tripEnd: end,
                                          calendar: cal).status, .noPassport)
    }

    func testSchengenListHas29Countries() {
        XCTAssertEqual(VisaRules.schengenCountries.count, 29)
    }
}
