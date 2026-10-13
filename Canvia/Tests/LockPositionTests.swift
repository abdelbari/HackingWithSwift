// Lock position, as round 21 adds it beside the whole lock, with the rows
// the Android twin's tests hold too: the key in the file, what each lock
// allows, and the Lock menu as one step each.

import XCTest
@testable import Canvia

@MainActor
final class LockPositionTests: XCTestCase {

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.group = group
        return el
    }

    private func json(_ el: Element) throws -> [String: Any] {
        let data = try JSONEncoder().encode(el)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// A design of `pages`, each with its id, its elements and, when given,
    /// a size of its own.
    private func store(_ pages: [(id: String, elements: [Element], size: CGSize?)],
                       width: Double = 1080, height: Double = 1080) -> DesignStore {
        var d = Design(title: "editing", width: width, height: height)
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

    // MARK: lock position in the file

    func testLockPositionIsWrittenOnlyWhenTrueAndReadBack() throws {
        var pinned = box("a", x: 10, y: 20)
        pinned = ElementLock.with(pinned, .position)
        let written = try json(pinned)
        XCTAssertEqual(written["lockPosition"] as? Bool, true)
        XCTAssertEqual(written["locked"] as? Bool, false, "the whole lock stays as it is beside it")
        let read = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(pinned))
        XCTAssertEqual(read, pinned)
        XCTAssertEqual(ElementLock.mode(of: read), .position)

        let free = try json(box("b", x: 0, y: 0))
        XCTAssertNil(free["lockPosition"], "no key when unlocked")
        let whole = try json(ElementLock.with(box("c", x: 0, y: 0), .full))
        XCTAssertNil(whole["lockPosition"])
        XCTAssertEqual(whole["locked"] as? Bool, true)
    }

    func testLockPositionFromAFileReadsAsTheAndroidTwinWritesIt() throws {
        let android = #"{"id":"e1","type":"shape","x":40,"y":50,"w":200,"h":100,"locked":false,"lockPosition":true}"#
        let el = try JSONDecoder().decode(Element.self, from: Data(android.utf8))
        XCTAssertEqual(el.lockPosition, true)
        XCTAssertFalse(el.locked)
        XCTAssertTrue(el.holdsPlace)
        let falseKey = #"{"id":"e2","type":"shape","lockPosition":false}"#
        let plain = try JSONDecoder().decode(Element.self, from: Data(falseKey.utf8))
        XCTAssertNil(plain.lockPosition, "false is read as no key, and written as none")
        XCTAssertNil(try json(plain)["lockPosition"])
        let both = #"{"id":"e3","type":"shape","locked":true,"lockPosition":true}"#
        XCTAssertEqual(ElementLock.mode(of: try JSONDecoder().decode(Element.self, from: Data(both.utf8))), .full,
                       "the whole lock wins")
    }

    // MARK: what a lock allows

    func testWhatEachLockAllows() {
        // The Android twin's rows: true is allowed.
        let rows: [(ElementLock.Action, unlocked: Bool, position: Bool, full: Bool)] = [
            (.move, true, false, false),
            (.resize, true, false, false),
            (.rotate, true, false, false),
            (.nudge, true, false, false),
            (.align, true, false, false),
            (.distribute, true, false, false),
            (.tidy, true, false, false),
            (.editText, true, true, false),
            (.recolour, true, true, false),
            (.crop, true, true, false),
            (.replace, true, true, false),
            (.delete, true, false, false),
        ]
        XCTAssertEqual(rows.count, ElementLock.Action.allCases.count)
        for row in rows {
            XCTAssertEqual(ElementLock.allows(.unlocked, row.0), row.unlocked, "\(row.0) unlocked")
            XCTAssertEqual(ElementLock.allows(.position, row.0), row.position, "\(row.0) position")
            XCTAssertEqual(ElementLock.allows(.full, row.0), row.full, "\(row.0) full")
        }
        XCTAssertEqual(ElementLock.name(.full), "Lock")
        XCTAssertEqual(ElementLock.name(.position), "Lock position")
        XCTAssertEqual(ElementLock.name(.unlocked), "Unlock")
        XCTAssertEqual(ElementLock.symbol(.position), "lock")
        XCTAssertEqual(ElementLock.symbol(.full), "lock.fill")
    }

    func testAPositionLockKeepsItsPlaceButTakesItsColour() {
        let pinned = ElementLock.with(box("a", x: 100, y: 100), .position)
        let free = box("b", x: 400, y: 400)
        let s = store([(id: "p1", elements: [pinned, free], size: nil)])
        s.selection = ["a"]
        XCTAssertEqual(s.movableSelectionCount, 0)
        XCTAssertEqual(s.unlockedSelectionCount, 1)
        s.nudgeSelected(dx: 10, dy: 0)
        s.alignSelected(.left)
        s.centreOnPage()
        s.updateSelectedPlacement { $0.w = 500 }
        s.rotateSelection(by: 45)
        XCTAssertEqual(s.element("a")?.frame, pinned.frame, "it stays where it is")
        XCTAssertEqual(s.element("a")?.rotation, 0)
        XCTAssertFalse(s.canUndo, "and nothing took a step")
        s.recolourSelection("#ff0000")
        XCTAssertEqual(s.element("a")?.fill?.color, "#ff0000", "but it takes a colour")
        s.deleteSelected()
        XCTAssertNotNil(s.element("a"), "and is not deleted, as a whole lock is not")
        // With the free one, only the free one moves.
        s.selection = ["a", "b"]
        s.nudgeSelected(dx: 0, dy: 10)
        XCTAssertEqual(s.element("a")?.y, 100)
        XCTAssertEqual(s.element("b")?.y, 410)
        XCTAssertFalse(s.canGroup)
    }

    func testTheLockMenuIsOneStepEachAndCopiesAreUnlocked() {
        let s = store([(id: "p1", elements: [box("a", x: 0, y: 0), box("b", x: 200, y: 0)], size: nil)])
        s.selection = ["a", "b"]
        XCTAssertEqual(s.selectionLock, .unlocked)
        s.lockSelected(.position)
        XCTAssertEqual(s.page.elements.map { ElementLock.mode(of: $0) }, [.position, .position])
        XCTAssertEqual(s.selectionLock, .position)
        s.lockSelected(.position)
        s.lockSelected(.full)
        XCTAssertEqual(s.page.elements.map(\.lockPosition), [nil, nil], "a whole lock clears the position key")
        XCTAssertEqual(s.page.elements.map(\.locked), [true, true])
        s.undo()
        XCTAssertEqual(s.selectionLock, .position, "locking again took no step")
        s.undo()
        XCTAssertEqual(s.selectionLock, .unlocked)
        XCTAssertFalse(s.canUndo)

        let pinned = ElementLock.with(box("c", x: 0, y: 0), .position)
        XCTAssertNil(Copies.of([pinned]).first?.lockPosition, "a copy is free")
        XCTAssertEqual(Copies.of(Page(elements: [pinned])).elements.first?.lockPosition, true,
                       "a page copied keeps its locks")
    }
}
