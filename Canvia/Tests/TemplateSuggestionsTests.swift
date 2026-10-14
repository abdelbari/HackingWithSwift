// "More like this" and "Adapted from other sizes": the two rankings both
// phones share (Templates), their fixtures, and the design types that had no
// template of their own.

import XCTest
@testable import Canvia

final class TemplateSuggestionsTests: XCTestCase {

    private func template(_ id: String, _ name: String, _ category: String, _ w: Double, _ h: Double) -> Template {
        Template(id: id, name: name, category: category, width: w, height: h,
                 background: .color("#ffffff"), elements: [])
    }

    private func preset(_ id: String) throws -> SizePreset {
        try XCTUnwrap(SizePreset.byId(id), id)
    }

    /// A fixture's JSON: from the test bundle, or beside this file.
    private func fixture(_ name: String, file: StaticString = #filePath) throws -> [String: Any] {
        let data: Data
        if let url = Bundle(for: TemplateSuggestionsTests.self).url(forResource: name, withExtension: "json") {
            data = try Data(contentsOf: url)
        } else {
            let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            data = try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
        }
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: more like this

    func testANamesWordsAreItsLettersAndDigits() {
        XCTAssertEqual(Templates.nameTokens("We\u{2019}ve Moved Postcard"), ["we", "ve", "moved", "postcard"])
        XCTAssertEqual(Templates.nameTokens("Q3 / Review & Plan"), ["q3", "review", "plan"])
        XCTAssertEqual(Templates.nameTokens("Sale sale SALE"), ["sale"])
    }

    /// Same category 3, same size 2, each shared word 1.
    func testLikenessIsCategorySizeThenWords() {
        let base = template("a", "Summer Sale Post", "Marketing", 1080, 1080)
        XCTAssertEqual(Templates.likeness(template("b", "Winter Sale Post", "Marketing", 1080, 1080), to: base), 3 + 2 + 2)
        XCTAssertEqual(Templates.likeness(template("c", "Summer Menu", "Food", 1080, 1080), to: base), 2 + 1)
        XCTAssertEqual(Templates.likeness(template("d", "Quarterly Deck", "Marketing", 1920, 1080), to: base), 3)
        XCTAssertEqual(Templates.likeness(template("e", "Quarterly Deck", "Business", 1920, 1080), to: base), 0)
    }

    /// Highest first, a tie in the library's order, the template itself
    /// never among them.
    func testSimilarRanksAndBreaksTiesByPlace() {
        let base = template("a", "Summer Sale Post", "Marketing", 1080, 1080)
        let library = [
            template("x", "Deck", "Business", 1920, 1080),
            base,
            template("y", "Story", "Marketing", 1080, 1920),
            template("z", "Summer Sale Story", "Marketing", 1080, 1920),
            template("w", "Post", "Food", 1080, 1080),
            template("v", "Banner", "Marketing", 1500, 500),
        ]
        let ids = Templates.similar(base, limit: 4, among: library).map(\.id)
        // z 3 + 2 words; then y 3, w 2 + 1 and v 3, tied, by place.
        XCTAssertEqual(ids, ["z", "y", "w", "v"])
        XCTAssertFalse(Templates.similar(base, among: library).contains { $0.id == "a" })
        XCTAssertEqual(Templates.similar(base, limit: 0, among: library).count, 0)
    }

    /// The shared fixture: both phones list the same eight.
    func testSimilarMatchesTheSharedFixture() throws {
        let json = try fixture("similar")
        let id = try XCTUnwrap(json["template"] as? String)
        let limit = try XCTUnwrap(json["limit"] as? Int)
        let expect = try XCTUnwrap(json["expect"] as? [String])
        let source = try XCTUnwrap(ContentLibrary.templates.first { $0.id == id }, id)
        XCTAssertEqual(Templates.similar(source, limit: limit).map(\.id), expect)
        XCTAssertEqual(Templates.similarCount, 8)
    }

    // MARK: adapted from other sizes

    func testAspectDistanceIsTheLogOfTheRatio() throws {
        let portrait = try preset("insta-portrait")
        XCTAssertEqual(Templates.aspectDistance(template("s", "S", "Social", 1080, 1080), portrait), log(1.25), accuracy: 1e-12)
        XCTAssertEqual(Templates.aspectDistance(template("t", "T", "Social", 2160, 2700), portrait), 0, accuracy: 1e-12)
        XCTAssertEqual(Templates.aspectDistance(template("z", "Z", "Social", 0, 10), portrait), .infinity)
    }

    /// Nearest first; at one distance the type's own family first; then
    /// the library's order. A template of the type's own size, or too far
    /// off in shape, is never borrowed.
    func testNearbyRanksByDistanceThenFamilyThenPlace() throws {
        let portrait = try preset("insta-portrait")  // Social, 1080 × 1350
        let library = [
            template("own", "Own", "Social", 1080, 1350),
            template("logo", "Logo", "Business", 800, 800),          // 0.223, Marketing family
            template("post", "Post", "Social", 1080, 1080),          // 0.223, Social family
            template("letter", "Letter", "Business", 2550, 3300),   // 0.034
            template("story", "Story", "Social", 1080, 1920),        // 0.35: too far
            template("deck", "Deck", "Business", 1920, 1080),        // far
        ]
        let ids = Templates.nearbyTemplates(portrait, among: library).map(\.id)
        XCTAssertEqual(ids, ["letter", "post", "logo"])
        XCTAssertEqual(Templates.nearbyTemplates(portrait, limit: 2, among: library).map(\.id), ["letter", "post"])
        XCTAssertEqual(Templates.nearbyReach, 0.25)
        XCTAssertEqual(Templates.nearbyCount, 12)
    }

    /// The flyer's templates of its former pixels are its own, not borrowed.
    func testAFormerSizeIsTheTypesOwn() throws {
        let flyer = try preset("flyer")
        XCTAssertTrue(Templates.isOwn(template("f", "F", "Marketing", 1240, 1748), of: flyer))
        XCTAssertFalse(Templates.nearbyTemplates(flyer).contains { $0.width == 1240 && $0.height == 1748 })
    }

    /// The shared fixture: both phones rank Instagram Portrait alike.
    func testNearbyMatchesTheSharedFixture() throws {
        let json = try fixture("nearby")
        let type = try preset(try XCTUnwrap(json["preset"] as? String))
        let expect = try XCTUnwrap(json["expect"] as? [String])
        XCTAssertEqual(Templates.nearbyTemplates(type).map(\.id), expect)
    }

    /// Each comes made at the type's size and in its unit, reflowed, under
    /// the template's name, and the tile counts them.
    func testAnAdaptedTemplateIsMadeAtTheTypesSize() throws {
        let poster = try preset("a3-poster")
        let adapted = Templates.nearby(poster, limit: 3)
        XCTAssertEqual(adapted.count, 3)
        for item in adapted {
            XCTAssertEqual(item.design.width, poster.w)
            XCTAssertEqual(item.design.height, poster.h)
            XCTAssertEqual(item.design.unit, "mm")
            XCTAssertEqual(item.design.title, item.template.name)
            XCTAssertEqual(item.design.pages.count, item.template.pageCount)
            XCTAssertFalse(Templates.isOwn(item.template, of: poster))
        }
        XCTAssertEqual(Templates.nearbyCounts["a3-poster"], Templates.nearbyTemplates(poster).count)
        XCTAssertLessThanOrEqual(Templates.nearbyCounts.values.max() ?? 0, 12)
    }

    func testTheTileSaysWhatIsAdapted() {
        XCTAssertEqual(Templates.countText(own: 0, adapted: 12), "0 + 12 adapted")
        XCTAssertEqual(Templates.countText(own: 4, adapted: 3), "4 + 3 adapted")
        XCTAssertEqual(Templates.countText(own: 4, adapted: 0), "4 ready-made")
        XCTAssertEqual(Templates.spokenCount(own: 1, adapted: 0), "1 ready-made designs")
    }

    func testThePreviewHeaderNamesCategorySizeAndPages() {
        XCTAssertEqual(Templates.caption(template("a", "A", "Business", 1920, 1080)), "Business · 1920 × 1080 · 1 page")
    }

    // MARK: the types that had none

    /// Each of the fourteen types that opened on a blank page alone now
    /// has at least four templates made at its size.
    func testEveryTypeThatHadNoTemplateHasFour() throws {
        let types = ["insta-portrait", "pinterest-pin", "linkedin-post", "x-post", "facebook-cover", "youtube-banner",
                     "linkedin-banner", "x-header", "presentation-4x3", "postcard", "a3-poster", "infographic",
                     "email-header", "display-ad"]
        for id in types {
            let type = try preset(id)
            XCTAssertGreaterThanOrEqual(ContentLibrary.sizedTemplates(for: type).count, 4, id)
        }
    }
}
