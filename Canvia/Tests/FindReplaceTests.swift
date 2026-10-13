// Find and replace across pages, and copying a style from one element to
// another. Both are pure document operations, so both are fully assertable.

import XCTest
@testable import Canvia

@MainActor
final class FindReplaceTests: XCTestCase {

    private func store(_ texts: [[String]]) -> DesignStore {
        var design = Design(title: "search", width: 800, height: 600)
        design.pages = texts.map { page in
            Page(background: .color("#ffffff"),
                 elements: page.map { Element.text($0, fontSize: 24, w: 400) })
        }
        return DesignStore(design: design)
    }

    // MARK: finding

    func testMatchesAreFoundOnEveryPage() {
        let s = store([["Acme quarterly"], ["Prepared for Acme"], ["Nothing here"]])
        let found = s.matches(for: "Acme")
        XCTAssertEqual(found.count, 2)
        XCTAssertEqual(found.map(\.pageIndex), [0, 1])
    }

    func testEveryOccurrenceInOneElementIsFound() {
        let s = store([["ha ha ha"]])
        XCTAssertEqual(s.matches(for: "ha").count, 3)
    }

    /// Overlapping needles must not spin forever, and must not be
    /// double-counted: "aa" appears twice in "aaaa", not three times.
    func testOverlappingMatchesTerminate() {
        let s = store([["aaaa"]])
        XCTAssertEqual(s.matches(for: "aa").count, 2)
    }

    func testCaseSensitivityIsHonoured() {
        let s = store([["Acme and acme"]])
        XCTAssertEqual(s.matches(for: "acme").count, 2)
        XCTAssertEqual(s.matches(for: "acme", caseSensitive: true).count, 1)
    }

    func testAnEmptyNeedleMatchesNothing() {
        XCTAssertTrue(store([["anything"]]).matches(for: "").isEmpty)
    }

    /// Only text elements: a shape whose id happens to contain the needle is
    /// not a match.
    func testNonTextElementsAreNotSearched() {
        var design = Design(width: 400, height: 400)
        design.pages = [Page(background: .color("#fff"),
                             elements: [Element.shape("rect", w: 10, h: 10)])]
        XCTAssertTrue(DesignStore(design: design).matches(for: "rect").isEmpty)
    }

    /// The preview is the line the match sits on, so a list of matches reads
    /// as context rather than as a column of identical needles.
    func testThePreviewIsTheLineAroundTheMatch() {
        let s = store([["First line\nAcme is here\nThird line"]])
        XCTAssertEqual(s.matches(for: "Acme").first?.preview, "Acme is here")
    }

    // MARK: replacing

    func testReplaceAllRewritesEveryPage() {
        let s = store([["Acme quarterly"], ["Prepared for Acme"]])
        XCTAssertEqual(s.replaceAll("Acme", with: "Globex"), 2)
        XCTAssertEqual(s.design.pages[0].elements[0].text, "Globex quarterly")
        XCTAssertEqual(s.design.pages[1].elements[0].text, "Prepared for Globex")
        XCTAssertTrue(s.matches(for: "Acme").isEmpty)
    }

    /// One step. Forty steps to undo a mistaken replace-all would be worse
    /// than no undo at all.
    func testReplaceAllIsASingleUndoStep() {
        let s = store([["Acme"], ["Acme"], ["Acme"]])
        s.replaceAll("Acme", with: "Globex")
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertEqual(s.design.pages.map { $0.elements[0].text }, ["Acme", "Acme", "Acme"])
        XCTAssertFalse(s.canUndo)
    }

    func testReplacingNothingChangesNothing() {
        let s = store([["Acme"]])
        XCTAssertEqual(s.replaceAll("Missing", with: "x"), 0)
        XCTAssertFalse(s.canUndo, "a no-op replace pushed an undo step")
    }

    /// Replacing changes how much room the text needs, and a box left at the
    /// old height clips the new text.
    func testReplacementResizesTheTextBox() {
        let s = store([["Hi"]])
        let before = s.design.pages[0].elements[0].h
        s.replaceAll("Hi", with: String(repeating: "Much longer text ", count: 8))
        XCTAssertGreaterThan(s.design.pages[0].elements[0].h, before)
    }

