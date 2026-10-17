// Tables edited further: rows and columns moved, cell spacing, alternating
// rows and Tab from cell to cell — on the test table both phones share
// (TablesTests), number for number, and each change one undo step.

import XCTest
@testable import Canvia

/// The shared test table: "Item, Qty / Coffee, 2 / Bagel, 1" in a 400-wide
/// frame at (100, 200), each line of words 20 tall. Type 22, so the cells are
/// inset 13.2; columns 267 and 133 wide at x 100 and 367; rows 46 tall at y
/// 200, 246 and 292; the header in the accent, the body banded white and
/// #f3f4f6 from row 1.
@MainActor
final class TableEditingTests: XCTestCase {

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

    private func rect(_ els: [Element], _ row: Int, _ col: Int) -> Element {
        els.first { $0.type == .shape && $0.table?.row == row && $0.table?.col == col } ?? Element.shape("rect")
    }

    private func text(_ els: [Element], _ row: Int, _ col: Int) -> Element {
        els.first { $0.type == .text && $0.table?.row == row && $0.table?.col == col } ?? Element.text("")
    }

    private func words(_ els: [Element]) -> [String] {
        els.filter { $0.type == .text }
            .sorted { a, b in (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0) }
            .map { $0.text ?? "" }
    }

    private func rowTops(_ els: [Element]) -> [Double] {
        DataGraphics.tableRows(els, id: tableId(els)).map { rect(els, $0, 0).y }
    }

    private func fills(_ els: [Element], column: Int) -> [String?] {
        DataGraphics.tableRows(els, id: tableId(els)).map { rect(els, $0, column).fill?.color }
    }

    private func merged(_ els: [Element], _ places: [(Int, Int)]) throws -> [Element] {
        let cells = Set(places.map { text(els, $0.0, $0.1).table }.compactMap { $0 })
        return try XCTUnwrap(DataGraphics.mergingTableCells(els, id: tableId(els), cells: cells, heightFor: heightFor))
    }

    // MARK: moving rows and columns

    func testARowMovesWithItsWordsAndColoursTheRowsStayingWhereTheyWere() throws {
        let table = made()
        let id = tableId(table)
        let down = try XCTUnwrap(DataGraphics.movedTableRow(table, id: id, row: 1, by: 1, heightFor: heightFor))
        XCTAssertEqual(words(down), ["Item", "Qty", "Bagel", "1", "Coffee", "2"])
        XCTAssertEqual(rowTops(down), [200, 246, 292])
        XCTAssertEqual(text(down, 1, 0).y, 259)
        XCTAssertEqual(fills(down, column: 0), ["#1f2430", "#f3f4f6", "#ffffff"], "the colours go with the cells")
        XCTAssertEqual(text(down, 1, 0).id, text(table, 2, 0).id, "the same cells, moved")
        let up = try XCTUnwrap(DataGraphics.movedTableRow(down, id: id, row: 2, by: -1, heightFor: heightFor))
        XCTAssertEqual(up, table, "moved back is as it was")
        XCTAssertNil(DataGraphics.movedTableRow(table, id: id, row: 2, by: 1, heightFor: heightFor), "no row below")
        XCTAssertNil(DataGraphics.movedTableRow(table, id: id, row: 0, by: -1, heightFor: heightFor), "no row above")
    }

    func testAColumnMovesWithItsWidth() throws {
        let table = made()
        let right = try XCTUnwrap(DataGraphics.movedTableColumn(table, id: tableId(table), col: 0, by: 1,
                                                                heightFor: heightFor))
        XCTAssertEqual(words(right), ["Qty", "Item", "2", "Coffee", "1", "Bagel"])
        XCTAssertEqual(DataGraphics.tableColumnWidths(right, id: tableId(right)), [133, 267])
        XCTAssertEqual(rect(right, 0, 1).x, 233)
        XCTAssertEqual(text(right, 0, 0).x, 113)
        XCTAssertEqual(text(right, 0, 1).x, 246)
        XCTAssertEqual(text(right, 0, 1).w, 240.6, accuracy: 1e-9)
        XCTAssertNil(DataGraphics.movedTableColumn(table, id: tableId(table), col: 1, by: 1, heightFor: heightFor))
    }

