// Round 34's design types: carousels cut into slides, and the types the
// catalogue gained, each with templates to start from — the Android twin's
// DesignTypesTest, row for row, with the shared fixtures carousel-tiles.json,
// sizes.json and sizes-json.sha256.

import XCTest
import CoreGraphics
import CryptoKit
@testable import Canvia

final class DesignTypesTests: XCTestCase {

    // MARK: slides

    /// Shared: Fixtures/carousel-tiles.json, the same rows on both phones.
    func testAPictureIsCutIntoSlidesOfWholePixelsThatCoverItExactly() throws {
        let cases = try XCTUnwrap(try SharedFixture.object("carousel-tiles")["cases"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 8)
        for row in cases {
            let width = try XCTUnwrap(row["width"] as? Double), height = try XCTUnwrap(row["height"] as? Double)
            let columns = try XCTUnwrap(row["columns"] as? Int), rows = try XCTUnwrap(row["rows"] as? Int)
            let expected = try XCTUnwrap(row["tiles"] as? [[Double]]).map {
                CGRect(x: $0[0], y: $0[1], width: $0[2], height: $0[3])
            }
            let tiles = ExportPlan.tiles(size: CGSize(width: width, height: height), columns: columns, rows: rows)
            XCTAssertEqual(tiles, expected, "\(width) × \(height) in \(columns) × \(rows)")
            // Whole pixels, and together the whole picture.
            for tile in tiles {
                XCTAssertEqual(tile.width, tile.width.rounded(.down))
                XCTAssertEqual(tile.height, tile.height.rounded(.down))
            }
            if !tiles.isEmpty {
                let area = tiles.reduce(0.0) { $0 + Double($1.width * $1.height) }
                XCTAssertEqual(area, (width + 0.5).rounded(.down) * (height + 0.5).rounded(.down), accuracy: 1e-9)
            }
        }
    }

    func testSlidesAreNamedAfterTheDesignInOrder() {
        XCTAssertEqual(ExportPlan.slideName("Lisbon weekend", pageIndex: 0, files: 1, slide: 0, ext: "png"),
                       "Lisbon-weekend_1.png")
        XCTAssertEqual(ExportPlan.slideName("Lisbon weekend", pageIndex: 0, files: 1, slide: 2, ext: "jpg"),
                       "Lisbon-weekend_3.jpg")
        XCTAssertEqual(ExportPlan.slideName("Lisbon weekend", pageIndex: 1, files: 2, slide: 0, ext: "png"),
                       "Lisbon-weekend-2_1.png")
        var cut = Design(title: "c", width: 3240, height: 1350)
        var first = Page(id: "a")
        first.split = PageSplit(columns: 3)
        cut.pages = [first, Page(id: "b")]
        XCTAssertTrue(ExportPlan.offersSplit(format: "png", design: cut, pages: [0, 1]))
        XCTAssertTrue(ExportPlan.offersSplit(format: "jpg", design: cut, pages: [0]))
        XCTAssertFalse(ExportPlan.offersSplit(format: "png", design: cut, pages: [1]))
        XCTAssertFalse(ExportPlan.offersSplit(format: "pdf", design: cut, pages: [0]))
        // A file a slide of the carousel, a file a page of the rest.
        XCTAssertEqual(ExportPlan.fileCount(design: cut, pages: [0, 1], split: true), 4)
        XCTAssertEqual(ExportPlan.fileCount(design: cut, pages: [0, 1], split: false), 2)
    }

    /// "split" is kept with the export settings, on when missing.
    func testSplitIntoSlidesIsKeptAndOnUnlessTurnedOff() throws {
        let off = ExportLast(format: "png", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                             pages: "all", split: false)
        XCTAssertTrue(off.json.hasSuffix(#""split":false}"#))
        XCTAssertEqual(ExportLast.read(off.json), off)
        XCTAssertEqual(ExportLast.read(#"{"format":"png"}"#)?.split, true)
    }

    // MARK: page.split

    private func json(_ page: Page) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
    }

    private func read(_ split: String) throws -> PageSplit? {
        try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p","split":\#(split)}"#.utf8)).split
    }

    func testAPagesSplitIsWrittenWholeAndReadBack() throws {
        var page = Page(id: "p")
        page.split = PageSplit(columns: 3)
        let written = try XCTUnwrap(try json(page)["split"] as? [String: Any])
        XCTAssertEqual(written["columns"] as? Int, 3)
        XCTAssertEqual(written["rows"] as? Int, 1)
        XCTAssertEqual(written.count, 2)
        XCTAssertEqual(try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page)).split,
                       PageSplit(columns: 3, rows: 1))
        page.split = nil
        XCTAssertNil(try json(page)["split"], "no split, no key")
        // A row count not written is one; nonsense is no split.
        XCTAssertEqual(try read(#"{"columns":4}"#), PageSplit(columns: 4, rows: 1))
        XCTAssertNil(try read(#"{"columns":0,"rows":1}"#))
        XCTAssertNil(try read(#"{"columns":"3"}"#))
        XCTAssertNil(try read("3"))
    }

    private func carousel() -> Design {
        var design = Design(title: "c", width: 3240, height: 1350)
        var text = Element.text("Hi")
        text.x = 2500
        var page = Page(id: "p", elements: [text])
        page.split = PageSplit(columns: 3)
        design.pages = [page, Page(id: "q")]
        return design
    }

    func testTheStepperResizesThePageASlideAtATimeTwoToTen() throws {
        let design = carousel()
        let four = try XCTUnwrap(PageSplit.resized(design, pageId: "p", columns: 4))
        XCTAssertEqual(four.size(for: four.pages[0]).width, 4320, accuracy: 1e-9)
        XCTAssertEqual(four.size(for: four.pages[0]).height, 1350, accuracy: 1e-9)
        XCTAssertEqual(four.pages[0].split?.columns, 4)
        // Nothing on it moves; the other page keeps the design's size.
        XCTAssertEqual(four.pages[0].elements[0].x, 2500, accuracy: 1e-9)
        XCTAssertEqual(four.size(for: four.pages[1]).width, 3240, accuracy: 1e-9)
        // Back to three is the design's own width again: none of its own.
        XCTAssertNil(try XCTUnwrap(PageSplit.resized(four, pageId: "p", columns: 3)).pages[0].width)
        // Held to 2...10.
        let two = try XCTUnwrap(PageSplit.resized(design, pageId: "p", columns: 1))
        XCTAssertEqual(two.size(for: two.pages[0]).width, 2160, accuracy: 1e-9)
        let ten = try XCTUnwrap(PageSplit.resized(design, pageId: "p", columns: 12))
        XCTAssertEqual(ten.size(for: ten.pages[0]).width, 10800, accuracy: 1e-9)
        // A page that is not cut, or already that many, is left alone.
        XCTAssertNil(PageSplit.resized(design, pageId: "q", columns: 4))
        XCTAssertNil(PageSplit.resized(design, pageId: "p", columns: 3))
        let seams = PageSplit.seams(CGSize(width: 3240, height: 1350), PageSplit(columns: 3))
        XCTAssertEqual(seams.vertical, [1080, 2160])
        XCTAssertEqual(seams.horizontal, [])
    }

    /// Resize, a page's own size and Copy & resize cut each page as its
    /// new size is: a carousel type's pixels into its slides, any other
    /// size not at all. Both phones' rows.
    @MainActor
    func testAResizedPageIsCutAsItsNewSizeIs() throws {
        XCTAssertEqual(PageSplit.forSize(width: 3240, height: 1350), PageSplit(columns: 3))
        XCTAssertNil(PageSplit.forSize(width: 1080, height: 1080))
        XCTAssertNil(PageSplit.forSize(width: 3240, height: 1080))
        var carousel = Design(title: "c", width: 3240, height: 1350)
        var page = Page(id: "p")
        page.split = PageSplit(columns: 3)
        carousel.pages = [page]
        XCTAssertNil(DesignStore.reflowed(carousel, width: 1080, height: 1080).pages[0].split)
        let scaled = DesignStore(design: carousel)
        scaled.resizeDesign(width: 1080, height: 1080)
        XCTAssertNil(scaled.design.pages[0].split)
        var square = Design(title: "s", width: 1080, height: 1080)
        square.pages = [Page(id: "p")]
        XCTAssertEqual(DesignStore.reflowed(square, width: 3240, height: 1350).pages[0].split, PageSplit(columns: 3))
        // A carousel stepped to four slides, resized to the carousel type:
        // three again, as its size says.
        let four = DesignStore(design: try XCTUnwrap(PageSplit.resized(carousel, pageId: "p", columns: 4)))
        four.resizeDesign(width: 3240, height: 1350)
        XCTAssertEqual(four.design.pages[0].split, PageSplit(columns: 3))
        // One page to a size of its own.
        let one = DesignStore(design: carousel)
        one.resizePage(width: 1080, height: 1080, reflow: true)
        XCTAssertNil(one.design.pages[0].split)
        let made = DesignStore(design: square)
        made.resizePage(width: 3240, height: 1350, reflow: false)
        XCTAssertEqual(made.design.pages[0].split, PageSplit(columns: 3))
        // Copy & resize.
        let copy = CopyResize.copy(of: carousel, to: .custom(width: 1080, height: 1080, unit: "px"), title: "t")
        XCTAssertNil(copy.pages[0].split)
    }

    @MainActor
    func testTheStepperIsOneUndoStepAndRefusedOnALockedPage() {
        var design = Design(title: "c", width: 3240, height: 1350)
        var page = Page(id: "p")
        page.split = PageSplit(columns: 3)
        design.pages = [page]
        let store = DesignStore(design: design)
        XCTAssertTrue(store.setSlides(5))
        XCTAssertEqual(store.pageSize.width, 5400, accuracy: 1e-9)
        XCTAssertFalse(store.setSlides(5))
        store.undo()
        XCTAssertEqual(store.slides?.columns, 3)
        XCTAssertNil(store.page.width)
        store.setPageLocked(true)
        XCTAssertFalse(store.setSlides(4))
        XCTAssertEqual(store.slides?.columns, 3)
    }

    // MARK: the catalogue

    /// The types this round adds, each with its size in pixels.
    private let added: [(String, Double, Double)] = [
        ("insta-carousel", 3240, 1350), ("linkedin-carousel", 3240, 1350), ("highlight-cover", 1080, 1920),
        ("threads-post", 1080, 1350), ("shorts-cover", 1080, 1920), ("linkedin-article", 1920, 1080),
        ("facebook-ad", 1080, 1080), ("whatsapp-status", 1080, 1920), ("twitch-panel", 320, 160),
        ("discord-banner", 960, 540), ("report-a4", 2480, 3508), ("report-letter", 2550, 3300),
        ("proposal", 2550, 3300), ("lesson-plan-a4", 2480, 3508), ("mind-map", 1920, 1080),
        ("flowchart", 1920, 1080), ("trifold-letter", 3300, 2550), ("rack-card", 1200, 2700),
        ("flyer-a5", 1748, 2480), ("flyer-dl", 1169, 2480), ("wedding-invitation", 1500, 2100),
        ("birthday-card", 1500, 2100), ("thank-you-card", 1500, 2100), ("tshirt-print", 4500, 5400),
        ("tote-print", 3600, 3600),
    ]

    func testEveryNewTypeIsInTheCatalogueAtItsSizeWithAtLeastSixTemplates() throws {
        XCTAssertEqual(SizePreset.all.count, 97)
        for (id, w, h) in added {
            let preset = try XCTUnwrap(SizePreset.byId(id), id)
            XCTAssertEqual(preset.w, w, id)
            XCTAssertEqual(preset.h, h, id)
            XCTAssertFalse(preset.keywords.isEmpty, "\(id) has no keywords")
            let count = ContentLibrary.sizedTemplates(for: preset).count
            XCTAssertGreaterThanOrEqual(count, 6, "\(id) has \(count) templates")
        }
        XCTAssertEqual(SizePreset.byId("insta-carousel")?.split, 3)
        XCTAssertEqual(SizePreset.byId("linkedin-carousel")?.split, 3)
        XCTAssertNil(SizePreset.byId("threads-post")?.split)
    }

    func testEverySizeIdHasTemplates() {
        for preset in SizePreset.all where preset.id != Docs.presetId {
            // A Doc starts from its own blocks (DocTemplates).
            XCTAssertFalse(ContentLibrary.sizedTemplates(for: preset).isEmpty, "\(preset.id) has no template")
        }
    }

    /// Shared: both repos pin the same digest of templates/sizes.json
    /// (Fixtures/sizes-json.sha256), so the file is byte for byte the same
    /// on either phone — and Content.json's sizes, which this phone reads,
    /// are that file entry for entry.
    func testSizesJSONIsTheOneBothReposPin() throws {
        let bytes = try SharedFixture.data("sizes")
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let pinned = try SharedFixture.text("sizes-json", ext: "sha256").trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(digest, pinned)
        XCTAssertEqual(try JSONDecoder().decode([SizePreset].self, from: bytes), SizePreset.all)
    }

    func testTheRoundsTemplatesAreSetsWhereTheTypeAsksAndCarouselsCrossTheirSeams() throws {
        func sets(_ sizeId: String) -> [Template] {
            ContentLibrary.templates.filter { $0.topic != nil && $0.id.hasPrefix(sizeId) }
        }
        XCTAssertTrue(sets("report-a4").allSatisfy { $0.pageCount == 4 })
        XCTAssertTrue(sets("report-letter").allSatisfy { $0.pageCount == 4 })
        XCTAssertEqual(sets("proposal").count, 6)
        XCTAssertTrue(sets("proposal").allSatisfy { $0.pageCount == 5 })
        XCTAssertTrue(sets("trifold-letter").allSatisfy { $0.pageCount == 2 })
        XCTAssertTrue(sets("birthday-card").allSatisfy { $0.pageCount == 2 })
        XCTAssertTrue(sets("thank-you-card").allSatisfy { $0.pageCount == 2 })
        let carousels = ContentLibrary.templates.filter { $0.topic == "carousel" }
        XCTAssertEqual(carousels.count, 6)
        let seams = [1080.0, 2160.0]
        for t in carousels {
            XCTAssertTrue(t.elements.contains { el in seams.contains { el.x < $0 && el.x + el.w > $0 } }, t.id)
            // Its words stay inside a slide each.
            for el in t.elements where el.type == .text {
                XCTAssertFalse(seams.contains { el.x < $0 && el.x + el.w > $0 }, "\(t.id): \(el.text ?? "")")
            }
            // Opened, it is cut into three slides.
            XCTAssertEqual(t.instantiate().pages[0].split, PageSplit(columns: 3))
        }
    }

    // MARK: what a blank design starts with

    func testACarouselStartsCutFoldedCardsAndTheTrifoldAsTwoPages() throws {
        let carousel = try XCTUnwrap(SizePreset.byId("linkedin-carousel")).makeDesign()
        XCTAssertEqual(carousel.pages[0].split, PageSplit(columns: 3))
        for id in ["birthday-card", "thank-you-card", "trifold-letter"] {
            XCTAssertEqual(try XCTUnwrap(SizePreset.byId(id)).makeDesign().pages.count, 2, id)
        }
        XCTAssertEqual(try XCTUnwrap(SizePreset.byId("wedding-invitation")).makeDesign().pages.count, 1)
        let trifold = try XCTUnwrap(SizePreset.byId("trifold-letter")).makeDesign()
        XCTAssertEqual(trifold.guides.map(\.position), [1100, 2200])
        XCTAssertTrue(trifold.guides.allSatisfy(\.vertical))
        XCTAssertTrue(try XCTUnwrap(SizePreset.byId("poster")).makeDesign().guides.isEmpty)
    }

    func testAMindMapAndAFlowchartStartAsWhiteboardsJoinedByConnectors() throws {
        let page = try XCTUnwrap(SizePreset.byId("mind-map")).makeDesign().pages[0]
        XCTAssertTrue(Whiteboards.isExpanded(page))
        XCTAssertEqual(page.elements.filter(DesignTypes.isConnector).count, 4)
        XCTAssertEqual(page.elements.filter { !DesignTypes.isConnector($0) }.count, 5)
        // Every arrow leaves the main idea.
        let centre = try XCTUnwrap(page.elements.first)
        XCTAssertTrue(page.elements.filter(DesignTypes.isConnector).allSatisfy { $0.connectFrom == centre.id })
        let flow = try XCTUnwrap(SizePreset.byId("flowchart")).makeDesign().pages[0]
        XCTAssertTrue(Whiteboards.isExpanded(flow))
        XCTAssertEqual(flow.elements.filter(DesignTypes.isConnector).count, 3)
        XCTAssertEqual(flow.elements.filter { !DesignTypes.isConnector($0) }.map(\.text),
                       ["Start", "Step", "Decision?", "End"])
    }

    func testATShirtOrAToteSuggestsAClearBackground() throws {
        XCTAssertTrue(DesignTypes.suggestsClear(try XCTUnwrap(SizePreset.byId("tshirt-print")).makeDesign()))
        XCTAssertTrue(DesignTypes.suggestsClear(try XCTUnwrap(SizePreset.byId("tote-print")).makeDesign()))
        XCTAssertFalse(DesignTypes.suggestsClear(try XCTUnwrap(SizePreset.byId("insta-post")).makeDesign()))
    }
}
