// Round 33's Unlock all and Show hidden: ElementLock.unlockedAll and
// PageVisibility.shownAll — the Android twin's rows — the hold menu's two
// items after Select all, and each as one named step that selects what it
// changed, a locked page refusing.

import XCTest
@testable import Canvia

final class PageRecoveryTests: XCTestCase {

    private static func box(_ id: String, locked: Bool = false, position: Bool = false, hidden: Bool = false) -> Element {
        var el = Element.shape("rect", w: 100, h: 100)
        el.id = id
        el.locked = locked
        el.lockPosition = position ? true : nil
        el.hidden = hidden ? true : nil
        return el
    }

    /// Back to front: a locked, b locked in position, c hidden, d as it
    /// is, e locked and hidden.
    private let page = Page(elements: [PageRecoveryTests.box("a", locked: true),
                                       PageRecoveryTests.box("b", position: true),
                                       PageRecoveryTests.box("c", hidden: true), PageRecoveryTests.box("d"),
                                       PageRecoveryTests.box("e", locked: true, hidden: true)])

    func testUnlockAllClearsBothLocksAndNothingElse() throws {
        let out = ElementLock.unlockedAll(page)
        XCTAssertEqual(out.elements.map { ElementLock.mode(of: $0) }, [.unlocked, .unlocked, .unlocked, .unlocked, .unlocked])
        XCTAssertEqual(out.elements.map(\.lockPosition), [nil, nil, nil, nil, nil], "no key left behind")
        XCTAssertEqual(out.elements.map(\.isHidden), page.elements.map(\.isHidden))
        XCTAssertEqual(ElementLock.lockedIds(page), ["a", "b", "e"])
        let data = try JSONEncoder().encode(out.elements[1])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(json["lockPosition"])
    }

    func testShowHiddenClearsHiddenAndNothingElse() {
        let out = PageVisibility.shownAll(page)
        XCTAssertEqual(out.elements.map(\.hidden), [nil, nil, nil, nil, nil])
        XCTAssertEqual(out.elements.map { ElementLock.mode(of: $0) }, page.elements.map { ElementLock.mode(of: $0) })
        XCTAssertEqual(PageVisibility.hiddenIds(page), ["c", "e"])
    }

    /// Shared rows: after Select all, Unlock all then Show hidden, each only
    /// when there is something to free — Unlock all never on a locked page.
    func testTheHoldMenuOffersThemAfterSelectAll() {
        XCTAssertEqual(HoldMenu.items(canPaste: false, canPastePage: false, locked: 3, hidden: 2),
                       [.selectAll, .unlockAll, .showHidden, .addText, .background, .animate])
        XCTAssertEqual(HoldMenu.items(canPaste: false, canPastePage: false, locked: 3, hidden: 0, pageLocked: true),
                       [.selectAll, .addText, .background, .animate])
        XCTAssertEqual(HoldMenu.items(canPaste: false, canPastePage: false, locked: 0, hidden: 1),
                       [.selectAll, .showHidden, .addText, .background, .animate])
        XCTAssertEqual(HoldMenu.unlockAllTitle(3), "Unlock all (3)")
        XCTAssertEqual(HoldMenu.showHiddenTitle(2), "Show hidden (2)")
    }

    @MainActor
    func testEachIsOneNamedStepThatSelectsWhatItChanged() {
        var d = Design(title: "recover", width: 1000, height: 1000)
        d.pages = [page]
        let s = DesignStore(design: d)
        XCTAssertEqual(s.lockedCount(onPage: 0), 3)
        XCTAssertEqual(s.hiddenCount(onPage: 0), 2)
        s.unlockAll(onPage: 0)
        XCTAssertEqual(s.lockedCount(onPage: 0), 0)
        XCTAssertEqual(s.selection, ["a", "b", "e"])
        XCTAssertEqual(s.undoLabel, "Unlock")
        s.showAllHidden(onPage: 0)
        XCTAssertEqual(s.hiddenCount(onPage: 0), 0)
        XCTAssertEqual(s.selection, ["c", "e"])
        XCTAssertEqual(s.undoLabel, "Show")
        s.undo()
        s.undo()
        XCTAssertEqual(s.page, page)
        XCTAssertFalse(s.canUndo)
    }

    @MainActor
    func testALockedPageRefuses() {
        var d = Design(title: "recover", width: 1000, height: 1000)
        var locked = page
        locked.locked = true
        d.pages = [locked]
        let s = DesignStore(design: d)
        s.showAllHidden(onPage: 0)
        XCTAssertEqual(s.hiddenCount(onPage: 0), 2)
        XCTAssertEqual(s.haptic.kind, .reject)
        XCTAssertEqual(s.announcementUnlocks, locked.id)
        XCTAssertFalse(s.canUndo)
    }
}
