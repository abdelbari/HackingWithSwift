// Locked pages, as the Android twin has them: the flag written only when
// true, every edit of what is on a locked page refused, Add landing on the
// next unlocked page, and locking as one Undo.

import XCTest
import CoreGraphics
@testable import Canvia

final class PageLocksTests: XCTestCase {

    private func json(_ page: Page) throws -> [String: Any] {
        let data = try JSONEncoder().encode(page)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func design(locked: [Bool]) -> Design {
        var d = Design(title: "l", width: 400, height: 300)
        d.pages = locked.map { flag in
            var p = Page(elements: [Element.shape("rect", w: 100, h: 100)])
            p.locked = flag ? true : nil
            return p
        }
        return d
    }

    // MARK: the file

    func testLockedRoundTripsAndUnlockedIsNeverWritten() throws {
        let plain = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","elements":[]}"#.utf8))
        XCTAssertNil(plain.locked)
        XCTAssertNil(try json(plain)["locked"])

        let page = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","locked":true}"#.utf8))
        XCTAssertEqual(page.locked, true)
        XCTAssertEqual(try json(page)["locked"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page)), page)

        let open = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","locked":false}"#.utf8))
        XCTAssertNil(open.locked, "false is never kept: unlocked is the key's absence")
        XCTAssertNil(try json(open)["locked"])
    }

    func testACopyOfALockedPageIsLockedToo() {
        var page = Page()
        page.locked = true
        XCTAssertEqual(Copies.of(page).locked, true)
    }

    // MARK: the rule

    func testOnlyALockedPagesElementsAndBackgroundAreHeld() {
        var locked = Page(elements: [Element.shape("rect", w: 100, h: 100)])
        locked.locked = true
        var moved = locked
        moved.elements[0].x += 10
        XCTAssertFalse(PageLocks.allows(locked, becoming: moved), "nothing on it moves")
        var emptied = locked
        emptied.elements = []
        XCTAssertFalse(PageLocks.allows(locked, becoming: emptied), "nothing on it is deleted")
        var painted = locked
        painted.background = .color("#ff0000")
        XCTAssertFalse(PageLocks.allows(locked, becoming: painted), "its background stays")
        var noted = locked
        noted.notes = "Say hello"
        noted.title = "Intro"
        noted.hidden = true
        noted.locked = nil
        XCTAssertTrue(PageLocks.allows(locked, becoming: noted), "its notes, title, hiding and lock still change")
        var open = locked
        open.locked = nil
        var changed = open
        changed.elements = []
        XCTAssertTrue(PageLocks.allows(open, becoming: changed))
    }

    /// The next unlocked page after it, else the nearest before, else none.
    func testAddLandsOnTheNextUnlockedPageElseTheOneBefore() {
        let pages = design(locked: [false, true, true, false, true]).pages
        XCTAssertEqual(PageLocks.landing(from: 0, in: pages), 0, "an unlocked page takes it")
        XCTAssertEqual(PageLocks.landing(from: 1, in: pages), 3)
        XCTAssertEqual(PageLocks.landing(from: 2, in: pages), 3)
        XCTAssertEqual(PageLocks.landing(from: 4, in: pages), 3, "none after it: the nearest before")
        XCTAssertNil(PageLocks.landing(from: 0, in: design(locked: [true, true]).pages))
    }

    @MainActor
    func testWhatDeletingSeveralSays() {
        XCTAssertEqual(PageLocks.deletedNote(deleted: 1, skipped: 0), "Deleted 1 page")
        XCTAssertEqual(PageLocks.deletedNote(deleted: 2, skipped: 1), "Deleted 2 pages, skipped 1 locked page")
        XCTAssertEqual(PageLocks.deletedNote(deleted: 0, skipped: 2), "Skipped 2 locked pages")
        XCTAssertEqual(PageLocks.deleteMessage(elements: 1, locked: true), "It is locked, with 1 element on it.")
        XCTAssertEqual(PageLocks.deleteMessage(elements: 3, locked: false), "It has 3 elements on it.")
        XCTAssertEqual(PagesBar.spokenThumb(number: 2, title: nil, current: false, hidden: true, locked: true),
                       "Page 2, hidden, locked")
    }

