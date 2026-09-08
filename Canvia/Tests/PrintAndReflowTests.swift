// Print layout maths, magic (reflowing) resize and the Spotlight index.

import XCTest
import CoreGraphics
import CoreSpotlight
@testable import Canvia

final class PrintAndReflowTests: XCTestCase {

    // MARK: Print layout

    func testFitRectCentresAndKeepsAspect() {
        let printable = CGRect(x: 18, y: 18, width: 559, height: 806)
        let r = PrintLayout.fitRect(page: CGSize(width: 800, height: 400), in: printable)
        XCTAssertEqual(r.width, 559, accuracy: 0.01)
        XCTAssertEqual(r.height, 279.5, accuracy: 0.01)
        XCTAssertEqual(r.midX, printable.midX, accuracy: 0.01)
        XCTAssertEqual(r.midY, printable.midY, accuracy: 0.01)
    }

    func testFitRectGrowsASmallPage() {
        let printable = CGRect(x: 0, y: 0, width: 500, height: 500)
        let r = PrintLayout.fitRect(page: CGSize(width: 100, height: 50), in: printable)
        XCTAssertEqual(r.width, 500, accuracy: 0.01)
        XCTAssertEqual(r.height, 250, accuracy: 0.01)
    }

    func testTilesCoverThePageWithOverlap() {
        let page = CGSize(width: 1000, height: 700)
        let printable = CGSize(width: 400, height: 400)
        let tiles = PrintLayout.tiles(page: page, printable: printable, overlap: 20)
        // 380pt steps: ceil(980/380)=3 columns, ceil(680/380)=2 rows.
        XCTAssertEqual(tiles.count, 6)
        XCTAssertEqual(tiles[0].origin, .zero)
        XCTAssertEqual(tiles[1].minX, 380)
        XCTAssertEqual(tiles[3].minY, 380)
        // Every tile is one printable area and neighbours overlap by 20.
        for t in tiles { XCTAssertEqual(t.size, printable) }
        XCTAssertEqual(tiles[0].maxX - tiles[1].minX, 20)
        // The union reaches past the page's far edges.
        XCTAssertGreaterThanOrEqual(tiles.last!.maxX, page.width)
        XCTAssertGreaterThanOrEqual(tiles.last!.maxY, page.height)
    }

    func testPageThatFitsIsOneTile() {
        let tiles = PrintLayout.tiles(page: CGSize(width: 300, height: 200),
                                      printable: CGSize(width: 400, height: 400), overlap: 20)
        XCTAssertEqual(tiles.count, 1)
    }

