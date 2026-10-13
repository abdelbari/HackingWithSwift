// Charts that stay editable: the typed data parsed into series, the layout
// of every kind at a fixed frame, and the `chart` and `chartPart` JSON — the
// same tables as the Android twin's.

import XCTest
@testable import Canvia

final class ChartDataTests: XCTestCase {

    private let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
    private let palette = ["#ff0000", "#00ff00", "#0000ff"]

    // MARK: parsing

    /// Non-numeric value cells read as 0; a line with no number at all is
    /// skipped. Empty cells at the end of a line — a trailing comma — are
    /// dropped.
    func testParseTable() {
        let rows: [(name: String, text: String, names: [String], labels: [String], values: [[Double]])] = [
            ("single series", "Spring, 40\nSummer, 65",
             ["Series 1"], ["Spring", "Summer"], [[40], [65]]),
            ("header row", "Quarter, North, South\nQ1, 40, 32\nQ2, 50, 41",
             ["North", "South"], ["Q1", "Q2"], [[40, 32], [50, 41]]),
            ("blank lines", "\nA, 1\n\n   \nB, 2\n",
             ["Series 1"], ["A", "B"], [[1], [2]]),
            ("non-numeric cells", "Quarter, North, South\nQ1, n/a, 32\nQ2, -, -\nQ3, 7, 8",
             ["North", "South"], ["Q1", "Q3"], [[0, 32], [7, 8]]),
            ("trailing comma", "A, 1,\nB, 2,",
             ["Series 1"], ["A", "B"], [[1], [2]]),
            ("trailing comma on the header", "Month, Sales,\nJan, 5,",
             ["Sales"], ["Jan"], [[5]]),
            ("a lone number, an empty label", "12\n, 7",
             ["Series 1"], ["Item 1", "Item 2"], [[12], [7]]),
            ("percent and below zero", "A, 50%\nB, -3",
             ["Series 1"], ["A", "B"], [[50], [0]]),
            ("a short row", "Q, N, S\nQ1, 4",
             ["N", "S"], ["Q1"], [[4, 0]]),
            ("no header", "Q1, 40, 32\nQ2, 50",
             ["Series 1", "Series 2"], ["Q1", "Q2"], [[40, 32], [50, 0]]),
            ("a header only", "Quarter, North, South",
             ["North", "South"], [], []),
            ("words first, one cell", "nothing here\nA, 3",
             ["Series 1"], ["A"], [[3]]),
        ]
        for row in rows {
            let data = DataGraphics.parseChart(row.text)
            XCTAssertEqual(data.names, row.names, row.name)
            XCTAssertEqual(data.rows.map(\.label), row.labels, row.name)
            XCTAssertEqual(data.rows.map(\.values), row.values, row.name)
        }
    }

    func testTheSingleSeriesReadingIsUnchanged() {
        let series = DataGraphics.parse("Spring, 40\nSummer,65%\n\nnothing here\n12\nWinter , -5")
        XCTAssertEqual(series.map(\.label), ["Spring", "Summer", "Item 5", "Winter"])
        XCTAssertEqual(series.map(\.value), [40, 65, 12, 0])
    }

    // MARK: layout

    private func chart(_ kind: DataGraphics.ChartKind, _ text: String, legend: Bool = false,
                       values: Bool = false, gridlines: Bool = false) -> [Element] {
        DataGraphics.chart(kind, data: DataGraphics.parseChart(text), in: frame, palette: palette,
                           legend: legend, values: values, gridlines: gridlines)
    }

    private func rects(_ els: [Element]) -> [[Double]] {
        els.filter { $0.chartPart?.hasPrefix("series:") == true }.map { [$0.x, $0.y, $0.w, $0.h] }
    }

    /// Element counts at the frame (100, 100, 600 × 400): marks, item
    /// labels, values, five gridlines, and a swatch and a name per legend
    /// entry.
    func testLayoutCountTable() {
        let single = "A, 10\nB, 20\nC, 5"
        let multi = "Q, N, S\nQ1, 30, 20\nQ2, 50, 30"
        let rows: [(name: String, kind: DataGraphics.ChartKind, text: String, all: Bool, count: Int)] = [
            ("column", .column, single, false, 6),
            ("column, every switch", .column, single, true, 20),
            ("column, two series", .column, multi, false, 6),
            ("column, two series, every switch", .column, multi, true, 19),
            ("stacked column", .stackedColumn, multi, false, 6),
            ("stacked column, every switch", .stackedColumn, multi, true, 19),
            ("stacked column, a zero", .stackedColumn, "Q, N, S\nQ1, 30, 0\nQ2, 50, 30", false, 5),
            ("bar", .bar, single, false, 6),
            ("stacked bar", .stackedBar, multi, false, 6),
            ("line, two series", .line, multi, false, 4),
            ("area, two series", .area, multi, false, 4),
            ("pie", .pie, single, false, 3),
            ("donut, every switch", .donut, single, true, 3 + 3 + 6),
            ("progress ring", .progressRing, "Done, 72", false, 3),
            ("progress ring at 0", .progressRing, "Done, 0", false, 2),
            ("progress ring, every switch", .progressRing, "Done, 72", true, 5),
            ("progress bar", .progressBar, "Done, 72", false, 3),
        ]
        for row in rows {
            let els = chart(row.kind, row.text, legend: row.all, values: row.all, gridlines: row.all)
            XCTAssertEqual(els.count, row.count, row.name)
        }
    }

