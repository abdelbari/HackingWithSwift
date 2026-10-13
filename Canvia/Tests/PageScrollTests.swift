// Round 22's scroll through pages: where each page lies in the column, which
// page a point or the view is on, which pages draw live, where a dropped box
// is kept inside a page, and a thing let go over another page — the rows the
// Android twin's PageColumnTest and MoveToPageTest hold too.

import XCTest
@testable import Canvia

@MainActor
final class PageScrollTests: XCTestCase {

    // Three pages in a 432-wide viewport, 16 gutters, 24 gap: 400 across.
    private let sizes = [CGSize(width: 1000, height: 1000), CGSize(width: 1000, height: 500),
                         CGSize(width: 500, height: 1000)]
    private var slots: [PageColumn.Slot] {
        PageColumn.pageOrigins(sizes, gap: 24, gutter: 16, viewportWidth: 432)
    }

    // MARK: the column

    func testTheNumbersAreTheAndroidTwins() {
        XCTAssertEqual(PageColumn.key, "pageScroll")
        XCTAssertEqual(PageColumn.gap, 24)
        XCTAssertEqual(PageColumn.gutter, 16)
        XCTAssertEqual(PageColumn.header, 32)
        XCTAssertEqual(PageColumn.room, 56, "the gap above each page: its header and the gap over that")
        XCTAssertEqual(PageColumn.addPageDrop, 8)
        XCTAssertEqual(PageColumn.addPageHeight, 40)
    }

    func testPagesStackTopToBottomEachFittedToTheWidthLessTheGutters() {
        // Rows: origin x, origin y, scale.
        let rows: [(Double, Double, Double)] = [
            (16, 24, 0.4),
            (16, 448, 0.4),
            (16, 672, 0.8),
        ]
        XCTAssertEqual(slots.count, rows.count)
        for (i, row) in rows.enumerated() {
            XCTAssertEqual(slots[i].origin.x, row.0, accuracy: 1e-9, "x of \(i)")
            XCTAssertEqual(slots[i].origin.y, row.1, accuracy: 1e-9, "y of \(i)")
            XCTAssertEqual(slots[i].scale, row.2, accuracy: 1e-9, "scale of \(i)")
        }
        XCTAssertEqual(PageColumn.columnHeight(slots, gap: 24), 1496, accuracy: 1e-9)
        XCTAssertEqual(slots[2].rect, CGRect(x: 16, y: 672, width: 400, height: 800))
    }

    func testNoPagesIsAnEmptyColumnOneGapTall() {
        XCTAssertEqual(PageColumn.pageOrigins([], gap: 24, gutter: 16, viewportWidth: 432), [])
        XCTAssertEqual(PageColumn.columnHeight([], gap: 24), 24, accuracy: 1e-9)
        XCTAssertNil(PageColumn.addPageRect([], unit: 1))
    }

    func testThePageAtAPointEdgesIncludedAndNoneOverAGapOrAGutter() {
        // Rows: x, y → page, or nil for none.
        let rows: [(Double, Double, Int?)] = [
            (100, 100, 0),
            (16, 24, 0),
            (100, 430, nil),
            (10, 100, nil),
            (416, 648, 1),
            (200, 1000, 2),
            (200, 1480, nil),
        ]
        for row in rows {
            XCTAssertEqual(PageColumn.pageAt(CGPoint(x: row.0, y: row.1), in: slots), row.2, "page at \(row)")
        }
    }

    func testTwoPagesThatTouchGiveTheirSharedEdgeToTheEarlier() {
        let two = [CGSize(width: 100, height: 100), CGSize(width: 100, height: 100)]
        let touching = PageColumn.pageOrigins(two, gap: 0, gutter: 0, viewportWidth: 100)
        XCTAssertEqual(PageColumn.pageAt(CGPoint(x: 50, y: 100), in: touching), 0)
        XCTAssertEqual(PageColumn.pageAt(CGPoint(x: 50, y: 100.5), in: touching), 1)
    }

    func testTheCurrentPageCoversTheMiddleOfTheViewportTiesGoingToTheEarlier() {
        // Rows: the viewport's middle height → page.
        let rows: [(Double, Int)] = [
            (200, 0),
            (500, 1),
            // Exactly halfway down the gap between 0 and 1, and between 1 and 2.
            (436, 0),
            (437, 1),
            (660, 1),
            (661, 2),
            (2000, 2),
            (-100, 0),
        ]
        for row in rows {
            let viewport = CGRect(x: 0, y: row.0 - 200, width: 432, height: 400)
            XCTAssertEqual(PageColumn.currentPage(viewport, in: slots), row.1, "current at \(row.0)")
        }
        XCTAssertEqual(PageColumn.currentPage(CGRect(x: 0, y: 0, width: 432, height: 400), in: []), 0)
    }

