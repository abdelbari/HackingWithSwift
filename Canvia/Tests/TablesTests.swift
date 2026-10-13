// Tables you can edit: the `table` key on each cell and its text, laying a
// table out again, rows and columns added and taken out, the header turned
// off and on, cells recoloured, the table as text and set again from it —
// on the test table both phones share, number for number — and each edit one
// undo step.

import XCTest
@testable import Canvia

/// The test table both phones share: "Item, Qty / Tea, 2 / Cake, 1" in a
/// 400-wide frame at (100, 200), each line of words 20 tall. Type 22, so the
/// cells are inset 13.2; columns 229 and 171 wide at x 100 and 329; rows 46
/// tall at y 200, 246 and 292.
@MainActor
final class TablesTests: XCTestCase {

    private let lineHeight = 20.0
    private var heightFor: (Element) -> Double {
        let line = lineHeight
        return { el in Double((el.text ?? "").components(separatedBy: "\n").count) * line }
    }

    private func made() -> [Element] {
        DataGraphics.table(DataGraphics.parseTable("Item, Qty\nTea, 2\nCake, 1"),
                           in: CGRect(x: 100, y: 200, width: 400, height: 300), accent: "#1f2430",
                           heightFor: heightFor)
    }

    private func tableId(_ els: [Element]) -> String {
        els.lazy.compactMap { $0.table?.id }.first ?? ""
    }

    private func rect(_ els: [Element], _ row: Int, _ col: Int) -> Element {
        let found = els.filter { $0.type == .shape && $0.table?.row == row && $0.table?.col == col }
        XCTAssertEqual(found.count, 1, "one rectangle at \(row), \(col)")
        return found.first ?? Element.shape("rect")
    }

    private func text(_ els: [Element], _ row: Int, _ col: Int) -> Element {
        let found = els.filter { $0.type == .text && $0.table?.row == row && $0.table?.col == col }
        XCTAssertEqual(found.count, 1, "one text at \(row), \(col)")
        return found.first ?? Element.text("")
    }

    private func rowTops(_ els: [Element]) -> [Double] {
        DataGraphics.tableRows(els, id: tableId(els)).map { rect(els, $0, 0).y }
    }

    private func columnLefts(_ els: [Element]) -> [Double] {
        DataGraphics.tableColumns(els, id: tableId(els)).map { rect(els, 0, $0).x }
    }

    private func columnWidths(_ els: [Element]) -> [Double] {
        DataGraphics.tableColumns(els, id: tableId(els)).map { rect(els, 0, $0).w }
    }

    // MARK: the test table, as on the Android twin

    func testANewTablesCellsKnowTheirPlacesAndLayingItOutAgainChangesNothing() {
        let table = made()
        XCTAssertEqual(table.count, 12)
        XCTAssertTrue(table.allSatisfy { $0.table?.id == tableId(table) })
        XCTAssertTrue(tableId(table).hasPrefix("tbl_"))
        XCTAssertEqual(columnLefts(table), [100, 329])
        XCTAssertEqual(columnWidths(table), [229, 171])
        XCTAssertEqual(rowTops(table), [200, 246, 292])
        XCTAssertEqual(rect(table, 2, 1).h, 46)
        XCTAssertEqual(text(table, 0, 0).x, 113)
        XCTAssertEqual(text(table, 0, 1).x, 342)
        XCTAssertEqual(text(table, 1, 0).y, 259)
        XCTAssertEqual(text(table, 1, 0).w, 202.6, accuracy: 1e-9)
        XCTAssertEqual(DataGraphics.relayout(table, heightFor: heightFor), table)
    }

    func testACellsWordsGrowingGrowItsRowAndPushTheRowsBelowDown() {
        let table = made()
        let tea = text(table, 1, 0).id
        let grown = table.map { el -> Element in
            var out = el
            if el.id == tea { out.text = "Tea\nwith milk" }
            return out
        }
        let laid = DataGraphics.relayout(grown, heightFor: heightFor)
        XCTAssertEqual(rect(laid, 1, 0).h, 66)
        XCTAssertEqual(rect(laid, 1, 1).h, 66)
        XCTAssertEqual(text(laid, 1, 0).h, 40)
        XCTAssertEqual(rowTops(laid), [200, 246, 312])
        XCTAssertEqual(text(laid, 2, 0).y, 325)
        XCTAssertEqual(rect(table, 0, 0), rect(laid, 0, 0))
    }