    func testAMoveThatWouldPartAMergedCellIsRefused() throws {
        let tall = try merged(made(), [(1, 0), (2, 0)])
        let id = tableId(tall)
        XCTAssertTrue(DataGraphics.rowMoveSplitsMerge(tall, id: id, row: 1, by: 1))
        XCTAssertTrue(DataGraphics.rowMoveSplitsMerge(tall, id: id, row: 0, by: 1), "row 1 is the merged cell's")
        XCTAssertNil(DataGraphics.movedTableRow(tall, id: id, row: 0, by: 1, heightFor: heightFor))
        XCTAssertFalse(DataGraphics.columnMoveSplitsMerge(tall, id: id, col: 0, by: 1), "a cell one column wide")
        XCTAssertNotNil(DataGraphics.movedTableColumn(tall, id: id, col: 0, by: 1, heightFor: heightFor))

        let wide = try merged(made(), [(1, 0), (1, 1)])
        XCTAssertTrue(DataGraphics.columnMoveSplitsMerge(wide, id: tableId(wide), col: 0, by: 1))
        XCTAssertNil(DataGraphics.movedTableColumn(wide, id: tableId(wide), col: 0, by: 1, heightFor: heightFor))
        let moved = try XCTUnwrap(DataGraphics.movedTableRow(wide, id: tableId(wide), row: 1, by: 1, heightFor: heightFor))
        XCTAssertEqual(text(moved, 2, 0).table?.colSpan, 2, "a whole row moves, its merged cell with it")
    }

    // MARK: cell spacing

    func testCellSpacingInsetsTheWordsAndTheRowsGrowToIt() {
        let table = made()
        let id = tableId(table)
        XCTAssertEqual(DataGraphics.tablePadding(table, id: id), 22 * 0.6, accuracy: 1e-9)
        let spaced = DataGraphics.withTablePadding(table, id: id, padding: 20, heightFor: heightFor)
        XCTAssertTrue(spaced.allSatisfy { $0.table?.pad == 20 })
        XCTAssertEqual(rowTops(spaced), [200, 260, 320])
        XCTAssertEqual(rect(spaced, 0, 0).h, 60)
        XCTAssertEqual(text(spaced, 0, 0).x, 120)
        XCTAssertEqual(text(spaced, 1, 0).y, 280)
        XCTAssertEqual(text(spaced, 0, 0).w, 227, accuracy: 1e-9)
        XCTAssertEqual(DataGraphics.tablePadding(spaced, id: id), 20)
        // Kept through a row added.
        let grown = DataGraphics.addingTableRow(spaced, id: id, row: 2, below: true, heightFor: heightFor)
        XCTAssertEqual(rowTops(grown), [200, 260, 320, 380])
        // Back at the inset the table was made with, there is no key.
        let back = DataGraphics.withTablePadding(spaced, id: id, padding: DataGraphics.defaultTablePadding(spaced, id: id),
                                                 heightFor: heightFor)
        XCTAssertEqual(back, table)
        let most = DataGraphics.withTablePadding(table, id: id, padding: 100, heightFor: heightFor)
        XCTAssertEqual(DataGraphics.tablePadding(most, id: id), 40, "held to the slider's 40")
        XCTAssertEqual(DataGraphics.withTablePadding(table, id: id, padding: 0, heightFor: heightFor).first?.table?.pad, 0)
    }

    // MARK: alternating rows

