// Pages with sizes of their own: the model, resizing one page, the canvas
// size the store reports, and the exports that keep each page's shape.

import XCTest
import CoreGraphics
@testable import Canvia

final class MixedPageSizeTests: XCTestCase {

    private func design() -> Design {
        var d = Design(title: "m", width: 1000, height: 1000)
        d.pages = [Page(elements: [Element.shape("rect", w: 200, h: 200)]), Page(), Page()]
        return d
    }

    func testAPageIsTheDocumentsSizeUntilItHasItsOwn() throws {
        var d = design()
        XCTAssertEqual(d.size(for: d.pages[1]), CGSize(width: 1000, height: 1000))
        XCTAssertFalse(d.hasMixedPageSizes)
        d.pages[1].width = 1080; d.pages[1].height = 1920
        XCTAssertEqual(d.size(for: d.pages[1]), CGSize(width: 1080, height: 1920))
        XCTAssertEqual(d.size(at: 1).height, 1920)
        XCTAssertEqual(d.size(at: 0).height, 1000)
        XCTAssertEqual(d.size(at: 99), d.size)
        XCTAssertTrue(d.hasMixedPageSizes)
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.pages[1].height, 1920)
        XCTAssertNil(back.pages[0].width)
    }

    @MainActor
    func testResizingOnePageLeavesTheOthersAndIsUndoable() {
        let store = DesignStore(design: design())
        var logo = Element.shape("rect", w: 100, h: 100); logo.x = 900; logo.y = 900
        store.setPage(1)
        store.applyToPage { $0.elements = [logo] }
        store.resizePage(width: 1080, height: 1920, reflow: true)
        XCTAssertEqual(store.pageSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(store.design.width, 1000, "the document keeps its size")
        XCTAssertEqual(store.design.size(at: 0), CGSize(width: 1000, height: 1000))
        // The corner logo is still in the corner of the taller page.
        let moved = store.page.elements[0]
        XCTAssertEqual(moved.x + moved.w, 1080, accuracy: 0.01)
        XCTAssertEqual(moved.y + moved.h, 1920, accuracy: 0.01)
        XCTAssertEqual(moved.w, 108, accuracy: 0.01, "scaled by the smaller ratio")
        store.undo()
        XCTAssertEqual(store.pageSize, CGSize(width: 1000, height: 1000))
        XCTAssertNil(store.page.width)
        // Choosing the document's size again clears the override.
        store.resizePage(width: 500, height: 500, reflow: false)
        XCTAssertEqual(store.page.width, 500)
        store.resizePage(width: 1000, height: 1000, reflow: false)
        XCTAssertNil(store.page.width)
    }

    @MainActor
    func testResizingTheDesignBringsEveryPageAlong() {
        var d = design()
        d.pages[2].width = 400; d.pages[2].height = 400
        let store = DesignStore(design: d)
        store.magicResize(width: 2000, height: 1000)
        XCTAssertFalse(store.design.hasMixedPageSizes)
        XCTAssertEqual(store.design.size(at: 2), CGSize(width: 2000, height: 1000))
        store.undo()
        XCTAssertEqual(store.design.size(at: 2), CGSize(width: 400, height: 400))
        store.resizeDesign(width: 500, height: 500)
        XCTAssertFalse(store.design.hasMixedPageSizes)
        XCTAssertEqual(store.design.width, 500)
    }

    @MainActor
    func testNewElementsCentreOnThePageNotTheDocument() {
        var d = design()
        d.pages[1].width = 400; d.pages[1].height = 2000
        let store = DesignStore(design: d)
        store.setPage(1)
        store.add(.shape("rect", w: 100, h: 100))
        let el = store.page.elements[0]
        XCTAssertEqual(el.x, 150); XCTAssertEqual(el.y, 950)
        let lines = Geometry.snapLines(design: store.design, page: store.page, excluding: [], settings: SnapSettings())
        XCTAssertTrue(lines.x.contains(400)); XCTAssertTrue(lines.y.contains(2000))
    }

    @MainActor
    func testTheSVGAndPDFKeepEachPagesShape() throws {
        var d = design()
        d.pages[1].width = 1080; d.pages[1].height = 1920
        let svg = SVGExporter.svg(design: d, page: d.pages[1])
        XCTAssertTrue(svg.contains("width=\"1080\" height=\"1920\""), svg.prefix(200).description)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mixed-\(UUID()).pdf")
        try DesignExporter.exportPDF(design: d, to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 3)
        let square = try XCTUnwrap(pdf.page(at: 1)).getBoxRect(.mediaBox)
        let tall = try XCTUnwrap(pdf.page(at: 2)).getBoxRect(.mediaBox)
        XCTAssertEqual(square.width, 750, accuracy: 0.5)
        XCTAssertEqual(tall.width, 810, accuracy: 0.5)
        XCTAssertEqual(tall.height, 1440, accuracy: 0.5)
    }

    func testVideoLetterboxesAPageShapedUnlikeTheFrame() {
        let frame = CGSize(width: 1000, height: 1000)
        XCTAssertEqual(MovieExporter.fitRect(image: CGSize(width: 1000, height: 1000), in: frame), CGRect(origin: .zero, size: frame))
        let tall = MovieExporter.fitRect(image: CGSize(width: 540, height: 960), in: frame)
        XCTAssertEqual(tall.height, 1000, accuracy: 0.001)
        XCTAssertEqual(tall.width, 562.5, accuracy: 0.001)
        XCTAssertEqual(tall.midX, 500, accuracy: 0.001)
        XCTAssertEqual(MovieExporter.renderScale(for: CGSize(width: 1080, height: 1920), in: frame), 1000.0 / 1920, accuracy: 0.0001)
    }
}