    func testARowIsAddedAboveOrBelowACopyOfItsNeighbourWithNoWords() {
        let table = made()
        let below = DataGraphics.addingTableRow(table, id: tableId(table), row: 1, below: true, heightFor: heightFor)
        XCTAssertEqual(below.count, 16)
        XCTAssertEqual(rowTops(below), [200, 246, 292, 338])
        XCTAssertEqual(text(below, 2, 0).text, "")
        XCTAssertEqual(rect(table, 1, 0).fill, rect(below, 2, 0).fill)
        XCTAssertEqual(text(below, 2, 1).fontWeight, 400)
        XCTAssertEqual(text(below, 3, 0).text, "Cake")
        XCTAssertEqual(rect(table, 1, 0).group, rect(below, 2, 0).group)
        XCTAssertEqual(Set(below.map(\.id)).count, 16, "the new row has ids of its own")
        // In the table's layer, under what was above it.
        let above0 = Element.text("Over the table")
        let layered = DataGraphics.addingTableRow(table + [above0], id: tableId(table), row: 1, below: true,
                                                  heightFor: heightFor)
        XCTAssertEqual(layered.last, above0)

        let above = DataGraphics.addingTableRow(table, id: tableId(table), row: 0, below: false, heightFor: heightFor)
        XCTAssertEqual(rowTops(above), [200, 246, 292, 338])
        XCTAssertEqual(rect(above, 0, 1).fill?.color, "#1f2430")
        XCTAssertEqual(text(above, 0, 0).text, "")
        XCTAssertEqual(text(above, 1, 0).text, "Item")
    }

    func testAColumnIsAddedAtTheAverageWidthTheTableAsWideAsItWas() {
        let table = made()
        let right = DataGraphics.addingTableColumn(table, id: tableId(table), col: 0, right: true, heightFor: heightFor)
        XCTAssertEqual(right.count, 18)
        XCTAssertEqual(columnWidths(right), [153, 133, 114])
        XCTAssertEqual(columnLefts(right), [100, 253, 386])
        XCTAssertEqual(columnWidths(right).reduce(0, +), 400)
        XCTAssertEqual(text(right, 0, 1).text, "")
        XCTAssertEqual(text(right, 0, 1).fontWeight, 700)
        XCTAssertEqual(text(right, 0, 2).text, "Qty")
        XCTAssertEqual(text(right, 1, 1).w, 106.6, accuracy: 1e-9)
        XCTAssertEqual(text(right, 1, 1).x, 266)

        let left = DataGraphics.addingTableColumn(table, id: tableId(table), col: 0, right: false, heightFor: heightFor)
        XCTAssertEqual(columnWidths(left), [133, 153, 114])
        XCTAssertEqual(columnLefts(left), [100, 233, 386])
        XCTAssertEqual(text(left, 0, 1).text, "Item")
    }

    func testARowOrAColumnIsDeletedButNeverTheLastOne() throws {
        let table = made()
        let noHeader = try XCTUnwrap(DataGraphics.deletingTableRow(table, id: tableId(table), row: 0, heightFor: heightFor))
        XCTAssertEqual(rowTops(noHeader), [200, 246])
        XCTAssertEqual(text(noHeader, 0, 0).text, "Tea")
        XCTAssertEqual(text(noHeader, 0, 0).y, 213)

        let narrower = try XCTUnwrap(DataGraphics.deletingTableColumn(table, id: tableId(table), col: 0,
                                                                      heightFor: heightFor))
        XCTAssertEqual(columnLefts(narrower), [100])
        XCTAssertEqual(columnWidths(narrower), [171])
        XCTAssertEqual(text(narrower, 0, 0).text, "Qty")
        XCTAssertEqual(text(narrower, 0, 0).x, 113)

        var one = narrower
        one = try XCTUnwrap(DataGraphics.deletingTableRow(one, id: tableId(one), row: 2, heightFor: heightFor))
        one = try XCTUnwrap(DataGraphics.deletingTableRow(one, id: tableId(one), row: 1, heightFor: heightFor))
        XCTAssertEqual(one.count, 2)
        XCTAssertNil(DataGraphics.deletingTableRow(one, id: tableId(one), row: 0, heightFor: heightFor))
        XCTAssertNil(DataGraphics.deletingTableColumn(one, id: tableId(one), col: 0, heightFor: heightFor))
    }

