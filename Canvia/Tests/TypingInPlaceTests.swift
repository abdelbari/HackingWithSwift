// Typing in place and dictation: every way out closes the typing as one
// step and takes an emptied box away, dictation writes only into the box it
// began on, and a restyled text box is measured again — as on the Android
// twin.

import XCTest
@testable import Canvia

@MainActor
final class TypingInPlaceTests: XCTestCase {

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "typing", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    private func type(_ s: DesignStore, _ words: String, into id: String) {
        s.select(id)
        s.beginGesture()
        s.editingTextId = id
        if let i = s.design.pages[0].elements.firstIndex(where: { $0.id == id }) {
            s.design.pages[0].elements[i].text = words
        }
    }

    func testEndingTypingIsOneStepOfItsOwn() {
        let text = Element.text("Hello")
        let s = store([text])
        type(s, "Hello there", into: text.id)
        s.endTextEdit()
        XCTAssertNil(s.editingTextId)
        XCTAssertFalse(s.hasPendingChanges)
        XCTAssertEqual(s.element(text.id)?.text, "Hello there")
        s.undo()
        XCTAssertEqual(s.element(text.id)?.text, "Hello", "Undo takes back exactly the typing")
    }

    func testAnEmptiedBoxIsRemovedHoweverTypingEnds() {
        let a = Element.text("A"), b = Element.text("B")
        let s = store([a, b])
        type(s, "   ", into: a.id)
        // Picking another element — a Layers row does this — ends the typing.
        s.select(b.id)
        XCTAssertNil(s.element(a.id), "an emptied box does not stay behind, invisible")
        XCTAssertEqual(s.selection, [b.id])
        XCTAssertNil(s.editingTextId)
    }

    func testChangingPageEndsTyping() {
        let text = Element.text("Page one")
        let s = store([text])
        s.design.pages.append(Page())
        type(s, "", into: text.id)
        s.setPage(1)
        XCTAssertNil(s.editingTextId)
        XCTAssertFalse(s.design.pages[0].elements.contains { $0.id == text.id })
        XCTAssertFalse(s.hasPendingChanges)
    }

    func testClearingTheSelectionEndsTyping() {
        let text = Element.text("Hi")
        let s = store([text])
        type(s, "Hi you", into: text.id)
        s.selection.removeAll()
        XCTAssertNil(s.editingTextId)
        XCTAssertFalse(s.hasPendingChanges)
    }

    // MARK: dictation

    func testDictationWritesOnlyIntoItsOwnBox() {
        let spoken = Element.text("Dear")
        let other = Element.text("Other")
        let s = store([spoken, other])
        s.select(spoken.id)
        s.dictationTarget = spoken.id
        XCTAssertTrue(s.dictate("Dear friends"))
        // Selecting anything else ends it, as its own step, there and then;
        // words recognised late go nowhere.
        s.select(other.id)
        XCTAssertNil(s.dictationTarget)
        XCTAssertFalse(s.hasPendingChanges, "the dictation was closed before anything else could join it")
        XCTAssertFalse(s.dictate("Dear friends and family"))
        XCTAssertEqual(s.element(other.id)?.text, "Other", "the newly selected text is left alone")
        XCTAssertEqual(s.element(spoken.id)?.text, "Dear friends")
        s.undo()
        XCTAssertEqual(s.element(spoken.id)?.text, "Dear", "the dictation was one step")
    }

    // MARK: Undo and commands while typing

    func testUndoWhileTypingTakesBackOnlyTheTyping() {
        let s = store([])
        let heading = Element.text("Heading")
        s.add(heading)
        type(s, "Summer Sale", into: heading.id)
        s.undo()
        XCTAssertNil(s.editingTextId)
        XCTAssertEqual(s.element(heading.id)?.text, "Heading", "the heading stays; only the words go")
        s.redo()
        XCTAssertEqual(s.element(heading.id)?.text, "Summer Sale")
    }

    func testACommandWhileTypingIsAStepOfItsOwn() {
        let text = Element.text("Hello")
        let s = store([text])
        type(s, "Hello there", into: text.id)
        s.duplicateSelected()
        XCTAssertEqual(s.page.elements.count, 2)
        s.undo()
        XCTAssertEqual(s.page.elements.count, 1, "Undo takes back the duplicate")
        XCTAssertEqual(s.element(text.id)?.text, "Hello there", "and keeps the words typed")
    }

    func testOpeningABoxAndLeavingItRecordsNothing() {
        let text = Element.text("Hello")
        let s = store([text])
        s.select(text.id)
        s.updateSelected { $0.fontSize = 60 }
        s.undo()
        XCTAssertTrue(s.canRedo)
        type(s, "Hello", into: text.id)
        s.endTextEdit()
        XCTAssertTrue(s.canRedo, "a visit that changed nothing keeps Redo")
        XCTAssertFalse(s.canUndo)
    }

    func testSelectingMoreThanTheBoxBeingTypedInEndsTheTyping() {
        var a = Element.text("Title"), b = Element.shape("rect")
        a.group = "g"; b.group = "g"
        let s = store([a, b])
        // Typing is into the one text, even inside a group, as the canvas
        // starts it...
        s.selection = [a.id]
        s.beginGesture()
        s.editingTextId = a.id
        s.design.pages[0].elements[0].text = "Title!"
        // ...and taking the group whole ends it, as its own step.
        s.selection = [a.id, b.id]
        XCTAssertNil(s.editingTextId)
        XCTAssertFalse(s.hasPendingChanges)
        XCTAssertEqual(s.element(a.id)?.text, "Title!")
    }

    func testDictationNeverWritesIntoAShapeOrALockedText() {
        let shape = Element.shape("rect")
        var locked = Element.text("Fixed")
        locked.locked = true
        let s = store([shape, locked])
        s.dictationTarget = shape.id
        XCTAssertFalse(s.dictate("hello"))
        XCTAssertNil(s.element(shape.id)?.text)
        s.dictationTarget = locked.id
        XCTAssertFalse(s.dictate("hello"))
        XCTAssertEqual(s.element(locked.id)?.text, "Fixed")
    }

    // MARK: remeasuring

    func testRestyledTextIsMeasuredAgain() {
        var before = Element.text("A line long enough to wrap onto another one", fontSize: 40, w: 300)
        before.h = 17
        var after = before
        after.fontWeight = 700
        XCTAssertEqual(DesignStore.remeasured(after, was: before).h, FontLibrary.layoutHeight(for: after))
    }

    func testAnEditThatSetsTheHeightItselfIsKept() {
        let before = Element.text("Words", fontSize: 40)
        var after = before
        after.textPath = "M0 0 L10 10"
        after.h = 500
        XCTAssertEqual(DesignStore.remeasured(after, was: before).h, 500)
    }

    func testAMoveIsNotARestyle() {
        var before = Element.text("Words", fontSize: 40)
        before.h = 3
        var after = before
        after.x = 50
        XCTAssertEqual(DesignStore.remeasured(after, was: before).h, 3)
    }

    // MARK: groups

    func testASecondTapGoesInsideAGroup() {
        var a = Element.shape("rect"), b = Element.shape("circle")
        a.group = "g"; b.group = "g"
        let s = store([a, b])
        XCTAssertFalse(s.selectMember(a.id), "the first tap takes the group")
        s.select(a.id)
        XCTAssertEqual(s.selection, [a.id, b.id])
        XCTAssertTrue(s.selectMember(b.id))
        XCTAssertEqual(s.selection, [b.id])
    }
}
