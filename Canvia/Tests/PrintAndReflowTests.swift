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

    func testATiledPosterMarksTheTrimOnlyOnTilesThatHoldItsCorners() {
        let page = CGSize(width: 300, height: 100)
        func tile(_ sourceX: Double) -> [(CGPoint, CGPoint)] {
            PrintLayout.sheetMarks(sheet: CGRect(x: 20, y: 20, width: 110, height: 100),
                                   source: CGRect(x: sourceX, y: 0, width: 110, height: 100),
                                   page: page, bleed: 10)
        }
        // The left tile holds the two left corners: two marks at each.
        XCTAssertEqual(tile(0).count, 4)
        XCTAssertTrue(tile(0).allSatisfy { $0.0.x < 40 })
        // A middle tile holds no corner, so it carries no mark.
        XCTAssertEqual(tile(100).count, 0)
        // The right tile's marks are at the trim (290 in the page), not the tile's edge.
        let right = tile(190)
        XCTAssertEqual(right.count, 4)
        XCTAssertTrue(right.contains { $0.0.x == $0.1.x && $0.0.x == 120 })
        // A page fitted whole keeps all eight, round its trim.
        let whole = PrintLayout.sheetMarks(sheet: CGRect(x: 0, y: 0, width: 300, height: 100),
                                           source: CGRect(x: 0, y: 0, width: 300, height: 100),
                                           page: page, bleed: 10)
        XCTAssertEqual(whole.count, 8)
    }

    /// The marks stand clear of the printed bleed: they start the bleed, at
    /// the sheet's scale, plus 4 pt out from the trim — as the Android twin
    /// draws them — so none is drawn over artwork, whatever the bleed.
    func testCropMarksStartPastTheBleed() {
        let page = CGSize(width: 300, height: 100)
        let bleed = 10.0
        for scale in [1.0, 2.0] {
            let sheet = CGRect(x: 0, y: 0, width: page.width * scale, height: page.height * scale)
            let marks = PrintLayout.sheetMarks(sheet: sheet, source: CGRect(origin: .zero, size: page),
                                               page: page, bleed: bleed)
            XCTAssertEqual(marks.count, 8)
            let gap = bleed * scale + 4
            let trim = sheet.insetBy(dx: bleed * scale, dy: bleed * scale)
            for (a, b) in marks {
                if a.y == b.y {
                    let out = a.x < trim.minX ? trim.minX - a.x : a.x - trim.maxX
                    XCTAssertEqual(out, gap, accuracy: 1e-9, "an across mark at \(a.x), scale \(scale)")
                    XCTAssertFalse(sheet.contains(CGPoint(x: (a.x + b.x) / 2, y: a.y)), "a mark on the bleed")
                } else {
                    let out = a.y < trim.minY ? trim.minY - a.y : a.y - trim.maxY
                    XCTAssertEqual(out, gap, accuracy: 1e-9, "a down mark at \(a.y), scale \(scale)")
                    XCTAssertFalse(sheet.contains(CGPoint(x: a.x, y: (a.y + b.y) / 2)), "a mark on the bleed")
                }
            }
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
    func testPrintPDFWritesOnePageForFitAndManyForTiles() async throws {
        var d = Design(title: "p", width: 4000, height: 3000)
        d.pages[0].elements = [.shape("rect", w: 500, h: 500)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("print-\(UUID()).pdf")
        var o = PrintLayout.Options()
        try await DesignExporter.exportPrintPDF(design: d, options: o, to: url)
        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 1)
        o.fit = .tile
        try await DesignExporter.exportPrintPDF(design: d, options: o, to: url)
        // 3000×2250pt onto 559×806 printable: many sheets.
        XCTAssertGreaterThan(CGPDFDocument(url as CFURL)?.numberOfPages ?? 0, 6)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: Several to a sheet

    /// A 3.5 × 2 in business card at 300 dpi.
    private func card(pages: Int = 1) -> Design {
        var d = Design(title: "card", width: 1050, height: 600)
        d.unit = "in"
        d.dpi = 300
        d.pages = (0..<pages).map { _ in Page(elements: [.shape("rect", w: 300, h: 200)]) }
        return d
    }

    private func letter() throws -> PrintLayout.Paper {
        try XCTUnwrap(PrintLayout.papers.first { $0.id == "letter" })
    }

    func testTheNewPapers() {
        let sizes = Dictionary(uniqueKeysWithValues: PrintLayout.papers.map { ($0.name, $0.size) })
        XCTAssertEqual(sizes["A5"], CGSize(width: 420, height: 595))
        XCTAssertEqual(sizes["Legal"], CGSize(width: 612, height: 1008))
        XCTAssertEqual(sizes["Photo 4×6"], CGSize(width: 288, height: 432))
        XCTAssertEqual(sizes["5×7"], CGSize(width: 360, height: 504))
        XCTAssertEqual(PrintLayout.Fit.allCases.map(\.rawValue), ["fit", "actual", "tile", "several"])
        XCTAssertEqual(PrintLayout.Fit.several.name, "Several to a sheet")
    }

    /// floor((576 + 0) / (252 + 0)) = 2 across and floor(756 / 144) = 5
    /// down: ten cards, the grid centred.
    func testABusinessCardOnLetterGivesTenPlacements() throws {
        var o = PrintLayout.Options()
        o.paper = try letter()
        o.fit = .several
        let d = card(pages: 2)
        let pts = PrintLayout.pagePoints(design: d, bleed: 0)
        XCTAssertEqual(pts, CGSize(width: 252, height: 144))
        let grid = PrintLayout.grid(page: pts, printable: o.printable, gap: o.gapPoints)
        XCTAssertEqual(grid.cols, 2)
        XCTAssertEqual(grid.rows, 5)
        XCTAssertEqual(DesignExporter.placements(pagePoints: pts, options: o).count, 10)
        XCTAssertEqual(grid.cells[0].minX, 306 - 252, accuracy: 0.001, "centred across")
        XCTAssertEqual(grid.cells[0].minY, 396 - 360, accuracy: 0.001, "centred down")
        let plan = DesignExporter.severalPlan(design: d, indices: [0, 1], options: o)
        XCTAssertEqual(plan.perSheet, 10)
        XCTAssertEqual(plan.sheets.count, 2, "repeat this page: a sheet a page")
        XCTAssertEqual(PrintLayout.severalNote(perSheet: plan.perSheet, sheets: plan.sheets.count), "10 per sheet, 2 sheets")
        XCTAssertEqual(PrintLayout.severalNote(perSheet: 4, sheets: 1), "4 per sheet, 1 sheet")
        XCTAssertEqual(DesignExporter.sheetCount(design: d, indices: [0, 1], options: o), 2)
    }

    /// No gap without bleed, twice the bleed with it, or as set; the gap
    /// counts in the grid's sum.
    func testTheGap() {
        var o = PrintLayout.Options()
        XCTAssertEqual(o.gapPoints, 0)
        o.bleed = 9
        XCTAssertEqual(o.gapPoints, 18)
        o.gap = 4
        XCTAssertEqual(o.gapPoints, 4)
        let printable = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(PrintLayout.grid(page: CGSize(width: 30, height: 30), printable: printable, gap: 5).cols, 3)
        XCTAssertEqual(PrintLayout.grid(page: CGSize(width: 30, height: 30), printable: printable, gap: 6).cols, 2)
        XCTAssertEqual(PrintLayout.grid(page: CGSize(width: 300, height: 30), printable: printable, gap: 0).cols, 1,
                       "too wide still prints one")
    }

    func testRepeatOrOneOfEach() {
        XCTAssertEqual(PrintLayout.severalSheets(indices: [0, 1, 2], perSheet: 2, mode: .oneOfEach, duplex: false),
                       [[0, 1], [2]])
        XCTAssertEqual(PrintLayout.severalSheets(indices: [3], perSheet: 3, mode: .repeatPage, duplex: false), [[3, 3, 3]])
        XCTAssertEqual(PrintLayout.severalSheets(indices: [0, 1], perSheet: 2, mode: .oneOfEach, duplex: true),
                       [[0, 0], [1, 1]], "double-sided: the front, then the back")
        XCTAssertEqual(PrintLayout.severalSheets(indices: [], perSheet: 2, mode: .repeatPage, duplex: false), [])
    }

    /// The back's columns mirrored for long-edge flip: column 0 lands on
    /// column cols − 1, so fronts and backs line up.
    func testDuplexMirroringMapsColumnZeroToTheLast() {
        XCTAssertEqual(PrintLayout.duplexColumn(0, cols: 2), 1)
        XCTAssertEqual(PrintLayout.duplexColumn(0, cols: 3), 2)
        XCTAssertEqual(PrintLayout.duplexColumn(1, cols: 3), 1)
        XCTAssertEqual(PrintLayout.duplexColumn(2, cols: 3), 0)
        XCTAssertEqual(PrintLayout.cellIndex(0, cols: 2, mirrored: true), 1)
        XCTAssertEqual(PrintLayout.cellIndex(3, cols: 2, mirrored: true), 2)
        XCTAssertEqual(PrintLayout.cellIndex(3, cols: 2, mirrored: false), 3)
        var o = PrintLayout.Options()
        o.fit = .several
        o.duplex = true
        let plan = DesignExporter.severalPlan(design: card(pages: 2), indices: [0, 1], options: o)
        XCTAssertTrue(plan.duplex)
        XCTAssertFalse(DesignExporter.severalPlan(design: card(pages: 3), indices: [0, 1], options: o).duplex,
                       "only a design of two pages")
    }

    /// Marks at every trim line, shared, and never inside a page placed —
    /// with no bleed, and with one.
    func testCropMarksNeverFallInsideAPlacedTrim() throws {
        for bleed in [0.0, 9] {
            var o = PrintLayout.Options()
            o.paper = try letter()
            o.bleed = bleed
            let pts = PrintLayout.pagePoints(design: card(), bleed: bleed)
            let cells = PrintLayout.grid(page: pts, printable: o.printable, gap: o.gapPoints).cells
            let trims = cells.map { $0.insetBy(dx: bleed, dy: bleed) }
            let marks = PrintLayout.gridMarks(trims: trims, placed: cells, gap: bleed + 4)
            XCTAssertFalse(marks.isEmpty)
            for (a, b) in marks {
                for trim in trims {
                    let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                    for point in [a, b, mid] {
                        XCTAssertFalse(point.x > trim.minX && point.x < trim.maxX && point.y > trim.minY && point.y < trim.maxY,
                                       "a mark inside a trim, bleed \(bleed)")
                    }
                }
            }
            // Every trim line has its marks: each column edge upright, each
            // row edge level.
            let uprights = Set(marks.filter { $0.0.x == $0.1.x }.map { Double($0.0.x) })
            let levels = Set(marks.filter { $0.0.y == $0.1.y }.map { Double($0.0.y) })
            for trim in trims {
                XCTAssertTrue(uprights.contains(Double(trim.minX)) && uprights.contains(Double(trim.maxX)))
                XCTAssertTrue(levels.contains(Double(trim.minY)) && levels.contains(Double(trim.maxY)))
            }
        }
    }

    @MainActor
    func testADoubleSidedSheetOfCardsIsTwoPages() async throws {
        var o = PrintLayout.Options()
        o.paper = try letter()
        o.fit = .several
        o.duplex = true
        o.cropMarks = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("several-\(UUID()).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await DesignExporter.exportPrintPDF(design: card(pages: 2), options: o, to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 2)
        XCTAssertEqual(try XCTUnwrap(pdf.page(at: 1)).getBoxRect(.mediaBox).size, CGSize(width: 612, height: 792))
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

    @MainActor
    func testResizingScalesEveryPageUnitAndMovesGuidesWithTheContent() {
        // The rule the Android twin's PageResize follows too, so the same
        // resize lands the same way on either phone.
        var d = Design(title: "r", width: 1080, height: 1080)
        var box = Element.shape("rect", w: 200, h: 100)
        box.radius = 20
        box.strokeWidth = 4
        var text = Element.text("Hi", fontSize: 40, w: 400)
        text.letterSpacing = 6
        d.pages[0].elements = [box, text]
        d.guides = [Guide(id: "h", vertical: false, position: 100)]
        let store = DesignStore(design: d)
        store.resizeDesign(width: 540, height: 960)
        // Scale 0.5, and the 540-square content is centred 210 down.
        XCTAssertEqual(store.design.guides[0].position, 100 * 0.5 + 210, accuracy: 0.001)
        XCTAssertEqual(store.design.pages[0].elements[0].radius ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(store.design.pages[0].elements[0].strokeWidth ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(store.design.pages[0].elements[1].letterSpacing ?? 0, 3, accuracy: 0.001)
    }

    @MainActor
    func testPerCornerRadiiScaleToo() {
        var d = Design(title: "r", width: 1080, height: 1080)
        var box = Element.shape("rect", w: 200, h: 200)
        box.corners = [60, 0, 60, 0]
        d.pages[0].elements = [box]
        let store = DesignStore(design: d)
        store.resizeDesign(width: 540, height: 540)
        XCTAssertEqual(store.design.pages[0].elements[0].corners ?? [], [30, 0, 30, 0])
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