    func testTheHeaderRowTurnsOffAndOn() {
        let table = made()
        XCTAssertTrue(DataGraphics.tableHasHeader(table, id: tableId(table)))
        let off = DataGraphics.withTableHeader(table, id: tableId(table), on: false, accent: "#1f2430", heightFor: heightFor)
        XCTAssertFalse(DataGraphics.tableHasHeader(off, id: tableId(off)))
        XCTAssertEqual(rect(off, 0, 0).fill?.color, "#f3f4f6")
        XCTAssertEqual(text(off, 0, 1).fontWeight, 400)
        XCTAssertEqual(text(off, 0, 1).color, "#1f2430")
        let on = DataGraphics.withTableHeader(off, id: tableId(off), on: true, accent: "#ffd166", heightFor: heightFor)
        XCTAssertTrue(DataGraphics.tableHasHeader(on, id: tableId(on)))
        XCTAssertEqual(rect(on, 0, 1).fill?.color, "#ffd166")
        XCTAssertEqual(text(on, 0, 0).fontWeight, 700)
        XCTAssertEqual(text(on, 0, 0).color, "#16181d")
        // The body is untouched.
        XCTAssertEqual(rect(table, 1, 0), rect(on, 1, 0))
    }

    func testACellsColourFillsItsRectangleOnly() {
        let table = made()
        let coloured = DataGraphics.colouringTableCells(table, id: tableId(table),
                                                        cells: [TableCell(id: tableId(table), row: 1, col: 1)],
                                                        color: "#ff0000")
        XCTAssertEqual(rect(coloured, 1, 1).fill?.color, "#ff0000")
        XCTAssertEqual(text(table, 1, 1), text(coloured, 1, 1))
        XCTAssertEqual(rect(table, 1, 0), rect(coloured, 1, 0))
    }

    func testEditedAsTextTheTableKeepsItsColumnWidthsAndItsUntouchedCells() throws {
        let table = made()
        XCTAssertEqual(DataGraphics.tableText(table, id: tableId(table)), "Item, Qty\nTea, 2\nCake, 1")
        let rebuilt = try XCTUnwrap(DataGraphics.rebuiltTable(
            table, id: tableId(table), rows: DataGraphics.parseTable("Item, Qty, Price\nTea, 2, 3.50"), heightFor: heightFor))
        XCTAssertEqual(rebuilt.count, 12)
        XCTAssertEqual(columnWidths(rebuilt), [229, 171, 200])
        XCTAssertEqual(columnLefts(rebuilt), [100, 329, 500])
        XCTAssertEqual(text(rebuilt, 1, 2).text, "3.50")
        XCTAssertEqual(text(table, 1, 0), text(rebuilt, 1, 0))
        XCTAssertEqual(rowTops(rebuilt), [200, 246])

        let longer = try XCTUnwrap(DataGraphics.rebuiltTable(
            table, id: tableId(table), rows: DataGraphics.parseTable("A, B\nC, D\nE, F\nG, H\nI, J"), heightFor: heightFor))
        XCTAssertEqual(DataGraphics.tableRows(longer, id: tableId(longer)).map { text(longer, $0, 0).text },
                       ["A", "C", "E", "G", "I"])
        // New rows keep the bands.
        XCTAssertEqual(rect(longer, 2, 0).fill, rect(longer, 4, 0).fill)
        XCTAssertEqual(rect(longer, 1, 0).fill, rect(longer, 3, 0).fill)
        XCTAssertNil(DataGraphics.rebuiltTable(table, id: tableId(table), rows: [], heightFor: heightFor))

        // A cell with a comma in it is set off by tabs.
        let tea = text(table, 1, 0).id
        let comma = table.map { el -> Element in
            var out = el
            if el.id == tea { out.text = "Tea, green" }
            return out
        }
        XCTAssertEqual(DataGraphics.tableText(comma, id: tableId(comma)), "Item, Qty\nTea, green\t2\nCake, 1")
    }

    // MARK: the file

