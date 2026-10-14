// Typing in place, taken back a burst at a time while the box stays open,
// and begun where the finger was: the bursts TypingCoalescer cuts, Undo and
// Redo while typing, the caret a tap puts (TextCaret), a word double tapped,
// and a new text's words all chosen — as on the Android twin, whose tests
// hold the same shared rows.

import XCTest
@testable import Canvia

@MainActor
final class TypingBurstsTests: XCTestCase {

    // MARK: bursts

    /// The words after each change and when it came, through a coalescer,
    /// and how many steps they make.
    private func steps(_ changes: [(words: String, time: Double)]) -> Int {
        var coalescer = TypingCoalescer()
        var words = ""
        var count = 0
        for change in changes {
            let opens = !coalescer.open
            let verdict = coalescer.change(from: words, to: change.words, at: change.time)
            if opens || verdict.closeFirst { count += 1 }
            words = change.words
        }
        return count
    }

    /// `typed` a character at a time, `gap` seconds apart — `pauses` more
    /// before the characters at those indices — and how many steps it makes.
    private func steps(typing typed: String, gap: Double = 0.1, pauses: [Int: Double] = [:]) -> Int {
        let chars = Array(typed)
        var time = 0.0
        var changes: [(words: String, time: Double)] = []
        for i in chars.indices {
            time += gap + (pauses[i] ?? 0)
            changes.append((words: String(chars[...i]), time: time))
        }
        return steps(changes)
    }

    /// The shared rows: 'Hello world.' with a 2 s pause after 'Hello' is two
    /// steps, and 'ab', a backspace and 'c' within a second is one.
    func testTheSharedBurstRows() {
        XCTAssertEqual(steps(typing: "Hello world.", pauses: [5: 2]), 2)
        XCTAssertEqual(steps([(words: "a", time: 0.1), (words: "ab", time: 0.2),
                              (words: "a", time: 0.3), (words: "ac", time: 0.4)]), 1)
    }

    /// A space or a mark of punctuation after letters ends the burst it is
    /// typed in, the space with it: "Hello " and "world." with no pause.
    func testASpaceAfterAWordEndsTheBurst() {
        XCTAssertEqual(steps(typing: "Hello world."), 2)
        XCTAssertEqual(steps(typing: "   "), 1, "spaces alone are no word")
        var coalescer = TypingCoalescer()
        XCTAssertEqual(coalescer.change(from: "", to: "Hi", at: 0), .init(closeFirst: false, closeAfter: false))
        XCTAssertEqual(coalescer.change(from: "Hi", to: "Hi,", at: 0.1), .init(closeFirst: false, closeAfter: true))
        XCTAssertFalse(coalescer.open)
    }

    /// The shared row: Bold armed after "Hello " and "world" typed is one
    /// burst. What each key typed is read as the words read, so the
    /// markers the field wraps the letters in end nothing.
    func testLettersWrappedInAnArmedStyleAreOneBurst() {
        var coalescer = TypingCoalescer()
        var words = "Hello "
        var caret = 6
        var pending: RichText.Pending? = RichText.Pending(style: RichText.Style(bold: true), from: 6)
        var count = 0
        for (i, key) in "world".enumerated() {
            let typed = RichText.typing(String(key), over: NSRange(location: caret, length: 0), in: words,
                                        pending: pending)
            let opens = !coalescer.open
            let verdict = coalescer.change(from: words, to: typed.text, at: 0.1 * Double(i + 1))
            if opens || verdict.closeFirst { count += 1 }
            XCTAssertFalse(verdict.closeAfter, "after \(typed.text)")
            words = typed.text
            caret = typed.caret
            pending = typed.pending
        }
        XCTAssertEqual(words, "Hello **world**")
        XCTAssertEqual(count, 1)
        // The first letter after a space a bold word carried: no burst ends.
        XCTAssertFalse(coalescer.change(from: "**Big** ", to: "**Big s**", at: 0.6).closeAfter)
    }

    func testACaretMovedElsewhereEndsTheBurst() {
        var coalescer = TypingCoalescer()
        _ = coalescer.change(from: "", to: "ab", at: 0)
        XCTAssertTrue(coalescer.change(from: "ab", to: "xab", at: 0.1, jumped: true).closeFirst)
        coalescer.close()
        XCTAssertFalse(coalescer.change(from: "xab", to: "xabc", at: 0.2).closeFirst, "closed already: a new one opens")
    }

