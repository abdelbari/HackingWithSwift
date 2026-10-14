// Pages in a new order — the organiser's grid, the pages bar's drag and
// VoiceOver's moves — through PageOrder.moved, the same rows as the Android
// twin's PageMoves tests; and the grid's columns and a page put in between.

import XCTest
import CoreGraphics
@testable import Canvia

final class PageOrderTests: XCTestCase {

    private func pages(_ ids: String) -> [Page] {
        ids.map { Page(id: String($0)) }
    }

    private func order(_ pages: [Page]) -> String {
        pages.map(\.id).joined()
    }

    // MARK: PageOrder.moved

    /// The gap is counted in the pages as they were: 0 before the first,
    /// count after the last.
    func testMovedPutsTheLiftedPagesInTheGap() {
        let deck = pages("abcde")
        let rows: [(Set<String>, Int, String)] = [
            (["b"], 0, "bacde"),
            (["b"], 4, "acdbe"),
            (["b"], 5, "acdeb"),
            (["e"], 0, "eabcd"),
            (["a"], 2, "bacde"),
            (["b"], 1, "abcde"),
            (["b"], 2, "abcde"),
            (["a", "c"], 5, "bdeac"),
            (["b", "d"], 0, "bdace"),
            (["d", "b"], 3, "acbde"),
            (["a", "e"], 2, "baecd"),
            (["b"], -3, "bacde"),
            (["b"], 99, "acdeb"),
            ([], 0, "abcde"),
            (["x"], 0, "abcde"),
        ]
        for (ids, gap, expected) in rows {
            XCTAssertEqual(order(PageOrder.moved(deck, ids: ids, toIndex: gap)), expected, "\(ids.sorted()) to \(gap)")
        }
    }

    func testVoiceOverMovesAPageOneStepOrToAnEnd() {
        XCTAssertEqual(PageOrder.gap(.earlier, from: 2, count: 5), 1)
        XCTAssertEqual(PageOrder.gap(.later, from: 2, count: 5), 4)
        XCTAssertEqual(PageOrder.gap(.start, from: 2, count: 5), 0)
        XCTAssertEqual(PageOrder.gap(.end, from: 2, count: 5), 5)
        XCTAssertNil(PageOrder.gap(.earlier, from: 0, count: 5), "the first page goes no earlier")
        XCTAssertNil(PageOrder.gap(.start, from: 0, count: 5))
        XCTAssertNil(PageOrder.gap(.later, from: 4, count: 5), "the last goes no later")
        XCTAssertNil(PageOrder.gap(.end, from: 4, count: 5))
        let deck = pages("abcde")
        XCTAssertEqual(order(PageOrder.moved(deck, ids: ["c"], toIndex: PageOrder.gap(.later, from: 2, count: 5) ?? 0)),
                       "abdce")
        XCTAssertEqual(PageOrder.Step.allCases.map(\.rawValue),
                       ["Move page earlier", "Move page later", "Move to start", "Move to end"])
    }

    // MARK: the grid

    func testTheGridHasTwoToFourColumns() {
        XCTAssertEqual(PageOrder.columns(forWidth: 375), 2)
        XCTAssertEqual(PageOrder.columns(forWidth: 400), 3)
        XCTAssertEqual(PageOrder.columns(forWidth: 699), 3)
        XCTAssertEqual(PageOrder.columns(forWidth: 700), 4)
        XCTAssertEqual(PageOrder.columns(forWidth: 1024), 4)
    }

    /// Beside the nearest thumbnail: before it in its left half, after it
    /// in its right.
    func testTheGapIsBesideTheNearestThumbnail() {
        let frames: [Int: CGRect] = [
            0: CGRect(x: 0, y: 0, width: 100, height: 100),
            1: CGRect(x: 120, y: 0, width: 100, height: 100),
            2: CGRect(x: 0, y: 120, width: 100, height: 100),
        ]
        XCTAssertEqual(PageOrder.gap(at: CGPoint(x: 20, y: 50), frames: frames), 0)
        XCTAssertEqual(PageOrder.gap(at: CGPoint(x: 80, y: 50), frames: frames), 1)
        XCTAssertEqual(PageOrder.gap(at: CGPoint(x: 200, y: 50), frames: frames), 2)
        XCTAssertEqual(PageOrder.gap(at: CGPoint(x: 90, y: 160), frames: frames), 3, "after the last")
        XCTAssertEqual(PageOrder.gap(at: CGPoint(x: 300, y: 60), frames: frames), 2, "off the end of a row")
        XCTAssertNil(PageOrder.gap(at: CGPoint.zero, frames: [:]))
    }

    func testADragScrollsOnlyAtTheEnds() {
        XCTAssertEqual(PageOrder.edgeScroll(10, length: 400, margin: 44), -1)
        XCTAssertEqual(PageOrder.edgeScroll(200, length: 400, margin: 44), 0)
        XCTAssertEqual(PageOrder.edgeScroll(390, length: 400, margin: 44), 1)
        XCTAssertEqual(PageOrder.edgeScroll(10, length: 60, margin: 44), 0, "too short to have ends")
    }

    func testABlankPageTakesTheBackgroundOfThePageToItsLeft() {
        var deck = pages("abc")
        deck[0].background = .color("#111111")
        deck[1].background = .color("#222222")
        deck[1].elements = [Element.shape("rect")]
        let between = PageOrder.blank(at: 2, in: deck)
        XCTAssertEqual(between.background, .color("#222222"))
        XCTAssertTrue(between.elements.isEmpty)
        XCTAssertEqual(PageOrder.blank(at: 0, in: deck).background, .color("#111111"), "first: the first page's")
    }

    // MARK: the editor

    @MainActor
    func testDraggingSeveralPagesIsOneUndoAndTheCurrentPageStaysCurrent() {
        var d = Design(title: "o", width: 400, height: 300)
        d.pages = pages("abcde")
        let store = DesignStore(design: d)
        store.setPage(2)
        store.movePages(["a", "c"], to: 5)
        XCTAssertEqual(order(store.design.pages), "bdeac")
        XCTAssertEqual(store.page.id, "c", "the current page stays current")
        store.movePages(["a", "c"], to: 5)
        store.undo()
        XCTAssertEqual(order(store.design.pages), "abcde")
        XCTAssertFalse(store.canUndo, "a move to where they are is no step")
    }

    @MainActor
    func testPlusBetweenThumbnailsPutsABlankPageThere() {
        var d = Design(title: "o", width: 400, height: 300)
        d.pages = pages("abc")
        d.pages[1].background = .color("#ff0000")
        let store = DesignStore(design: d)
        store.setPage(2)
        store.insertPage(at: 2)
        XCTAssertEqual(store.design.pages.count, 4)
        XCTAssertEqual(store.design.pages[2].background, .color("#ff0000"))
        XCTAssertEqual(store.page.id, "c")
        store.undo()
        XCTAssertEqual(order(store.design.pages), "abc")
    }
}