    func testACellIsReadAsTheAndroidTwinWritesItAndGoesOutTheSame() throws {
        var el = Element.shape("rect")
        el.table = TableCell(id: "tbl_abc", row: 2, col: 1)
        let data = try JSONEncoder().encode(el)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cell = try XCTUnwrap(written["table"] as? [String: Any])
        XCTAssertEqual(Set(cell.keys), ["id", "row", "col"])
        XCTAssertEqual(cell["id"] as? String, "tbl_abc")
        XCTAssertEqual(cell["row"] as? Int, 2)
        XCTAssertEqual(cell["col"] as? Int, 1)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data), el)
        // A plain element has no key at all.
        let plain = try JSONEncoder().encode(Element.shape("rect"))
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])["table"])

        func read(_ json: String) throws -> TableCell? {
            try JSONDecoder().decode(Element.self,
                                     from: Data(#"{"id":"e","type":"shape","table":\#(json)}"#.utf8)).table
        }
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 1.0, "col": 0}"#), TableCell(id: "tbl_x", row: 1, col: 0))
        XCTAssertNil(try read(#"{"row": 1, "col": 0}"#))
        XCTAssertNil(try read(#"{"id": "tbl_x", "row": "1", "col": 0}"#))
        XCTAssertNil(try read(#"{"id": "tbl_x", "row": -1, "col": 0}"#))
        XCTAssertNil(try read(#""tbl_x""#))
        // An unreadable place leaves the element itself as it was.
        let kept = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e","type":"text","text":"A","table":{"id":"tbl_a","row":"one","col":0}}"#.utf8))
        XCTAssertEqual(kept.text, "A")
        XCTAssertNil(kept.table)
    }

    func testACopyOfATableIsATableOfItsOwn() {
        let table = made()
        let copy = Copies.of(table, offset: 24)
        XCTAssertNotEqual(tableId(table), tableId(copy))
        XCTAssertTrue(copy.allSatisfy { $0.table?.id == tableId(copy) })
        XCTAssertEqual(copy[5].table, table[5].table.map { TableCell(id: tableId(copy), row: $0.row, col: $0.col) })
    }

    // MARK: the store

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "tables", width: 1000, height: 1000)
        design.pages[0].elements = elements
        let s = DesignStore(design: design)
        s.measure = heightFor
        return s
    }

    func testTypingInACellRegrowsItsRowInTheSameStep() {
        let s = store(made())
        let table = s.page.elements
        let cell = text(table, 1, 0)
        s.selection = [cell.id]
        s.updateSelectedTransient { $0.text = "Tea\nwith milk" }
        s.commit()
        XCTAssertEqual(rect(s.page.elements, 1, 1).h, 66)
        XCTAssertEqual(rect(s.page.elements, 2, 0).y, 312)
        s.undo()
        XCTAssertEqual(s.page.elements, table)
        XCTAssertFalse(s.canUndo)

        // Moving a cell is not typing in it: the table is left as it is.
        s.updateSelected { $0.x += 50 }
        XCTAssertEqual(text(s.page.elements, 1, 0).x, cell.x + 50)
    }

    func testTypingInPlaceInACellIsOneStepAndAnEmptiedCellStays() {
        let s = store(made())
        let table = s.page.elements
        let tea = text(table, 1, 0)
        s.startTyping(tea.id)
        s.typeWords("Tea\nwith milk", into: tea.id)
        s.endTextEdit()
        XCTAssertEqual(rowTops(s.page.elements), [200, 246, 312])
        s.undo()
        XCTAssertEqual(s.page.elements, table, "one Undo takes back the words and the rows")

        let qty = text(table, 1, 1)
        s.startTyping(qty.id)
        s.typeWords("", into: qty.id)
        s.endTextEdit()
        XCTAssertEqual(s.element(qty.id)?.text, "", "a cell's words can be none")
        XCTAssertEqual(s.page.elements.count, 12)
    }

    func testEachTableChangeIsOneStepAndTheWholeTableStaysSelected() {
        let s = store(made())
        let table = s.page.elements
        s.selection = Set(table.map(\.id))
        let whole = s.tableSelection
        XCTAssertEqual(whole?.rows, [0, 1, 2])
        XCTAssertEqual(whole?.whole, true)
        XCTAssertEqual(whole?.canDeleteRow, false)
        XCTAssertEqual(whole?.deleteNote, "Select one cell to delete its row or column.")
        s.addTableRow(below: true)
        XCTAssertEqual(s.page.elements.count, 16)
        XCTAssertEqual(rowTops(s.page.elements), [200, 246, 292, 338])
        XCTAssertEqual(text(s.page.elements, 3, 0).text, "", "below the bottom row")
        XCTAssertEqual(s.selection, Set(s.page.elements.map(\.id)))
        s.addTableColumn(right: true)
        XCTAssertEqual(s.page.elements.count, 24)
        XCTAssertEqual(s.tableSelection?.rowCount, 4)
        XCTAssertEqual(s.tableSelection?.columnCount, 3)
        s.undo()
        XCTAssertEqual(s.page.elements.count, 16)
        s.undo()
        XCTAssertEqual(s.page.elements, table)
    }

    func testDeletingTheSelectedCellsRowSelectsTheCellNowInItsPlace() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 2, 1).id]
        XCTAssertEqual(s.tableSelection?.canDeleteRow, true)
        XCTAssertNil(s.tableSelection?.deleteNote)
        s.deleteTableRow()
        XCTAssertEqual(rowTops(s.page.elements), [200, 246])
        XCTAssertEqual(s.selection, [text(s.page.elements, 1, 1).id])
        s.deleteTableColumn()
        XCTAssertEqual(columnWidths(s.page.elements), [229])
        XCTAssertEqual(s.selection, [text(s.page.elements, 1, 0).id])
        XCTAssertEqual(s.tableSelection?.deleteNote, "A table keeps at least one column.")
        s.deleteTableColumn()
        XCTAssertEqual(s.page.elements.count, 4, "the last column stays")
    }

    func testCellColourAndHeaderEachAStep() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [rect(table, 1, 1).id, text(table, 2, 1).id]
        XCTAssertNil(s.tableCellColour, "two cells of different bands")
        XCTAssertTrue(s.setTableCellColour("#ff0000"))
        XCTAssertEqual(rect(s.page.elements, 1, 1).fill?.color, "#ff0000")
        XCTAssertEqual(rect(s.page.elements, 2, 1).fill?.color, "#ff0000")
        XCTAssertEqual(s.tableCellColour, "#ff0000")
        XCTAssertFalse(s.setTableCellColour("#ff0000"), "nothing to change")
        s.undo()
        XCTAssertEqual(s.page.elements, table)

        XCTAssertEqual(s.tableSelection?.header, true)
        s.setTableHeader(false)
        XCTAssertEqual(s.tableSelection?.header, false)
        s.undo()
        XCTAssertEqual(s.page.elements, table)
    }

    func testEditAsTextSetsTheTableAgainAsOneStep() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 0, 0).id]
        XCTAssertEqual(s.tableText, "Item, Qty\nTea, 2\nCake, 1")
        XCTAssertFalse(s.rebuildTable(from: "  \n"))
        XCTAssertTrue(s.rebuildTable(from: "Item, Qty, Price\nTea, 2, 3.50"))
        XCTAssertEqual(columnWidths(s.page.elements), [229, 171, 200])
        s.undo()
        XCTAssertEqual(s.page.elements, table)
    }

    func testATurnedTableIsLeftAsItIs() {
        var turned = made()
        for i in turned.indices { turned[i].rotation = 10 }
        let s = store(turned)
        s.selection = [text(turned, 1, 0).id]
        XCTAssertEqual(s.tableSelection?.turned, true)
        s.addTableRow(below: true)
        XCTAssertEqual(s.page.elements, turned)
        XCTAssertFalse(s.canUndo)
        XCTAssertEqual(DataGraphics.relayout(turned, heightFor: heightFor), turned)
    }

    func testADoubleTapOnACellsRectangleTypesInItsWords() {
        let s = store(made())
        let table = s.page.elements
        XCTAssertEqual(s.typedIn(rect(table, 1, 0))?.id, text(table, 1, 0).id)
        XCTAssertEqual(s.typedIn(text(table, 1, 0))?.id, text(table, 1, 0).id)
        let plain = Element.shape("rect")
        XCTAssertEqual(s.typedIn(plain)?.id, plain.id, "a plain shape takes its own words")
    }
}