    func testPagesWithinOneViewportHeightOfWhatIsSeenAreLive() {
        // Rows: visible top, visible height → live pages.
        let rows: [(Double, Double, [Int])] = [
            (0, 300, [0, 1]),
            (1200, 300, [2]),
            (700, 100, [1, 2]),
        ]
        for row in rows {
            let visible = CGRect(x: 0, y: row.0, width: 432, height: row.1)
            XCTAssertEqual(PageColumn.livePages(slots, visible: visible), row.2, "live from \(row.0)")
        }
    }

    func testADroppedBoxComesInsideThePageByTheLeastItCan() {
        // Rows: box x, y, w, h on a 1000 × 1000 page → top-left x, y.
        let rows: [(Double, Double, Double, Double, Double, Double)] = [
            (950, 950, 100, 100, 900, 900),
            (-20, 500, 100, 100, 0, 500),
            (200, 300, 100, 100, 200, 300),
            // Wider than the page: its left edge at the page's.
            (100, -50, 1200, 100, 0, 0),
        ]
        for row in rows {
            let at = PageColumn.clampToPage(CGRect(x: row.0, y: row.1, width: row.2, height: row.3),
                                            page: CGSize(width: 1000, height: 1000))
            XCTAssertEqual(at.x, row.4, accuracy: 1e-9, "x of \(row)")
            XCTAssertEqual(at.y, row.5, accuracy: 1e-9, "y of \(row)")
        }
        let smaller = PageColumn.clampToPage(CGRect(x: 500, y: 350, width: 200, height: 100),
                                             page: CGSize(width: 600, height: 400))
        XCTAssertEqual(smaller, CGPoint(x: 400, y: 300))
    }

    func testAPointInTheColumnMapsOntoAnyPageAndBack() {
        // The column at its own size: the Android twin's screen point with
        // no pan and a zoom of one.
        let onPage = slots[1].toPage(CGPoint(x: 216, y: 548))
        XCTAssertEqual(onPage.x, 500, accuracy: 1e-9)
        XCTAssertEqual(onPage.y, 250, accuracy: 1e-9)
        let back = slots[2].toColumn(slots[2].toPage(CGPoint(x: 120, y: 980)))
        XCTAssertEqual(back.x, 120, accuracy: 1e-9)
        XCTAssertEqual(back.y, 980, accuracy: 1e-9)
        XCTAssertEqual(slots[2].columnBox(CGRect(x: 0, y: 0, width: 500, height: 1000)), slots[2].rect)
    }

    func testABoxLandsWhereItWasLetGoOnAnotherPage() {
        // A box on the first page dragged down over the second, through the
        // column: below the first page's foot, at the second's scale.
        let landed = PageColumn.landing(CGRect(x: 100, y: 1200, width: 100, height: 100), from: slots[0], to: slots[1])
        XCTAssertEqual(landed.x, 100, accuracy: 1e-9)
        XCTAssertEqual(landed.y, 140, accuracy: 1e-9)
        // Onto the narrower third page, twice the scale: half the units.
        let third = PageColumn.landing(CGRect(x: 500, y: 1000, width: 100, height: 100), from: slots[1], to: slots[2])
        XCTAssertEqual(third.x, 250, accuracy: 1e-9)
        XCTAssertEqual(third.y, 220, accuracy: 1e-9)
    }

    func testTheHeaderAndAddPageKeepTheirSizeOnScreen() {
        XCTAssertEqual(PageColumn.headerRect(slots[1], unit: 1), CGRect(x: 16, y: 416, width: 400, height: 32))
        // Zoomed out to half, two column units to a point.
        XCTAssertEqual(PageColumn.headerRect(slots[1], unit: 2), CGRect(x: 16, y: 384, width: 400, height: 64))
        XCTAssertEqual(PageColumn.addPageRect(slots, unit: 1), CGRect(x: 16, y: 1480, width: 400, height: 40))
    }

    func testTheZoomRangeIsTheAndroidTwins() {
        XCTAssertEqual(Geometry.zoomRange(fit: 0.3), 0.05...4)
        XCTAssertEqual(Geometry.zoomRange(fit: 1), 0.05...8)
        XCTAssertEqual(Geometry.zoomRange(fit: 0.06), 0.03...4)
    }

    // MARK: dragged onto another page

    private func box(_ id: String, x: Double, y: Double, group: String? = nil) -> Element {
        var el = Element.shape("rect", w: 100, h: 100)
        el.id = id
        el.x = x
        el.y = y
        el.group = group
        return el
    }

    private func store(_ pages: [(id: String, elements: [Element], size: CGSize?)]) -> DesignStore {
        var d = Design(title: "scroll", width: 1000, height: 1000)
        d.pages = pages.map { spec in
            var page = Page(id: spec.id, elements: spec.elements)
            if let size = spec.size {
                page.width = size.width
                page.height = size.height
            }
            return page
        }
        return DesignStore(design: d)
    }

