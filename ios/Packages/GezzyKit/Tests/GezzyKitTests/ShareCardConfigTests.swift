import XCTest
@testable import GezzyKit

final class ShareCardConfigTests: XCTestCase {
    func testDefaultsKeepMoneyPrivate() {
        let c = ShareCardConfig.default(for: .stats)
        XCTAssertEqual(c.stats, [.days, .stops, .distance, .travellers])
        XCTAssertEqual(c.format, .story)
        XCTAssertTrue(c.showsBrand)
        XCTAssertNil(c.paletteID)
    }

    func testCodableRoundTrip() throws {
        var c = ShareCardConfig.default(for: .collage)
        c.photoIDs = ["x", "y"]; c.title = "Kopenhag"; c.stats.insert(.spent); c.format = .square
        let data = try JSONEncoder().encode(c)
        XCTAssertEqual(try JSONDecoder().decode(ShareCardConfig.self, from: data), c)
    }

    func testPhotoLimits() {
        XCTAssertEqual(ShareCardConfig.photoLimit(.postcard), 1...1)
        XCTAssertEqual(ShareCardConfig.photoLimit(.collage), 2...9)
        XCTAssertEqual(ShareCardConfig.photoLimit(.stats), 0...0)
        XCTAssertEqual(ShareCardConfig.photoLimit(.route), 0...0)
        XCTAssertEqual(ShareCardConfig.photoLimit(.ticket), 0...0)
    }

    func testAspects() {
        XCTAssertEqual(ShareCardConfig.Format.story.aspect, 9.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(ShareCardConfig.Format.post.aspect, 4.0 / 5.0, accuracy: 0.0001)
        XCTAssertEqual(ShareCardConfig.Format.square.aspect, 1, accuracy: 0.0001)
    }

    func testCollageColumns() {
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 4, format: .square), 2)
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 6, format: .post), 2)
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 9, format: .square), 3)
        XCTAssertEqual(ShareCardConfig.collageColumns(count: 9, format: .story), 2)
    }

    func testTextClamped() {
        XCTAssertEqual(ShareCardConfig.clampedText(String(repeating: "a", count: 50)).count, 40)
        XCTAssertEqual(ShareCardConfig.clampedText("  Kopenhag  "), "Kopenhag")
    }
}
