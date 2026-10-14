// A chart's text look, smooth lines and axis range, as the Android twin's
// ChartStyleTest has them, row for row: in the shared frame (100, 100,
// 400 × 300), every label 20 tall. And Import CSV's reading of a file, as
// its DataGridTest has it.

import XCTest
@testable import Canvia

@MainActor
final class ChartStyleTests: XCTestCase {

    private let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let palette = ["#ff0000", "#00ff00", "#0000ff"]

    private func made(_ spec: ChartSpec, in at: CGRect? = nil) -> [Element] {
        DataGraphics.chart(spec, in: at ?? frame, palette: palette, heightFor: { _ in 20 })
    }

    private func rect(_ el: Element) -> [Double] { [el.x, el.y, el.w, el.h] }

    func testTheSharedLabelSizeTable() {
        // Frame, text scale, label size: 6% of the shorter side, whole and
        // at least 10, times the scale (held to 0.5…2), whole again.
        let small = CGRect(x: 0, y: 0, width: 100, height: 100)
        let table: [(frame: CGRect, scale: Double?, size: Double)] = [
            (frame, nil, 18), (frame, 1, 18), (frame, 0.5, 9), (frame, 1.5, 27), (frame, 2, 36),
            (frame, 0.25, 9), (frame, 3, 36), (small, 0.5, 5), (small, 0.75, 8),
        ]
        for row in table {
            let spec = ChartSpec(id: "chart_t", kind: "column", data: "A, 10", textScale: row.scale)
            XCTAssertEqual(DataGraphics.labelSize(spec, in: row.frame), row.size, "\(row)")
            XCTAssertEqual(made(spec, in: row.frame).first { $0.type == .text }?.fontSize, row.size, "\(row)")
        }
        // A progress ring's figure is 20% of its side, at least 10, scaled too.
        let ring = made(ChartSpec(id: "chart_t", kind: "progressRing", data: "Done, 40", textScale: 0.5))
        XCTAssertEqual(ring.filter { $0.type == .text }.map(\.fontSize), [30])
    }

