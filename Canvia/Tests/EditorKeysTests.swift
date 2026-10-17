// The hardware keyboard's new keys and the system's undo: the text
// formatting table (TextKeys), Tab through what is on the page
// (Layers.neighbour), the step names the undo gestures and shake say
// (History.label, DesignUndo), and the help that lists them.

import XCTest
@testable import Canvia

final class EditorKeysTests: XCTestCase {

    // MARK: text keys

    /// Shared rows: the thirteen keys, each with or without Shift, and what
    /// each does — the Android twin's TextKeys, row for row.
    func testTheTextKeysAreCanvas() {
        // key, shift, action
        let rows: [(String, Bool, TextKeys.Command)] = [
            ("b", false, .bold), ("i", false, .italic), ("u", false, .underline),
            ("x", true, .strike), ("k", true, .uppercase),
            ("l", true, .alignLeft), ("c", true, .alignCenter), ("r", true, .alignRight), ("j", true, .alignJustify),
            ("7", true, .numberedList), ("8", true, .bulletedList),
            (",", true, .smaller), (".", true, .larger),
        ]
        XCTAssertEqual(TextKeys.all.count, rows.count)
        for (key, shift, action) in rows {
            XCTAssertEqual(TextKeys.action(for: key, shift: shift), action, key)
            XCTAssertEqual(TextKeys.action(for: key.uppercased(), shift: shift), action, "\(key) in capitals")
        }
        // No key means two things, and Shift tells ⌘X from ⇧⌘X.
        XCTAssertEqual(Set(TextKeys.all.map { "\($0.key)|\($0.shift)" }).count, TextKeys.all.count)
        XCTAssertNil(TextKeys.action(for: "b", shift: true))
        XCTAssertNil(TextKeys.action(for: "x", shift: false))
        XCTAssertNil(TextKeys.action(for: "z", shift: false))
        XCTAssertEqual(TextKeys.addText, "t")
        XCTAssertEqual(TextKeys.keyAlignment(.alignJustify), "justify")
        XCTAssertEqual(TextKeys.keyAlignment(.alignCenter), "center")
        XCTAssertNil(TextKeys.keyAlignment(.bold))
        XCTAssertEqual(TextKeys.keyList(.bulletedList), "bullet")
        XCTAssertEqual(TextKeys.keyList(.numberedList), "number")
        XCTAssertNil(TextKeys.keyList(.larger))
        XCTAssertEqual(TextKeys.keyName(.bold), "Bold")
        XCTAssertEqual(TextKeys.keyName(.numberedList), "Numbered list")
        for action in TextKeys.Command.allCases {
            XCTAssertFalse(TextKeys.keyName(action).isEmpty)
            XCTAssertTrue(TextKeys.all.contains { $0.action == action }, "\(action) has no key")
        }
    }

    // MARK: tab

    private func shape(_ id: String, group: String? = nil, hidden: Bool = false) -> Element {
        var e = Element.shape("rect", w: 100, h: 50)
        e.id = id
        e.group = group
        e.hidden = hidden ? true : nil
        return e
    }

    /// Tab goes forward through the page's blocks, a group as one, round
    /// past the front; Shift-Tab back; nothing hidden is stopped on; with
    /// nothing selected, the back-most or the front-most.
    func testTabStepsThroughWhatIsShownAGroupAsOne() {
        let page = [shape("a"), shape("b"), shape("c", group: "g"), shape("d", group: "g"), shape("e", hidden: true)]
        XCTAssertEqual(Layers.neighbour(of: ["a"], in: page, forward: true), ["b"])
        XCTAssertEqual(Layers.neighbour(of: ["b"], in: page, forward: true), ["c", "d"])
        XCTAssertEqual(Layers.neighbour(of: ["c", "d"], in: page, forward: true), ["a"], "past the front, round to the back")
        XCTAssertEqual(Layers.neighbour(of: ["c"], in: page, forward: true), ["a"], "a member alone steps as its group")
        XCTAssertEqual(Layers.neighbour(of: ["a"], in: page, forward: false), ["c", "d"])
        XCTAssertEqual(Layers.neighbour(of: ["b"], in: page, forward: false), ["a"])
        XCTAssertEqual(Layers.neighbour(of: [], in: page, forward: true), ["a"])
        XCTAssertEqual(Layers.neighbour(of: [], in: page, forward: false), ["c", "d"])
        // Several selected: on from the front-most of them.
        XCTAssertEqual(Layers.neighbour(of: ["a", "b"], in: page, forward: true), ["c", "d"])
        XCTAssertEqual(Layers.neighbour(of: ["e"], in: page, forward: true), ["a"])
        XCTAssertEqual(Layers.neighbour(of: [], in: [], forward: true), [])
        XCTAssertEqual(Layers.neighbour(of: [], in: [shape("e", hidden: true)], forward: true), [])
    }

    func testTabSelectsTheNeighbourAndRefusesALockedPage() {
        var design = Design(title: "keys", width: 600, height: 600)
        design.pages[0].elements = [shape("a"), shape("b")]
        let s = DesignStore(design: design)
        s.selectNeighbour(forward: true)
        XCTAssertEqual(s.selection, ["a"])
        s.selectNeighbour(forward: true)
        XCTAssertEqual(s.selection, ["b"])
        s.selectNeighbour(forward: true)
        XCTAssertEqual(s.selection, ["a"])
        s.selectNeighbour(forward: false)
        XCTAssertEqual(s.selection, ["b"])
        XCTAssertFalse(s.canUndo, "selecting is never a step")
        s.setPageLocked(true)
        s.announcement = nil
        s.selectNeighbour(forward: true)
        XCTAssertTrue(s.selection.isEmpty)
        XCTAssertNotNil(s.announcement, "a locked page was not said")
    }

