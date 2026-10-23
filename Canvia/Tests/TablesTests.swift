// Tables you can edit: the `table` key on each cell and its text, laying a
// table out again, rows and columns added and taken out, the header turned
// off and on, cells recoloured, the table as text and set again from it —
// on the test table both phones share, number for number — and each edit one
// undo step.

import XCTest
@testable import Canvia

/// The test table both phones share, number for number: "Item, Qty /
/// Coffee, 2 / Bagel, 1" in a 400-wide frame at (100, 200), each line of
/// words 20 tall. Type 22, so the cells are inset 13.2; columns 267 and 133
/// wide at x 100 and 367; rows 46 tall at y 200, 246 and 292.
@MainActor
final class TablesTests: XCTestCase {

    private let lineHeight = 20.0
    private var heightFor: (Element) -> Double {
        let line = lineHeight
        return { el in Double((el.text ?? "").components(separatedBy: "\n").count) * line }
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

    /// The cells' words, row by row.
    private func words(_ els: [Element]) -> [String] {
        els.filter { $0.type == .text }
            .sorted { a, b in (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0) }
            .map { $0.text ?? "" }
    }

    /// `els` with cell (`row`, `col`)'s words set to `words`.
    private func withWords(_ els: [Element], _ row: Int, _ col: Int, _ words: String) -> [Element] {
        let cell = text(els, row, col).id
        return els.map { el -> Element in
            var out = el
            if el.id == cell { out.text = words }
            return out
        }
    }

    // MARK: the test table, as on the Android twin

    func testANewTablesCellsKnowTheirPlacesAndLayingItOutAgainChangesNothing() {
        let table = made()
        XCTAssertEqual(table.count, 12)
        XCTAssertTrue(table.allSatisfy { $0.table?.id == tableId(table) })
        XCTAssertTrue(tableId(table).hasPrefix("tbl_"))
        XCTAssertEqual(columnLefts(table), [100, 367])
        XCTAssertEqual(columnWidths(table), [267, 133])
        XCTAssertEqual(rowTops(table), [200, 246, 292])
        XCTAssertEqual(rect(table, 2, 1).h, 46)
        XCTAssertEqual(text(table, 0, 0).x, 113)
        XCTAssertEqual(text(table, 0, 1).x, 380)
        XCTAssertEqual(text(table, 1, 0).y, 259)
        XCTAssertEqual(text(table, 1, 0).w, 240.6, accuracy: 1e-9)
        XCTAssertEqual(DataGraphics.relayout(table, heightFor: heightFor), table)
    }

    func testACellsWordsGrowingGrowItsRowAndPushTheRowsBelowDown() {
        let table = made()
        let laid = DataGraphics.relayout(withWords(table, 1, 0, "Coffee\nwith milk"), heightFor: heightFor)
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
        XCTAssertEqual(words(below), ["Item", "Qty", "Coffee", "2", "", "", "Bagel", "1"])
        XCTAssertEqual(rect(table, 1, 0).fill, rect(below, 2, 0).fill)
        XCTAssertEqual(text(below, 2, 1).fontWeight, 400)
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
        XCTAssertEqual(text(above, 0, 0).fontWeight, 700)
        XCTAssertEqual(words(above), ["", "", "Item", "Qty", "Coffee", "2", "Bagel", "1"])
    }

    func testAColumnIsAddedAtTheAverageWidthTheTableAsWideAsItWas() {
        let table = made()
        // The new column is the 200 the two averaged; 267 and 133 halve to
        // make room, 133.5 rounding to 134, and the last column takes the
        // 66 left of the 400.
        let right = DataGraphics.addingTableColumn(table, id: tableId(table), col: 0, right: true, heightFor: heightFor)
        XCTAssertEqual(right.count, 18)
        XCTAssertEqual(columnWidths(right), [134, 200, 66])
        XCTAssertEqual(columnLefts(right), [100, 234, 434])
        XCTAssertEqual(text(right, 0, 1).text, "")
        XCTAssertEqual(text(right, 0, 1).fontWeight, 700)
        XCTAssertEqual(text(right, 0, 2).text, "Qty")
        XCTAssertEqual(text(right, 1, 1).w, 173.6, accuracy: 1e-9)
        XCTAssertEqual(text(right, 1, 1).x, 247)
        XCTAssertEqual(words(right), ["Item", "", "Qty", "Coffee", "", "2", "Bagel", "", "1"])

        let left = DataGraphics.addingTableColumn(table, id: tableId(table), col: 0, right: false, heightFor: heightFor)
        XCTAssertEqual(columnWidths(left), [200, 134, 66])
        XCTAssertEqual(columnLefts(left), [100, 300, 434])
        XCTAssertEqual(text(left, 0, 1).text, "Item")
    }

    func testANamedCellsNewNeighboursHaveNoNameOfTheirOwn() {
        let table = made()
        let named = text(table, 1, 0).id
        let total = table.map { el -> Element in
            var out = el
            if el.id == named { out.layerName = "Total" }
            return out
        }
        let row = DataGraphics.addingTableRow(total, id: tableId(total), row: 1, below: true, heightFor: heightFor)
        XCTAssertEqual(text(row, 1, 0).layerName, "Total")
        XCTAssertNil(text(row, 2, 0).layerName)
        XCTAssertEqual(row.compactMap(\.layerName), ["Total"])
        let column = DataGraphics.addingTableColumn(total, id: tableId(total), col: 0, right: true,
                                                    heightFor: heightFor)
        XCTAssertEqual(text(column, 1, 0).layerName, "Total")
        XCTAssertNil(text(column, 1, 1).layerName)
        XCTAssertEqual(column.compactMap(\.layerName), ["Total"])
    }

    func testARowOrAColumnIsDeletedButNeverTheLastOne() throws {
        let table = made()
        let noHeader = try XCTUnwrap(DataGraphics.deletingTableRow(table, id: tableId(table), row: 0, heightFor: heightFor))
        XCTAssertEqual(rowTops(noHeader), [200, 246])
        XCTAssertEqual(words(noHeader), ["Coffee", "2", "Bagel", "1"])
        XCTAssertEqual(text(noHeader, 0, 0).y, 213)
        let middle = try XCTUnwrap(DataGraphics.deletingTableRow(table, id: tableId(table), row: 1, heightFor: heightFor))
        XCTAssertEqual(words(middle), ["Item", "Qty", "Bagel", "1"])
        XCTAssertEqual(rowTops(middle), [200, 246])

        // The columns left widen in proportion, so the table keeps its width.
        let wide = try XCTUnwrap(DataGraphics.deletingTableColumn(table, id: tableId(table), col: 0,
                                                                  heightFor: heightFor))
        XCTAssertEqual(columnLefts(wide), [100])
        XCTAssertEqual(columnWidths(wide), [400])
        XCTAssertEqual(text(wide, 0, 0).text, "Qty")
        XCTAssertEqual(text(wide, 0, 0).x, 113)
        XCTAssertEqual(text(wide, 0, 0).w, 373.6, accuracy: 1e-9)
        let three = DataGraphics.addingTableColumn(table, id: tableId(table), col: 0, right: true, heightFor: heightFor)
        // 134 and 66 doubled, 268 and the 132 left.
        let two = try XCTUnwrap(DataGraphics.deletingTableColumn(three, id: tableId(three), col: 1, heightFor: heightFor))
        XCTAssertEqual(columnWidths(two), [268, 132])
        XCTAssertEqual(columnLefts(two), [100, 368])

        var one = wide
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
        XCTAssertEqual([rect(off, 0, 0), rect(off, 0, 1)].map { $0.fill?.color }, ["#f3f4f6", "#f3f4f6"])
        XCTAssertEqual([text(off, 0, 0), text(off, 0, 1)].map(\.fontWeight), [400, 400])
        XCTAssertEqual([text(off, 0, 0), text(off, 0, 1)].map(\.color), ["#1f2430", "#1f2430"])
        let on = DataGraphics.withTableHeader(off, id: tableId(off), on: true, accent: "#ffd166", heightFor: heightFor)
        XCTAssertTrue(DataGraphics.tableHasHeader(on, id: tableId(on)))
        XCTAssertEqual(rect(on, 0, 1).fill?.color, "#ffd166")
        XCTAssertEqual(text(on, 0, 0).fontWeight, 700)
        // A light accent takes dark ink, a dark one light.
        XCTAssertEqual(text(on, 0, 0).color, "#16181d")
        XCTAssertEqual(text(DataGraphics.withTableHeader(off, id: tableId(off), on: true, accent: "#123456",
                                                         heightFor: heightFor), 0, 0).color, "#ffffff")
        // The body is untouched.
        XCTAssertEqual(table.filter { $0.table?.row != 0 }, on.filter { $0.table?.row != 0 })
    }

    func testTheHeaderOffTakesTheAlternatingRowsColourOrWhite() {
        // Row 0 is filled as row 0 of the body is banded: the colour kept,
        // the default band while the body is striped as made, white with
        // the rows off. The other rows are left as they are.
        let table = made()
        let id = tableId(table)
        let pink = DataGraphics.withTableHeader(DataGraphics.withTableBands(table, id: id, on: true, colour: "#ffd6e0"),
                                                id: id, on: false, accent: "#1f2430", heightFor: heightFor)
        XCTAssertEqual(DataGraphics.tableRows(pink, id: id).map { rect(pink, $0, 0).fill?.color }, ["#ffd6e0", "#ffffff", "#ffd6e0"])
        let white = DataGraphics.withTableHeader(DataGraphics.withTableBands(table, id: id, on: false, colour: "#ffd6e0"),
                                                 id: id, on: false, accent: "#1f2430", heightFor: heightFor)
        XCTAssertEqual(DataGraphics.tableRows(white, id: id).map { rect(white, $0, 0).fill?.color }, ["#ffffff", "#ffffff", "#ffffff"])
        let own = DataGraphics.colouringTableCells(table, id: id, cells: Set([rect(table, 2, 1).table].compactMap { $0 }), color: "#ef4444")
        let kept = DataGraphics.withTableHeader(own, id: id, on: false, accent: "#1f2430", heightFor: heightFor)
        XCTAssertEqual(rect(kept, 0, 0).fill?.color, "#ffffff")
        XCTAssertEqual(rect(kept, 2, 1).fill?.color, "#ef4444")
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

    // MARK: merged cells, as on the Android twin

    /// Table `els`'s cells at `places` (row, column), as a selection holds them.
    private func cells(_ els: [Element], _ places: [(Int, Int)]) -> Set<TableCell> {
        Set(places.map { TableCell(id: tableId(els), row: $0.0, col: $0.1) })
    }

    private func merging(_ els: [Element], _ places: [(Int, Int)]) -> [Element]? {
        DataGraphics.mergingTableCells(els, id: tableId(els), cells: cells(els, places), heightFor: heightFor)
    }

    private func box(_ el: Element) -> [Double] { [el.x, el.y, el.w, el.h] }

    func testCellsSideBySideMergeIntoTheTopLeftOneTheirWordsJoinedByLineBreaks() throws {
        let table = made()
        let id = tableId(table)
        let merged = try XCTUnwrap(merging(table, [(1, 0), (1, 1)]))
        XCTAssertEqual(merged.count, 10)
        XCTAssertEqual(rect(merged, 1, 0).table, TableCell(id: id, row: 1, col: 0, colSpan: 2))
        XCTAssertEqual(text(merged, 1, 0).table, TableCell(id: id, row: 1, col: 0, colSpan: 2))
        XCTAssertEqual(text(merged, 1, 0).text, "Coffee\n2")
        // As wide as both columns, as tall as its two lines.
        XCTAssertEqual(box(rect(merged, 1, 0)), [100, 246, 400, 66])
        XCTAssertEqual(text(merged, 1, 0).x, 113)
        XCTAssertEqual(text(merged, 1, 0).y, 259)
        XCTAssertEqual(text(merged, 1, 0).w, 373.6, accuracy: 1e-9)
        XCTAssertEqual(text(merged, 1, 0).h, 40)
        XCTAssertEqual(rowTops(merged), [200, 246, 312])
        // The columns keep their widths, read from the cells one column wide.
        XCTAssertEqual(columnWidths(merged), [267, 133])
        XCTAssertEqual(DataGraphics.tableColumns(merged, id: id), [0, 1])
        XCTAssertEqual(DataGraphics.relayout(merged, heightFor: heightFor), merged)
        // What the grid shows: a place merged into another blank, and covered.
        XCTAssertEqual(DataGraphics.tableGrid(merged, id: id), [["Item", "Qty"], ["Coffee 2", ""], ["Bagel", "1"]])
        XCTAssertEqual(DataGraphics.tableCovered(merged, id: id), [[1, 1]])
        XCTAssertEqual(DataGraphics.tableText(merged, id: id), "Item, Qty\nCoffee 2, \nBagel, 1")
    }

    func testWordsTheGridPutsAtAPlaceAMergedCellCoversJoinTheMergedCells() throws {
        let table = made()
        let side = try XCTUnwrap(merging(table, [(1, 0), (1, 1)]))
        let id = tableId(side)
        // Pasted across the merged cell: the word on its covered place is
        // added to its own, not lost.
        let pasted = DataGrid.pasting("x\ty", into: DataGraphics.tableGrid(side, id: id), row: 1, col: 0)
        XCTAssertEqual(pasted, [["Item", "Qty"], ["x", "y"], ["Bagel", "1"]])
        let joined = try XCTUnwrap(DataGraphics.rebuiltTable(side, id: id, rows: pasted, heightFor: heightFor))
        XCTAssertEqual(joined.count, 10)
        XCTAssertEqual(words(joined), ["Item", "Qty", "x\ny", "Bagel", "1"])
        XCTAssertEqual(DataGraphics.tableCovered(joined, id: id), [[1, 1]])
        // Its own place blank: the covered place's words alone.
        let only = try XCTUnwrap(DataGraphics.rebuiltTable(
            side, id: id, rows: [["Item", "Qty"], ["", "y"], ["Bagel", "1"]], heightFor: heightFor))
        XCTAssertEqual(text(only, 1, 0).text, "y")
        // The grid as it was read: the merged cell is left as it is.
        let same = try XCTUnwrap(DataGraphics.rebuiltTable(
            side, id: id, rows: DataGraphics.tableGrid(side, id: id), heightFor: heightFor))
        XCTAssertEqual(text(same, 1, 0), text(side, 1, 0))
        // A cell merged down: words below its own join after them.
        let down = try XCTUnwrap(merging(table, [(1, 0), (2, 0)]))
        let below = try XCTUnwrap(DataGraphics.rebuiltTable(
            down, id: tableId(down), rows: [["Item", "Qty"], ["Coffee Bagel", "2"], ["c3", "1"]], heightFor: heightFor))
        XCTAssertEqual(words(below), ["Item", "Qty", "Coffee Bagel\nc3", "2", "1"])
    }

    func testCellsOneAboveAnotherMergeAsTallAsTheirRowsTogether() throws {
        let table = made()
        let id = tableId(table)
        let merged = try XCTUnwrap(merging(table, [(1, 0), (2, 0)]))
        XCTAssertEqual(merged.count, 10)
        XCTAssertEqual(rect(merged, 1, 0).table, TableCell(id: id, row: 1, col: 0, rowSpan: 2))
        XCTAssertEqual(text(merged, 1, 0).text, "Coffee\nBagel")
        // Its two lines need 66 of the 92 its rows already have.
        XCTAssertEqual(box(rect(merged, 1, 0)), [100, 246, 267, 92])
        XCTAssertEqual(text(merged, 1, 0).y, 259)
        XCTAssertEqual([rect(merged, 1, 1).y, rect(merged, 2, 1).y], [246, 292])
        XCTAssertEqual(DataGraphics.tableRows(merged, id: id), [0, 1, 2])
        // A merged text taller than its rows grows the last of them.
        let tall = DataGraphics.relayout(withWords(merged, 1, 0, "a\nb\nc\nd\ne"), heightFor: heightFor)
        XCTAssertEqual([rect(tall, 1, 1).h, rect(tall, 2, 1).h], [46, 80])
        XCTAssertEqual(rect(tall, 1, 0).h, 126)
    }

    func testOnlyTwoOrMoreCellsFormingARectangleMerge() throws {
        let table = made()
        let id = tableId(table)
        func block(_ els: [Element], _ places: [(Int, Int)]) -> [Int]? {
            DataGraphics.mergeBlock(els, id: id, cells: cells(els, places)).map {
                [$0.rows.lowerBound, $0.cols.lowerBound, $0.rows.count, $0.cols.count]
            }
        }
        XCTAssertNil(merging(table, [(1, 0)]))
        XCTAssertNil(merging(table, [(0, 0), (1, 1)]))
        XCTAssertNil(merging(table, [(0, 0), (2, 0)]))
        XCTAssertNil(block(table, [(0, 0), (0, 1), (1, 0)]), "an L")
        XCTAssertEqual(block(table, [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]), [0, 0, 3, 2])
        // A merged cell counts as the places it covers.
        let down = try XCTUnwrap(merging(table, [(1, 0), (2, 0)]))
        XCTAssertEqual(block(down, [(0, 0), (1, 0)]), [0, 0, 3, 1])
        XCTAssertNil(block(down, [(0, 0), (0, 1), (1, 1)]))
        // Only the top-left cell has words: they are kept as they were.
        let one = try XCTUnwrap(merging(withWords(table, 1, 1, ""), [(1, 0), (1, 1)]))
        XCTAssertEqual(text(one, 1, 0).text, "Coffee")
        // The whole table: its rows, none with a cell of its own, keep their
        // heights, and its columns share its width.
        let all = try XCTUnwrap(merging(withWords(table, 1, 1, ""), [(0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)]))
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(text(all, 0, 0).text, "Item\nQty\nCoffee\nBagel\n1")
        XCTAssertEqual(box(rect(all, 0, 0)), [100, 200, 400, 138])
        XCTAssertEqual(DataGraphics.tableColumnWidths(all, id: id), [200, 200])
    }

    func testUnmergeGivesBackBlankCellsAndTheColumnsAsTheyWere() throws {
        let table = made()
        let id = tableId(table)
        let merged = try XCTUnwrap(merging(table, [(1, 0), (1, 1)]))
        XCTAssertNil(DataGraphics.unmergingTableCells(table, id: id, cells: cells(table, [(1, 0)]), heightFor: heightFor))
        let back = try XCTUnwrap(DataGraphics.unmergingTableCells(merged, id: id, cells: cells(merged, [(1, 0)]),
                                                                  heightFor: heightFor))
        XCTAssertEqual(back.count, 12)
        XCTAssertEqual(rect(back, 1, 0).table, TableCell(id: id, row: 1, col: 0))
        XCTAssertEqual(words(back), ["Item", "Qty", "Coffee\n2", "", "Bagel", "1"])
        XCTAssertEqual(columnWidths(back), [267, 133])
        XCTAssertEqual([rect(back, 1, 0).x, rect(back, 1, 1).x], [100, 367])
        XCTAssertEqual([rect(back, 1, 0).h, rect(back, 1, 1).h], [66, 66])
        XCTAssertEqual(rect(back, 1, 1).fill, rect(table, 1, 0).fill)
        XCTAssertEqual(Set(back.map(\.id)).count, 12)
        // A merged header, the columns' top row: each part goes back to its
        // own column, as the rows below have them.
        let header = try XCTUnwrap(merging(table, [(0, 0), (0, 1)]))
        let parted = try XCTUnwrap(DataGraphics.unmergingTableCells(header, id: id, cells: cells(header, [(0, 0)]),
                                                                    heightFor: heightFor))
        XCTAssertEqual(words(parted), ["Item\nQty", "", "Coffee", "2", "Bagel", "1"])
        XCTAssertEqual(columnWidths(parted), [267, 133])
        XCTAssertEqual(columnLefts(parted), [100, 367])
        XCTAssertEqual([rect(parted, 0, 0).h, rect(parted, 0, 1).h], [66, 66])
        XCTAssertEqual(rowTops(parted), [200, 266, 312])
    }

    func testARowOrAColumnAddedOrDeletedThroughAMergedCellGrowsOrShrinksIt() throws {
        let table = made()
        let id = tableId(table)
        let down = try XCTUnwrap(merging(table, [(1, 0), (2, 0)]))
        // A row added inside it: the merged cell grows a row, and the new
        // row has a cell only beside it.
        let grown = DataGraphics.addingTableRow(down, id: id, row: 1, below: true, heightFor: heightFor)
        XCTAssertEqual(grown.count, 12)
        XCTAssertEqual(rect(grown, 1, 0).table, TableCell(id: id, row: 1, col: 0, rowSpan: 3))
        XCTAssertEqual(words(grown), ["Item", "Qty", "Coffee\nBagel", "2", "", "1"])
        XCTAssertEqual(DataGraphics.tableRows(grown, id: id), [0, 1, 2, 3])
        XCTAssertEqual((0...3).map { rect(grown, $0, 1).y }, [200, 246, 292, 338])
        XCTAssertEqual(rect(grown, 1, 0).h, 138)
        // A row added below it: a cell under each column, the one under it
        // a copy of it.
        let below = DataGraphics.addingTableRow(down, id: id, row: 2, below: true, heightFor: heightFor)
        XCTAssertEqual(below.count, 14)
        XCTAssertEqual(rect(below, 1, 0).table, TableCell(id: id, row: 1, col: 0, rowSpan: 2))
        XCTAssertEqual(rect(below, 3, 0).table, TableCell(id: id, row: 3, col: 0))
        // Its first row deleted: it is a row shorter and keeps its words.
        let shrunk = try XCTUnwrap(DataGraphics.deletingTableRow(down, id: id, row: 1, heightFor: heightFor))
        XCTAssertEqual(shrunk.count, 8)
        XCTAssertEqual(rect(shrunk, 1, 0).table, TableCell(id: id, row: 1, col: 0))
        XCTAssertEqual(words(shrunk), ["Item", "Qty", "Coffee\nBagel", "1"])
        XCTAssertEqual(rowTops(shrunk), [200, 246])
        XCTAssertEqual(rect(shrunk, 1, 1).h, 66)

        let across = try XCTUnwrap(merging(table, [(1, 0), (1, 1)]))
        let wider = DataGraphics.addingTableColumn(across, id: id, col: 0, right: true, heightFor: heightFor)
        XCTAssertEqual(wider.count, 14)
        XCTAssertEqual(rect(wider, 1, 0).table, TableCell(id: id, row: 1, col: 0, colSpan: 3))
        XCTAssertEqual(columnWidths(wider), [134, 200, 66])
        XCTAssertEqual(rect(wider, 1, 0).w, 400)
        let narrower = try XCTUnwrap(DataGraphics.deletingTableColumn(across, id: id, col: 1, heightFor: heightFor))
        XCTAssertEqual(rect(narrower, 1, 0).table, TableCell(id: id, row: 1, col: 0))
        XCTAssertEqual(columnWidths(narrower), [400])
        XCTAssertEqual(rect(narrower, 1, 0).w, 400)
    }

    // MARK: borders and column widths, as on the Android twin

    func testABorderIsEveryCellRectanglesStroke() {
        let table = made()
        let id = tableId(table)
        XCTAssertEqual(DataGraphics.tableBorderWidth(table, id: id), 1)
        XCTAssertEqual(DataGraphics.tableBorderColour(table, id: id), "#00000022")
        XCTAssertEqual(DataGraphics.tableBorderWeights.map(\.name), ["None", "Thin", "Medium", "Thick"])
        XCTAssertEqual(DataGraphics.tableBorderWeights.map(\.width), [0, 1, 2, 4])
        let red = DataGraphics.borderingTable(table, id: id, width: 4, color: "#ff0000")
        XCTAssertTrue(red.filter { $0.type == .shape }.allSatisfy { $0.strokeWidth == 4 && $0.stroke == "#ff0000" })
        XCTAssertEqual(red.filter { $0.type == .text }, table.filter { $0.type == .text })
        XCTAssertEqual(DataGraphics.tableBorderWidth(red, id: id), 4)
        XCTAssertEqual(rowTops(red), rowTops(table), "a border takes no room")
        // Colour alone keeps the width, and the width is held to 0…12.
        XCTAssertEqual(DataGraphics.tableBorderWidth(DataGraphics.borderingTable(table, id: id, width: nil, color: "#00ff00"), id: id), 1)
        XCTAssertEqual(DataGraphics.tableBorderWidth(DataGraphics.borderingTable(table, id: id, width: 20, color: nil), id: id), 12)
        XCTAssertEqual(DataGraphics.tableBorderWidth(DataGraphics.borderingTable(table, id: id, width: -1, color: nil), id: id), 0)
        // Cells of differing borders have none to show.
        let corner = rect(table, 0, 0).id
        let mixed = table.map { el -> Element in
            guard el.id == corner else { return el }
            var out = el
            out.strokeWidth = 3
            out.stroke = "#123456"
            return out
        }
        XCTAssertNil(DataGraphics.tableBorderWidth(mixed, id: id))
        XCTAssertNil(DataGraphics.tableBorderColour(mixed, id: id))
    }

    func testTheSharedColumnDragTable() {
        let rows: [(widths: [Double], edge: Int, dx: Double, out: [Double])] = [
            ([267, 133], 0, 20, [287, 113]),
            ([267, 133], 0, 200, [376, 24]),
            ([267, 133], 0, -300, [24, 376]),
            ([100, 100, 100], 1, -10.4, [100, 90, 110]),
            ([100, 100, 100], 0, 0.5, [101, 99, 100]),
            ([30, 10], 0, 5, [30, 10]),
        ]
        for row in rows {
            XCTAssertEqual(DataGraphics.draggedColumns(row.widths, edge: row.edge, by: row.dx), row.out,
                           "\(row.widths) \(row.edge) \(row.dx)")
        }
        XCTAssertNil(DataGraphics.draggedColumns([267, 133], edge: 1, by: 10))
        XCTAssertNil(DataGraphics.draggedColumns([267, 133], edge: -1, by: 10))

        let even: [(total: Double, count: Int, out: [Double])] = [
            (400, 2, [200, 200]),
            (400, 3, [133, 133, 134]),
            (100, 3, [33, 33, 34]),
            (10, 4, [3, 3, 3, 1]),
            (400, 1, [400]),
        ]
        for row in even {
            XCTAssertEqual(DataGraphics.evenColumns(total: row.total, count: row.count), row.out, "\(row.total) / \(row.count)")
        }
    }

    func testAColumnEdgeDraggedWidensOneNeighbourAndNarrowsTheOther() throws {
        let table = made()
        let id = tableId(table)
        XCTAssertEqual(DataGraphics.tableColumnWidths(table, id: id), [267, 133])
        XCTAssertEqual(DataGraphics.tableColumnEdges(table, id: id), [367])
        let widths = try XCTUnwrap(DataGraphics.draggedColumns([267, 133], edge: 0, by: 20))
        let dragged = DataGraphics.placingTableColumns(table, id: id, widths: widths, heightFor: heightFor)
        XCTAssertEqual(columnWidths(dragged), [287, 113])
        XCTAssertEqual(columnLefts(dragged), [100, 387])
        XCTAssertEqual(text(dragged, 0, 1).x, 400)
        XCTAssertEqual(text(dragged, 1, 0).w, 260.6, accuracy: 1e-9)
        XCTAssertEqual(rowTops(dragged), [200, 246, 292])
        XCTAssertEqual(DataGraphics.placingTableColumns(table, id: id, widths: [400], heightFor: heightFor), table,
                       "not one width per column")
        // A merged cell across the edge keeps the width of both.
        let merged = try XCTUnwrap(merging(table, [(1, 0), (1, 1)]))
        let across = DataGraphics.placingTableColumns(merged, id: id, widths: widths, heightFor: heightFor)
        XCTAssertEqual([rect(across, 1, 0).x, rect(across, 1, 0).w], [100, 400])
        XCTAssertEqual([rect(across, 0, 1).x, rect(across, 0, 1).w], [387, 113])

        let even = DataGraphics.placingTableColumns(table, id: id, widths: DataGraphics.evenColumns(total: 400, count: 2),
                                                    heightFor: heightFor)
        XCTAssertEqual(columnWidths(even), [200, 200])
        XCTAssertEqual(columnLefts(even), [100, 300])
    }

    // MARK: as text

    func testATableReadsAsALinePerRow() {
        let table = made()
        XCTAssertEqual(DataGraphics.tableText(table, id: tableId(table)), "Item, Qty\nCoffee, 2\nBagel, 1")
        // A cell with a comma in it: every row's cells go apart with tabs,
        // which parse back.
        let comma = withWords(table, 1, 0, "Coffee, iced")
        XCTAssertEqual(DataGraphics.tableText(comma, id: tableId(comma)), "Item\tQty\nCoffee, iced\t2\nBagel\t1")
        XCTAssertEqual(DataGraphics.parseTable(DataGraphics.tableText(comma, id: tableId(comma))),
                       [["Item", "Qty"], ["Coffee, iced", "2"], ["Bagel", "1"]])
        // Line breaks and tabs in a cell are spaces.
        let broken = withWords(table, 1, 0, "Coffee\tblack\nhot")
        XCTAssertEqual(DataGraphics.tableText(broken, id: tableId(broken)), "Item, Qty\nCoffee black hot, 2\nBagel, 1")
    }

    func testEditedAsTextTheTableKeepsItsColumnWidthsAndItsUntouchedCells() throws {
        let table = made()
        let rebuilt = try XCTUnwrap(DataGraphics.rebuiltTable(
            table, id: tableId(table), rows: DataGraphics.parseTable("Item, Qty, Price\nCoffee, 2, 3.50"), heightFor: heightFor))
        XCTAssertEqual(rebuilt.count, 12)
        // The columns it had keep their widths; a column more is the 200
        // they average, and the table grows to the right.
        XCTAssertEqual(columnWidths(rebuilt), [267, 133, 200])
        XCTAssertEqual(columnLefts(rebuilt), [100, 367, 500])
        XCTAssertEqual(text(rebuilt, 1, 2).text, "3.50")
        XCTAssertEqual(text(rebuilt, 1, 0).id, text(table, 1, 0).id)
        XCTAssertEqual(text(rebuilt, 1, 0).text, "Coffee")
        XCTAssertEqual(text(rebuilt, 1, 0), text(table, 1, 0))
        XCTAssertEqual(rowTops(rebuilt), [200, 246])
        XCTAssertEqual(Set(rebuilt.compactMap { $0.table?.id }), [tableId(table)])
        // A column fewer: the table narrows from the right.
        let narrower = try XCTUnwrap(DataGraphics.rebuiltTable(
            table, id: tableId(table), rows: DataGraphics.parseTable("A\nB"), heightFor: heightFor))
        XCTAssertEqual(columnWidths(narrower), [267])
        XCTAssertEqual(columnLefts(narrower), [100])
        XCTAssertEqual(words(narrower), ["A", "B"])
        XCTAssertNil(DataGraphics.rebuiltTable(table, id: tableId(table), rows: [], heightFor: heightFor))

        // A cell whose words did not change keeps its own styles; new rows
        // keep the bands.
        let coffee = text(table, 1, 0).id
        let styled = table.map { el -> Element in
            var out = el
            if el.id == coffee { out.italic = true }
            return out
        }
        let longer = try XCTUnwrap(DataGraphics.rebuiltTable(
            styled, id: tableId(styled), rows: DataGraphics.parseTable("Item, Qty\nCoffee, 2\nBagel, 1\nJam, 3\nBun, 4"),
            heightFor: heightFor))
        XCTAssertEqual(words(longer), ["Item", "Qty", "Coffee", "2", "Bagel", "1", "Jam", "3", "Bun", "4"])
        XCTAssertEqual(text(longer, 1, 0).italic, true)
        XCTAssertEqual(columnWidths(longer), [267, 133])
        XCTAssertEqual(rowTops(longer), [200, 246, 292, 338, 384])
        XCTAssertEqual(rect(longer, 2, 0).fill, rect(longer, 4, 0).fill)
        XCTAssertEqual(rect(longer, 1, 0).fill, rect(longer, 3, 0).fill)
    }

    func testEditedAsTextACommaStaysInItsCellAndABlankRowStaysARow() throws {
        let table = made()
        // One column with a comma in its words: written with tabs, so read
        // back on tabs alone, and Update changes nothing.
        let narrowed = try XCTUnwrap(DataGraphics.deletingTableColumn(table, id: tableId(table), col: 1,
                                                                      heightFor: heightFor))
        let one = withWords(narrowed, 1, 0, "Smith, John")
        let text = DataGraphics.tableText(one, id: tableId(one))
        XCTAssertEqual(text, "Item\nSmith, John\nBagel")
        XCTAssertTrue(DataGraphics.tableTextTabbed(one, id: tableId(one)))
        XCTAssertFalse(DataGraphics.tableTextTabbed(table, id: tableId(table)))
        XCTAssertEqual(DataGraphics.parseEditedTable(text, opened: text, tabs: true), [["Item"], ["Smith, John"], ["Bagel"]])
        let again = try XCTUnwrap(DataGraphics.rebuiltTable(
            one, id: tableId(one), rows: DataGraphics.parseEditedTable(text, opened: text, tabs: true), heightFor: heightFor))
        XCTAssertEqual(words(again), ["Item", "Smith, John", "Bagel"])
        XCTAssertEqual(columnWidths(again), [400])
        // Without tabs, a comma parts cells, as ever.
        XCTAssertEqual(DataGraphics.parseEditedTable("Smith, John", opened: "Smith, John", tabs: false), [["Smith", "John"]])
        // A line typed in, with no tab (a phone's keyboard has no tab key),
        // splits on commas even when the table was written with tabs; the
        // lines as they were opened stay whole.
        XCTAssertEqual(DataGraphics.parseEditedTable(text + "\nJuice, 3\nTea\t1", opened: text, tabs: true),
                       [["Item"], ["Smith, John"], ["Bagel"], ["Juice", "3"], ["Tea", "1"]])

        // Blank lines between rows are rows with no words; those before the
        // first row and after the last are not rows at all.
        XCTAssertEqual(DataGraphics.parseEditedTable("\n \nItem\n\nBagel\n\n", opened: "", tabs: false), [["Item"], [""], ["Bagel"]])
        XCTAssertEqual(DataGraphics.parseEditedTable("Item\tQty\n\t\nBagel\t1", opened: "Item\tQty\nBagel\t1", tabs: true),
                       [["Item", "Qty"], ["", ""], ["Bagel", "1"]])
        XCTAssertEqual(DataGraphics.parseEditedTable("A\r\nB", opened: "", tabs: false), [["A"], ["B"]])
        XCTAssertEqual(DataGraphics.parseEditedTable(" \n\t\n", opened: "", tabs: true), [])
        let gap = DataGraphics.addingTableRow(one, id: tableId(one), row: 1, below: true, heightFor: heightFor)
        let gapText = DataGraphics.tableText(gap, id: tableId(gap))
        XCTAssertEqual(gapText, "Item\nSmith, John\n\nBagel")
        let gapRows = DataGraphics.parseEditedTable(gapText, opened: gapText,
                                                   tabs: DataGraphics.tableTextTabbed(gap, id: tableId(gap)))
        let kept = try XCTUnwrap(DataGraphics.rebuiltTable(gap, id: tableId(gap), rows: gapRows, heightFor: heightFor))
        XCTAssertEqual(words(kept), ["Item", "Smith, John", "", "Bagel"])
        XCTAssertEqual(rowTops(kept), rowTops(gap))
        XCTAssertEqual(rect(kept, 3, 0).fill, rect(gap, 3, 0).fill)
    }

    func testEditedAsTextATableOfAHeaderAloneGrowsBandedBodyRows() throws {
        let header = DataGraphics.table(DataGraphics.parseTable("Item, Qty"),
                                        in: CGRect(x: 100, y: 200, width: 400, height: 300), accent: "#1f2430",
                                        heightFor: heightFor)
        let grown = try XCTUnwrap(DataGraphics.rebuiltTable(
            header, id: tableId(header), rows: DataGraphics.parseTable("Item, Qty\nCoffee, 2\nBagel, 1\nJam, 3"),
            heightFor: heightFor))
        XCTAssertEqual((0...3).map { rect(grown, $0, 0).fill?.color ?? "" }, ["#1f2430", "#ffffff", "#f3f4f6", "#ffffff"])
        XCTAssertEqual((0...3).map { text(grown, $0, 1).fontWeight ?? 0 }, [700, 400, 400, 400])
        XCTAssertEqual((1...3).map { text(grown, $0, 0).color ?? "" }, ["#1f2430", "#1f2430", "#1f2430"])
        XCTAssertTrue(DataGraphics.tableHasHeader(grown, id: tableId(grown)))
        // As a table made from the same rows bands them.
        let table = made()
        XCTAssertEqual((0...2).map { rect(table, $0, 1).fill }, (0...2).map { rect(grown, $0, 1).fill })

        // A header and one body row: the new rows copy the body row, its
        // fonts and colours, and a cell in its band takes the next band.
        let two = DataGraphics.table(DataGraphics.parseTable("Item, Qty\nCoffee, 2"),
                                     in: CGRect(x: 100, y: 200, width: 400, height: 300), accent: "#1f2430",
                                     heightFor: heightFor)
        let longer = DataGraphics.parseTable("Item, Qty\nCoffee, 2\nBagel, 1\nJam, 3")
        let plainRows = try XCTUnwrap(DataGraphics.rebuiltTable(two, id: tableId(two), rows: longer, heightFor: heightFor))
        XCTAssertEqual((0...3).map { rect(plainRows, $0, 1).fill?.color ?? "" }, ["#1f2430", "#ffffff", "#f3f4f6", "#ffffff"])
        XCTAssertEqual((0...3).map { text(plainRows, $0, 1).fontWeight ?? 0 }, [700, 400, 400, 400])
        let yellow = two.map { el -> Element in
            guard el.table?.row == 1 else { return el }
            var out = el
            if el.type == .shape && el.table?.col == 0 { out.fill = .solid("#ffeb3b") }
            if el.type == .text {
                out.fontFamily = "Lora"
                out.color = "#c62828"
            }
            return out
        }
        let styledRows = try XCTUnwrap(DataGraphics.rebuiltTable(yellow, id: tableId(yellow), rows: longer, heightFor: heightFor))
        XCTAssertEqual((1...3).map { rect(styledRows, $0, 0).fill?.color ?? "" }, ["#ffeb3b", "#ffeb3b", "#ffeb3b"])
        XCTAssertEqual((1...3).map { rect(styledRows, $0, 1).fill?.color ?? "" }, ["#ffffff", "#f3f4f6", "#ffffff"])
        XCTAssertEqual((1...3).map { text(styledRows, $0, 0).fontFamily ?? "" }, ["Lora", "Lora", "Lora"])
        XCTAssertEqual((1...3).map { text(styledRows, $0, 1).color ?? "" }, ["#c62828", "#c62828", "#c62828"])
        XCTAssertEqual(text(styledRows, 2, 0).fontSize, text(two, 1, 0).fontSize)
    }

    func testOnlyWordsTypedLayATableOutAgainNeverACopyOrALockedTable() {
        let table = made()
        // Row 1 made taller by hand.
        let tall = table.map { el -> Element in
            var out = el
            if el.table?.row == 1 && el.type == .shape { out.h = 80 }
            return out
        }
        var start = Design(title: "tables", width: 1000, height: 1000)
        start.pages[0].elements = tall
        let before = start
        func after(_ elements: [Element]) -> Design {
            var out = before
            out.pages[0].elements = elements
            return out
        }

        // A copy's cells are new, not typed in: it stays as its original stands.
        let copy = Copies.of(tall, offset: 24)
        XCTAssertEqual(DataGraphics.settlingTables(after(tall + copy), since: before, heightFor: heightFor).pages[0].elements,
                       tall + copy)

        // Words typed in a cell lay the table out again...
        let typed = withWords(tall, 1, 0, "Coffee\nwith milk")
        let laid = DataGraphics.settlingTables(after(typed), since: before, heightFor: heightFor).pages[0].elements
        XCTAssertEqual(rect(laid, 1, 1).h, 66)
        XCTAssertEqual(rect(laid, 2, 0).y, 312)
        // ...but not when a cell of it is locked: nothing locked moves.
        let locked = typed.map { el -> Element in
            var out = el
            if el.table?.row == 2 { out.locked = true }
            return out
        }
        XCTAssertEqual(DataGraphics.settlingTables(after(locked), since: before, heightFor: heightFor).pages[0].elements,
                       locked)
    }

    /// Uppercase, a list, an indent and the like change how much room a
    /// cell's words take, so the table is laid out again, as on the Android
    /// twin, where they are among the element's extras.
    func testACellMadeUppercaseLaysTheTableOutAgain() {
        let table = made()
        let coffee = text(table, 1, 0).id
        // Words grown but not yet laid out, then made uppercase.
        var grown = Design(title: "tables", width: 1000, height: 1000)
        grown.pages[0].elements = withWords(table, 1, 0, "Coffee\nwith milk")
        var cased = grown
        cased.pages[0].elements = grown.pages[0].elements.map { el -> Element in
            var out = el
            if el.id == coffee { out.uppercase = true }
            return out
        }
        XCTAssertEqual(rect(cased.pages[0].elements, 1, 1).h, 46)
        let laid = DataGraphics.settlingTables(cased, since: grown, heightFor: heightFor).pages[0].elements
        XCTAssertEqual(rect(laid, 1, 1).h, 66)
        XCTAssertEqual(rect(laid, 2, 0).y, 312)
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
        XCTAssertNil(try read(#"{"id": "", "row": 1, "col": 0}"#))
        XCTAssertNil(try read(#"{"id": "tbl_x", "row": "1", "col": 0}"#))
        XCTAssertNil(try read(#"{"id": "tbl_x", "row": -1, "col": 0}"#))
        // A row or column is below 1,000,000, so a span added to it never wraps.
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 999999, "col": 0}"#), TableCell(id: "tbl_x", row: 999999, col: 0))
        XCTAssertNil(try read(#"{"id": "tbl_x", "row": 1000000, "col": 0}"#))
        XCTAssertNil(try read(#"{"id": "tbl_x", "row": 9223372036854775807, "col": 0}"#))
        XCTAssertNil(try read(#"{"id": "tbl_x", "row": 0, "col": 2147483647}"#))
        XCTAssertNil(try read(#""tbl_x""#))
        // An unreadable place leaves the element itself as it was.
        let kept = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e","type":"text","text":"A","table":{"id":"tbl_a","row":"one","col":0}}"#.utf8))
        XCTAssertEqual(kept.text, "A")
        XCTAssertNil(kept.table)
    }

    func testAMergedCellsSpansAreWrittenOnlyOverOneAndReadTolerantly() throws {
        var el = Element.shape("rect")
        el.table = TableCell(id: "tbl_abc", row: 1, col: 0, rowSpan: 2, colSpan: 3)
        let data = try JSONEncoder().encode(el)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cell = try XCTUnwrap(written["table"] as? [String: Any])
        XCTAssertEqual(Set(cell.keys), ["id", "row", "col", "rowSpan", "colSpan"])
        XCTAssertEqual(cell["rowSpan"] as? Int, 2)
        XCTAssertEqual(cell["colSpan"] as? Int, 3)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data), el)
        var wide = Element.shape("rect")
        wide.table = TableCell(id: "tbl_abc", row: 2, col: 1, colSpan: 3)
        let one = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(wide)) as? [String: Any])
        let written3 = try XCTUnwrap(one["table"] as? [String: Any])
        XCTAssertEqual(Set(written3.keys), ["id", "row", "col", "colSpan"])
        XCTAssertEqual(written3["colSpan"] as? Int, 3)

        func read(_ json: String) throws -> TableCell? {
            try JSONDecoder().decode(Element.self,
                                     from: Data(#"{"id":"e","type":"shape","table":\#(json)}"#.utf8)).table
        }
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 1, "col": 0, "rowSpan": 2.0, "colSpan": 3}"#),
                       TableCell(id: "tbl_x", row: 1, col: 0, rowSpan: 2, colSpan: 3))
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 1, "col": 0, "rowSpan": 0, "colSpan": "2"}"#),
                       TableCell(id: "tbl_x", row: 1, col: 0))
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 1, "col": 0, "rowSpan": 1.5, "colSpan": -2}"#),
                       TableCell(id: "tbl_x", row: 1, col: 0))
        // Past maxSpan, which no table made on either phone reaches, a span is 1.
        XCTAssertEqual(try read(#"{"id": "tbl_x", "row": 1, "col": 0, "rowSpan": 1000, "colSpan": 1001}"#),
                       TableCell(id: "tbl_x", row: 1, col: 0, rowSpan: 1000))
    }

    func testACopyOfAMergedTableKeepsItsSpans() throws {
        let table = try XCTUnwrap(merging(made(), [(1, 0), (1, 1)]))
        let copy = Copies.of(table, offset: 24)
        XCTAssertNotEqual(tableId(table), tableId(copy))
        XCTAssertEqual(rect(copy, 1, 0).table?.colSpan, 2)
        XCTAssertEqual(text(copy, 1, 0).table?.colSpan, 2)
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
        s.updateSelectedTransient { $0.text = "Coffee\nwith milk" }
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
        let coffee = text(table, 1, 0)
        s.startTyping(coffee.id)
        s.typeWords("Coffee\nwith milk", into: coffee.id)
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
        XCTAssertEqual(columnWidths(s.page.elements), [400], "the table keeps its width")
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
        XCTAssertEqual(s.tableText, "Item, Qty\nCoffee, 2\nBagel, 1")
        XCTAssertFalse(s.tableTextTabbed)
        XCTAssertFalse(s.rebuildTable(from: "  \n"))
        XCTAssertTrue(s.rebuildTable(from: "Item, Qty, Price\nCoffee, 2, 3.50"))
        XCTAssertEqual(columnWidths(s.page.elements), [267, 133, 200])
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

    func testATableWithALockedCellIsLeftAsItIsAndSaysWhy() {
        var locked = made()
        let qty = locked.firstIndex { $0.type == .text && $0.table?.row == 2 && $0.table?.col == 1 } ?? 0
        locked[qty].locked = true
        let s = store(locked)
        s.selection = [text(locked, 1, 0).id]
        s.addTableColumn(right: true)
        XCTAssertEqual(s.page.elements, locked)
        XCTAssertEqual(s.announcement, "A cell of this table is locked. Unlock it to change the table.")
        XCTAssertFalse(s.rebuildTable(from: "Item, Qty, Price\nCoffee, 2, 3.50"))
        XCTAssertFalse(s.setTableCellColour("#ff0000"))
        XCTAssertEqual(s.page.elements, locked)
        XCTAssertFalse(s.canUndo)
    }

    func testADoubleTapOnACellsRectangleTypesInItsWords() {
        let s = store(made())
        let table = s.page.elements
        XCTAssertEqual(s.typedIn(rect(table, 1, 0))?.id, text(table, 1, 0).id)
        XCTAssertEqual(s.typedIn(text(table, 1, 0))?.id, text(table, 1, 0).id)
        let plain = Element.shape("rect")
        XCTAssertEqual(s.typedIn(plain)?.id, plain.id, "a plain shape takes its own words")
    }

    func testADoubleTapOnAnotherPageTypesOnlyWhatIsUnlockedThere() {
        let s = store([])
        var table = made()
        XCTAssertEqual(s.typedIn(rect(table, 1, 0), among: table)?.id, text(table, 1, 0).id,
                       "a cell on another page finds its words on that page")
        XCTAssertNil(s.typedIn(rect(table, 1, 0)), "not among the page worked")
        let words = table.firstIndex { $0.id == text(table, 1, 0).id } ?? 0
        table[words].locked = true
        XCTAssertNil(s.typedIn(rect(table, 1, 0), among: table), "locked words zoom")
        var shape = Element.shape("rect")
        shape.locked = true
        XCTAssertNil(s.typedIn(shape, among: [shape]), "a locked shape zooms")
    }

    func testMergeAndUnmergeAreEachOneStep() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 1, 1).id]
        XCTAssertEqual(s.tableSelection?.canMerge, false)
        s.selection = [text(table, 1, 0).id, rect(table, 1, 1).id]
        XCTAssertEqual(s.tableSelection?.canMerge, true)
        XCTAssertEqual(s.tableSelection?.canUnmerge, false)
        XCTAssertTrue(s.mergeTableCells())
        XCTAssertEqual(s.page.elements.count, 10)
        XCTAssertEqual(s.selection, [text(s.page.elements, 1, 0).id], "the merged cell stays selected")
        XCTAssertEqual(s.tableSelection?.columns, [0, 1])
        XCTAssertEqual(s.tableSelection?.canUnmerge, true)
        XCTAssertEqual(s.tableGrid, [["Item", "Qty"], ["Coffee 2", ""], ["Bagel", "1"]])
        XCTAssertEqual(s.tableCovered, [[1, 1]])
        XCTAssertTrue(s.unmergeTableCells())
        XCTAssertEqual(s.page.elements.count, 12)
        s.undo()
        XCTAssertEqual(s.page.elements.count, 10)
        s.undo()
        XCTAssertEqual(s.page.elements, table)
        XCTAssertFalse(s.canUndo)
    }

    func testBordersAreOneStepAndTheSliderOneForItsDrag() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 1, 0).id]
        XCTAssertEqual(s.tableBorderWidth, 1)
        XCTAssertEqual(s.tableBorderColour, "#00000022")
        XCTAssertTrue(s.setTableBorderWidth(4))
        XCTAssertFalse(s.setTableBorderWidth(4), "nothing to change")
        XCTAssertTrue(s.setTableBorderColour("#ff0000"))
        XCTAssertEqual(s.tableBorderWidth, 4)
        XCTAssertEqual(s.tableBorderColour, "#ff0000")
        s.setTableBorderTransient(width: 7, color: nil)
        s.setTableBorderTransient(width: 9, color: nil)
        s.commit()
        XCTAssertEqual(s.tableBorderWidth, 9)
        s.undo()
        XCTAssertEqual(s.tableBorderWidth, 4, "the slider's drag is one step")
        s.undo()
        s.undo()
        XCTAssertEqual(s.page.elements, table)
    }

    func testColumnEdgesDragAndDistributeAsOneStepOnAWholeTable() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 1, 0).id]
        XCTAssertNil(s.tableColumnEdges, "only on a whole table")
        s.selection = Set(table.map(\.id))
        XCTAssertEqual(s.tableColumnEdges?.xs, [367])
        XCTAssertEqual(s.tableColumnEdges?.top, 200)
        XCTAssertEqual(s.tableColumnEdges?.bottom, 338)
        s.setTableColumnWidthsTransient([150, 250])
        s.setTableColumnWidthsTransient(DataGraphics.draggedColumns([267, 133], edge: 0, by: -107) ?? [])
        s.commit()
        XCTAssertEqual(s.tableColumnWidths, [160, 240])
        XCTAssertEqual(s.tableColumnEdges?.xs, [260])
        s.undo()
        XCTAssertEqual(s.page.elements, table, "one step for the whole drag")
        XCTAssertTrue(s.distributeTableColumns())
        XCTAssertEqual(s.tableColumnWidths, [200, 200])
        XCTAssertFalse(s.distributeTableColumns(), "already even")
        s.undo()
        XCTAssertEqual(s.page.elements, table)
    }

