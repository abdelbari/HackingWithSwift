// A size first, then something to start from: the templates at exactly
// that size, a topic row only when it helps, the Facebook size, and a
// custom size's range, ratios and recent sizes — each as the Android twin
// has it.

import XCTest
@testable import Canvia

final class StartAndSizesTests: XCTestCase {

    private var suites: [String] = []

    override func tearDown() {
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        suites = []
        super.tearDown()
    }

    private func freshDefaults() throws -> UserDefaults {
        let name = "sizes-\(UUID())"
        suites.append(name)
        return try XCTUnwrap(UserDefaults(suiteName: name))
    }

    private func preset(_ id: String) throws -> SizePreset {
        try XCTUnwrap(SizePreset.all.first { $0.id == id })
    }

    // MARK: templates by size

    /// Exactly the size, nothing near it, in library order.
    func testASizeHasTheTemplatesMadeAtExactlyThatSize() throws {
        let post = try preset("insta-post")
        let bucket = ContentLibrary.sizedTemplates(for: post)
        XCTAssertFalse(bucket.isEmpty)
        XCTAssertTrue(bucket.allSatisfy { $0.width == 1080 && $0.height == 1080 })
        let order = ContentLibrary.templates.filter { $0.width == 1080 && $0.height == 1080 }.map(\.id)
        XCTAssertEqual(bucket.map(\.id), order)
        XCTAssertEqual(ContentLibrary.templateCounts["insta-post"], bucket.count)

        let topic = try XCTUnwrap(bucket.first?.category)
        let narrowed = ContentLibrary.sizedTemplates(width: 1080, height: 1080, category: topic)
        XCTAssertTrue(narrowed.allSatisfy { $0.category == topic })
        XCTAssertEqual(narrowed.count, bucket.filter { $0.category == topic }.count)
        XCTAssertTrue(ContentLibrary.sizedTemplates(width: 1081, height: 1080, category: nil).isEmpty)
    }

    /// The seven templates already made at 1200 × 630 have a size to be
    /// reached by, after YouTube as on the Android twin.
    func testFacebookPostIsASize() throws {
        let facebook = try preset("facebook-post")
        XCTAssertEqual(facebook.name, "Facebook Post")
        XCTAssertEqual(facebook.w, 1200)
        XCTAssertEqual(facebook.h, 630)
        let ids = SizePreset.all.map(\.id)
        XCTAssertEqual(ids.firstIndex(of: "facebook-post"), try XCTUnwrap(ids.firstIndex(of: "youtube-thumb")) + 1)
        XCTAssertGreaterThan(ContentLibrary.templateCounts["facebook-post"] ?? 0, 0)
        XCTAssertEqual(Set(ids).count, ids.count, "two sizes share an id")
    }

    /// Topics once each and alphabetical, and a row of them only for more
    /// than eight templates in more than one topic.
    func testATopicRowOnlyWhenItHelps() throws {
        func template(_ category: String) throws -> Template {
            var t = try XCTUnwrap(ContentLibrary.templates.first)
            t.category = category
            return t
        }
        let mixed = try ["Social", "Events", "Social", "Business", "Events", "Social", "Food", "Social", "Travel"].map(template)
        XCTAssertEqual(ContentLibrary.topics(in: mixed), ["Business", "Events", "Food", "Social", "Travel"])
        XCTAssertTrue(ContentLibrary.showsTopics(mixed))
        XCTAssertFalse(ContentLibrary.showsTopics(Array(mixed.prefix(8))), "eight is few enough to see at once")
        XCTAssertFalse(ContentLibrary.showsTopics(try Array(repeating: "Social", count: 12).map(template)),
                       "one topic is nothing to choose between")
    }

    // MARK: custom size

    func testASideIsDigitsInRange() {
        XCTAssertEqual(CustomSizes.digits("1 0 8 0px"), "1080")
        XCTAssertEqual(CustomSizes.digits("1234567"), "12345", "five digits at most")
        XCTAssertEqual(CustomSizes.digits("٣٤"), "", "digits a size field can read")
        XCTAssertEqual(CustomSizes.side("40"), 40)
        XCTAssertEqual(CustomSizes.side("4000"), 4000)
        XCTAssertNil(CustomSizes.side("39"))
        XCTAssertNil(CustomSizes.side("4001"))
        XCTAssertNil(CustomSizes.side(""))
        XCTAssertEqual(CustomSizes.title(width: 1600, height: 900), "1600 × 900")
    }

    /// A ratio keeps the width and sets the height, truncated and not
    /// clamped; an empty width counts as 1080.
    func testARatioSetsTheHeightFromTheWidth() {
        XCTAssertEqual(CustomSizes.ratios.map { $0.label }, ["1:1", "4:5", "16:9", "9:16"])
        XCTAssertEqual(CustomSizes.height(forWidth: "1080", ratio: 9.0 / 16), "1920")
        XCTAssertEqual(CustomSizes.height(forWidth: "1080", ratio: 16.0 / 9), "607")
        XCTAssertEqual(CustomSizes.height(forWidth: "1000", ratio: 0.8), "1250")
        XCTAssertEqual(CustomSizes.height(forWidth: "", ratio: 1), "1080")
        XCTAssertEqual(CustomSizes.height(forWidth: "4000", ratio: 9.0 / 16), "7111")
        XCTAssertNil(CustomSizes.side(CustomSizes.height(forWidth: "4000", ratio: 9.0 / 16)), "out of range, and said so")
    }

    /// Newest first, once each, four at most; anything that is not two
    /// positive sides is passed over.
    func testRecentSizesAreTheLastFourMade() throws {
        let defaults = try freshDefaults()
        XCTAssertTrue(CustomSizes.recent(defaults).isEmpty)
        let made: [(Double, Double)] = [(1600, 900), (2048, 2048), (1000, 1500), (800, 600), (1200, 1200)]
        for (w, h) in made {
            CustomSizes.remember(width: w, height: h, defaults: defaults)
        }
        XCTAssertEqual(CustomSizes.recent(defaults).map(\.label), ["1200×1200", "800×600", "1000×1500", "2048×2048"])
        CustomSizes.remember(width: 1000.7, height: 1500, defaults: defaults)
        XCTAssertEqual(CustomSizes.recent(defaults).map(\.label), ["1000×1500", "1200×1200", "800×600", "2048×2048"],
                       "a size made again moves to the front rather than appearing twice")
        XCTAssertEqual(defaults.stringArray(forKey: CustomSizes.key)?.first, "1000x1500", "written as the Android twin writes it")

        defaults.set(["1600x900", "wide", "0x100", "300x-2", "", "640x480"], forKey: CustomSizes.key)
        XCTAssertEqual(CustomSizes.recent(defaults), [CustomSizes.Entry(width: 1600, height: 900),
                                                      CustomSizes.Entry(width: 640, height: 480)])
    }
}