    func testTheSharedCurvePathTable() {
        let table: [(points: [CGPoint], d: String)] = [
            ([CGPoint(x: 0, y: 0)], "M0 0"),
            ([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50)], "M0 0 C16.67 8.33 83.33 41.67 100 50"),
            ([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)],
             "M0 0 C8.33 8.33 33.33 50 50 50 C66.67 50 91.67 8.33 100 0"),
            ([], ""),
        ]
        for row in table {
            XCTAssertEqual(DataGraphics.smoothLine(row.points), row.d)
        }
    }

    func testASmoothLineAndAreaAreCurvesThroughTheSamePoints() {
        let data = "A, 10\nB, 5\nC, 10"
        let line = made(ChartSpec(id: "chart_t", kind: "line", data: data, smooth: true))
        XCTAssertEqual(line[0].pathData, "M0 0 C8.33 8.33 33.33 50 50 50 C66.67 50 91.67 8.33 100 0")
        let area = made(ChartSpec(id: "chart_t", kind: "area", data: data, smooth: true))
        XCTAssertEqual(area[0].pathData, "M0 0 C8.33 8.33 33.33 50 50 50 C66.67 50 91.67 8.33 100 0 L100 100 L0 100 Z")
        // Straight unless asked.
        XCTAssertEqual(made(ChartSpec(id: "chart_t", kind: "line", data: data))[0].pathData, "M0 0 L50 50 L100 0")
    }

    func testTheSharedAxisRangeTable() {
        func bars(_ low: Double?, _ high: Double?) -> [[Double]] {
            made(ChartSpec(id: "chart_t", kind: "column", data: "A, 10\nB, 5", axisMin: low, axisMax: high))
                .filter { $0.chartPart?.hasPrefix("series:") == true }.map(rect)
        }
        let plain: [[Double]] = [[136, 100, 128, 271], [336, 236, 128, 136]]
        XCTAssertEqual(bars(nil, nil), plain)
        // From 5 to 10: B stands at the foot, a pixel tall.
        XCTAssertEqual(bars(5, 10), [[136, 100, 128, 271], [336, 371, 128, 1]])
        // Up to 20: both half as tall.
        XCTAssertEqual(bars(nil, 20), [[136, 236, 128, 136], [336, 303, 128, 68]])
        // Up to 8: A is held at the top.
        XCTAssertEqual(bars(nil, 8), [[136, 100, 128, 271], [336, 202, 128, 170]])
        // A minimum at or above the maximum is ignored, both ends.
        XCTAssertEqual(bars(10, 5), plain)
        XCTAssertEqual(bars(12, nil), plain)
        // A line's points are on the same scale.
        let line = made(ChartSpec(id: "chart_t", kind: "line", data: "A, 10\nB, 5", axisMax: 20))
        XCTAssertEqual(line[0].pathData, "M0 50 L100 75")
        // A kind with no scale has none to set.
        let pie = DataGraphics.axisRange(ChartSpec(id: "chart_t", kind: "pie", data: "A, 10", axisMin: 5, axisMax: 20), peak: 10)
        XCTAssertEqual([pie.low, pie.high], [0, 10])
        let bar = DataGraphics.axisRange(ChartSpec(id: "chart_t", kind: "bar", data: "A, 10", axisMin: 5, axisMax: 20), peak: 10)
        XCTAssertEqual([bar.low, bar.high], [5, 20])
    }

    func testLabelsAxisAndLegendAreInTheChartsFontAndInk() {
        let spec = ChartSpec(id: "chart_t", kind: "scatter", data: "A, 1, 2\nB, 3, 4", legend: true, gridlines: true,
                             font: "serif", ink: "#336699")
        let els = made(spec)
        let words = els.filter { $0.type == .text }
        XCTAssertFalse(words.isEmpty)
        XCTAssertTrue(words.allSatisfy { $0.fontFamily == "serif" && $0.color == "#336699" })
        XCTAssertTrue(els.filter { $0.chartPart == "axis" }.allSatisfy { $0.fill?.color == "#33669966" })
        XCTAssertTrue(els.filter { $0.chartPart == "grid" }.allSatisfy { $0.fill?.color == "#33669933" })
        // Without them, the default face and the ink given.
        var bare = spec
        bare.font = nil
        bare.ink = nil
        XCTAssertTrue(made(bare).filter { $0.type == .text }.allSatisfy { $0.fontFamily == "sans" && $0.color == "#1f2430" })
    }

    func testTheStyleKeysAreWrittenOnlyWhenSetAndReadBack() throws {
        func keys(_ spec: ChartSpec) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(spec)) as? [String: Any]
            return Set(try XCTUnwrap(object).keys)
        }
        XCTAssertEqual(try keys(ChartSpec(id: "chart_t", kind: "line", data: "A, 1\nB, 2", textScale: 1)), ["id", "kind", "data"])
        let spec = ChartSpec(id: "chart_t", kind: "line", data: "A, 1\nB, 2", font: "serif", ink: "#336699",
                             textScale: 1.5, smooth: true, axisMin: 1, axisMax: 4)
        XCTAssertEqual(try keys(spec), ["id", "kind", "data", "font", "ink", "textScale", "smooth", "axisMin", "axisMax"])
        let el = try XCTUnwrap(made(spec).first)
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.chart, spec)
        // As the Android twin writes them, and read tolerantly: a blank font
        // and an ink that is no colour are none.
        let android = #"{"type":"text","chart":{"id":"chart_a","kind":"line","data":"A, 1","font":"","ink":"blue","textScale":0.5,"smooth":true,"axisMax":9}}"#
        let read = try XCTUnwrap(try JSONDecoder().decode(Element.self, from: Data(android.utf8)).chart)
        XCTAssertNil(read.font)
        XCTAssertNil(read.ink)
        XCTAssertEqual(read.textScale, 0.5)
        XCTAssertTrue(read.smooth)
        XCTAssertNil(read.axisMin)
        XCTAssertEqual(read.axisMax, 9)
    }

    func testAFontOrColourGivenToAChartsWordsByHandIsKeptForItsUpdate() throws {
        let spec = ChartSpec(id: "chart_t", kind: "column", data: "A, 10\nB, 5", legend: true)
        let els = made(spec)
        var design = Design(title: "chart", width: 1000, height: 1000)
        design.pages[0].elements = els
        let s = DesignStore(design: design)
        let label = try XCTUnwrap(els.first { $0.chartPart == "label" })
        s.selection = [label.id]
        s.updateSelected { $0.fontFamily = "serif"; $0.color = "#FF0000" }
        let kept = s.page.elements.compactMap(\.chart)
        XCTAssertEqual(kept.count, els.count)
        XCTAssertTrue(kept.allSatisfy { $0.font == "serif" && $0.ink == "#ff0000" })
        // Only the one label changed on the page; the next Update draws them all so.
        let remade = made(kept[0])
        XCTAssertTrue(remade.filter { $0.type == .text }.allSatisfy { $0.fontFamily == "serif" && $0.color == "#ff0000" })
        // One step, undone whole.
        s.undo()
        XCTAssertTrue(s.page.elements.allSatisfy { $0.chart == spec })
        // A step that leaves the words alone leaves the spec alone.
        s.selection = [label.id]
        s.updateSelected { $0.x += 5 }
        XCTAssertTrue(s.page.elements.allSatisfy { $0.chart == spec })
    }

    func testAnAxisEndIsReadAsTyped() {
        XCTAssertEqual(DataSheet.axisNumber(" 12.5 "), 12.5)
        XCTAssertEqual(DataSheet.axisNumber("1,5"), 1.5)
        XCTAssertNil(DataSheet.axisNumber(""))
        XCTAssertNil(DataSheet.axisNumber("lots"))
        XCTAssertEqual(DataSheet.axisText(20), "20")
        XCTAssertEqual(DataSheet.axisText(nil), "")
    }

    // MARK: Import CSV

    func testTheSharedCsvTable() {
        let table: [(text: String, cells: [[String]])] = [
            // CRLF rows, a last line break that ends no row.
            ("Name,Score\r\nAnn,5\r\nBob,7\r\n", [["Name", "Score"], ["Ann", "5"], ["Bob", "7"]]),
            // A byte-order mark is no part of the first cell.
            ("\u{FEFF}a,b\n1,2", [["a", "b"], ["1", "2"]]),
            // Quoted commas and doubled quotes.
            ("\"Smith, John\",\"He said \"\"hi\"\"\"\nx,y", [["Smith, John", "He said \"hi\""], ["x", "y"]]),
            // A quoted line break stays in its cell.
            ("\"two\nlines\",1", [["two\nlines", "1"]]),
            // A first line with a tab makes the file tab-separated.
            ("a\tb\n1\t2,5", [["a", "b"], ["1", "2,5"]]),
            // Blank lines are left out, short rows padded, spaces trimmed.
            ("a, b ,c\n\n1\n", [["a", "b", "c"], ["1", "", ""]]),
            // CR alone ends a row too; a quote inside a cell is a quote.
            ("a,b\rc,d\"e", [["a", "b"], ["c", "d\"e"]]),
            ("", []),
        ]
        for row in table {
            let read = DataGrid.fromCsv(row.text)
            XCTAssertEqual(read.cells, row.cells, row.text)
            XCTAssertNil(read.note, row.text)
        }
    }

    func testAnImportKeeps50RowsAnd12ColumnsAndSaysWhatItLeftOut() {
        func csv(_ rows: Int, _ columns: Int) -> String {
            (1...rows).map { r in (1...columns).map { c in "r\(r)c\(c)" }.joined(separator: ",") }.joined(separator: "\n")
        }
        let big = DataGrid.fromCsv(csv(212, 15))
        XCTAssertEqual(big.cells.count, 50)
        XCTAssertTrue(big.cells.allSatisfy { $0.count == 12 })
        XCTAssertEqual(big.cells[49][11], "r50c12")
        XCTAssertEqual(big.rows, 212)
        XCTAssertEqual(big.columns, 15)
        XCTAssertEqual(big.note, "Imported 50 of 212 rows and 12 of 15 columns")
        XCTAssertEqual(DataGrid.fromCsv(csv(212, 2)).note, "Imported 50 of 212 rows")
        XCTAssertEqual(DataGrid.fromCsv(csv(3, 20)).note, "Imported 12 of 20 columns")
        XCTAssertNil(DataGrid.fromCsv(csv(50, 12)).note)
        // What a chart and a table make of it: the grid's own text.
        let read = DataGrid.fromCsv("Quarter,North,South\nQ1,40,32\n\"Q2, late\",55,41").cells
        XCTAssertEqual(DataGrid.chartText(read), "Quarter, North, South\nQ1, 40, 32\nQ2 late, 55, 41")
        XCTAssertEqual(DataGrid.tableText(read), "Quarter\tNorth\tSouth\nQ1\t40\t32\nQ2, late\t55\t41")
    }

    func testAFileIsReadUpTo1MBAndOnlyWithRows() {
        XCTAssertEqual(DataGrid.read(csv: nil), .refused("That file could not be read"))
        XCTAssertEqual(DataGrid.read(csv: Data(repeating: 65, count: DataGrid.csvBytes + 1)), .refused("That file is over 1 MB"))
        XCTAssertEqual(DataGrid.read(csv: Data(" \n,\n".utf8)), .refused("No rows to import in that file"))
        XCTAssertEqual(DataGrid.read(csv: Data("a,1".utf8)), .rows(DataGrid.CsvImport(cells: [["a", "1"]], rows: 1, columns: 2)))
    }
}