    /// The rule both phones share (the Android twin's TablesTest): with no
    /// `bands` kept, a body striped as a table is made reads On, in the
    /// default band; Off takes the stripes away; a body coloured its own
    /// way reads Off.
    func testANewTableReadsAlternatingRowsOnAndOffTakesTheStripesAway() throws {
        let table = made()
        let id = tableId(table)
        XCTAssertNil(DataGraphics.tableBands(table, id: id), "nothing kept")
        XCTAssertEqual(fills(table, column: 0), ["#1f2430", "#ffffff", "#f3f4f6"])
        XCTAssertEqual(DataGraphics.tableBandsShown(table, id: id), DataGraphics.tableBand)
        let off = DataGraphics.withTableBands(table, id: id, on: false, colour: DataGraphics.tableBand)
        XCTAssertNil(DataGraphics.tableBandsShown(off, id: id))
        XCTAssertEqual(fills(off, column: 0), ["#1f2430", "#ffffff", "#ffffff"])
        let own = try XCTUnwrap(rect(table, 2, 1).table)
        let coloured = DataGraphics.colouringTableCells(table, id: id, cells: [own], color: "#ef4444")
        XCTAssertNil(DataGraphics.tableBandsShown(coloured, id: id))
        let kept = DataGraphics.withTableBands(coloured, id: id, on: true, colour: "#dbeafe")
        XCTAssertEqual(DataGraphics.tableBandsShown(kept, id: id), "#dbeafe")
    }

    func testAlternatingRowsStripeTheBodyAndFollowARowMoved() throws {
        var table = made()
        let id = tableId(table)
        // Striped as a table is made, whatever colour a body cell had: the
        // simplest rule, and the Android twin's.
        let own = try XCTUnwrap(rect(table, 2, 1).table)
        table = DataGraphics.colouringTableCells(table, id: id, cells: [own], color: "#ef4444")
        let banded = DataGraphics.withTableBands(table, id: id, on: true, colour: "#DBEAFE")
        XCTAssertEqual(DataGraphics.tableBands(banded, id: id), "#dbeafe")
        XCTAssertTrue(banded.allSatisfy { $0.table?.bands == "#dbeafe" })
        XCTAssertEqual(fills(banded, column: 0), ["#1f2430", "#ffffff", "#dbeafe"], "the header keeps its own")
        XCTAssertEqual(fills(banded, column: 1), ["#1f2430", "#ffffff", "#dbeafe"])

        let moved = try XCTUnwrap(DataGraphics.movedTableRow(banded, id: id, row: 1, by: 1, heightFor: heightFor))
        XCTAssertEqual(words(moved), ["Item", "Qty", "Bagel", "1", "Coffee", "2"])
        XCTAssertEqual(fills(moved, column: 0), ["#1f2430", "#ffffff", "#dbeafe"], "striped again")
        XCTAssertEqual(fills(moved, column: 1), ["#1f2430", "#ffffff", "#dbeafe"])
        let added = DataGraphics.addingTableRow(moved, id: id, row: 2, below: true, heightFor: heightFor)
        XCTAssertEqual(fills(added, column: 0), ["#1f2430", "#ffffff", "#dbeafe", "#ffffff"])
        let deleted = try XCTUnwrap(DataGraphics.deletingTableRow(added, id: id, row: 1, heightFor: heightFor))
        XCTAssertEqual(fills(deleted, column: 0), ["#1f2430", "#ffffff", "#dbeafe"])

        let off = DataGraphics.withTableBands(banded, id: id, on: false, colour: "#dbeafe")
        XCTAssertNil(DataGraphics.tableBands(off, id: id))
        XCTAssertEqual(fills(off, column: 0), ["#1f2430", "#ffffff", "#ffffff"])
        XCTAssertEqual(fills(off, column: 1), ["#1f2430", "#ffffff", "#ffffff"])
        // With no header, every row is a body row.
        let other = made()
        let otherId = tableId(other)
        let headless = DataGraphics.withTableHeader(other, id: otherId, on: false, accent: "#1f2430", heightFor: heightFor)
        let unheaded = DataGraphics.withTableBands(headless, id: otherId, on: true, colour: "#ffeedd")
        XCTAssertEqual(fills(unheaded, column: 0), ["#ffeedd", "#ffffff", "#ffeedd"])
        // Without kept bands, a moved row keeps the colours it had.
        let fresh = made()
        let plain = try XCTUnwrap(DataGraphics.movedTableRow(fresh, id: tableId(fresh), row: 1, by: 1, heightFor: heightFor))
        XCTAssertEqual(fills(plain, column: 0), ["#1f2430", "#f3f4f6", "#ffffff"])
    }

