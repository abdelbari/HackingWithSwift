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
}