    func testRevealSwitchesPageAndSelects() throws {
        let s = store([["nothing"], ["Acme"]])
        let match = try XCTUnwrap(s.matches(for: "Acme").first)
        s.reveal(match)
        XCTAssertEqual(s.pageIndex, 1)
        XCTAssertEqual(s.selection, [match.elementId])
    }

    // MARK: the shared matcher

    /// One row of the table the Android twin's FindReplaceTest runs too, row
    /// for row: the needle, the words, Match case and Whole words, and the
    /// UTF-16 (start, length) of every match.
    private struct Row {
        var needle: String
        var body: String
        var matchCase = false
        var wholeWord = false
        var expected: [[Int]]
    }

    private var rows: [Row] {
        [
            Row(needle: "cat", body: "cat, catalog", wholeWord: true, expected: [[0, 3]]),
            Row(needle: "cat", body: "cat, catalog", expected: [[0, 3], [5, 3]]),
            Row(needle: "cat", body: "concat cat", wholeWord: true, expected: [[7, 3]]),
            Row(needle: "cat", body: "cat2 cat_ 2cat", wholeWord: true, expected: [[5, 3]]),
            Row(needle: "Cat", body: "cat Cat CAT", matchCase: true, wholeWord: true, expected: [[4, 3]]),
            Row(needle: "cat", body: "cat Cat CAT", wholeWord: true, expected: [[0, 3], [4, 3], [8, 3]]),
            Row(needle: "café", body: "le café, cafés", wholeWord: true, expected: [[3, 4]]),
            Row(needle: "aa", body: "aaaa", expected: [[0, 2], [2, 2]]),
            Row(needle: "aa", body: "aaa", wholeWord: true, expected: []),
            Row(needle: "cat", body: "\u{732B}cat", wholeWord: true, expected: []),
            Row(needle: "ok", body: "\u{1F600}ok\u{1F600}", wholeWord: true, expected: [[2, 2]]),
            Row(needle: "ab", body: "ab-ab.ab", wholeWord: true, expected: [[0, 2], [3, 2], [6, 2]]),
            Row(needle: "", body: "anything", expected: []),
        ]
    }