    func testWhatIsTypedIsWhatTheNewWordsAdd() {
        XCTAssertEqual(TypingCoalescer.typed(from: "Hello", to: "Hello there"), " there")
        XCTAssertEqual(TypingCoalescer.typed(from: "Helo", to: "Hello"), "l")
        XCTAssertEqual(TypingCoalescer.typed(from: "Hello", to: "Hell"), "")
    }

    // MARK: Undo while typing

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "typing", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    /// Undo selects what a step changed, a whole group for a member
    /// (restore); while typing in a grouped box, the box stays the one thing
    /// selected and typing goes on, as on the Android twin.
    func testUndoWhileTypingInAGroupKeepsTypingInTheBox() {
        var text = Element.text("Hi", fontSize: 24, w: 400)
        var other = Element.text("There", fontSize: 24, w: 400)
        text.group = "g"
        other.group = "g"
        other.y = 300
        let s = store([text, other])
        s.startTyping(text.id)
        s.typeWords("Hi you", into: text.id)
        s.typingSelection = NSRange(location: 6, length: 0)
        s.closeTypingStep()

        s.undo()
        XCTAssertEqual(s.editingTextId, text.id, "still typing")
        XCTAssertEqual(s.selection, [text.id], "the box alone, not its group")
        XCTAssertEqual(s.element(text.id)?.text, "Hi")
    }

