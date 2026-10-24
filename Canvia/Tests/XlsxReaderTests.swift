// Excel workbooks for a chart's or a table's data, as the Android twin's
// XlsxReaderTest reads them: the shared fixture (Tests/Fixtures/sheet.xlsx
// and sheet.json, Tools/generate_xlsx_fixture.py) gives the same sheets and
// the same grid on both phones; cell places, dates and the grid's limits.

import XCTest
@testable import Canvia

final class XlsxReaderTests: XCTestCase {

    /// Shared: sheet.xlsx reads to the sheets in sheet.json on both phones.
    func testTheSharedWorkbookReadsToTheSharedSheets() throws {
        let sheets = XlsxReader.read(try SharedFixture.data("sheet", ext: "xlsx"))
        let json = try JSONSerialization.jsonObject(with: try SharedFixture.data("sheet"))
        let expected = try XCTUnwrap(json as? [[String: Any]]).map { sheet in
            XlsxReader.Sheet(name: sheet["name"] as? String ?? "", cells: sheet["cells"] as? [[String]] ?? [])
        }
        XCTAssertEqual(expected.count, 2)
        XCTAssertEqual(sheets, expected)
    }

    /// Shared: the first sheet in the grid as a CSV file's would be — the
    /// empty row left out, spaces trimmed — as Android's XlsxReaderTest.
    func testASheetBecomesTheGridAsACsvFileDoes() throws {
        let sheets = XlsxReader.read(try SharedFixture.data("sheet", ext: "xlsx"))
        let grid = DataGrid.fromRows(try XCTUnwrap(sheets.first).cells)
        XCTAssertEqual(grid.cells, [
            ["Month", "Sales", "Costs", "Day", ""],
            ["January", "1200.5", "-300", "2024-01-15", ""],
            ["February", "980", "", "2024-02-15T18:00:00", "0.5"],
            ["Total <all>", "2180.5", "xy", "TRUE", "#DIV/0!"],
            ["Merged across", "", "", "", ""],
            ["1900-01-01", "18:00:00", "3", "06:00:00", "12:00:00"],
        ])
        XCTAssertNil(grid.note)
    }

    func testImportDataAsksWhichSheetOfSeveral() throws {
        let data = try SharedFixture.data("sheet", ext: "xlsx")
        XCTAssertTrue(DataGrid.isZip(data))
        guard case .sheets(let sheets) = DataGrid.read(xlsx: data) else { return XCTFail("two sheets with rows") }
        XCTAssertEqual(sheets.count, 2)
        let grid = DataGrid.fromRows(sheets[0].cells)
        XCTAssertEqual(grid.cells.count, 6)
        XCTAssertNil(grid.note, "nothing left out")
        XCTAssertEqual(DataGrid.read(xlsx: Data("not a workbook".utf8)),
                       .refused("That file isn't a spreadsheet Canvia can read."))
        XCTAssertEqual(DataGrid.read(xlsx: nil), .refused("That file isn't a spreadsheet Canvia can read."))
    }

    func testRowsFromASheetAreTakenInAsACsvFilesAre() {
        let rows = (0..<60).map { r in (0..<14).map { c in r == 3 ? " " : "r\(r)c\(c)" } }
        let read = DataGrid.fromRows(rows)
        XCTAssertEqual(read.rows, 59, "a row with no words is left out")
        XCTAssertEqual(read.columns, 14)
        XCTAssertEqual(read.cells.count, DataGrid.csvRows)
        XCTAssertEqual(read.cells[0].count, DataGrid.csvColumns)
        XCTAssertEqual(read.note, "Imported 50 of 59 rows and 12 of 14 columns")
        XCTAssertEqual(DataGrid.fromCsv("a, b\n1,2").cells, DataGrid.fromRows([["a", " b"], ["1", "2"]]).cells)
        // Trailing empty cells are no columns of their own.
        XCTAssertEqual(DataGrid.fromRows([["a", "b", "", ""]]).columns, 2)
    }

