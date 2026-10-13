// The data grid's text both ways, as the Android twin's DataGridTest has
// it, row for row: what a chart's and a table's text reads as in cells, the
// text the cells write back, pasting, rows and columns added and taken out,
// and a chart's header row.

import XCTest
@testable import Canvia

final class DataGridTests: XCTestCase {

    func testTheSharedTextToCellsTable() {
        let table: [(text: String, cells: [[String]])] = [
            ("Spring, 40\nSummer, 65", [["Spring", "40"], ["Summer", "65"]]),
            // Blank lines are left out, and short rows padded.
            ("Quarter, North, South\n\nQ1, 40\n", [["Quarter", "North", "South"], ["Q1", "40", ""]]),
            // A line with a tab splits on tabs alone.
            ("Name\tNote\nSmith, John\tHi", [["Name", "Note"], ["Smith, John", "Hi"]]),
            ("A,B\r\nC\tD", [["A", "B"], ["C", "D"]]),
            ("  \n", []),
            ("\"a, b\", 1", [["\"a", "b\"", "1"]]),
        ]
        for row in table {
            XCTAssertEqual(DataGrid.cells(row.text), row.cells, row.text)
        }
    }

    func testTheSharedCellsToChartTextTable() {
        let table: [(cells: [[String]], text: String)] = [
            ([["Spring", "40"], ["Summer", "65"]], "Spring, 40\nSummer, 65"),
            // Empty cells at a row's end and empty rows are left off; a comma is taken out.
            ([["Q1", "40", ""], ["", "", ""], ["1,000", "5", ""]], "Q1, 40\n1000, 5"),
            // A line break or a tab in a cell is a space.
            ([["A\nB", "1"], ["C\tD", "2"]], "A B, 1\nC D, 2"),
            ([["Quarter", "North", "South"], ["Q1", "", "32"]], "Quarter, North, South\nQ1, , 32"),
            ([], ""),
        ]
        for row in table {
            XCTAssertEqual(DataGrid.chartText(row.cells), row.text, "\(row.cells)")
        }
    }

    func testTheSharedCellsToTableTextTable() {
        let table: [(cells: [[String]], text: String)] = [
            ([["Item", "Qty"], ["Coffee", "2"]], "Item, Qty\nCoffee, 2"),
            // Every cell kept; tabs between cells in every row once one holds a comma.
            ([["Smith, John", "1"], ["Ann", ""]], "Smith, John\t1\nAnn\t"),
            ([["A", ""], ["", ""]], "A, \n, "),
            ([["Two\nlines", "x"]], "Two lines, x"),
        ]
        for row in table {
            XCTAssertEqual(DataGrid.tableText(row.cells), row.text, "\(row.cells)")
        }
    }

    func testAChartsTextReadIntoTheGridAndWrittenBackReadsTheSame() {
        let texts = [
            "Coffee, 42\nTea, 18%\n7",
            "Quarter, North, South\nQ1, 40, 32\nQ2, 55, 41",
            "\n  \nQuarter, North, South\n\nQ1, 40, 32\n \nQ2, 55, 41\n",
            "Month, Sales\nJan, 40\nFeb, 25",
            "A, 10, 20\nB, 40, 5",
        ]
        for text in texts {
            let again = DataGrid.chartText(DataGrid.cells(text))
            XCTAssertEqual(DataGraphics.parseChart(again), DataGraphics.parseChart(text), text)
            XCTAssertEqual(DataGraphics.parseScatter(again), DataGraphics.parseScatter(text), text)
            XCTAssertEqual(DataGrid.chartText(DataGrid.cells(again)), again, text)
        }
    }

    func testATablesTextIsTheGridsTableText() {
        let rows = DataGraphics.parseTable("Name, Note\nAnn, Hi")
        let table = DataGraphics.table(rows, in: CGRect(x: 0, y: 0, width: 400, height: 300), accent: "#1f2430",
                                       heightFor: { el in Double((el.text ?? "").components(separatedBy: "\n").count) * 20 })
        let id = table.lazy.compactMap { $0.table?.id }.first ?? ""
        XCTAssertEqual(DataGraphics.tableGrid(table, id: id), rows)
        XCTAssertEqual(DataGraphics.tableText(table, id: id), DataGrid.tableText(DataGraphics.tableGrid(table, id: id)))
    }