    func testADragLetGoOverAnotherPageLandsWhereItWasDroppedDragAndMoveOneStep() {
        let s = store([(id: "p1", elements: [box("a", x: 100, y: 200), box("b", x: 300, y: 300)], size: nil),
                       (id: "p2", elements: [box("x", x: 10, y: 10)], size: nil)])
        s.selection = ["a"]
        // Dragged down past the bottom of the page, the step still open.
        s.beginGesture()
        s.updateSelectedTransient { $0.y = 1400 }
        XCTAssertTrue(s.moveSelectedToPage(1, at: CGPoint(x: 250, y: 380)))
        XCTAssertEqual(s.pageIndex, 1)
        XCTAssertEqual(s.page.elements.map(\.id), ["x", "a"])
        XCTAssertEqual(s.element("a")?.x, 250)
        XCTAssertEqual(s.element("a")?.y, 380)
        XCTAssertEqual(s.selection, ["a"])
        XCTAssertEqual(s.announcement, "Moved to page 2")
        s.undo()
        XCTAssertEqual(s.pageIndex, 0)
        XCTAssertEqual(s.element("a")?.y, 200)
        XCTAssertFalse(s.canUndo, "the drag and the move, one step")
    }

    func testADropOverTheEdgeOfAPageOfAnotherSizeComesInsideItTheBlockAsOne() {
        let s = store([(id: "p1", elements: [box("a", x: 0, y: 0, group: "g"), box("b", x: 200, y: 50, group: "g")],
                        size: nil),
                       (id: "p2", elements: [], size: CGSize(width: 600, height: 400))])
        s.selection = ["a", "b"]
        // The pair is 300 × 150: dropped at 450, 300 it would hang 150 and
        // 50 over the right and bottom edges.
        XCTAssertTrue(s.moveSelectedToPage(1, at: CGPoint(x: 450, y: 300)))
        XCTAssertEqual(s.element("a")?.x, 300)
        XCTAssertEqual(s.element("a")?.y, 250)
        XCTAssertEqual(s.element("b")?.x, 500)
        XCTAssertEqual(s.element("b")?.y, 300)
    }

    func testADropOverTheEdgeOfAPageTheSameSizeStaysWhereItWasLetGo() {
        // Kept inside only when the sizes differ: on a page like its own, a
        // thing may hang over the edge, as it may when moved on one page.
        let s = store([(id: "p1", elements: [box("a", x: 0, y: 0)], size: nil),
                       (id: "p2", elements: [], size: nil)])
        s.selection = ["a"]
        XCTAssertTrue(s.moveSelectedToPage(1, at: CGPoint(x: 950, y: -30)))
        XCTAssertEqual(s.element("a")?.x, 950)
        XCTAssertEqual(s.element("a")?.y, -30)
    }

    func testTheRestOfAGroupGoesBesideTheSelection() {
        // The selection's own box is put at the drop; the rest of its group
        // keeps its place beside it.
        let s = store([(id: "p1", elements: [box("a", x: 200, y: 200, group: "g"), box("b", x: 400, y: 300, group: "g")],
                        size: nil),
                       (id: "p2", elements: [], size: nil)])
        s.selection = ["a"]
        XCTAssertTrue(s.moveSelectedToPage(1, at: CGPoint(x: 300, y: 100)))
        XCTAssertEqual(s.element("a")?.x, 300)
        XCTAssertEqual(s.element("a")?.y, 100)
        XCTAssertEqual(s.element("b")?.x, 500)
        XCTAssertEqual(s.element("b")?.y, 200)
    }

    func testADropWithNothingMovableLeavesTheDragOpenOnItsPage() {
        var locked = box("a", x: 0, y: 0)
        locked.locked = true
        let s = store([(id: "p1", elements: [locked], size: nil),
                       (id: "p2", elements: [], size: nil)])
        s.selection = ["a"]
        XCTAssertFalse(s.moveSelectedToPage(1, at: CGPoint(x: 10, y: 10)))
        XCTAssertEqual(s.pageIndex, 0)
        XCTAssertFalse(s.canUndo)
        s.beginGesture()
        XCTAssertFalse(s.moveSelectedToPage(1, at: CGPoint(x: 10, y: 10)))
        XCTAssertTrue(s.hasPendingChanges, "the canvas closes the drag itself")
    }

    func testWithoutADropPointItLandsWhereItSat() {
        let s = store([(id: "p1", elements: [box("a", x: 300, y: 200)], size: nil),
                       (id: "p2", elements: [], size: nil)])
        s.selection = ["a"]
        s.moveSelectedToPage(1)
        XCTAssertEqual(s.element("a")?.x, 300)
        XCTAssertEqual(s.element("a")?.y, 200)
    }
}
