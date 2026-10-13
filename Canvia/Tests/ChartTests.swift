// Charts that stay editable: the typed data parsed into series, the layout
// of every kind at a fixed frame, and the `chart` and `chartPart` JSON. The
// parse and layout tables are the Android twin's ChartsTest, vector for
// vector — the same frame, every label 20 tall — so the same text makes the
// same chart on both phones.

import XCTest
@testable import Canvia

final class ChartDataTests: XCTestCase {

    private let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let palette = ["#ff0000", "#00ff00", "#0000ff"]

    private func spec(_ kind: DataGraphics.ChartKind, _ data: String, legend: Bool = false,
                      values: Bool = false, gridlines: Bool = false) -> ChartSpec {
        ChartSpec(id: "chart_t", kind: kind.rawValue, data: data, legend: legend, values: values, gridlines: gridlines)
    }

    private func made(_ spec: ChartSpec) -> [Element] {
        DataGraphics.chart(spec, in: frame, palette: palette, heightFor: { _ in 20 })
    }

    private func rect(_ el: Element) -> [Double] { [el.x, el.y, el.w, el.h] }

    // MARK: the shared parse table

    func testTheSharedParseTable() {
        let table: [(text: String, names: [String], labels: [String], values: [[Double]])] = [
            // One series, as ever: no number skips the line, a bare number is numbered by its line.
            ("Coffee, 42\nTea, 18%\njust words\n7", ["Series 1"], ["Coffee", "Tea", "Item 4"], [[42], [18], [7]]),
            // A header names the series.
            ("Quarter, North, South\nQ1, 40, 32\nQ2, 55, 41", ["North", "South"], ["Q1", "Q2"], [[40, 32], [55, 41]]),
            // A header over one series names it, and reads the rows as before.
            ("Month, Sales\nJan, 40\nFeb, 25", ["Sales"], ["Jan", "Feb"], [[40], [25]]),
            // Blank lines, before the header and between rows, are skipped.
            ("\n  \nQuarter, North, South\n\nQ1, 40, 32\n \nQ2, 55, 41\n", ["North", "South"], ["Q1", "Q2"], [[40, 32], [55, 41]]),
            // A cell that is no number reads as 0; a row with no number at all is skipped.
            ("Quarter, North, South\nQ1, n/a, 32\nQ2, -, -\nQ3, 12", ["North", "South"], ["Q1", "Q3"], [[0, 32], [12, 0]]),
            // A trailing comma is nothing on a header or a row of several series.
            ("Quarter, North, South,\nQ1, 40, 32,", ["North", "South"], ["Q1"], [[40, 32]]),
            // One series reads each line as it always did: "5," is no number after a label, a bare "7," is 7.
            ("A, 5,\nB, 6\n7,", ["Series 1"], ["B", "Item 3"], [[6], [7]]),
            // Several numbers with no header above them are no single value.
            ("Q1, 40, 32", ["Series 1"], [], []),
            // A blank series name is numbered; negatives count as zero; a blank label is numbered by its line.
            ("Team, , Away\n, -4, 7%", ["Series 1", "Away"], ["Item 2"], [[0, 7]]),
        ]
        for row in table {
            let data = DataGraphics.parseChart(row.text)
            XCTAssertEqual(data.names, row.names, row.text)
            XCTAssertEqual(data.rows.map(\.label), row.labels, row.text)
            XCTAssertEqual(data.rows.map(\.values), row.values, row.text)
        }
    }

    func testTheSingleSeriesReadingIsUnchanged() {
        let series = DataGraphics.parse("Spring, 40\nSummer,65%\n\nnothing here\n12\nWinter , -5")
        XCTAssertEqual(series.map(\.label), ["Spring", "Summer", "Item 5", "Winter"])
        XCTAssertEqual(series.map(\.value), [40, 65, 12, 0])
    }

    // MARK: the shared layout table, at (100, 100, 400 × 300), every label 20 tall

    func testTheSharedLayoutTableColumn() {
        let els = made(spec(.column, "A, 10\nB, 5"))
        XCTAssertEqual(els.count, 4)
        let bars = els.filter { $0.chartPart?.hasPrefix("series:") == true }
        XCTAssertEqual(rect(bars[0]), [136, 100, 128, 271])
        XCTAssertEqual(rect(bars[1]), [336, 236, 128, 136])
        XCTAssertEqual(els.map(\.chartPart), ["series:0", "label", "series:1", "label"])
    }

    func testTheSharedLayoutTableLineAsItAlwaysWas() {
        let els = made(spec(.line, "A, 10\nB, 5"))
        XCTAssertEqual(els.map(\.chartPart), ["series:0", "label", "label"])
        XCTAssertEqual(rect(els[0]), [100, 100, 400, 271])
        XCTAssertEqual(els[0].pathData, "M0 0 L100 50")
        XCTAssertEqual(els[0].stroke, "#ff0000")
        XCTAssertEqual(els[0].strokeWidth, 5)
        XCTAssertEqual(els.dropFirst().map(\.x), [0, 400])
    }

