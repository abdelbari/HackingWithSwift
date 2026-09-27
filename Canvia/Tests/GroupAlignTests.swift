// A group lined up with the page as one box, several things with each other,
// and a selection centred on the page as one.

import XCTest
@testable import Canvia

final class GroupAlignTests: XCTestCase {

    // MARK: fixtures

    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double, group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.x = x
        el.y = y
        el.group = group
        return el
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "align", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    // MARK: a group and the page

    /// A group's box goes to the page's edge, every member by the same
    /// offset, so the group keeps its layout — rather than every member
    /// piling up against the edge on its own.
    func testAGroupLinesUpWithThePageAsOneBox() {
        let a = box(100, 200, 100, 100, group: "grp_1")
        let b = box(300, 400, 200, 100, group: "grp_1")
        let s = store([a, b])
        s.select(a.id)
        XCTAssertTrue(s.alignsToPage)
        s.alignSelected(.right)
        XCTAssertEqual(s.element(b.id)?.x, 800, "the group's right edge is the page's")
        XCTAssertEqual(s.element(a.id)?.x, 600, "and the other member keeps its place in it")
        s.alignSelected(.top)
        XCTAssertEqual(s.element(a.id)?.y, 0)
        XCTAssertEqual(s.element(b.id)?.y, 200)
        s.alignSelected(.centerX)
        XCTAssertEqual(s.element(a.id)?.x, 300)
        XCTAssertEqual(s.element(b.id)?.x, 500)
        s.undo()
        XCTAssertEqual(s.element(a.id)?.x, 600, "each alignment is one step")
    }

    /// Several loose things still line up with each other.
    func testSeveralLooseThingsLineUpWithEachOther() {
        let a = box(100, 200, 100, 100)
        let b = box(300, 400, 200, 100)
        let s = store([a, b])
        s.selection = [a.id, b.id]
        XCTAssertFalse(s.alignsToPage)
        s.alignSelected(.right)
        XCTAssertEqual(s.element(a.id)?.x, 400)
        XCTAssertEqual(s.element(b.id)?.x, 300)
    }

    func testOneThingLinesUpWithThePage() {
        let a = box(100, 200, 100, 100)
        let s = store([a])
        s.selection = [a.id]
        XCTAssertTrue(s.alignsToPage)
        s.alignSelected(.bottom)
        XCTAssertEqual(s.element(a.id)?.y, 900)
    }

    /// Centring moves the selection's box as one, keeping places; a locked
    /// thing stays where it is.
    func testCentringOnThePageMovesTheBoxAsOneStep() {
        let a = box(0, 0, 100, 100)
        let b = box(300, 0, 100, 100)
        var locked = box(700, 700, 50, 50)
        locked.locked = true
        let s = store([a, b, locked])
        s.selection = [a.id, b.id, locked.id]
        s.centreOnPage()
        XCTAssertEqual(s.element(a.id)?.x, 300)
        XCTAssertEqual(s.element(a.id)?.y, 450)
        XCTAssertEqual(s.element(b.id)?.x, 600)
        XCTAssertEqual(s.element(locked.id)?.x, 700)
        s.undo()
        XCTAssertEqual(s.element(a.id)?.x, 0)
        XCTAssertFalse(s.canUndo)
    }
}