    // MARK: undo names

    private func store() -> DesignStore {
        var design = Design(title: "undo", width: 600, height: 600)
        var a = shape("a"); a.x = 10; a.y = 10
        design.pages[0].elements = [a, shape("b")]
        return DesignStore(design: design)
    }

    /// Shared rows: what a step is called, read from what it changed.
    func testAStepIsNamedByWhatItDid() {
        let before = store().design
        func after(_ change: (inout Design) -> Void) -> String {
            var d = before
            change(&d)
            return History.label(before: before, after: d)
        }
        XCTAssertEqual(after { $0.pages[0].elements[0].x += 5 }, "Move")
        XCTAssertEqual(after { $0.pages[0].elements[0].w = 200; $0.pages[0].elements[0].x -= 50 }, "Resize")
        XCTAssertEqual(after { $0.pages[0].elements[0].rotation = 30 }, "Rotate")
        XCTAssertEqual(after { $0.pages[0].elements[0].x += 5; $0.pages[0].elements[0].rotation = 30 }, "Rotate")
        XCTAssertEqual(after { $0.pages[0].elements[0].text = "Hi" }, "Edit text")
        XCTAssertEqual(after { $0.pages[0].elements[0].opacity = 0.5 }, "Edit")
        XCTAssertEqual(after { $0.pages[0].elements.removeLast() }, "Delete")
        XCTAssertEqual(after { $0.pages[0].elements.append(Element.shape("rect", w: 10, h: 10)) }, "Add")
        XCTAssertEqual(after { $0.pages[0].elements.removeLast(); $0.pages[0].elements.append(Element.shape("rect", w: 10, h: 10)) }, "Delete")
        XCTAssertEqual(after { $0.pages.append(Page()) }, "Add page")
        XCTAssertEqual(after { $0.pages.insert(Page(), at: 0); $0.pages.removeLast() }, "Move page")
        var two = before
        two.pages.append(Page())
        XCTAssertEqual(History.label(before: two, after: before), "Delete page")
        XCTAssertEqual(History.label(before: two, after: two.reversedPages), "Move page")
        XCTAssertEqual(after { $0.pages[0].background = .color("#123456") }, "Edit")
        XCTAssertEqual(after { _ in }, "Edit")
        // A text's corner resize scales its type with its box: still Resize.
        var text = before
        text.pages[0].elements[0] = Element.text("Hello")
        var grown = text
        grown.pages[0].elements[0].w *= 2; grown.pages[0].elements[0].h *= 2
        grown.pages[0].elements[0].fontSize = 84; grown.pages[0].elements[0].letterSpacing = 2
        XCTAssertEqual(History.label(before: text, after: grown), "Resize")
    }

    /// The store names what Undo would take back and Redo do again, and
    /// a DesignUndo hands the system those, with Undo and Redo themselves.
    func testTheSystemsUndoIsTheStoresNamed() {
        let s = store()
        let undo = DesignUndo()
        undo.store = s
        XCTAssertFalse(undo.canUndo)
        XCTAssertNil(s.undoLabel)
        XCTAssertEqual(undo.undoActionName, "")
        s.select("a")
        s.nudgeSelected(dx: 10, dy: 0)
        XCTAssertEqual(s.undoLabel, "Move")
        XCTAssertEqual(undo.undoActionName, "Move")
        s.deleteSelected()
        XCTAssertEqual(s.undoLabel, "Delete")
        XCTAssertTrue(undo.canUndo)
        XCTAssertFalse(undo.canRedo)
        undo.undo()
        XCTAssertEqual(s.page.elements.count, 2, "the system's Undo did not undo")
        XCTAssertEqual(s.selection, ["a"], "Undo did not reselect what came back")
        XCTAssertEqual(s.undoLabel, "Move")
        XCTAssertEqual(s.redoLabel, "Delete")
        XCTAssertEqual(undo.redoActionName, "Delete")
        XCTAssertTrue(undo.canRedo)
        undo.redo()
        XCTAssertEqual(s.page.elements.count, 1, "the system's Redo did not redo")
        XCTAssertNil(s.redoLabel)
        undo.undo()
        undo.undo()
        XCTAssertEqual(s.element("a")?.x, 10)
        XCTAssertEqual(s.redoLabel, "Move")
        XCTAssertNil(s.undoLabel)
        XCTAssertFalse(undo.canUndo)
    }

    // MARK: help

    func testTheHelpListsTheKeysAndTheGestures() throws {
        let keyboard = try XCTUnwrap(HelpTopics.all.first { $0.id == "keyboard" })
        for words in ["⌘=", "⌘0", "⌘1", "Page Up", "Tab", "⇧H", "⌥⇧L", "T adds", "⌘B", "⇧⌘K", "⇧⌘7", "⇧⌘,"] {
            XCTAssertTrue(keyboard.body.contains(words), words)
        }
        let undo = try XCTUnwrap(HelpTopics.all.first { $0.id == "undo" })
        XCTAssertTrue(undo.body.contains("three-finger"))
        XCTAssertTrue(undo.body.contains("shake"))
        XCTAssertTrue(HelpTopics.search("shake").contains { $0.id == "undo" })
        XCTAssertTrue(HelpTopics.search("tab").contains { $0.id == "keyboard" })
    }
}

private extension Design {
    /// The pages in the other order.
    var reversedPages: Design {
        var out = self
        out.pages.reverse()
        return out
    }
}