    func testTheSharedMatcherRows() {
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            let found = FindReplace.ranges(of: row.needle, in: row.body,
                                           caseSensitive: row.matchCase, wholeWord: row.wholeWord)
            XCTAssertEqual(found.map { [$0.location, $0.length] }, row.expected, "\(row.needle) in \(row.body)")
        }
    }

    func testWholeWordsAcrossTheDesign() {
        let s = store([["cat, catalog"], ["Concat the cat"]])
        XCTAssertEqual(s.matches(for: "cat").count, 4)
        let whole = s.matches(for: "cat", wholeWord: true)
        XCTAssertEqual(whole.map(\.pageIndex), [0, 1])
        XCTAssertEqual(whole.map(\.range.location), [0, 11])
        XCTAssertEqual(s.replaceAll("cat", with: "dog", wholeWord: true), 2)
        XCTAssertEqual(s.design.pages.map { $0.elements[0].text }, ["dog, catalog", "Concat the dog"])
    }

    /// Hidden and locked boxes are left alone, the same rule on both phones;
    /// a position lock still takes new words.
    func testHiddenAndLockedBoxesAreSkipped() {
        var design = Design(title: "search", width: 800, height: 600)
        var hidden = Element.text("Acme", fontSize: 24, w: 400)
        hidden.hidden = true
        var locked = Element.text("Acme", fontSize: 24, w: 400)
        locked.locked = true
        var pinned = Element.text("Acme", fontSize: 24, w: 400)
        pinned.lockPosition = true
        design.pages = [Page(background: .color("#ffffff"), elements: [hidden, locked, pinned])]
        let s = DesignStore(design: design)
        XCTAssertEqual(s.matches(for: "Acme").map(\.elementId), [pinned.id])
        XCTAssertEqual(s.replaceAll("Acme", with: "Globex"), 1)
        XCTAssertEqual(s.element(hidden.id)?.text, "Acme")
        XCTAssertEqual(s.element(locked.id)?.text, "Acme")
        XCTAssertEqual(s.element(pinned.id)?.text, "Globex")
    }

    // MARK: one at a time

    func testReplaceChangesOnlyTheOneMatchAsOneStep() throws {
        let s = store([["Acme and Acme"], ["Acme"]])
        let found = s.matches(for: "Acme")
        XCTAssertEqual(found.count, 3)
        XCTAssertTrue(s.replaceOne(found[1], with: "Globex"))
        XCTAssertEqual(s.design.pages[0].elements[0].text, "Acme and Globex")
        XCTAssertEqual(s.design.pages[1].elements[0].text, "Acme")
        s.undo()
        XCTAssertEqual(s.design.pages[0].elements[0].text, "Acme and Acme")
        XCTAssertFalse(s.canUndo, "one Replace, one step")
    }

    func testReplaceKeepsTheMarkersAndWordStylesOutsideTheMatch() throws {
        var text = Element.text("**red** car, red", fontSize: 24, w: 400)
        text.setSpans([TextSpan(start: 4, end: 7, color: "#0000ff")])
        var design = Design(title: "one", width: 800, height: 600)
        design.pages[0].elements = [text]
        let found = DesignStore.matches(in: design, for: "red", caseSensitive: false, wholeWord: true)
        XCTAssertEqual(found.count, 2)
        let after = try XCTUnwrap(DesignStore.replacingOne(design, found[1], with: "green"))
        let el = after.pages[0].elements[0]
        XCTAssertEqual(el.text, "**red** car, green")
        XCTAssertEqual(el.liveSpans, [TextSpan(start: 4, end: 7, color: "#0000ff")])
        XCTAssertEqual(design.pages[0].elements[0].text, "**red** car, red", "the design given is left as it was")
    }

    func testAMatchNoLongerThereIsNotReplaced() {
        let s = store([["Acme"]])
        var gone = s.matches(for: "Acme")[0]
        gone.range = NSRange(location: 2, length: 10)
        XCTAssertFalse(s.replaceOne(gone, with: "x"))
        XCTAssertFalse(s.canUndo)
    }

    func testReplaceMovesOnToTheNextMatch() {
        let s = store([["cat cat"], ["cat"]])
        let found = s.matches(for: "cat")
        s.replaceOne(found[0], with: "cats")
        let now = s.matches(for: "cat")
        // "cats cat" / "cat": the replacement holds a match of its own, so
        // the next is the second word, not the word just written.
        XCTAssertEqual(now.count, 3)
        XCTAssertEqual(DesignStore.matchAfter(replacing: found[0], at: 0, length: 4, in: now), 1)
        // After the last, round to the first.
        let last = now[2]
        s.replaceOne(last, with: "dog")
        let left = s.matches(for: "cat")
        XCTAssertEqual(DesignStore.matchAfter(replacing: last, at: 2, length: 3, in: left), 0)
    }

    func testPreviousAndNextGoRoundAndTheReadoutCountsFromOne() {
        XCTAssertEqual(FindReplace.step(from: 0, by: 1, count: 12), 1)
        XCTAssertEqual(FindReplace.step(from: 11, by: 1, count: 12), 0)
        XCTAssertEqual(FindReplace.step(from: 0, by: -1, count: 12), 11)
        XCTAssertEqual(FindReplace.step(from: 5, by: -1, count: 0), 0)
        XCTAssertEqual(FindReplace.position(2, of: 12), "3 of 12")
        XCTAssertEqual(FindReplace.position(20, of: 3), "3 of 3", "held to the last")
        XCTAssertEqual(FindReplace.position(0, of: 0), "")
    }

    // MARK: style

    func testCopyingAStyleCarriesLookAndNotContent() {
        var source = Element.text("Source", fontSize: 80, w: 300)
        source.color = "#ff0066"
        source.fontWeight = 900
        source.effect = TextEffectSpec(type: "neon")
        var target = Element.text("Target", fontSize: 20, w: 300)
        target.x = 123
        target.y = 456
        let id = target.id

        DesignStore.apply(DesignStore.style(of: source), to: &target)

        XCTAssertEqual(target.fontSize, 80)
        XCTAssertEqual(target.color, "#ff0066")
        XCTAssertEqual(target.fontWeight, 900)
        XCTAssertEqual(target.effect?.type, "neon")
        // Identity, position and content are what make it a different element.
        XCTAssertEqual(target.text, "Target")
        XCTAssertEqual(target.x, 123)
        XCTAssertEqual(target.y, 456)
        XCTAssertEqual(target.id, id)
    }

    /// Pasting a text style onto a rectangle should change nothing about the
    /// rectangle — not give it a font it will never use.
    func testAStyleDoesNotCrossElementKinds() {
        let source = Element.text("Source", fontSize: 80, w: 300)
        var target = Element.shape("rect", w: 100, h: 100)
        let before = target
        DesignStore.apply(DesignStore.style(of: source), to: &target)
        XCTAssertNil(target.fontSize)
        XCTAssertEqual(target.shapeId, before.shapeId)
        XCTAssertEqual(target.w, before.w)
    }

    func testShapeStyleCarriesFillAndBorder() {
        var source = Element.shape("rect", w: 100, h: 100)
        source.fill = .solid("#00ff88")
        source.stroke = "#112233"
        source.strokeWidth = 5
        source.radius = 12
        var target = Element.shape("ellipse", w: 50, h: 50)
        DesignStore.apply(DesignStore.style(of: source), to: &target)
        XCTAssertEqual(target.fill, .solid("#00ff88"))
        XCTAssertEqual(target.stroke, "#112233")
        XCTAssertEqual(target.strokeWidth, 5)
        XCTAssertEqual(target.radius, 12)
        XCTAssertEqual(target.shapeId, "ellipse", "the shape itself was overwritten")
    }

    func testPastingAStyleThroughTheStoreIsUndoable() {
        var design = Design(width: 400, height: 400)
        var a = Element.shape("rect", w: 100, h: 100)
        a.fill = .solid("#00ff88")
        let b = Element.shape("rect", w: 100, h: 100)
        design.pages = [Page(background: .color("#fff"), elements: [a, b])]
        let s = DesignStore(design: design)

        s.selection = [a.id]
        s.copyStyle()
        XCTAssertTrue(s.hasCopiedStyle)
        s.selection = [b.id]
        s.pasteStyle()
        XCTAssertEqual(s.design.pages[0].elements[1].fill, .solid("#00ff88"))
        s.undo()
        XCTAssertNotEqual(s.design.pages[0].elements[1].fill, .solid("#00ff88"))
    }

    func testPastingWithNothingCopiedDoesNothing() {
        let s = store([["a"]])
        s.selection = [s.design.pages[0].elements[0].id]
        s.pasteStyle()
        XCTAssertFalse(s.canUndo)
    }

    // MARK: the sheet's words

    func testTheSummarySaysHowManyAndOnHowManyPages() {
        let s = store([["Acme quarterly, Acme"], ["Prepared for Acme"], ["Nothing here"]])
        let found = s.matches(for: "Acme")
        XCTAssertEqual(FindReplaceSheet.summary(needle: "Acme", matches: found, replaced: nil), "3 found on 2 pages")
        XCTAssertEqual(FindReplaceSheet.summary(needle: "Acme", matches: Array(found.prefix(2)), replaced: nil),
                       "2 found on 1 page")
        XCTAssertEqual(FindReplaceSheet.summary(needle: "Zed", matches: [], replaced: nil), "Not found in this design.")
        XCTAssertEqual(FindReplaceSheet.summary(needle: "Acme", matches: found, replaced: 3), "Replaced 3 occurrences.")
    }
}