    func testCropMarksSitOutsideEveryCorner() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 100)
        let marks = PrintLayout.cropMarkSegments(around: rect)
        XCTAssertEqual(marks.count, 8)
        for (a, b) in marks {
            // Neither end is inside the trimmed page.
            XCTAssertFalse(rect.insetBy(dx: -1, dy: -1).contains(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)))
            // Marks are axis aligned.
            XCTAssertTrue(a.x == b.x || a.y == b.y)
        }
    }

    func testLandscapeSwapsTheSheet() {
        var o = PrintLayout.Options()
        o.paper = PrintLayout.papers[0]
        XCTAssertEqual(o.sheet, CGSize(width: 595, height: 842))
        o.landscape = true
        XCTAssertEqual(o.sheet, CGSize(width: 842, height: 595))
        XCTAssertEqual(o.printable.width, 842 - 2 * o.margin)
    }

    func testPagePointsIncludesBleed() {
        let d = Design(title: "p", width: 960, height: 480)
        let pts = PrintLayout.pagePoints(design: d, bleed: 9)
        XCTAssertEqual(pts.width, 720 + 18, accuracy: 0.001)
        XCTAssertEqual(pts.height, 360 + 18, accuracy: 0.001)
    }

    @MainActor
    func testPrintPDFWritesOnePageForFitAndManyForTiles() throws {
        var d = Design(title: "p", width: 4000, height: 3000)
        d.pages[0].elements = [.shape("rect", w: 500, h: 500)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("print-\(UUID()).pdf")
        var o = PrintLayout.Options()
        try DesignExporter.exportPrintPDF(design: d, options: o, to: url)
        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 1)
        o.fit = .tile
        try DesignExporter.exportPrintPDF(design: d, options: o, to: url)
        // 3000×2250pt onto 559×806 printable: many sheets.
        XCTAssertGreaterThan(CGPDFDocument(url as CFURL)?.numberOfPages ?? 0, 6)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Magic resize

    func testReflowKeepsEdgesAnchoredAndShapesUnstretched() {
        var d = Design(title: "r", width: 1000, height: 1000)
        var logo = Element.shape("rect", w: 100, h: 100)
        logo.x = 900; logo.y = 0                 // top-right
        var footer = Element.shape("rect", w: 1000, h: 50)
        footer.x = 0; footer.y = 950             // bottom, full width
        d.pages[0].elements = [logo, footer]

        let tall = DesignStore.reflowed(d, width: 1000, height: 2000)
        XCTAssertEqual(tall.width, 1000); XCTAssertEqual(tall.height, 2000)
        let l = tall.pages[0].elements[0], f = tall.pages[0].elements[1]
        // The logo is still square, still touching the top-right corner.
        XCTAssertEqual(l.w, 100, accuracy: 0.01); XCTAssertEqual(l.h, 100, accuracy: 0.01)
        XCTAssertEqual(l.x + l.w, 1000, accuracy: 0.01); XCTAssertEqual(l.y, 0, accuracy: 0.01)
        // The footer sits at the foot of the taller page, not mid-way.
        XCTAssertEqual(f.y + f.h, 2000, accuracy: 0.01)
    }

    func testReflowScalesByTheSmallerRatioAndKeepsElementsOnPage() {
        var d = Design(title: "r", width: 1000, height: 1000)
        var e = Element.shape("circle", w: 400, h: 400)
        e.x = 300; e.y = 300
        d.pages[0].elements = [e]
        let wide = DesignStore.reflowed(d, width: 3000, height: 500)
        let c = wide.pages[0].elements[0]
        XCTAssertEqual(c.w, 200, accuracy: 0.01)          // min(3, 0.5) = 0.5
        XCTAssertEqual(c.h, 200, accuracy: 0.01)
        XCTAssertEqual(c.x + c.w / 2, 1500, accuracy: 0.01)  // centre stays centred
        XCTAssertGreaterThanOrEqual(c.y, 0)
        XCTAssertLessThanOrEqual(c.y + c.h, 500)
    }

    @MainActor
    func testTextWidensOnAWiderPageAndFontScales() {
        var d = Design(title: "r", width: 1000, height: 1000)
        var t = Element.text("Hello wide world", fontSize: 40, w: 400)
        t.x = 300; t.y = 100
        d.pages[0].elements = [t]
        let wide = DesignStore.reflowed(d, width: 2000, height: 1000)
        let out = wide.pages[0].elements[0]
        XCTAssertEqual(out.fontSize ?? 0, 40, accuracy: 0.01)   // ratio min(2, 1) = 1
        XCTAssertEqual(out.w, 800, accuracy: 0.01)               // stretched by the width ratio
        XCTAssertLessThanOrEqual(out.x + out.w, 2000)
    }

    func testReflowMovesGuidesAndIsIdentityForSameSize() {
        var d = Design(title: "r", width: 1000, height: 500)
        d.guides = [Guide(id: "g", vertical: true, position: 250), Guide(id: "h", vertical: false, position: 100)]
        let out = DesignStore.reflowed(d, width: 2000, height: 1000)
        XCTAssertEqual(out.guides[0].position, 500)
        XCTAssertEqual(out.guides[1].position, 200)
        XCTAssertEqual(DesignStore.reflowed(d, width: 1000, height: 500), d)
    }

    @MainActor
    func testMagicResizeIsUndoable() {
        var d = Design(title: "r", width: 1000, height: 1000)
        d.pages[0].elements = [.shape("rect", w: 100, h: 100)]
        let store = DesignStore(design: d)
        store.magicResize(width: 500, height: 2000)
        XCTAssertEqual(store.design.width, 500)
        XCTAssertEqual(store.design.pages[0].elements[0].w, 50, accuracy: 0.01)
        store.undo()
        XCTAssertEqual(store.design.width, 1000)
        XCTAssertEqual(store.design.pages[0].elements[0].w, 100, accuracy: 0.01)
    }

    // MARK: Spotlight

    func testSpotlightWordsAreDistinctLowercaseAndSkipOneLetterWords() {
        var d = Design(title: "s", width: 100, height: 100)
        d.pages[0].elements = [.text("Summer Sale! A sale, summer-time 2026"), .shape("rect")]
        XCTAssertEqual(SpotlightIndexer.words(in: d), ["summer", "sale", "time", "2026"])
    }

    func testSpotlightAttributesCarryTitleKeywordsAndDescription() {
        var d = Design(title: "Bake Sale", width: 800, height: 600)
        d.pages[0].elements = [.text("Fresh bread Sunday")]
        let a = SpotlightIndexer.attributes(for: d)
        XCTAssertEqual(a.title, "Bake Sale")
        XCTAssertEqual(a.keywords ?? [], ["fresh", "bread", "sunday"])
        XCTAssertEqual(a.contentDescription, "fresh bread sunday")
        XCTAssertNil(a.thumbnailData)

        let empty = SpotlightIndexer.attributes(for: Design(title: "Blank", width: 800, height: 600))
        XCTAssertEqual(empty.contentDescription, "1 page, 800 × 600")
    }

    func testSpotlightActivityYieldsDesignID() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "abc"]
        XCTAssertEqual(SpotlightIndexer.designID(from: activity), "abc")
        XCTAssertNil(SpotlightIndexer.designID(from: NSUserActivity(activityType: "other")))
    }
}