    func testTheHeaderRowStaysAtTheTop() throws {
        // Moved with the alternating rows on, the old header would be
        // striped as a body row, its light bold words on white: neither it
        // nor the row under it crosses the top. A table with no header
        // moves its first row freely.
        let table = made()
        let id = tableId(table)
        let on = DataGraphics.withTableBands(table, id: id, on: true, colour: "#ffd6e0")
        XCTAssertTrue(DataGraphics.tableHeaderStays(on, id: id, row: 0, by: 1))
        XCTAssertTrue(DataGraphics.tableHeaderStays(on, id: id, row: 1, by: -1))
        XCTAssertFalse(DataGraphics.tableHeaderStays(on, id: id, row: 1, by: 1))
        XCTAssertNil(DataGraphics.movedTableRow(on, id: id, row: 0, by: 1, heightFor: heightFor))
        XCTAssertNil(DataGraphics.movedTableRow(on, id: id, row: 1, by: -1, heightFor: heightFor))
        XCTAssertNil(DataGraphics.movedTableRow(table, id: id, row: 0, by: 1, heightFor: heightFor))
        let headless = DataGraphics.withTableHeader(on, id: id, on: false, accent: "#1f2430", heightFor: heightFor)
        XCTAssertFalse(DataGraphics.tableHeaderStays(headless, id: id, row: 0, by: 1))
        let moved = try XCTUnwrap(DataGraphics.movedTableRow(headless, id: id, row: 0, by: 1, heightFor: heightFor))
        XCTAssertEqual(words(moved), ["Coffee", "2", "Item", "Qty", "Bagel", "1"])
        XCTAssertEqual(fills(moved, column: 0), ["#ffd6e0", "#ffffff", "#ffd6e0"])
    }

    func testRowsTypedInTakeTheTablesAlternatingRows() throws {
        let table = made()
        let id = tableId(table)
        let one = try XCTUnwrap(DataGraphics.deletingTableRow(DataGraphics.withTableBands(table, id: id, on: true, colour: "#ffd6e0"),
                                                              id: id, row: 2, heightFor: heightFor))
        let rows = [["Item", "Qty"], ["Coffee", "2"], ["Tea", "3"], ["Milk", "4"]]
        let more = try XCTUnwrap(DataGraphics.rebuiltTable(one, id: id, rows: rows, heightFor: heightFor))
        XCTAssertEqual(words(more), ["Item", "Qty", "Coffee", "2", "Tea", "3", "Milk", "4"])
        XCTAssertEqual(fills(more, column: 0), ["#1f2430", "#ffffff", "#ffd6e0", "#ffffff"])
        // With none kept, the default band as a table is made.
        let plain = try XCTUnwrap(DataGraphics.rebuiltTable(
            try XCTUnwrap(DataGraphics.deletingTableRow(table, id: id, row: 2, heightFor: heightFor)),
            id: id, rows: rows, heightFor: heightFor))
        XCTAssertEqual(fills(plain, column: 0), ["#1f2430", "#ffffff", "#f3f4f6", "#ffffff"])
    }

    // MARK: cell spacing scaled