    // MARK: the editor

    @MainActor
    func testLockingIsOneUndoAndLetsGoOfTheSelection() {
        let store = DesignStore(design: design(locked: [false, false]))
        store.select(store.page.elements[0].id)
        store.setPageLocked(true)
        XCTAssertEqual(store.design.pages[0].locked, true)
        XCTAssertTrue(store.selection.isEmpty)
        store.setPageLocked(false)
        XCTAssertNil(store.design.pages[0].locked, "unlocked is nil, never false")
        store.undo()
        XCTAssertEqual(store.design.pages[0].locked, true)
        store.undo()
        XCTAssertNil(store.design.pages[0].locked)
        XCTAssertFalse(store.canUndo)
    }

    @MainActor
    func testNothingOnALockedPageIsSelectedMovedOrDeleted() {
        let store = DesignStore(design: design(locked: [true, false]))
        let before = store.design
        let id = store.page.elements[0].id
        store.select(id)
        XCTAssertTrue(store.selection.isEmpty, "a tap selects nothing")
        XCTAssertEqual(store.announcement, PageLocks.lockedNote)
        XCTAssertEqual(store.announcementUnlocks, store.design.pages[0].id, "the toast offers Unlock")
        store.selectAll()
        XCTAssertTrue(store.selection.isEmpty)
        store.select(within: CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertTrue(store.selection.isEmpty, "no marquee")
        store.applyToPage { $0.elements.removeAll() }
        store.setBackground(.color("#000000"))
        store.paste()
        store.addText(at: CGPoint(x: 50, y: 50))
        XCTAssertEqual(store.design, before, "every edit refused")
        XCTAssertFalse(store.canUndo)
        // Its notes still change, as one step.
        store.applyToPage { $0.notes = "Keep" }
        XCTAssertEqual(store.page.notes, "Keep")
        XCTAssertTrue(store.canUndo)
    }

    @MainActor
    func testAddGoesToTheNextUnlockedPageOrAsks() {
        let store = DesignStore(design: design(locked: [true, false]))
        store.add(Element.shape("circle", w: 50, h: 50))
        XCTAssertEqual(store.pageIndex, 1, "the next unlocked page is brought up")
        XCTAssertEqual(store.design.pages[1].elements.count, 2)
        XCTAssertEqual(store.design.pages[0].elements.count, 1)

        let all = DesignStore(design: design(locked: [true, true]))
        all.add(Element.shape("circle", w: 50, h: 50))
        XCTAssertEqual(all.design.pages.map(\.elements.count), [1, 1])
        XCTAssertEqual(all.announcement, PageLocks.lockedNote, "every page locked: asked to unlock")
        all.unlockPage(all.design.pages[0].id)
        XCTAssertNil(all.design.pages[0].locked)
    }

    @MainActor
    func testDeletingSeveralPagesSkipsLockedOnes() {
        let store = DesignStore(design: design(locked: [false, true, false]))
        let ids = Set(store.design.pages.map(\.id))
        let lockedId = store.design.pages[1].id
        store.deletePages(ids)
        XCTAssertEqual(store.design.pages.map(\.id), [lockedId])
        XCTAssertEqual(store.announcement, "Deleted 2 pages, skipped 1 locked page")
        store.undo()
        XCTAssertEqual(store.design.pages.count, 3)
    }

    @MainActor
    func testTheOrganizerLocksSeveralPagesInOneStep() {
        let store = DesignStore(design: design(locked: [false, false, false]))
        let ids: Set<String> = [store.design.pages[0].id, store.design.pages[2].id]
        store.setPagesLocked(ids, locked: true)
        XCTAssertEqual(store.design.pages.map { $0.locked == true }, [true, false, true])
        store.undo()
        XCTAssertEqual(store.design.pages.map { $0.locked == true }, [false, false, false])
        XCTAssertFalse(store.canUndo)
    }

    @MainActor
    func testNothingIsMovedOntoALockedPage() {
        let store = DesignStore(design: design(locked: [false, true]))
        store.select(store.page.elements[0].id)
        XCTAssertFalse(store.moveSelectedToPage(1, at: nil))
        XCTAssertEqual(store.design.pages.map(\.elements.count), [1, 1])
    }
}
