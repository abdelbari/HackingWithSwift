// Layers' Select: several rows ticked — a group's row all its members,
// hidden and locked rows too — and a ticked row's drag moving every ticked
// row as one block. The Android twin's LayersTest holds the same rows for
// Layers.toggled.

import XCTest
@testable import Canvia

@MainActor
final class LayersSelectTests: XCTestCase {

    private func box(_ id: String, group: String? = nil, hidden: Bool = false, locked: Bool = false) -> Element {
        var el = Element.shape("rect", w: 100, h: 100)
        el.id = id
        el.group = group
        el.hidden = hidden ? true : nil
        el.locked = locked
        return el
    }

    /// Back to front: a, g1, g2 (grouped), h (hidden), l (locked).
    private var page: [Element] {
        [box("a"), box("g1", group: "g"), box("g2", group: "g"), box("h", hidden: true), box("l", locked: true)]
    }

    /// Shared rows: what is selected, the row tapped, and the selection then.
    func testToggledTable() {
        let rows = LayerRows.rows(page, expanded: [])
        XCTAssertEqual(rows.map(\.id), ["l", "h", "group:g", "a"])
        let table: [(Set<String>, String, Set<String>)] = [
            ([], "a", ["a"]),
            (["a"], "a", []),
            (["a"], "group:g", ["a", "g1", "g2"]),
            (["a", "g1", "g2"], "group:g", ["a"]),
            // Part of a group ticked: its row takes the rest in.
            (["g1"], "group:g", ["g1", "g2"]),
            (["a"], "h", ["a", "h"]),
            (["a"], "l", ["a", "l"]),
            (["a"], "missing", ["a"]),
        ]
        for (selection, row, next) in table {
            XCTAssertEqual(Layers.toggled(rows, selection: selection, rowId: row), next, "\(selection) tick \(row)")
        }
    }

    func testATickedRowsDragMovesEveryTickedRowAsOneBlock() {
        let els = page
        let rows = LayerRows.rows(els, expanded: [])
        // l and a ticked; l's handle dragged: both move, in their order.
        let source = Layers.dragged(rows, selection: ["l", "a"], source: [0])
        XCTAssertEqual(source, IndexSet([0, 3]))
        XCTAssertEqual(LayerRows.moved(els, rows: rows, from: source, to: 2).map(\.id), ["g1", "g2", "a", "l", "h"],
                       "above the group, l still over a")
        // A row not ticked moves alone.
        XCTAssertEqual(Layers.dragged(rows, selection: ["l", "a"], source: [1]), IndexSet([1]))
    }

    func testSelectingRowsFromLayersTakesHiddenAndLockedOnesAndActsInOneStep() {
        var d = Design(title: "layers", width: 1080, height: 1080)
        d.pages = [Page(elements: page)]
        let s = DesignStore(design: d)
        let rows = LayerRows.rows(s.page.elements, expanded: [])
        s.selectLayers(Layers.toggled(rows, selection: s.selection, rowId: "h"))
        s.selectLayers(Layers.toggled(rows, selection: s.selection, rowId: "a"))
        XCTAssertEqual(s.selection, ["h", "a"])
        s.setHidden(s.selection, hidden: false)
        XCTAssertNil(s.element("h")?.hidden)
        s.groupSelected()
        XCTAssertNotNil(s.element("a")?.group)
        XCTAssertEqual(s.element("a")?.group, s.element("h")?.group)
        s.undo()
        XCTAssertNil(s.element("a")?.group, "each one undo step")
        s.undo()
        XCTAssertEqual(s.element("h")?.hidden, true)
    }
}
