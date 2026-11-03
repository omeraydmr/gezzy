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

    // MARK: Kurallar

    func testFreeUserAlwaysShowsBrand() {
        var c = ShareCardConfig.default(for: .stats)
        c.showsBrand = false
        XCTAssertTrue(c.effectiveShowsBrand(isPremium: false))
        // Kayıtlı tercih korunur.
        XCTAssertFalse(c.sanitized(hidden: [], available: nil).showsBrand)
    }

    func testPremiumRespectsBrandChoice() {
        var c = ShareCardConfig.default(for: .ticket)
        c.showsBrand = false
        XCTAssertFalse(c.effectiveShowsBrand(isPremium: true))
        c.showsBrand = true
        XCTAssertTrue(c.effectiveShowsBrand(isPremium: true))
    }

    func testSanitizedDropsHiddenUnavailableDuplicatesAndTrims() {
        var c = ShareCardConfig.default(for: .collage)
        c.photoIDs = ["a", "b", "a", "h", "gone"] + (1...12).map { "p\($0)" }
        let s = c.sanitized(hidden: ["h"], available: Set(["a", "b", "h"] + (1...12).map { "p\($0)" }))
        XCTAssertEqual(s.photoIDs.count, 9)
        XCTAssertEqual(Array(s.photoIDs.prefix(3)), ["a", "b", "p1"])
        XCTAssertFalse(s.photoIDs.contains("h"))
        XCTAssertFalse(s.photoIDs.contains("gone"))
    }

    func testSanitizedWithoutMomentsKeepsVisibleIDs() {
        var c = ShareCardConfig.default(for: .postcard)
        c.photoIDs = ["x", "y"]
        XCTAssertEqual(c.sanitized(hidden: [], available: nil).photoIDs, ["x"])
    }

    func testPhotoPaletteFallsBackWithoutPhotos() {
        var c = ShareCardConfig.default(for: .postcard)
        c.paletteID = "photo"
        c.photoIDs = ["h"]
        XCTAssertNil(c.sanitized(hidden: ["h"], available: nil).paletteID)
        c.paletteID = "sunset"
        XCTAssertEqual(c.sanitized(hidden: ["h"], available: nil).paletteID, "sunset")
    }

    func testInitialTemplateAvoidsPhotoTemplatesWithoutPhotos() {
        XCTAssertEqual(ShareCardConfig.initialTemplate(.postcard, hasRoute: true, hasPhotos: false), .stats)
        XCTAssertEqual(ShareCardConfig.initialTemplate(.collage, hasRoute: true, hasPhotos: false), .stats)
        XCTAssertEqual(ShareCardConfig.initialTemplate(.route, hasRoute: false, hasPhotos: false), .stats)
        XCTAssertEqual(ShareCardConfig.initialTemplate(.route, hasRoute: false, hasPhotos: true), .postcard)
        XCTAssertEqual(ShareCardConfig.initialTemplate(.ticket, hasRoute: false, hasPhotos: false), .ticket)
        XCTAssertEqual(ShareCardConfig.initialTemplate(.postcard, hasRoute: true, hasPhotos: true), .postcard)
    }

    func testCanExportNeedsPhotosForPhotoTemplates() {
        var c = ShareCardConfig.default(for: .postcard)
        XCTAssertFalse(c.canExport(hasRoute: true))
        c.photoIDs = ["a"]
        XCTAssertTrue(c.canExport(hasRoute: true))
        c.template = .collage
        XCTAssertFalse(c.canExport(hasRoute: true))
        XCTAssertTrue(ShareCardConfig.default(for: .stats).canExport(hasRoute: false))
        XCTAssertFalse(ShareCardConfig.default(for: .route).canExport(hasRoute: false))
    }
}