    func testCellSpacingScalesWithTheTableSoItsNextRelayoutHoldsItsRows() throws {
        // Lines as tall as the type, so a scaled table measures scaled.
        let typed: (Element) -> Double = { $0.fontSize ?? 20 }
        let table = DataGraphics.table(DataGraphics.parseTable("Item, Qty\nCoffee, 2\nBagel, 1"),
                                       in: CGRect(x: 100, y: 200, width: 400, height: 300), accent: "#1f2430",
                                       heightFor: typed)
        let id = tableId(table)
        let padded = DataGraphics.withTablePadding(table, id: id, padding: 30, heightFor: typed)
        XCTAssertEqual(rect(padded, 0, 0).table?.pad, 30)
        XCTAssertEqual(DataGraphics.tableRows(padded, id: id).map { rect(padded, $0, 0).h }, [82, 82, 82])
        // With the page (scaledSizes): pad 15 and rows 41 tall, which the
        // relayout keeps.
        let small = padded.map { el -> Element in
            var out = el.scaledSizes(by: 0.5)
            out.x = el.x * 0.5
            out.y = el.y * 0.5
            return out
        }
        XCTAssertEqual(rect(small, 0, 0).table?.pad, 15)
        XCTAssertEqual(text(small, 1, 0).fontSize, 11)
        let relaid = DataGraphics.relaidTable(small, id: id, heightFor: typed)
        XCTAssertEqual(DataGraphics.tableRows(relaid, id: id).map { rect(relaid, $0, 0).h }, [41, 41, 41])
        XCTAssertEqual(rowTops(small), rowTops(relaid))
        // With the selection (Geometry.scale): the same.
        let box = Geometry.union(padded.map(Geometry.aabb))
        let grouped = Geometry.scale(padded, from: box, to: CGRect(x: box.minX, y: box.minY, width: box.width / 2, height: box.height / 2))
        XCTAssertEqual(rect(grouped, 0, 0).table?.pad, 15)
        let regrouped = DataGraphics.relaidTable(grouped, id: id, heightFor: typed)
        XCTAssertEqual(DataGraphics.tableRows(regrouped, id: id).map { rect(regrouped, $0, 0).h }, [41, 41, 41])
        // Nothing kept scales to nothing.
        XCTAssertNil(rect(table.map { $0.scaledSizes(by: 0.5) }, 0, 0).table?.pad)
    }

    // MARK: the file