    func testTheSharedSummaryTable() {
        let table: [(text: String, kind: DataGraphics.ChartKind, words: String)] = [
            ("", .column, "No numbers found yet."),
            ("A, 1\nB, 2", .column, "2 values, coloured from this page."),
            ("A, 1", .pie, "1 value, coloured from this page."),
            ("Q, N, S\nQ1, 1, 2", .line, "1 row × 2 series, coloured from this page."),
            ("Score, 140", .progressRing, "The first value, as a percentage: 100%."),
            ("72.4", .progressBar, "The first value, as a percentage: 72%."),
        ]
        for row in table {
            XCTAssertEqual(DataGraphics.chartSummary(DataGraphics.parseChart(row.text), kind: row.kind), row.words, row.text)
        }
    }

    func testTheSharedLayoutTableColumnWithTwoSeriesLegendValuesAndGridlines() {
        let els = made(spec(.column, "Quarter, North, South\nQ1, 40, 20\nQ2, 30, 10", legend: true, values: true, gridlines: true))
        XCTAssertEqual(els.count, 19)
        let parts = els.map(\.chartPart)
        XCTAssertEqual(parts.filter { $0 == "grid" }.count, 5)
        XCTAssertEqual(parts.filter { $0 == "value" }.count, 4)
        XCTAssertEqual(parts.filter { $0 == "legend" }.count, 4)
        XCTAssertEqual(els.filter { $0.chartPart == "grid" }.map(\.y), [129, 182, 236, 289, 342])
        let bars = els.filter { $0.chartPart?.hasPrefix("series:") == true }
        XCTAssertEqual(rect(bars[0]), [136, 129, 64, 214])
        XCTAssertEqual(rect(bars[1]), [200, 236, 64, 107])
        XCTAssertEqual(rect(bars[2]), [336, 182, 64, 160])
        XCTAssertEqual(rect(bars[3]), [400, 289, 64, 53])
        // Coloured by series, not by row.
        XCTAssertEqual(bars.map(\.chartPart), ["series:0", "series:1", "series:0", "series:1"])
        XCTAssertEqual(bars.map { $0.fill?.color }, ["#ff0000", "#00ff00", "#ff0000", "#00ff00"])
        let swatches = els.filter { $0.chartPart == "legend" && $0.type == .shape }
        XCTAssertEqual(rect(swatches[0]), [100, 379, 14, 14])
        XCTAssertEqual(rect(swatches[1]), [300, 379, 14, 14])
        XCTAssertEqual(els.filter { $0.chartPart == "legend" && $0.type == .text }.map(\.text), ["North", "South"])
    }

    func testTheSharedLayoutTableStackedColumn() {
        let els = made(spec(.stackedColumn, "Quarter, North, South\nQ1, 40, 20\nQ2, 30, 10"))
        XCTAssertEqual(els.count, 6)
        let segments = els.filter { $0.type == .shape }
        XCTAssertEqual(rect(segments[0]), [136, 190, 128, 181])
        XCTAssertEqual(rect(segments[1]), [136, 100, 128, 90])
        XCTAssertEqual(rect(segments[2]), [336, 236, 128, 135])
        XCTAssertEqual(rect(segments[3]), [336, 190, 128, 46])
    }

    func testTheSharedLayoutTableProgressRing() {
        let els = made(spec(.progressRing, "72"))
        XCTAssertEqual(els.count, 3)
        XCTAssertEqual(els.map(\.chartPart), ["axis", "series:0", "value"])
        XCTAssertEqual(rect(els[0]), [150, 100, 300, 300])
        XCTAssertEqual(rect(els[1]), [150, 100, 300, 300])
        XCTAssertEqual(rect(els[2]), [150, 240, 300, 20])
        XCTAssertEqual(els[2].text, "72%")
        // Clamped to 0…100; nothing to fill at none.
        XCTAssertEqual(made(spec(.progressRing, "Score, 140")).last?.text, "100%")
        let none = made(spec(.progressRing, "-5"))
        XCTAssertEqual(none.count, 2)
        XCTAssertEqual(none.last?.text, "0%")
    }

    func testTheSharedLayoutTableProgressBar() {
        let els = made(spec(.progressBar, "72"))
        XCTAssertEqual(els.count, 3)
        XCTAssertEqual(rect(els[0]), [100, 236, 328, 29])
        XCTAssertEqual(rect(els[1]), [100, 236, 236, 29])
        XCTAssertEqual(rect(els[2]), [437, 240, 63, 20])
        XCTAssertEqual(els[2].text, "72%")
    }

    // MARK: the rest of the kinds