    func testColumnRectangles() {
        XCTAssertEqual(rects(chart(.column, "A, 10\nB, 20\nC, 5")),
                       [[136, 281, 128, 181], [336, 100, 128, 362], [536, 371, 128, 90]])
        XCTAssertEqual(rects(chart(.column, "A, 10\nB, 20\nC, 5", legend: true, values: true, gridlines: true)),
                       [[136, 317, 128, 145], [336, 172, 128, 290], [536, 389, 128, 72]])
        let grouped = chart(.column, "Q, N, S\nQ1, 40, 32\nQ2, 50, 41")
        XCTAssertEqual(rects(grouped),
                       [[154, 172, 96, 289], [250, 230, 96, 231], [454, 100, 96, 362], [550, 165, 96, 297]])
        XCTAssertEqual(grouped.compactMap(\.chartPart), ["series:0", "series:1", "series:0", "series:1", "label", "label"])
        XCTAssertEqual(grouped.prefix(4).map { $0.fill?.color }, ["#ff0000", "#00ff00", "#ff0000", "#00ff00"],
                       "two series, a colour each")
    }

    func testStackedColumnRectangles() {
        let text = "Q, N, S\nQ1, 30, 20\nQ2, 50, 30"
        XCTAssertEqual(rects(chart(.stackedColumn, text)),
                       [[154, 326, 192, 136], [154, 236, 192, 90], [454, 236, 192, 226], [454, 100, 192, 136]])
        XCTAssertEqual(rects(chart(.stackedColumn, text, legend: true, values: true, gridlines: true)),
                       [[154, 340, 192, 122], [154, 260, 192, 80], [454, 260, 192, 202], [454, 138, 192, 122]])
    }

    func testProgressRing() {
        let ring = chart(.progressRing, "Done, 72")
        XCTAssertEqual(ring.map(\.chartPart), ["axis", "series:0", "value"])
        XCTAssertEqual(ring.prefix(2).map { [$0.x, $0.y, $0.w, $0.h] }, [[200, 100, 400, 400], [200, 100, 400, 400]])
        XCTAssertEqual(ring[2].text, "72%")
        let keyed = chart(.progressRing, "Done, 72", legend: true)
        XCTAssertEqual(keyed.filter { $0.chartPart == "series:0" }.map { [$0.x, $0.y, $0.w, $0.h] }, [[219, 138, 362, 362]])
        XCTAssertEqual(chart(.progressRing, "Done, 140").last?.text, "100%", "clamped to 100")
        XCTAssertEqual(chart(.progressRing, "Done, 72.6").last?.text, "73%")
        XCTAssertEqual(chart(.progressBar, "Done, 40").last?.text, "40%", "at the end of the bar")
    }

    func testEveryKindStaysInsideItsFrameWithEverySwitch() {
        for kind in DataGraphics.ChartKind.allCases {
            let els = chart(kind, "Q, N, S\nQ1, 30, 20\nQ2, 50, 30\nQ3, 10, 40", legend: true, values: true, gridlines: true)
            XCTAssertFalse(els.isEmpty, kind.rawValue)
            XCTAssertEqual(Set(els.compactMap(\.group)).count, 1, "\(kind.rawValue): one group")
            XCTAssertTrue(els.allSatisfy { $0.chartPart != nil }, "\(kind.rawValue): every element has a part")
            for e in els {
                XCTAssertTrue(frame.insetBy(dx: -2, dy: -2).contains(Geometry.aabb(e)),
                              "\(kind.rawValue): \(e.chartPart ?? "") leaves the frame: \(Geometry.aabb(e))")
            }
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
        let els = DataGraphics.chart(spec, in: frame, palette: palette)
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
        XCTAssertEqual(DataGraphics.chart(kept, in: frame, palette: palette).count, 3,
                       "and drawn as columns: a column, its label and its value")
        let broken = #"{"type":"shape","chart":{"id":"chart_a","kind":"pie"}}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(broken.utf8)).chart, "no data, no chart")
        let old = #"{"type":"shape","group":"grp_1"}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(old.utf8)).chart)
    }
}