    func testSpacingAndBandsAreWrittenOnlyWhenSetAndReadTolerantly() throws {
        var el = Element.shape("rect")
        el.table = TableCell(id: "tbl_abc", row: 1, col: 0, pad: 12.5, bands: "#dbeafe")
        let data = try JSONEncoder().encode(el)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cell = try XCTUnwrap(written["table"] as? [String: Any])
        XCTAssertEqual(Set(cell.keys), ["id", "row", "col", "pad", "bands"])
        XCTAssertEqual(cell["pad"] as? Double, 12.5)
        XCTAssertEqual(cell["bands"] as? String, "#dbeafe")
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data), el)

        func read(_ json: String) throws -> TableCell? {
            try JSONDecoder().decode(Element.self,
                                     from: Data(#"{"id":"e","type":"shape","table":\#(json)}"#.utf8)).table
        }
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 0, "col": 0, "pad": 8}"#),
                       TableCell(id: "tbl_x", row: 0, col: 0, pad: 8))
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 0, "col": 0, "pad": -2, "bands": "blue"}"#),
                       TableCell(id: "tbl_x", row: 0, col: 0))
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 0, "col": 0, "pad": "8", "bands": 3}"#),
                       TableCell(id: "tbl_x", row: 0, col: 0))
    }

    // MARK: the store

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "tables", width: 1000, height: 1000)
        design.pages[0].elements = elements
        let s = DesignStore(design: design)
        s.measure = heightFor
        return s
    }

    func testEachMoveIsOneStepAndAMergedCellSaysWhy() throws {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 1, 0).id]
        let picked = try XCTUnwrap(s.tableSelection)
        XCTAssertFalse(picked.canMoveRowUp, "the row under the header never crosses the top")
        XCTAssertTrue(picked.canMoveRowDown)
        XCTAssertFalse(picked.canMoveColumnLeft)
        XCTAssertTrue(picked.canMoveColumnRight)
        s.moveTableRow(by: 1)
        XCTAssertEqual(words(s.page.elements), ["Item", "Qty", "Bagel", "1", "Coffee", "2"])
        XCTAssertEqual(s.selection, [text(table, 1, 0).id], "the cell moved stays selected")
        XCTAssertEqual(s.tableSelection?.rows, [2])
        XCTAssertTrue(try XCTUnwrap(s.tableSelection).canMoveRowUp, "a body row moves up to the row under the header")
        s.moveTableColumn(by: 1)
        XCTAssertEqual(words(s.page.elements), ["Qty", "Item", "1", "Bagel", "2", "Coffee"])
        s.undo()
        s.undo()
        XCTAssertEqual(s.page.elements, table)

        // A body cell beside the merged one: its row would split the merge.
        // (The header cell is refused for the header's own reason first,
        // on both phones: see testTheHeaderRowStaysAtTheTop.)
        let tall = store(try merged(made(), [(1, 0), (2, 0)]))
        let before = tall.page.elements
        tall.selection = [text(before, 1, 1).id]
        tall.moveTableRow(by: 1)
        XCTAssertEqual(tall.page.elements, before)
        XCTAssertEqual(tall.announcement, "Unmerge first to move this row")
        XCTAssertFalse(tall.canUndo)
        tall.selection = [text(before, 0, 0).id]
        tall.moveTableRow(by: 1)
        XCTAssertEqual(tall.page.elements, before)
        XCTAssertEqual(tall.announcement, "The header row stays at the top")
        XCTAssertFalse(tall.canUndo)
    }

    func testSpacingAndAlternatingRowsAreEachOneStep() {
        let s = store(made())
        let table = s.page.elements
        s.selection = Set(table.map(\.id))
        XCTAssertEqual(s.tablePadding ?? 0, 13.2, accuracy: 1e-9)
        s.setTablePaddingTransient(16)
        s.setTablePaddingTransient(24)
        s.commit()
        XCTAssertEqual(s.tablePadding, 24)
        XCTAssertEqual(s.tableBands, DataGraphics.tableBand, "a new table is striped, so the switch reads On")
        s.setTableBands(true, colour: nil)
        XCTAssertEqual(s.tableBands, DataGraphics.tableBand)
        s.setTableBands(true, colour: "#fde68a")
        XCTAssertEqual(s.tableBands, "#fde68a")
        s.undo()
        s.undo()
        XCTAssertEqual(s.tablePadding, 24)
        s.undo()
        XCTAssertEqual(s.page.elements, table, "the slider's drag was one step")
    }

    func testTabTypesInTheNextCellAndAddsARowAfterTheLast() {
        let s = store(made())
        let table = s.page.elements
        s.startTyping(text(table, 1, 0).id)
        XCTAssertTrue(s.typeInNextCell(back: false))
        XCTAssertEqual(s.editingTextId, text(table, 1, 1).id)
        XCTAssertTrue(s.typeInNextCell(back: true))
        XCTAssertEqual(s.editingTextId, text(table, 1, 0).id)

        s.startTyping(text(table, 0, 0).id)
        XCTAssertFalse(s.typeInNextCell(back: true), "Shift-Tab in the first cell stays")
        XCTAssertEqual(s.editingTextId, text(table, 0, 0).id)
        XCTAssertEqual(s.haptic.kind, .reject, "and buzzes, as on Android")

        s.startTyping(text(table, 2, 1).id)
        XCTAssertTrue(s.typeInNextCell(back: false))
        XCTAssertEqual(s.page.elements.count, 16, "a row added")
        XCTAssertEqual(s.editingTextId, text(s.page.elements, 3, 0).id, "and typing in its first cell")
        s.endTextEdit()
        s.undo()
        XCTAssertEqual(s.page.elements, table, "the row was one step")
    }
}