    func testTheSharedPasteTable() {
        let start = [["a", "b"], ["c", "d"]]
        let table: [(row: Int, col: Int, clip: String, out: [[String]])] = [
            (1, 1, "x\ty\nz\tw", [["a", "b", ""], ["c", "x", "y"], ["", "z", "w"]]),
            (0, 0, "p, q", [["p", "q"], ["c", "d"]]),
            (0, 1, "one", [["a", "one"], ["c", "d"]]),
            (2, 0, "e\nf", [["a", "b"], ["c", "d"], ["e", ""], ["f", ""]]),
            (0, 0, "\n", start),
        ]
        for row in table {
            XCTAssertEqual(DataGrid.pasting(row.clip, into: start, row: row.row, col: row.col), row.out,
                           "\(row.row), \(row.col) \(row.clip)")
        }
        XCTAssertEqual(DataGrid.pasting("x", into: [], row: 0, col: 0), [["x"]])
    }

    func testRowsAndColumnsAreAddedAndDeletedNeverTheLast() {
        let start = [["a", "b"], ["c", "d"]]
        XCTAssertEqual(DataGrid.addingRow(start, at: 1), [["a", "b"], ["", ""], ["c", "d"]])
        XCTAssertEqual(DataGrid.addingRow(start, at: 9), [["a", "b"], ["c", "d"], ["", ""]])
        XCTAssertEqual(DataGrid.addingColumn(start, at: 0), [["", "a", "b"], ["", "c", "d"]])
        XCTAssertEqual(DataGrid.addingColumn(start, at: 2), [["a", "b", ""], ["c", "d", ""]])
        XCTAssertEqual(DataGrid.removingRow(start, at: 0), [["c", "d"]])
        XCTAssertEqual(DataGrid.removingColumn(start, at: 0), [["b"], ["d"]])
        XCTAssertEqual(DataGrid.removingRow([["c"]], at: 0), [["c"]])
        XCTAssertEqual(DataGrid.removingColumn([["c"]], at: 0), [["c"]])
        XCTAssertEqual(DataGrid.addingRow([], at: 0), [[""]])
        XCTAssertEqual(DataGrid.addingColumn([], at: 0), [[""]])
        XCTAssertEqual(DataGrid.settingCell(start, row: 1, col: 1, to: "e"), [["a", "b"], ["c", "e"]])
    }

    func testAChartsHeaderRowIsReadAsParseChartReadsOneAndSwitched() {
        XCTAssertTrue(DataGrid.chartHasHeader([["Quarter", "North", "South"], ["Q1", "1", "2"]]))
        XCTAssertTrue(DataGrid.chartHasHeader([["", "Sales", ""], ["Q1", "1", ""]]))
        XCTAssertFalse(DataGrid.chartHasHeader([["A", "1"]]))
        XCTAssertFalse(DataGrid.chartHasHeader([["A", ""]]))
        XCTAssertFalse(DataGrid.chartHasHeader([["Year", "2024", "Sales"]]))
        XCTAssertFalse(DataGrid.chartHasHeader([]))
        let plain = [["A", "1", "2"], ["B", "3", "4"]]
        let headed = DataGrid.withChartHeader(plain, on: true)
        XCTAssertEqual(headed, [["", "Series 1", "Series 2"], ["A", "1", "2"], ["B", "3", "4"]])
        XCTAssertEqual(DataGraphics.parseChart(DataGrid.chartText(headed)).names, ["Series 1", "Series 2"])
        XCTAssertEqual(DataGrid.withChartHeader(headed, on: true), headed)
        XCTAssertEqual(DataGrid.withChartHeader(headed, on: false), plain)
        XCTAssertEqual(DataGrid.withChartHeader(plain, on: false), plain)
        XCTAssertEqual(DataGrid.withChartHeader([["A"]], on: true), [["", "Series 1"], ["A", ""]])
    }

    func testColumnsAreNamedAsASpreadsheetNamesThem() {
        XCTAssertEqual([0, 1, 25, 26, 27, 701, 702].map(DataGrid.columnName), ["A", "B", "Z", "AA", "AB", "ZZ", "AAA"])
    }
}
