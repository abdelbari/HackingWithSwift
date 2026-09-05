// Freehand strokes, drops, reading order, read-aloud scripts, the tour,
// folders and template categories.

import XCTest
import UIKit
@testable import Canvia

final class DrawingAndHomeTests: XCTestCase {

    // MARK: freehand

    func testThinningDropsJitterButKeepsTheLine() {
        let jitter = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 21, y: 0.5)]
        XCTAssertEqual(Freehand.thinned(jitter), [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0)])
    }

    func testPathDataIsQuadraticsThroughMidpoints() {
        let d = Freehand.pathData([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0)])
        // Start, one curve to the midpoint of the last pair, one to the end.
        XCTAssertEqual(d, "M0 0Q10 10 15 5Q20 0 20 0")
    }

    func testTwoPointsDrawStraightAndOneIsADot() {
        XCTAssertEqual(Freehand.pathData([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)]), "M0 0Q5 0 10 0")
        XCTAssertEqual(Freehand.pathData([CGPoint(x: 3, y: 4)]), "M3 4Q3 4 3 4")
        XCTAssertEqual(Freehand.pathData([]), "")
        XCTAssertNil(Freehand.element(points: [], tool: Freehand.Tool()))
    }

    func testStrokeElementIsAnUnfilledPathInItsOwnBox() throws {
        let tool = Freehand.Tool(color: "#ef4444", width: 10)
        let el = try XCTUnwrap(Freehand.element(points: [CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 260)], tool: tool))
        // Bounds 200×60 padded by width/2 + 1 on every side.
        XCTAssertEqual(el.x, 94); XCTAssertEqual(el.y, 194)
        XCTAssertEqual(el.w, 212); XCTAssertEqual(el.h, 72)
        XCTAssertEqual(el.type, .shape)
        XCTAssertEqual(el.fill?.kind, "none")
        XCTAssertEqual(el.stroke, "#ef4444")
        XCTAssertEqual(el.strokeWidth, 10)
        // Normalised into the 0…100 box: the first point sits width/2+1 in.
        XCTAssertTrue(el.pathData?.hasPrefix("M2.83 8.33") == true, el.pathData ?? "")
        // The live path and the stored data agree on where the line goes.
        let box = Freehand.cgPath([CGPoint(x: 100, y: 200), CGPoint(x: 300, y: 200), CGPoint(x: 300, y: 260)]).boundingBoxOfPath
        XCTAssertEqual(box.minX, 100, accuracy: 0.01)
        XCTAssertEqual(box.maxX, 300, accuracy: 0.01)
    }

    @MainActor
    func testAStrokeIsOneUndoStepAndLeavesNothingSelected() {
        let store = DesignStore(design: Design(title: "d", width: 400, height: 300))
        store.toggleDrawing()
        XCTAssertNotNil(store.drawing)
        store.finishStroke([CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 40), CGPoint(x: 90, y: 10)])
        XCTAssertEqual(store.page.elements.count, 1)
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertEqual(store.haptic.kind, .stroke)
        store.undo()
        XCTAssertTrue(store.page.elements.isEmpty)
        store.toggleDrawing()
        XCTAssertNil(store.drawing)
    }

    @MainActor
    func testUnfilledShapesExportWithNoFillAndRoundCaps() {
        var d = Design(title: "s", width: 400, height: 300)
        var el = Element.shape("rect", w: 100, h: 50)
        el.fill = Paint.clear; el.stroke = "#ff0000"; el.strokeWidth = 3
        d.pages[0].elements = [el]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("fill=\"none\""), svg)
        XCTAssertTrue(svg.contains("stroke-linecap=\"round\""), svg)
        XCTAssertTrue(svg.contains("stroke=\"#ff0000\""), svg)
    }

    // MARK: drop

    func testDroppedPictureIsHalfThePageWideCentredAndOnThePage() {
        let page = CGSize(width: 1000, height: 800)
        let mid = CanvasDrop.imageFrame(natural: CGSize(width: 400, height: 300), page: page, at: CGPoint(x: 500, y: 400))
        // Smaller than half the page, so it keeps its own size.
        XCTAssertEqual(mid, CGRect(x: 300, y: 250, width: 400, height: 300))
        let big = CanvasDrop.imageFrame(natural: CGSize(width: 4000, height: 3000), page: page, at: CGPoint(x: 500, y: 400))
        XCTAssertEqual(big, CGRect(x: 250, y: 212, width: 500, height: 375))
        // Dropped at the corner: slid back inside, not shrunk.
        let corner = CanvasDrop.imageFrame(natural: CGSize(width: 400, height: 300), page: page, at: CGPoint(x: 990, y: 790))
        XCTAssertEqual(corner.maxX, 1000); XCTAssertEqual(corner.maxY, 800)
        XCTAssertEqual(corner.size, mid.size)
        // A tiny picture keeps its own size.
        XCTAssertEqual(CanvasDrop.imageFrame(natural: CGSize(width: 100, height: 50), page: page, at: .zero).size, CGSize(width: 100, height: 50))
    }

    @MainActor
    func testDroppedTextIsLeftAlignedAtTheDropPoint() {
        let el = CanvasDrop.textElement("  Hello there  ", page: CGSize(width: 1000, height: 800), at: CGPoint(x: 500, y: 100))
        XCTAssertEqual(el.text, "Hello there")
        XCTAssertEqual(el.align, "left")
        XCTAssertEqual(el.w, 600)
        XCTAssertEqual(el.x, 200)
        XCTAssertGreaterThan(el.h, 0)
        XCTAssertEqual(el.fontSize, 40)
    }

    // MARK: reading order

    func testReadingOrderIsRowsTopToBottomThenLeftToRight() {
        func at(_ x: Double, _ y: Double, _ id: String) -> Element {
            var e = Element.shape("rect", w: 50, h: 50); e.x = x; e.y = y; e.id = id; return e
        }
        // Added out of order; c and b share a row (tops 10 apart on a 1000 page).
        let els = [at(300, 500, "footer"), at(400, 20, "c"), at(100, 30, "b"), at(0, 600, "bottomLeft"), at(0, 0, "a")]
        XCTAssertEqual(CanvasAccessibility.readingOrder(els, pageHeight: 1000), ["a", "b", "c", "footer", "bottomLeft"])
        XCTAssertEqual(CanvasAccessibility.readingOrder([], pageHeight: 1000), [])
    }

    // MARK: read aloud

    @MainActor
    func testScriptReadsTextInOrderWithAltTextAndPageNumbers() {
        var d = Design(title: "r", width: 400, height: 600)
        var title = Element.text("Big Sale!", fontSize: 40); title.x = 0; title.y = 0
        var body = Element.text("Everything half price", fontSize: 20); body.x = 0; body.y = 200
        var pic = Element.image("asset:x", w: 100, h: 100); pic.x = 0; pic.y = 400; pic.altText = "a red bicycle"
        var footer = Element.text("Page {page} of {pages}", fontSize: 12); footer.x = 0; footer.y = 560
        var mute = Element.image("asset:y", w: 10, h: 10); mute.x = 200; mute.y = 400
        d.pages = [Page(elements: [footer, mute, pic, body, title]), Page()]
        XCTAssertEqual(ReadAloud.script(for: d.pages[0], in: d),
                       "Big Sale! Everything half price. Picture: a red bicycle. Page 1 of 2.")
        XCTAssertEqual(ReadAloud.script(for: d.pages[1], in: d), "")
    }

    func testSentencesEndEveryPartOnce() {
        XCTAssertEqual(ReadAloud.sentences(["SALE", "50% off!", "Sunday:"]), "SALE. 50% off! Sunday:")
        XCTAssertEqual(ReadAloud.sentences([]), "")
    }

    // MARK: tour

    func testTourShowsOnceAndNeverUnderTheCamera() {
        let defaults = UserDefaults(suiteName: "tour-\(UUID())")!
        XCTAssertTrue(Onboarding.needsTour(defaults: defaults, arguments: []))
        XCTAssertFalse(Onboarding.needsTour(defaults: defaults, arguments: ["-canviaSkipTour"]))
        XCTAssertFalse(Onboarding.needsTour(defaults: defaults, arguments: ["-canviaOpenTemplate", "0"]))
        Onboarding.markSeen(defaults)
        XCTAssertFalse(Onboarding.needsTour(defaults: defaults, arguments: []))
        Onboarding.reset(defaults)
        XCTAssertTrue(Onboarding.needsTour(defaults: defaults, arguments: []))
        XCTAssertEqual(Onboarding.cards.count, 4)
        XCTAssertEqual(Set(Onboarding.cards.map(\.id)).count, 4)
    }

    // MARK: folders

    private func recent(_ title: String, folder: String?) -> RecentDesign {
        RecentDesign(id: UID.make("doc"), title: title, width: 100, height: 100, pages: 1,
                     updatedAt: 0, thumbnail: nil, folder: folder)
    }

    func testFolderListAndFilter() {
        let all = [recent("a", folder: "Work"), recent("b", folder: nil), recent("c", folder: "home"), recent("d", folder: "Work")]
        XCTAssertEqual(DesignLibrary.folders(in: all), ["home", "Work"])
        XCTAssertEqual(DesignLibrary.filter(all, query: "", sort: .name, folder: "Work").map(\.title), ["a", "d"])
        XCTAssertEqual(DesignLibrary.filter(all, query: "", sort: .name, folder: nil).map(\.title), ["a", "b", "c", "d"])
        XCTAssertEqual(DesignLibrary.filter(all, query: "d", sort: .name, folder: "Work").map(\.title), ["d"])
    }

    func testMovingADesignFilesItWithoutTouchingItsEditTime() {
        var d = Design(title: "filed", width: 100, height: 100)
        d.updatedAt = 12345
        XCTAssertTrue(DesignLibrary.save(d))
        defer { DesignLibrary.delete(id: d.id) }
        XCTAssertTrue(DesignLibrary.move(id: d.id, toFolder: "  Clients  "))
        var loaded = DesignLibrary.load(id: d.id)
        XCTAssertEqual(loaded?.folder, "Clients")
        XCTAssertEqual(loaded?.updatedAt, 12345)
        XCTAssertEqual(DesignLibrary.recents().first { $0.id == d.id }?.folder, "Clients")
        XCTAssertTrue(DesignLibrary.move(id: d.id, toFolder: "   "))
        loaded = DesignLibrary.load(id: d.id)
        XCTAssertNil(loaded?.folder)
        XCTAssertFalse(DesignLibrary.move(id: "nope", toFolder: "x"))
    }

    func testFolderSurvivesEncoding() throws {
        var d = Design(title: "f", width: 100, height: 100)
        d.folder = "Posters"
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.folder, "Posters")
    }

    // MARK: template categories

    func testTemplateCategoriesAreDistinctAndFilterTheLibrary() {
        let categories = ContentLibrary.templateCategories
        XCTAssertFalse(categories.isEmpty)
        XCTAssertEqual(Set(categories).count, categories.count)
        for c in categories {
            let inCategory = ContentLibrary.filteredTemplates(in: c, matching: "")
            XCTAssertFalse(inCategory.isEmpty)
            XCTAssertTrue(inCategory.allSatisfy { $0.category == c })
        }
        XCTAssertEqual(ContentLibrary.filteredTemplates(in: nil, matching: "").count, ContentLibrary.templates.count)
        XCTAssertTrue(ContentLibrary.filteredTemplates(in: nil, matching: "zzzz-no-such-template").isEmpty)
        let first = ContentLibrary.templates[0]
        XCTAssertTrue(ContentLibrary.filteredTemplates(in: first.category, matching: first.name).contains { $0.id == first.id })
    }

    // MARK: haptics

    func testEveryHapticIsAChange() {
        var e = HapticEvent(kind: .undo, serial: 0)
        let a = e
        e = HapticEvent(kind: .undo, serial: e.serial + 1)
        XCTAssertNotEqual(a, e)
    }
}