    func testUndoWhileTypingTakesBackABurstAndKeepsTyping() {
        let text = Element.text("Hi", fontSize: 24, w: 400)
        let s = store([text])
        s.startTyping(text.id)
        s.typeWords("Hi there", into: text.id)
        s.typingSelection = NSRange(location: 8, length: 0)
        s.closeTypingStep()
        s.typeWords("Hi there you", into: text.id)
        s.typingSelection = NSRange(location: 12, length: 0)
        XCTAssertTrue(s.canUndo)

        s.undo()
        XCTAssertEqual(s.editingTextId, text.id, "still typing")
        XCTAssertEqual(s.element(text.id)?.text, "Hi there")
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 8, length: 0), "the caret where it was")
        s.undo()
        XCTAssertEqual(s.element(text.id)?.text, "Hi")
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 2, length: 0))
        s.redo()
        XCTAssertEqual(s.element(text.id)?.text, "Hi there")
        XCTAssertEqual(s.editingTextId, text.id)

        // Ending the typing keeps the steps as they are, never one.
        s.endTextEdit()
        XCTAssertEqual(s.element(text.id)?.text, "Hi there")
        s.undo()
        XCTAssertEqual(s.element(text.id)?.text, "Hi")
        XCTAssertNil(s.editingTextId)
    }

    /// With nothing typed since it opened left to take back, Undo ends the
    /// typing and takes back what came before, as ever.
    func testUndoPastTheTypingEndsIt() {
        let s = store([])
        let text = Element.text("Hello")
        s.add(text)
        s.startTyping(text.id)
        s.undo()
        XCTAssertNil(s.editingTextId)
        XCTAssertNil(s.element(text.id), "the text added is taken back")
    }

    /// Typing opened and nothing typed yet is nothing to take back: Undo
    /// stays off until a key changes the words.
    func testUndoIsOffUntilTypingChangesSomething() {
        let text = Element.text("Hi", fontSize: 24, w: 400)
        let s = store([text])
        s.startTyping(text.id)
        XCTAssertFalse(s.canUndo)
        s.typeWords("Hi there", into: text.id)
        XCTAssertTrue(s.canUndo)
    }

    func testAShapesFirstWordsLookIsInTheFirstBurst() {
        let shape = Element.shape("rect", w: 200, h: 200)
        let s = store([shape])
        s.startTyping(shape.id)
        s.typeWords("SALE", into: shape.id)
        s.closeTypingStep()
        s.typeWords("SALE now", into: shape.id)
        s.undo()
        XCTAssertEqual(s.element(shape.id)?.text, "SALE")
        s.undo()
        XCTAssertEqual(s.element(shape.id), shape, "the words' look goes with the first of them")
        XCTAssertEqual(s.editingTextId, shape.id)
    }

    // MARK: where typing begins

    /// The shared rows: left-aligned "Hello world" at size 40 — a tap at x 0
    /// is the caret 0, one past the end 11.
    func testATapPutsTheCaretWhereTheFingerWas() {
        var el = Element.text("Hello world", fontSize: 40, w: 600)
        el.align = "left"
        el.h = FontLibrary.layoutHeight(for: el)
        XCTAssertEqual(TextCaret.caretFor(el, at: CGPoint(x: 0, y: 20)), 0)
        XCTAssertEqual(TextCaret.caretFor(el, at: CGPoint(x: 5000, y: 20)), 11)
        let middle = TextCaret.caretFor(el, at: CGPoint(x: FontLibrary.lineWidth(for: el) / 2, y: 20)) ?? 0
        XCTAssertTrue((1...10).contains(middle), "\(middle)")
        var styled = el
        styled.text = "**Hello** world"
        XCTAssertEqual(TextCaret.caretFor(styled, at: CGPoint(x: 0, y: 20)), 2, "inside the bold")
        el.curve = 120
        XCTAssertNil(TextCaret.caretFor(el, at: CGPoint(x: 0, y: 20)), "a curve opens at the end")
    }

    func testADoubleTapChoosesTheWord() {
        XCTAssertEqual(TextCaret.word(at: 3, in: "**Big** sale"), NSRange(location: 2, length: 3))
        XCTAssertEqual(TextCaret.word(at: 9, in: "**Big** sale"), NSRange(location: 8, length: 4))
        XCTAssertEqual(TextCaret.word(at: 12, in: "**Big** sale"), NSRange(location: 8, length: 4), "just after it")
        XCTAssertEqual(TextCaret.word(at: 0, in: ""), NSRange(location: 0, length: 0))
    }

    func testTypingBeginsWhereTheTapWas() {
        var el = Element.text("Hello world", fontSize: 40, w: 600)
        el.align = "left"
        el.x = 100
        el.y = 100
        el.h = FontLibrary.layoutHeight(for: el)
        let s = store([el])
        s.select(el.id)
        s.startTyping(el.id, at: CGPoint(x: 100, y: 120))
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 0, length: 0))
        s.endTextEdit()
        s.startTyping(el.id, at: CGPoint(x: 5000, y: 120), word: true)
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 6, length: 5), "the word there")
        s.endTextEdit()
        s.startTyping(el.id)
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 11, length: 0), "else at the end")
    }

    /// Text just added opens with its words all chosen, so the first key
    /// replaces them — once, and only while they are as they were added.
    func testANewTextOpensWithItsWordsAllChosen() {
        let s = store([])
        let heading = Element.text("Add a heading", fontSize: 60, w: 600)
        s.addText(heading)
        s.startTyping(heading.id)
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 0, length: 13))
        s.endTextEdit()
        s.startTyping(heading.id)
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 13, length: 0), "then the caret at the end")

        let body = Element.text("Add a little bit of body text", fontSize: 30, w: 600)
        s.endTextEdit()
        s.addText(body)
        s.select(body.id)
        s.updateSelected { $0.setText("Our story") }
        s.startTyping(body.id)
        XCTAssertEqual(s.typingSelectionAsked?.range, NSRange(location: 9, length: 0), "changed: the caret at the end")
    }

    /// A tap types only in what is already the one thing selected, unlocked,
    /// outside Select multiple, and only a quick one.
    func testOnlyAQuickTapOnTheOneThingSelectedTypes() {
        XCTAssertTrue(CanvasGestures.tapTypes(onlySelected: true, typable: true, selectingMultiple: false, held: 0.1))
        XCTAssertFalse(CanvasGestures.tapTypes(onlySelected: false, typable: true, selectingMultiple: false, held: 0.1))
        XCTAssertFalse(CanvasGestures.tapTypes(onlySelected: true, typable: false, selectingMultiple: false, held: 0.1))
        XCTAssertFalse(CanvasGestures.tapTypes(onlySelected: true, typable: true, selectingMultiple: true, held: 0.1))
        XCTAssertFalse(CanvasGestures.tapTypes(onlySelected: true, typable: true, selectingMultiple: false, held: 0.35))
    }
}
