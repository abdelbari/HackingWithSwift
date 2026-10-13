// Design types and real units: the shared catalogue of sizes (Content.json's
// "sizes"), its search, and designs measured in mm, cm or inches that export
// and print at their true size. The rows are the Android twin's, so both
// phones read the same list and convert the same way.

import XCTest
@testable import Canvia

final class DesignTypesAndUnitsTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func designType(_ id: String) throws -> SizePreset {
        try XCTUnwrap(SizePreset.byId(id), "no design type \(id)")
    }

    // MARK: the catalogue

    func testEveryIdIsUniqueAndTheElevenComeFirst() {
        let ids = SizePreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "two design types share an id")
        XCTAssertGreaterThanOrEqual(ids.count, 35, "about forty types")
        XCTAssertEqual(SizePreset.hero.map(\.id), [
            "insta-post", "insta-story", "presentation", "youtube-thumb", "facebook-post",
            "poster", "flyer", "a4", "business-card", "quote-card", "logo",
        ])
        for id in ["tiktok-video", "insta-reel", "facebook-cover", "linkedin-post", "linkedin-banner",
                   "x-post", "x-header", "pinterest-pin", "youtube-banner", "us-letter", "resume-a4",
                   "resume-letter", "invitation", "postcard", "certificate", "menu", "infographic",
                   "phone-wallpaper", "desktop-wallpaper", "video-call-background", "email-header"] {
            XCTAssertNotNil(SizePreset.byId(id), id)
        }
    }

    /// Read from the bundled catalogue, not the fallback, and in the six
    /// categories both phones show.
    func testTheCatalogueIsReadFromContentJSON() {
        XCTAssertNotNil(ContentLibrary.bundle.sizes)
        XCTAssertEqual(ContentLibrary.bundle.sizes?.count, SizePreset.all.count)
        XCTAssertEqual(Set(SizePreset.categories),
                       ["Social", "Video", "Presentations", "Print", "Documents", "Marketing"])
    }

    func testTheSizesInPixels() throws {
        let rows: [(String, Double, Double)] = [
            ("insta-post", 1080, 1080), ("tiktok-video", 1080, 1920), ("facebook-cover", 1640, 624),
            ("linkedin-post", 1200, 627), ("linkedin-banner", 1584, 396), ("x-post", 1600, 900),
            ("x-header", 1500, 500), ("pinterest-pin", 1000, 1500), ("youtube-banner", 2560, 1440),
            ("infographic", 800, 2000), ("email-header", 600, 200),
            // Physical: whole pixels at their dpi.
            ("a4", 2480, 3508), ("flyer", 1748, 2480), ("business-card", 1050, 600),
            ("poster", 1587, 2245), ("us-letter", 2550, 3300), ("invitation", 1500, 2100),
            ("postcard", 1800, 1200), ("certificate", 3300, 2550),
        ]
        for (id, w, h) in rows {
            let t = try designType(id)
            XCTAssertEqual(t.w, w, id)
            XCTAssertEqual(t.h, h, id)
        }
        let a4 = try designType("a4")
        XCTAssertEqual(a4.unit, "mm")
        XCTAssertEqual(a4.dpi, 300)
        XCTAssertEqual(a4.dimensions, "210 × 297 mm")
        XCTAssertEqual(try designType("business-card").dimensions, "3.5 × 2 in")
        XCTAssertEqual(try designType("poster").dpi, 96, "existing poster files unchanged")
        XCTAssertNil(try designType("insta-post").unit)
        XCTAssertNil(try designType("insta-post").dpi)
        XCTAssertEqual(try designType("insta-post").dimensions, "1080 × 1080")
    }

    /// The A5 flyer's templates were made at 1240 × 1748, and are still its
    /// own, fitted to the true A5 page.
    func testTheFlyerKeepsItsTemplatesFittedToA5() throws {
        let flyer = try designType("flyer")
        let bucket = ContentLibrary.sizedTemplates(for: flyer)
        XCTAssertGreaterThanOrEqual(bucket.count, 3)
        let template = try XCTUnwrap(bucket.first)
        let design = template.instantiate(for: flyer)
        XCTAssertEqual(design.width, 1748)
        XCTAssertEqual(design.height, 2480)
        XCTAssertEqual(design.unit, "mm")
        XCTAssertEqual(design.dpi, 300)
        XCTAssertFalse(design.pages[0].elements.isEmpty)
    }

    /// A template made at a print type's pixels is that type: the A4
    /// templates open on an A4 page.
    func testATemplateAtAPrintSizeTakesItsUnit() throws {
        let a4 = try XCTUnwrap(ContentLibrary.templates.first { $0.width == 2480 && $0.height == 3508 })
        let design = a4.instantiate()
        XCTAssertEqual(design.unit, "mm")
        XCTAssertEqual(design.dpi, 300)
        let post = try XCTUnwrap(ContentLibrary.templates.first { $0.width == 1080 && $0.height == 1080 })
        XCTAssertNil(post.instantiate().unit)
    }

    // MARK: search

    func testSearchFindsTikTokFirst() {
        XCTAssertEqual(SizePreset.search("tiktok").first?.id, "tiktok-video")
        XCTAssertEqual(SizePreset.search("TikTok").first?.id, "tiktok-video", "case ignored")
    }

    func testSearchIgnoresAccentsAndFindsKeywordsAndPixels() {
        let resumes = SizePreset.search("Résumé").map(\.id)
        XCTAssertEqual(resumes, ["resume-a4", "resume-letter"])
        XCTAssertTrue(SizePreset.search("cv").map(\.id).contains("resume-a4"), "by a keyword")
        XCTAssertEqual(SizePreset.search("letter").first?.id, "us-letter")
        let tall = SizePreset.search("1080x1920").map(\.id)
        XCTAssertTrue(tall.contains("tiktok-video"))
        XCTAssertTrue(tall.contains("insta-story"))
        XCTAssertFalse(tall.contains("insta-post"))
        XCTAssertEqual(SizePreset.search("1080 × 1920").map(\.id), tall)
        XCTAssertTrue(SizePreset.search("").isEmpty)
        XCTAssertTrue(SizePreset.search("   ").isEmpty)
    }

    /// A name that starts with the query before one that only has it,
    /// each band in catalogue order.
    func testNamesThatStartWithTheQueryLead() throws {
        let found = SizePreset.search("post").map(\.id)
        XCTAssertEqual(Array(found.prefix(3)), ["poster", "poster-a3", "postcard"])
        let card = try XCTUnwrap(found.firstIndex(of: "postcard"))
        let post = try XCTUnwrap(found.firstIndex(of: "insta-post"))
        XCTAssertLessThan(card, post)
    }

    // MARK: units

    /// The shared rows: 85 × 55 mm is 1004 × 650 px at 300 dpi, and back.
    func testMillimetresRoundTripThroughPixels() {
        XCTAssertEqual(Units.pixels(85, unit: "mm", dpi: 300), 1004)
        XCTAssertEqual(Units.pixels(55, unit: "mm", dpi: 300), 650)
        XCTAssertEqual(Units.format(Units.value(ofPixels: 1004, unit: "mm", dpi: 300), unit: "mm"), "85")
        XCTAssertEqual(Units.format(Units.value(ofPixels: 650, unit: "mm", dpi: 300), unit: "mm"), "55")
        XCTAssertEqual(Units.pixels(8.5, unit: "in", dpi: 300), 2550)
        XCTAssertEqual(Units.pixels(21, unit: "cm", dpi: 300), 2480)
        XCTAssertEqual(Units.pixels(1080.4, unit: "px", dpi: 300), 1080)
        XCTAssertEqual(Units.dimensions(width: 1004, height: 650, unit: "mm", dpi: 300), "85 × 55 mm")
        XCTAssertEqual(Units.dimensions(width: 2480, height: 3508, unit: "cm", dpi: 300), "21 × 29.7 cm")
        XCTAssertEqual(Units.dimensions(width: 1080, height: 1920, unit: nil, dpi: nil), "1080 × 1920")
    }

    func testFormatRows() {
        XCTAssertEqual(Units.format(209.97, unit: "mm"), "210")
        XCTAssertEqual(Units.format(148.46, unit: "mm"), "148.5")
        XCTAssertEqual(Units.format(8.5, unit: "in"), "8.5")
        XCTAssertEqual(Units.format(3.333, unit: "in"), "3.33")
        XCTAssertEqual(Units.format(29.7, unit: "cm"), "29.7")
        XCTAssertEqual(Units.format(1080.4, unit: "px"), "1080")
    }

    /// Points per pixel: 72 / dpi, and exactly today's 72 / 96 without one.
    func testPointsPerPixel() throws {
        XCTAssertEqual(Units.pointsPerPixel(dpi: nil), 0.75)
        XCTAssertEqual(Units.pointsPerPixel(dpi: 300), 0.24, accuracy: 1e-12)
        let plain = Design(title: "p", width: 960, height: 480)
        XCTAssertEqual(PrintLayout.pxToPt(plain), 0.75)
        XCTAssertEqual(PrintLayout.pagePoints(design: plain, bleed: 0), CGSize(width: 720, height: 360))
        let a4 = try designType("a4").makeDesign()
        let pts = PrintLayout.pagePoints(design: a4, bleed: 0)
        XCTAssertEqual(pts.width, 595, accuracy: 1)
        XCTAssertEqual(pts.height, 842, accuracy: 1)
        // A physical unit with no dpi written is at 300, as one typed is.
        var bare = Design(title: "mm", width: 2480, height: 3508)
        bare.unit = "mm"
        XCTAssertEqual(bare.effectiveDPI, 300)
        XCTAssertEqual(PrintLayout.pxToPt(bare), 0.24, accuracy: 1e-12)
        XCTAssertEqual(bare.sizeReadout, "210 × 297 mm")
    }

    /// The A4 type comes out as an A4 PDF page.
    @MainActor
    func testTheA4TypeGivesAnA4PDFPage() async throws {
        var a4 = try designType("a4").makeDesign()
        a4.pages[0].elements = [.shape("rect", w: 400, h: 400)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("a4-\(UUID()).pdf")
        written.append(url)
        try await DesignExporter.exportPDF(design: a4, to: url)
        let box = try XCTUnwrap(CGPDFDocument(url as CFURL)?.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 595, accuracy: 1)
        XCTAssertEqual(box.height, 842, accuracy: 1)
    }

    /// Fit or actual size on A4 paper prints at the true size.
    func testActualSizeFitsOnTheSheet() throws {
        let a4 = try designType("a4").makeDesign()
        var options = PrintLayout.Options()
        options.fit = .actual
        options.margin = 0
        XCTAssertEqual(DesignExporter.sheetCount(design: a4, indices: [0], options: options), 1)
        let pts = PrintLayout.pagePoints(design: a4, bleed: 0)
        XCTAssertLessThanOrEqual(pts.width, options.printable.width + 1)
        XCTAssertLessThanOrEqual(pts.height, options.printable.height + 1)
    }

    /// A picture says its dpi when the design has one, and nothing when not.
    func testAPictureSaysTheDesignsDPI() throws {
        let a4 = try designType("a4").makeDesign()
        XCTAssertEqual(DesignExporter.imageDPI(design: a4, page: a4.pages[0], requested: 1), 300)
        let post = Design(title: "p", width: 1080, height: 1080)
        XCTAssertNil(DesignExporter.imageDPI(design: post, page: post.pages[0], requested: 2))
    }

    // MARK: the file

    /// A design in pixels writes neither key; one in mm writes both and
    /// reads back; "px" reads as pixels.
    func testUnitAndDpiAreOptionalKeys() throws {
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Design(title: "p"))) as? [String: Any]
        XCTAssertNil(plain?["unit"])
        XCTAssertNil(plain?["dpi"])

        let a4 = try designType("a4").makeDesign()
        let data = try JSONEncoder().encode(a4)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["unit"] as? String, "mm")
        XCTAssertEqual(json?["dpi"] as? Double, 300)
        let back = try JSONDecoder().decode(Design.self, from: data)
        XCTAssertEqual(back, a4)

        let px = #"{"id":"d1","width":100,"height":100,"pages":[],"unit":"px"}"#
        XCTAssertNil(try JSONDecoder().decode(Design.self, from: Data(px.utf8)).unit)
    }

    // MARK: readouts and sizes typed

    func testReadoutsInTheDesignsUnit() throws {
        XCTAssertEqual(EditorCaption.text(width: 2480, height: 3508, unit: "mm", dpi: 300, page: 0, of: 2),
                       "210 × 297 mm · Page 1 of 2")
        XCTAssertEqual(EditorCaption.text(width: 1080, height: 1920, page: 1, of: 5), "1080 × 1920 · Page 2 of 5")
        let card = RecentDesign(id: "d", title: "A4", width: 2480, height: 3508, pages: 1, updatedAt: 0,
                                unit: "mm", dpi: 300)
        XCTAssertEqual(card.sizeText, "210 × 297 mm")
    }

    func testASizeTypedInAPhysicalUnitIsMadeAt300Dpi() {
        XCTAssertEqual(CustomSizes.side("210", unit: "mm"), 2480)
        XCTAssertEqual(CustomSizes.side("8.5", unit: "in"), 2550)
        XCTAssertNil(CustomSizes.side("1000", unit: "mm"), "11811 px is past 8000")
        XCTAssertEqual(CustomSizes.outOfRangeText, "Must be 40 to 8000 px")
        XCTAssertEqual(CustomSizes.field("8,5 in", unit: "in"), "8.5")
        XCTAssertEqual(CustomSizes.field("1.2.3", unit: "mm"), "1.23")
        XCTAssertEqual(CustomSizes.field("8.5", unit: "px"), "85")
        XCTAssertEqual(CustomSizes.convert("2480", from: "px", to: "mm"), "210")
        XCTAssertEqual(CustomSizes.convert("210", from: "mm", to: "px"), "2480")
        XCTAssertEqual(CustomSizes.resizeTitle(width: "210", height: "297", unit: "mm"), "Resize to 210 × 297 mm")
        let design = CustomSizes.design(width: 2480, height: 3508, unit: "mm")
        XCTAssertEqual(design.title, "210 × 297 mm")
        XCTAssertEqual(design.unit, "mm")
        XCTAssertEqual(design.dpi, 300)
        XCTAssertNil(CustomSizes.design(width: 1600, height: 900, unit: "px").unit)
        XCTAssertEqual(CustomSizes.design(width: 1600, height: 900, unit: "px").title, "1600 × 900")
    }

    /// Resizing to a type in place takes its unit in the same step.
    func testResizingToATypeTakesItsUnit() throws {
        let store = DesignStore(design: Design(title: "p", width: 1080, height: 1080))
        let a4 = try designType("a4")
        store.magicResize(width: a4.w, height: a4.h, units: UnitChoice(unit: a4.unit, dpi: a4.dpi))
        XCTAssertEqual(store.design.width, 2480)
        XCTAssertEqual(store.design.unit, "mm")
        XCTAssertEqual(store.design.dpi, 300)
        store.undo()
        XCTAssertNil(store.design.unit, "one step")
        XCTAssertEqual(store.design.width, 1080)
    }

    // MARK: asked for by id

    func testALaunchRequestForATypeIsServedOnce() throws {
        let name = "types-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        LaunchRequest.set(.newType(id: "us-letter", title: "US Letter"), defaults: defaults)
        XCTAssertEqual(LaunchRequest.take(defaults), .newType(id: "us-letter", title: "US Letter"))
        XCTAssertNil(LaunchRequest.take(defaults))
        XCTAssertEqual(DesignSizeChoice(rawValue: "tiktok-video")?.preset?.name, "TikTok Video")
        for preset in SizePreset.all {
            XCTAssertNotNil(DesignSizeChoice(rawValue: preset.id), "Shortcuts offers \(preset.id)")
        }
    }
}
