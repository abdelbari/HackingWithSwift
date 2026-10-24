// Which of a table's lines show, and where its words sit in their cells —
// on the test table both phones share (TablesTests), and the sides of a
// merged 3x3 from the shared fixture (Fixtures/table-sides.json), as the
// Android twin's TableBordersTest.

import XCTest
@testable import Canvia

final class TableBordersTests: XCTestCase {

    private var heightFor: (Element) -> Double {
        { el in Double((el.text ?? "").components(separatedBy: "\n").count) * 20 }
    }

    private func made() -> [Element] {
        DataGraphics.table(DataGraphics.parseTable("Item, Qty\nCoffee, 2\nBagel, 1"),
                           in: CGRect(x: 100, y: 200, width: 400, height: 300), accent: "#1f2430",
                           heightFor: heightFor)
    }

    private func tableId(_ els: [Element]) -> String {
        els.lazy.compactMap { $0.table?.id }.first ?? ""
    }

    private func cell(_ els: [Element], _ type: ElementType, _ row: Int, _ col: Int) -> Element {
        els.first { $0.type == type && $0.table?.row == row && $0.table?.col == col } ?? Element.shape("rect")
    }

    /// Shared with the Android twin's TableBordersTest.
    func testTheSidesEachCellStrokesMatchTheSharedFixture() throws {
        let root = try SharedFixture.object("table-sides")
        let rows = try XCTUnwrap(root["rows"] as? Int)
        let cols = try XCTUnwrap(root["cols"] as? Int)
        let cells = try XCTUnwrap(root["cells"] as? [[Int]]).map {
            TableCell(id: "tbl_x", row: $0[0], col: $0[1], rowSpan: $0[2], colSpan: $0[3])
        }
        let sides = try XCTUnwrap(root["sides"] as? [String: [String]])
        XCTAssertEqual(Set(sides.keys), Set(Tables.borderModes))
        for (mode, expected) in sides {
            XCTAssertEqual(cells.map { Tables.sides($0, rows: rows, cols: cols, mode: mode) }, expected, mode)
        }
    }

    func testAnUnknownModeDrawsEverySide() {
        XCTAssertEqual(Tables.sides(TableCell(id: "t", row: 1, col: 1), rows: 3, cols: 3, mode: "dotted"), "tlbr")
    }

    func testANewTableStrokesEverySideAndKeepsNoSides() {
        let table = made()
        XCTAssertEqual(Tables.borderMode(table, id: tableId(table)), "all")
        XCTAssertTrue(table.allSatisfy { $0.sides == nil })
        XCTAssertTrue(table.filter { $0.type == .shape }.allSatisfy { Tables.sideLines($0) == nil })
    }

    func testOuterBordersKeepTheModeOnEveryCellAndTheSidesOnTheRectangles() throws {
        let table = made()
        let id = tableId(table)
        let outer = try XCTUnwrap(Tables.withBorderMode(table, id: id, mode: "outer"))
        XCTAssertEqual(Tables.borderMode(outer, id: id), "outer")
        XCTAssertEqual(cell(outer, .shape, 0, 0).sides, "tl")
        XCTAssertEqual(cell(outer, .shape, 1, 1).sides, "r")
        XCTAssertNil(cell(outer, .text, 0, 0).sides)
        // A row added is lined as the mode has it: the old last row's bottom
        // is inside now.
        let added = DataGraphics.addingTableRow(outer, id: id, row: 2, below: true, heightFor: heightFor)
        XCTAssertEqual(cell(added, .shape, 2, 0).sides, "l")
        XCTAssertEqual(cell(added, .shape, 3, 0).sides, "lb")
        // Back to all: no sides left, and no key.
        let all = try XCTUnwrap(Tables.withBorderMode(added, id: id, mode: "all"))
        XCTAssertTrue(all.allSatisfy { $0.sides == nil })
        XCTAssertTrue(all.allSatisfy { $0.table?.borders == nil })
        XCTAssertNil(Tables.withBorderMode(all, id: id, mode: "all"))
        XCTAssertNil(Tables.withBorderMode(all, id: id, mode: "dotted"))
    }

    func testNoBordersStrokesNoSide() throws {
        let table = made()
        let none = try XCTUnwrap(Tables.withBorderMode(table, id: tableId(table), mode: "none"))
        let rect = cell(none, .shape, 1, 0)
        XCTAssertEqual(rect.sides, "")
        XCTAssertEqual(Tables.sideLines(rect)?.count, 0)
    }