    func testEveryKindDrawsFromShapesAndTextAlone() {
        let data = "Quarter, North, South\nQ1, 40, 20\nQ2, 30, 10\nQ3, 50, 25"
        for kind in DataGraphics.ChartKind.allCases {
            let els = made(spec(kind, data, legend: true, values: true, gridlines: true))
            XCTAssertFalse(els.isEmpty, kind.rawValue)
            XCTAssertTrue(els.allSatisfy { $0.type == .shape || $0.type == .text }, kind.rawValue)
            XCTAssertTrue(els.allSatisfy { $0.chartPart != nil && $0.chart?.kind == kind.rawValue }, kind.rawValue)
            XCTAssertEqual(Set(els.compactMap(\.group)).count, 1, "\(kind.rawValue): one group")
        }
        // Lines and areas: one path per series; stacked bars: a segment per value.
        XCTAssertEqual(made(spec(.line, data)).filter { $0.type == .shape }.count, 2)
        XCTAssertEqual(made(spec(.area, data)).filter { $0.type == .shape }.count, 2)
        XCTAssertEqual(made(spec(.stackedBar, data)).filter { $0.type == .shape }.count, 6)
    }

    func testLegendValuesAndGridlinesAreOffUnlessAskedFor() {
        let plain = made(spec(.bar, "A, 3\nB, 4"))
        XCTAssertFalse(plain.contains { ["legend", "value", "grid"].contains($0.chartPart ?? "") })
        // A pie's legend names its slices, its values are shares.
        let pie = made(spec(.pie, "Yes, 3\nNo, 1", legend: true, values: true))
        XCTAssertEqual(pie.filter { $0.chartPart == "legend" && $0.type == .text }.map(\.text), ["Yes", "No"])
        XCTAssertEqual(pie.filter { $0.chartPart == "value" }.map(\.text), ["75%", "25%"])
    }

    func testDrawnIntoTheFrameThatFillsItsOwnBoxAChartStaysWhereItIs() {
        for kind in DataGraphics.ChartKind.allCases {
            let s = spec(kind, "Quarter, North, South\nQ1, 40, 20\nQ2, 30, 10\nQ3, 50, 25", legend: true)
            let bounds = Geometry.union(made(s).map(\.frame))
            let filling = DataGraphics.frameFilling(s, bounds: bounds, heightFor: { _ in 20 })
            let again = Geometry.union(DataGraphics.chart(s, in: filling, palette: palette, heightFor: { _ in 20 }).map(\.frame))
            XCTAssertEqual(again.minX, bounds.minX, accuracy: 2, kind.rawValue)
            XCTAssertEqual(again.minY, bounds.minY, accuracy: 2, kind.rawValue)
            XCTAssertEqual(again.width, bounds.width, accuracy: 2, kind.rawValue)
            XCTAssertEqual(again.height, bounds.height, accuracy: 2, kind.rawValue)
        }
    }

    func testTheKindsAreNamedAsOnAndroid() {
        XCTAssertEqual(DataGraphics.ChartKind.allCases.map(\.name),
                       ["Column", "Bar", "Line", "Pie", "Donut", "Stacked column", "Stacked bar", "Area",
                        "Progress ring", "Progress bar"])
        XCTAssertEqual(DataGraphics.ChartKind.allCases.map(\.rawValue),
                       ["column", "bar", "line", "pie", "donut", "stackedColumn", "stackedBar", "area",
                        "progressRing", "progressBar"])
    }

    // MARK: JSON

    func testEveryElementCarriesTheChartAndItsPart() throws {
        let spec = ChartSpec(kind: "column", data: "A, 1\nB, 2", legend: true)
        XCTAssertTrue(spec.id.hasPrefix("chart_"))
        let els = made(spec)
        XCTAssertTrue(els.allSatisfy { $0.chart == spec })
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(els[0]), encoding: .utf8))
        XCTAssertTrue(json.contains("\"chartPart\":\"series:0\""), json)
        XCTAssertTrue(json.contains("\"legend\":true"), json)
        XCTAssertFalse(json.contains("\"values\""), "a switch that is off is not written: \(json)")
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(els[0]))
        XCTAssertEqual(back.chart, spec)
        XCTAssertEqual(back.chartPart, "series:0")
    }

    func testTheChartObjectReadsTolerantly() throws {
        let android = #"{"type":"shape","chart":{"id":"chart_a","kind":"radar","data":"A, 1","legend":false,"values":true},"chartPart":"label"}"#
        let el = try JSONDecoder().decode(Element.self, from: Data(android.utf8))
        XCTAssertEqual(el.chart?.kind, "radar", "a kind this build does not know is kept")
        XCTAssertEqual(el.chart?.values, true)
        XCTAssertEqual(el.chart?.legend, false)
        XCTAssertEqual(el.chart?.gridlines, false)
        XCTAssertEqual(el.chartPart, "label")
        let kept = try XCTUnwrap(el.chart)
        XCTAssertTrue(made(kept).isEmpty, "and not drawn as some other kind")
        let again = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(again.chart, kept, "but written back as it was")
        let broken = #"{"type":"shape","chart":{"id":"chart_a","kind":"pie"}}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(broken.utf8)).chart, "no data, no chart")
        let old = #"{"type":"shape","group":"grp_1"}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(old.utf8)).chart)
    }
}
