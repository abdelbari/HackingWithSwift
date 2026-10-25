// Moving a page from its header's More and ⌥⇧↑/↓ (DesignStore.moveCurrentPage):
// one undo step named Move page, the view following it, the move said, a
// locked page moving and a hidden one staying hidden, nothing at the ends.

import XCTest
@testable import Canvia

final class PageMoveMenuTests: XCTestCase {

    @MainActor
    func testAPageMovesUpDownAndToEitherEndAsOneStep() {
        var d = Design(title: "Deck", width: 1080, height: 1080)
        d.pages = ["a", "b", "c", "d"].map { Page(id: $0) }
        d.pages[1].locked = true
        d.pages[1].hidden = true
        let store = DesignStore(design: d)
        store.setPage(1)
        store.moveCurrentPage(.later)
        XCTAssertEqual(store.design.pages.map(\.id), ["a", "c", "b", "d"], "a locked page moves, as Canva lets it")
        XCTAssertEqual(store.pageIndex, 2, "the view follows the page")
        XCTAssertEqual(store.page.hidden, true)
        XCTAssertEqual(store.announcement, "Page 2 moved to 3")
        XCTAssertEqual(store.undoLabel, "Move page")
        store.moveCurrentPage(.end)
        XCTAssertEqual(store.design.pages.map(\.id), ["a", "c", "d", "b"])
        let before = store.design.pages.map(\.id)
        store.moveCurrentPage(.end)
        store.moveCurrentPage(.later)
        XCTAssertEqual(store.design.pages.map(\.id), before, "nothing past the end")
        store.moveCurrentPage(.start)
        XCTAssertEqual(store.design.pages.map(\.id), ["b", "a", "c", "d"])
        XCTAssertEqual(store.pageIndex, 0)
        store.undo()
        XCTAssertEqual(store.design.pages.map(\.id), ["a", "c", "d", "b"])
    }

    func testTheMenuNamesEachMove() {
        XCTAssertEqual(PageOrder.Step.allCases.map(\.menuTitle),
                       ["Move page up", "Move page down", "Move to start", "Move to end"])
        XCTAssertEqual(PageOrder.movedNote(from: 4, to: 3), "Page 4 moved to 3")
    }
}