    func testTheGridSetsTheTableAndItsHeaderAsOneStep() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 0, 0).id]
        XCTAssertEqual(s.tableGrid, [["Item", "Qty"], ["Coffee", "2"], ["Bagel", "1"]])
        XCTAssertTrue(s.rebuildTable(rows: [["Item", "Qty"], ["Tea", "3"]], header: false))
        XCTAssertEqual(s.tableSelection?.header, false)
        XCTAssertEqual(s.tableGrid, [["Item", "Qty"], ["Tea", "3"]])
        XCTAssertFalse(s.rebuildTable(rows: [], header: nil))
        s.undo()
        XCTAssertEqual(s.page.elements, table)
    }

    // MARK: read aloud

    func testACellReadsItsPlaceItsHeaderAndItsWords() throws {
        let t = made()
        let id = tableId(t)
        XCTAssertEqual(DataGraphics.spokenCell(t, id: id, row: 1, col: 1), "Row 2 of 3, Column 2 of 2, Qty: 2")
        XCTAssertEqual(DataGraphics.spokenCell(t, id: id, row: 0, col: 0), "Row 1 of 3, Column 1 of 2, Item")
        XCTAssertNil(DataGraphics.spokenCell(t, id: id, row: 5, col: 0))
        // A merged cell says how far it spans.
        let merged = try XCTUnwrap(merging(t, [(2, 0), (2, 1)]))
        XCTAssertEqual(DataGraphics.spokenCell(merged, id: id, row: 2, col: 0), "Row 3 of 3, Column 1 of 2, Item: Bagel 1, spans 2 columns")
        // VoiceOver reads a cell so.
        XCTAssertEqual(CanvasAccessibility.label(for: rect(t, 1, 1), on: t), "Row 2 of 3, Column 2 of 2, Qty: 2")
    }

    // MARK: row heights, the shared table

    private func rowHeights(_ els: [Element]) -> [Double] {
        let boxes = DataGraphics.tableRowBoxes(els, id: tableId(els))
        return boxes.keys.sorted().compactMap { boxes[$0]?.h }
    }

    func testARowDraggedTallerKeepsItsHeightWrittenOnItsFirstCellOnly() throws {
        let t = made()
        let id = tableId(t)
        XCTAssertEqual(rowHeights(t), [46, 46, 46])
        let tall = try XCTUnwrap(DataGraphics.withRowDragged(t, id: id, boundary: 0, dy: 30, heightFor: heightFor))
        XCTAssertEqual(rowHeights(tall), [76, 46, 46])
        XCTAssertEqual(rowTops(tall), [200, 276, 322])
        XCTAssertEqual(rect(tall, 0, 0).table?.minH, 76)
        XCTAssertEqual(text(tall, 0, 0).table?.minH, 76)
        XCTAssertNil(rect(tall, 0, 1).table?.minH)
        XCTAssertNil(rect(tall, 1, 0).table?.minH)
        // Its words changing keep it so; words taller than it win.
        XCTAssertEqual(rowHeights(DataGraphics.relaidTable(withWords(tall, 0, 1, "Q"), id: id, heightFor: heightFor))[0], 76)
        XCTAssertEqual(rowHeights(DataGraphics.relaidTable(withWords(tall, 0, 1, "1\n2\n3"), id: id, heightFor: heightFor))[0], 86)
        // Dragged back to its words' height or under, it keeps none; never under 24 or its words.
        let back = try XCTUnwrap(DataGraphics.withRowDragged(tall, id: id, boundary: 0, dy: -50, heightFor: heightFor))
        XCTAssertEqual(rowHeights(back), [46, 46, 46])
        XCTAssertNil(rect(back, 0, 0).table?.minH)
        XCTAssertNil(DataGraphics.withRowDragged(t, id: id, boundary: 0, dy: -40, heightFor: heightFor))
        XCTAssertNil(DataGraphics.withRowDragged(t, id: id, boundary: 7, dy: 10, heightFor: heightFor))
        XCTAssertEqual(DataGraphics.minRowHeight, 24)
        // Written as "minH" in the cell's table object, and read back.
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(rect(tall, 0, 0)), encoding: .utf8))
        XCTAssertTrue(json.contains(#""minH":76"#), json)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: Data(json.utf8)).table?.minH, 76)
    }

    func testDistributeRowsMakesThemOneHeightAndAMovedRowKeepsItsOwn() throws {
        let t = made()
        let id = tableId(t)
        let tall = try XCTUnwrap(DataGraphics.withRowDragged(t, id: id, boundary: 0, dy: 30, heightFor: heightFor))
        let even = try XCTUnwrap(DataGraphics.evenRows(tall, id: id, heightFor: heightFor))
        XCTAssertEqual(rowHeights(even), [56, 56, 56])
        XCTAssertNil(DataGraphics.evenRows(even, id: id, heightFor: heightFor))
        XCTAssertNil(DataGraphics.evenRows(t, id: id, heightFor: heightFor))
        // Row moves carry the height with the row.
        let second = try XCTUnwrap(DataGraphics.withRowDragged(t, id: id, boundary: 1, dy: 30, heightFor: heightFor))
        let moved = try XCTUnwrap(DataGraphics.movedTableRow(second, id: id, row: 1, by: 1, heightFor: heightFor))
        XCTAssertEqual(rowHeights(moved), [46, 46, 76])
        // Scaled with the table, as its spacing is.
        XCTAssertEqual(TableCell.scaledPad(rect(tall, 0, 0).table, by: 2)?.minH, 152)
    }

    func testRowEdgesDragAndDistributeAsOneStep() {
        let s = store(made())
        let table = s.page.elements
        s.selection = [text(table, 1, 0).id]
        XCTAssertEqual(s.tableRowEdges?.ys, [246, 292, 338])
        XCTAssertEqual(s.tableRowEdges?.left, 100)
        s.dragTableRowTransient(from: table, row: 0, by: 10)
        s.dragTableRowTransient(from: table, row: 0, by: 30)
        s.commit()
        XCTAssertEqual(s.tableRowHeights[0], 76)
        s.undo()
        XCTAssertEqual(s.page.elements, table, "one step for the whole drag")
        s.selection = [text(table, 1, 0).id]
        XCTAssertTrue(s.resizeTableRow(taller: true))
        XCTAssertEqual(s.tableRowHeights[1], 54)
        XCTAssertTrue(s.resizeTableRow(taller: false))
        XCTAssertEqual(s.tableRowHeights[1], 46)
        XCTAssertFalse(s.resizeTableRow(taller: false), "never under its words")
        XCTAssertFalse(s.distributeTableRows(), "already even")
        s.dragTableRowTransient(from: s.page.elements, row: 0, by: 30)
        s.commit()
        XCTAssertTrue(s.distributeTableRows())
        XCTAssertEqual(s.tableRowHeights.keys.sorted().compactMap { s.tableRowHeights[$0] }, [56, 56, 56])
        s.undo()
        XCTAssertEqual(s.tableRowHeights[0], 76)
    }
}