    func testASidesLineRunsAlongTheRectanglesEdge() {
        var rect = Element.shape("rect", w: 40, h: 20)
        rect.sides = "br"
        XCTAssertEqual(Tables.sideLines(rect), [[0, 20, 40, 20], [40, 0, 40, 20]])
    }

    func testTheModeAndTheSidesAreWrittenAndReadBack() throws {
        let table = made()
        let id = tableId(table)
        let inner = try XCTUnwrap(Tables.withBorderMode(table, id: id, mode: "inner"))
        let rect = cell(inner, .shape, 0, 0)
        let json = String(decoding: try JSONEncoder().encode(rect), as: UTF8.self)
        XCTAssertTrue(json.contains(#""borders":"inner""#))
        XCTAssertTrue(json.contains(#""sides":"br""#))
        let back = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertEqual(back.sides, "br")
        XCTAssertEqual(back.table?.borders, "inner")
        // A mode this build does not know is every line.
        let odd = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e","type":"shape","table":{"id":"t","row":0,"col":0,"borders":"dotted"}}"#.utf8))
        XCTAssertNil(odd.table?.borders)
    }

    // MARK: alignment in cells

    func testWordsSetMiddleOrBottomSitDownTheRoomATallerRowLeaves() throws {
        let table = made()
        let id = tableId(table)
        // Row 1 held at 86 tall: 40 of room beyond the 46 its words need.
        let tall = DataGraphics.relaidTable(DataGraphics.withRowMinimum(table, id: id, row: 1, height: 86), id: id,
                                            heightFor: heightFor)
        let top = cell(tall, .text, 1, 0).y
        let middle = try XCTUnwrap(Tables.aligned(tall, id: id, cells: [[1, 0]], align: "middle", heightFor: heightFor))
        XCTAssertEqual(cell(middle, .text, 1, 0).y, top + 20, accuracy: 1e-9)
        XCTAssertEqual(cell(middle, .text, 1, 0).vAlign, "middle")
        // The cell beside it stays at the top.
        XCTAssertEqual(cell(middle, .text, 1, 1).y, cell(tall, .text, 1, 1).y, accuracy: 1e-9)
        XCTAssertNil(Tables.cellAlignment(middle, id: id, cells: nil))
        XCTAssertEqual(Tables.cellAlignment(middle, id: id, cells: [[1, 0]]), "middle")
        let bottom = try XCTUnwrap(Tables.aligned(middle, id: id, cells: nil, align: "bottom", heightFor: heightFor))
        XCTAssertEqual(cell(bottom, .text, 1, 0).y, top + 40, accuracy: 1e-9)
        XCTAssertEqual(Tables.cellAlignment(bottom, id: id, cells: nil), "bottom")
        // Top takes the key off again.
        let back = try XCTUnwrap(Tables.aligned(bottom, id: id, cells: nil, align: "top", heightFor: heightFor))
        XCTAssertTrue(back.allSatisfy { $0.vAlign == nil })
        XCTAssertEqual(cell(back, .text, 1, 0).y, top, accuracy: 1e-9)
        XCTAssertNil(Tables.aligned(back, id: id, cells: nil, align: "top", heightFor: heightFor))
    }

    func testAMergedCellsWordsSitInTheMiddleOfItsRows() throws {
        let table = made()
        let id = tableId(table)
        let places = Set([cell(table, .text, 1, 1), cell(table, .text, 2, 1)].compactMap(\.table))
        let merged = try XCTUnwrap(DataGraphics.mergingTableCells(table, id: id, cells: places, heightFor: heightFor))
        let rect = cell(merged, .shape, 1, 1)
        let aligned = try XCTUnwrap(Tables.aligned(merged, id: id, cells: [[1, 1]], align: "middle", heightFor: heightFor))
        let words = cell(aligned, .text, 1, 1)
        let pad = DataGraphics.tablePadding(merged, id: id)
        XCTAssertEqual(words.y, (rect.y + pad + (rect.h - 2 * pad - words.h) / 2 + 0.5).rounded(.down), accuracy: 1e-9)
    }

    func testTheSlackIsNeverBelowNone() {
        var text = Element.text("A", fontSize: 10, w: 50)
        text.h = 30
        text.vAlign = "bottom"
        XCTAssertEqual(Tables.cellSlack(text, room: 20), 0, accuracy: 1e-9)
        XCTAssertEqual(Tables.cellSlack(text, room: 40), 10, accuracy: 1e-9)
    }
}