    /// Shared: Android's XlsxReaderTest holds the same serials and formats.
    func testCellPlacesAndDates() {
        XCTAssertEqual(XlsxReader.place(of: "A1")?.column, 0)
        XCTAssertEqual(XlsxReader.place(of: "AA10")?.column, 26)
        XCTAssertEqual(XlsxReader.place(of: "AA10")?.row, 9)
        XCTAssertNil(XlsxReader.place(of: "10A"))
        XCTAssertNil(XlsxReader.place(of: "B0"))
        XCTAssertEqual(XlsxReader.isoDate(45306, base1904: false), "2024-01-15")
        XCTAssertEqual(XlsxReader.isoDate(45306.5, base1904: false), "2024-01-15T12:00:00")
        XCTAssertEqual(XlsxReader.isoDate(0.75, base1904: false), "18:00:00")
        XCTAssertEqual(XlsxReader.isoDate(1, base1904: false), "1900-01-01")
        XCTAssertEqual(XlsxReader.isoDate(61, base1904: false), "1900-03-01")
        XCTAssertEqual(XlsxReader.isoDate(60, base1904: false), "1900-03-01")
        XCTAssertEqual(XlsxReader.isoDate(45337.75, base1904: false), "2024-02-15T18:00:00")
        XCTAssertEqual(XlsxReader.isoDate(45306.999999999, base1904: false), "2024-01-16")
        XCTAssertEqual(XlsxReader.isoDate(0, base1904: true), "1904-01-01")
        XCTAssertEqual(XlsxReader.isoDate(1, base1904: true), "1904-01-02")
        XCTAssertNil(XlsxReader.isoDate(-1, base1904: false))
        XCTAssertNil(XlsxReader.isoDate(.nan, base1904: false))
        XCTAssertTrue(XlsxReader.isDateFormat(14, code: nil))
        XCTAssertFalse(XlsxReader.isDateFormat(2, code: nil))
        XCTAssertTrue(XlsxReader.isDateFormat(164, code: "dd/mm/yyyy"))
        XCTAssertFalse(XlsxReader.isDateFormat(165, code: "[Red]0.00\"d\""))
        XCTAssertTrue(XlsxReader.isDateFormat(20, code: nil))
        XCTAssertTrue(XlsxReader.isDateFormat(166, code: "h:mm AM/PM"))
        XCTAssertFalse(XlsxReader.isDateFormat(167, code: "0.0\\d"))
        XCTAssertFalse(XlsxReader.isDateFormat(168, code: "[h]:mm:ss"))
    }

    /// As Android's share-in: a chart with its legend, or a table of rows
    /// with no numbers, titled by the file.
    func testAWorkbookOpenedInCanviaIsAChartOrATableOfASheet() throws {
        let design = try XCTUnwrap(Spreadsheets.design(rows: [["Month", "Sales"], ["Jan", "3"], ["Feb", "5"]],
                                                       title: "Sales"))
        XCTAssertEqual(design.title, "Sales")
        XCTAssertEqual(design.pages.count, 1)
        XCTAssertFalse(design.pages[0].elements.isEmpty)
        XCTAssertTrue(design.pages[0].elements.contains { $0.chart?.legend == true })
        let words = try XCTUnwrap(Spreadsheets.design(rows: [["Name", "Town"], ["Ada", "London"]], title: "People"))
        XCTAssertTrue(words.pages[0].elements.allSatisfy { $0.chart == nil }, "no numbers: a table")
        XCTAssertFalse(words.pages[0].elements.isEmpty)
        XCTAssertNil(Spreadsheets.design(rows: [], title: "Empty"))
        XCTAssertTrue(Spreadsheets.isSpreadsheet(URL(fileURLWithPath: "/tmp/Book.XLSX")))
        XCTAssertEqual(Spreadsheets.title(fromFileName: "Sales.XLSX"), "Sales")
        XCTAssertEqual(Spreadsheets.title(fromFileName: ".xlsx"), "Untitled design")
    }
}
