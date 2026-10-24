// Find and replace and spelling reach the speaker notes, and a chart's
// labels changed in place keep their words through the chart's Update —
// the rows the Android twin's FindReplaceTest runs too.

import XCTest
@testable import Canvia

@MainActor
final class FindScopeTests: XCTestCase {

    private func design(text: String, notes: String?, locked: Bool = false) -> Design {
        var design = Design(title: "notes", width: 800, height: 600)
        design.pages[0].elements = [Element.text(text, fontSize: 24, w: 400)]
        design.pages[0].notes = notes
        if locked { design.pages[0].locked = true }
        return design
    }

    /// Shared: a match in the notes is found after the page's boxes, and
    /// replaced there as plain text.
    func testANotesMatchIsFoundAndReplaced() throws {
        let start = design(text: "Q1 plan", notes: "Talk about **Q1** first")
        let found = DesignStore.matches(in: start, for: "Q1", caseSensitive: false, wholeWord: false)
        XCTAssertEqual(found.map(\.kind), [.element, .notes])
        XCTAssertEqual(found[1].elementId, "")
        XCTAssertEqual(found[1].range, NSRange(location: 13, length: 2), "the notes' own characters, stars and all")
        XCTAssertEqual(found[1].preview, "Talk about **Q1** first")
        XCTAssertEqual(FindReplaceSheet.notesPlace(found[1].pageIndex), "Notes, page 1")
        let one = try XCTUnwrap(DesignStore.replacingOne(start, found[1], with: "Q2"))
        XCTAssertEqual(one.pages[0].notes, "Talk about **Q2** first")
        XCTAssertEqual(one.pages[0].elements[0].text, "Q1 plan")

        let store = DesignStore(design: start)
        XCTAssertEqual(store.replaceAll("Q1", with: "Spring"), 2)
        XCTAssertEqual(store.design.pages[0].notes, "Talk about **Spring** first")
        XCTAssertEqual(store.design.pages[0].elements[0].text, "Spring plan")
    }

    /// Shared: a locked page's notes are neither searched nor changed.
    func testALockedPagesNotesAreUntouched() {
        let locked = design(text: "Q1 plan", notes: "Q1 notes", locked: true)
        XCTAssertTrue(DesignStore.matches(in: locked, for: "Q1", caseSensitive: false, wholeWord: false).isEmpty)
        let match = DesignStore.TextMatch(pageIndex: 0, elementId: "", range: NSRange(location: 0, length: 2),
                                          plain: NSRange(location: 0, length: 2), preview: "Q1 notes", kind: .notes)
        XCTAssertNil(DesignStore.replacingOne(locked, match, with: "Q2"))
        let store = DesignStore(design: locked)
        XCTAssertEqual(store.replaceAll("Q1", with: "Q2"), 0)
        XCTAssertEqual(store.design.pages[0].notes, "Q1 notes")
    }

    /// Shared: a chart's row label replaced is its data's too, so drawing
    /// the chart again keeps the new word; its value labels are found but
    /// never replaced, being drawn from its numbers.
    func testReplacingAChartLabelSurvivesTheRedraw() throws {
        let spec = ChartSpec(id: "chart_q", kind: "column", data: "Q1, 10\nQ2, 20", values: true)
        let frame = CGRect(x: 0, y: 0, width: 400, height: 300)
        let drawn = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"], heightFor: { _ in 20 })
        var start = Design(title: "chart", width: 800, height: 600)
        start.pages[0].elements = drawn
        let values = DesignStore.matches(in: start, for: "10", caseSensitive: false, wholeWord: true)
        XCTAssertEqual(values.count, 1)
        XCTAssertNil(DesignStore.replacingOne(start, values[0], with: "11"))
        XCTAssertEqual(DesignStore(design: start).replaceAll("10", with: "11", wholeWord: true), 0)
        let found = DesignStore.matches(in: start, for: "Q1", caseSensitive: true, wholeWord: true)
        XCTAssertEqual(found.count, 1)
        let after = try XCTUnwrap(DesignStore.replacingOne(start, found[0], with: "Spring"))
        let specs = after.pages[0].elements.compactMap(\.chart)
        XCTAssertEqual(specs.count, drawn.count)
        XCTAssertTrue(specs.allSatisfy { $0.data == "Spring, 10\nQ2, 20" })
        let again = DataGraphics.chart(try XCTUnwrap(specs.first), in: frame, palette: ["#ff0000"],
                                       heightFor: { _ in 20 })
        let labels = again.filter { $0.chartPart == "label" }.map { RichText.strip($0.text ?? "") }
        XCTAssertTrue(labels.contains("Spring"))
        XCTAssertFalse(labels.contains("Q1"))
        // A series name in a header follows its legend the same way.
        XCTAssertEqual(DataGraphics.withNames("Quarter, North, South\nQ1, 1, 2", renaming: "North", to: "East"),
                       "Quarter, East, South\nQ1, 1, 2")
        XCTAssertEqual(DataGraphics.withRows("Q1, 10", renaming: "Q9", to: "x"), "Q1, 10", "nothing to rename")
        // Shared: only the label's cell is written again, the other lines
        // as typed; a label that would not read back as one cell is not.
        XCTAssertEqual(DataGraphics.withRows("Q1,\t10\n\nQ2, 20", renaming: "Q1", to: "Q1 2024"),
                       "Q1 2024,\t10\n\nQ2, 20")
        XCTAssertEqual(DataGraphics.withRows("Q1, 1\nQ1x, 2", renaming: "Q1", to: "Q1"), "Q1, 1\nQ1x, 2")
        XCTAssertEqual(DataGraphics.withRows("A,B, 1", renaming: "A", to: "x,y"), "A,B, 1")
        XCTAssertEqual(DataGraphics.withRows("Q1, 10", renaming: "Q1", to: "Q1, 2024"), "Q1, 10")
        XCTAssertEqual(DataGraphics.withNames("Quarter, North, South\nQ1, 1, 2", renaming: "Quarter", to: "Season"),
                       "Quarter, North, South\nQ1, 1, 2")
    }

    /// The notes' misspellings are listed after the page's boxes', and a
    /// fix there changes the notes as plain text.
    func testANotesMisspellingIsFixedInTheNotes() throws {
        let start = design(text: "Hello", notes: "Remember the agnda")
        let found = Proofreader.misspellings(in: start, language: "en-US")
        let miss = try XCTUnwrap(found.first { $0.kind == .notes })
        XCTAssertEqual(miss.elementId, "")
        XCTAssertEqual(miss.range, NSRange(location: 13, length: 5))
        let fixed = try XCTUnwrap(Proofreader.fixed(start, miss, with: "agenda"))
        XCTAssertEqual(fixed.pages[0].notes, "Remember the agenda")
        var locked = start
        locked.pages[0].locked = true
        XCTAssertNil(Proofreader.fixed(locked, miss, with: "agenda"))
    }
}
