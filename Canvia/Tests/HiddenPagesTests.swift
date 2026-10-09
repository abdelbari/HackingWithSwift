// Hidden pages, as the Android twin has them: the flag on the page written
// only when true, Present stepping over hidden pages, and hiding as one Undo.
// The same cases as the Android twin's tests.

import XCTest
@testable import Canvia

final class HiddenPagesTests: XCTestCase {

    private func json(_ page: Page) throws -> [String: Any] {
        let data = try JSONEncoder().encode(page)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func design(hidden: [Bool]) -> Design {
        var d = Design(title: "h", width: 400, height: 300)
        d.pages = hidden.map { flag in
            var p = Page()
            p.hidden = flag ? true : nil
            return p
        }
        return d
    }

    // MARK: the file

    func testAPageWithoutTheKeyIsShownAndWrittenWithoutIt() throws {
        let page = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","elements":[]}"#.utf8))
        XCTAssertNil(page.hidden)
        XCTAssertNil(try json(page)["hidden"])
    }

    func testHiddenRoundTrips() throws {
        let page = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","hidden":true}"#.utf8))
        XCTAssertEqual(page.hidden, true)
        XCTAssertEqual(try json(page)["hidden"] as? Bool, true)
        let back = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(back.hidden, true)
    }

    func testShowingAPageAgainRemovesTheKey() throws {
        var page = Page()
        page.hidden = true
        page.hidden = false
        XCTAssertNil(try json(page)["hidden"], "false is never written: shown is the key's absence")
        let read = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","hidden":false}"#.utf8))
        XCTAssertNil(read.hidden)
    }

    /// The rest of the page is written as it always was.
    func testTheOtherKeysAreStillWritten() throws {
        var page = Page(notes: "Say hello")
        page.usesMaster = false
        page.holdSeconds = 4
        page.width = 1080
        let back = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(back, page)
        XCTAssertEqual(try json(page)["usesMaster"] as? Bool, false)
    }

    // MARK: which pages are shown

    func testVisibleIndicesSkipHiddenPages() {
        XCTAssertEqual(design(hidden: [false, true, false, true]).visiblePageIndices, [0, 2])
        XCTAssertEqual(design(hidden: [true, true]).visiblePageIndices, [])
    }

    // MARK: present

    func testPresentStepsOverHiddenPages() {
        let visible = design(hidden: [false, true, false, true, false]).visiblePageIndices
        XCTAssertEqual(PageVisibility.next(after: 0, in: visible), 2)
        XCTAssertEqual(PageVisibility.next(after: 2, in: visible), 4)
        XCTAssertNil(PageVisibility.next(after: 4, in: visible))
        XCTAssertEqual(PageVisibility.previous(before: 4, in: visible), 2)
        XCTAssertEqual(PageVisibility.previous(before: 2, in: visible), 0)
        XCTAssertNil(PageVisibility.previous(before: 0, in: visible))
    }

    func testPresentStartsOnTheNextShownPageElseThePreviousOne() {
        let visible = design(hidden: [false, true, false, true]).visiblePageIndices
        XCTAssertEqual(PageVisibility.start(at: 2, in: visible), 2, "a shown page starts where it is")
        XCTAssertEqual(PageVisibility.start(at: 1, in: visible), 2, "a hidden page starts at the next shown one")
        XCTAssertEqual(PageVisibility.start(at: 3, in: visible), 2, "none after it: the one before")
        XCTAssertNil(PageVisibility.start(at: 0, in: design(hidden: [true, true]).visiblePageIndices))
    }

    // MARK: the editor

    @MainActor
    func testHidingAPageIsOneUndo() {
        let store = DesignStore(design: design(hidden: [false, false]))
        store.setPageHidden(true)
        XCTAssertEqual(store.design.pages[0].hidden, true)
        XCTAssertEqual(store.design.visiblePageIndices, [1])
        store.setPageHidden(false)
        XCTAssertNil(store.design.pages[0].hidden, "shown is nil, never false")
        store.undo()
        XCTAssertEqual(store.design.pages[0].hidden, true)
        store.undo()
        XCTAssertNil(store.design.pages[0].hidden)
        XCTAssertFalse(store.canUndo)
    }

    @MainActor
    func testTheOrganizerHidesSeveralPagesInOneStep() {
        let store = DesignStore(design: design(hidden: [false, false, false]))
        let ids: Set<String> = [store.design.pages[0].id, store.design.pages[2].id]
        store.setPagesHidden(ids, hidden: true)
        XCTAssertEqual(store.design.visiblePageIndices, [1])
        store.setPagesHidden(ids, hidden: false)
        XCTAssertEqual(store.design.visiblePageIndices, [0, 1, 2])
        store.undo()
        XCTAssertEqual(store.design.visiblePageIndices, [1])
        store.undo()
        XCTAssertFalse(store.canUndo)
    }

    /// A duplicate of a hidden page is hidden too: it is the same page again.
    @MainActor
    func testADuplicatedHiddenPageStaysHidden() {
        let store = DesignStore(design: design(hidden: [true, false]))
        store.duplicatePage()
        XCTAssertEqual(store.design.pages[1].hidden, true)
    }

    // MARK: what VoiceOver says

    @MainActor
    func testAHiddenPageSaysSo() {
        XCTAssertEqual(PagesBar.spokenThumb(number: 2, current: true, hidden: true), "Page 2, current, hidden")
        XCTAssertEqual(PagesBar.spokenThumb(number: 3, current: false, hidden: false), "Page 3")
        XCTAssertEqual(PageOrganizerSheet.spokenRow(number: 2, current: false, hidden: true, elements: 1, notes: nil),
                       "Page 2, hidden, 1 element")
    }
}
