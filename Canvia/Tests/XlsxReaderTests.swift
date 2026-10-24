// Excel workbooks for a chart's or a table's data, as the Android twin's
// XlsxReaderTest reads them: the shared fixture (Tests/Fixtures/sheets.xlsx,
// tools/generate_xlsx_fixture.py) gives the same sheets and the same grid on
// both phones; cell places, dates and the grid's limits.

import XCTest
@testable import Canvia

final class XlsxReaderTests: XCTestCase {

    func testTheSharedWorkbookReadsAsOnAndroid() throws {
        let sheets = XlsxReader.read(try SharedFixture.data("sheets", ext: "xlsx"))
        XCTAssertEqual(sheets.map(\.name), ["Sales", "Notes"])
        XCTAssertEqual(sheets[0].cells, [
            ["Month", "Sales", "Date", "Paid"],
            ["Jan", "1200", "2024-01-15", "TRUE"],
            ["Feb", "950.5", "2024-02-29", "FALSE"],
            ["Total", "2150.5", "", ""],
            ["Merged note", "", "inline", "x"],
        ])
        XCTAssertEqual(sheets[1].cells, [["Remember the milk"]])
    }

    func testImportDataAsksWhichSheetOfSeveral() throws {
        let data = try SharedFixture.data("sheets", ext: "xlsx")
        XCTAssertTrue(DataGrid.isZip(data))
        guard case .sheets(let sheets) = DataGrid.read(xlsx: data) else { return XCTFail("two sheets with rows") }
        XCTAssertEqual(sheets.count, 2)
        let grid = DataGrid.fromRows(sheets[0].cells)
        XCTAssertEqual(grid.cells.count, 5)
        XCTAssertNil(grid.note, "nothing left out")
        XCTAssertEqual(DataGrid.read(xlsx: Data("not a workbook".utf8)), .refused("That file could not be read"))
        XCTAssertEqual(DataGrid.read(xlsx: nil), .refused("That file could not be read"))
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
    }

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
        XCTAssertEqual(XlsxReader.isoDate(0, base1904: true), "1904-01-01")
        XCTAssertTrue(XlsxReader.isDateFormat(14, code: nil))
        XCTAssertFalse(XlsxReader.isDateFormat(2, code: nil))
        XCTAssertTrue(XlsxReader.isDateFormat(164, code: "dd/mm/yyyy"))
        XCTAssertFalse(XlsxReader.isDateFormat(165, code: "[Red]0.00\"d\""))
    }

    func testAWorkbookOpenedInCanviaIsAChartOfItsFirstSheet() throws {
        let design = try XCTUnwrap(Spreadsheets.design(rows: [["Month", "Sales"], ["Jan", "3"], ["Feb", "5"]],
                                                       title: "Sales"))
        XCTAssertEqual(design.title, "Sales")
        XCTAssertEqual(design.pages.count, 1)
        XCTAssertFalse(design.pages[0].elements.isEmpty)
        XCTAssertNil(Spreadsheets.design(rows: [], title: "Empty"))
        XCTAssertTrue(Spreadsheets.isSpreadsheet(URL(fileURLWithPath: "/tmp/Book.XLSX")))
    }
}
