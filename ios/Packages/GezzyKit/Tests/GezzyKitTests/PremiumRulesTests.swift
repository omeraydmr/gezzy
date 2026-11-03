import XCTest
@testable import GezzyKit

final class PremiumRulesTests: XCTestCase {
    func testFreeUserCanCreateTwoTrips() {
        XCTAssertTrue(PremiumRules.canCreateTrip(created: 0, isPremium: false))
        XCTAssertTrue(PremiumRules.canCreateTrip(created: 1, isPremium: false))
        XCTAssertFalse(PremiumRules.canCreateTrip(created: 2, isPremium: false))
        XCTAssertFalse(PremiumRules.canCreateTrip(created: 7, isPremium: false))
    }

    func testPremiumIsUnlimited() {
        XCTAssertTrue(PremiumRules.canCreateTrip(created: 50, isPremium: true))
    }

    func testDeletingDoesNotRefund() {
        // Keychain 2 diyor, cihazda 0 seyahat kaldı: hak geri gelmez.
        XCTAssertEqual(PremiumRules.tripsCreated(stored: 2, owned: 0), 2)
        // İlk geçiş: sayaç yok ama 3 sahipli seyahat var.
        XCTAssertEqual(PremiumRules.tripsCreated(stored: 0, owned: 3), 3)
    }

    func testRemaining() {
        XCTAssertEqual(PremiumRules.remainingFreeTrips(created: 0), 2)
        XCTAssertEqual(PremiumRules.remainingFreeTrips(created: 1), 1)
        XCTAssertEqual(PremiumRules.remainingFreeTrips(created: 5), 0)
    }

    func testProductIDs() {
        XCTAssertEqual(PremiumRules.productIDs, ["gezzy.premium.yearly", "gezzy.premium.monthly"])
    }
}
