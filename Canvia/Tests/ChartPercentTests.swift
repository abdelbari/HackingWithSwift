// Round 34's chart labels: values read as a share (labelAs), 100% stacked
// columns and bars, and the legend along the top or down the right. The
// label and normalisation rows are the shared fixture chart-percent.json,
// read by the Android twin too.

import XCTest
@testable import Canvia

final class ChartPercentTests: XCTestCase {

    private let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
    private let palette = ["#ff0000", "#00ff00", "#0000ff"]

    private func spec(_ kind: DataGraphics.ChartKind, _ data: String, legend: Bool = false,
                      values: Bool = false, labelAs: String? = nil, legendAt: String? = nil) -> ChartSpec {
        var s = ChartSpec(id: "chart_t", kind: kind.rawValue, data: data, legend: legend, values: values)
        s.labelAs = labelAs
        s.legendAt = legendAt
        return s
    }

    private func made(_ spec: ChartSpec) -> [Element] {
        DataGraphics.chart(spec, in: frame, palette: palette, heightFor: { _ in 20 })
    }

    private func series(_ els: [Element]) -> [Element] { els.filter { $0.chartPart?.hasPrefix("series:") == true } }

    // MARK: the shared rows

    func testTheSharedLabelRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("chart-percent")["labels"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let kind = try XCTUnwrap(row["kind"] as? String)
            var s = ChartSpec(id: "chart_t", kind: kind, data: "")
            s.labelAs = row["labelAs"] as? String
            s.prefix = row["prefix"] as? String
            s.decimals = (row["decimals"] as? NSNumber)?.intValue
            let value = try XCTUnwrap((row["value"] as? NSNumber)?.doubleValue)
            let share = try XCTUnwrap((row["share"] as? NSNumber)?.doubleValue)
            XCTAssertEqual(DataGraphics.labelText(value, share: share, s), row["text"] as? String, "\(row)")
        }
    }

    func testTheSharedNormalisationRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("chart-percent")["normalised"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let stack = try XCTUnwrap(row["stack"] as? [NSNumber]).map(\.doubleValue)
            let out = try XCTUnwrap(row["out"] as? [NSNumber]).map(\.doubleValue)
            let got = DataGraphics.normalisedStack(stack)
            XCTAssertEqual(got.count, out.count, "\(stack)")
            for (a, b) in zip(got, out) { XCTAssertEqual(a, b, accuracy: 1e-9, "\(stack)") }
        }
    }

    // MARK: the kinds

    func testTheHundredKindsAreNamedStackedAndPartToWhole() {
        XCTAssertEqual(DataGraphics.ChartKind.stackedColumn100.name, "100% stacked column")
        XCTAssertEqual(DataGraphics.ChartKind.stackedBar100.name, "100% stacked bar")
        let partToWhole = DataGraphics.ChartKind.allCases.filter(\.isPartToWhole).map(\.rawValue)
        XCTAssertEqual(partToWhole, ["pie", "donut", "stackedColumn", "stackedBar", "funnel", "pictogram",
                                     "stackedColumn100", "stackedBar100"])
        XCTAssertTrue(DataGraphics.ChartKind.stackedBar100.hasBars)
        XCTAssertTrue(DataGraphics.ChartKind.stackedColumn100.hasScale)
    }

    func testEachStackFillsTheScaleWithItsGridlinesAlwaysOn() {
        let els = made(spec(.stackedColumn100, "Q, N, S\nA, 1, 3\nB, 2, 2"))
        // Gridlines at quarters though none were asked for.
        XCTAssertEqual(els.filter { $0.chartPart == "grid" }.count, 5)
        let segments = series(els)
        XCTAssertEqual(segments.count, 4)
        // Both stacks run the whole plot, from the same top to the same foot.
        let a = segments.prefix(2), b = segments.suffix(2)
        XCTAssertEqual(a.map(\.h).reduce(0, +), b.map(\.h).reduce(0, +), accuracy: 1)
        XCTAssertEqual(a.map(\.y).min(), b.map(\.y).min())
        // 1 of 4 is a quarter of the stack, 3 of 4 three quarters.
        XCTAssertEqual(a.first!.h * 3, a.last!.h, accuracy: 2)
        let bars = series(made(spec(.stackedBar100, "Q, N, S\nA, 1, 3\nB, 2, 2")))
        XCTAssertEqual(bars.prefix(2).map(\.w).reduce(0, +), bars.suffix(2).map(\.w).reduce(0, +), accuracy: 1)
    }

    func testStacksLabelEachSegmentWithItsShareOrTheirTotal() {
        let data = "Q, N, S\nA, 1, 3\nB, 2, 2"
        let shares = made(spec(.stackedColumn100, data, values: true, labelAs: "percent"))
        XCTAssertEqual(shares.filter { $0.chartPart == "value" }.map(\.text), ["25%", "75%", "50%", "50%"])
        // Each share sits inside its segment.
        let segments = series(shares)
        for (label, segment) in zip(shares.filter { $0.chartPart == "value" }, segments) {
            XCTAssertEqual(label.center.y, segment.center.y, accuracy: 1)
        }
        let both = made(spec(.stackedColumn, data, values: true, labelAs: "both"))
        XCTAssertEqual(both.filter { $0.chartPart == "value" }.map(\.text), ["1 (25%)", "3 (75%)", "2 (50%)", "2 (50%)"])
        // As values, a stack writes its total above it; a 100% one each
        // value in its segment, as on the Android twin.
        let totals = made(spec(.stackedColumn, data, values: true))
        XCTAssertEqual(totals.filter { $0.chartPart == "value" }.map(\.text), ["4", "4"])
        let full = made(spec(.stackedBar100, "Q, N, S\nA, 10, 30", values: true))
        XCTAssertEqual(full.filter { $0.chartPart == "value" }.map(\.text), ["10", "30"])
        // A value below 0 draws nothing and counts for nothing in the shares.
        let odd = made(spec(.stackedColumn100, "Q, N, S, T\nA, 2, -1, 2", values: true, labelAs: "percent"))
        XCTAssertEqual(odd.filter { $0.chartPart == "value" }.map(\.text), ["50%", "50%"])
    }

    func testAHundredStackLabelsItsScaleFromNoneToAll() {
        let column = made(spec(.stackedColumn100, "Q, N, S\nA, 1, 3\nB, 10, 10"))
        XCTAssertEqual(column.filter { $0.chartPart == "axis" }.map(\.text), ["100%", "75%", "50%", "25%", "0%"])
        let bar = made(spec(.stackedBar100, "Q, N, S\nA, 10, 30", values: true))
        XCTAssertEqual(bar.filter { $0.chartPart == "axis" }.map(\.text), ["0%", "25%", "50%", "75%", "100%"])
        // The columns stand right of the scale.
        let left = column.filter { $0.chartPart == "axis" }.map { $0.x + $0.w }.max() ?? 0
        XCTAssertTrue(series(column).allSatisfy { $0.x >= left })
    }

    func testAHundredStacksXTitleSitsBelowItsScaleAcrossTheWholePlot() {
        // The scale takes its strip off the plot without moving the axis
        // titles: under a bar's ticks, centred under a column's whole
        // width. The Android twin's ChartPercentTest, row for row.
        for kind in [DataGraphics.ChartKind.stackedBar100, .stackedColumn100] {
            var s = spec(kind, "Q, N, S\nA, 10, 30")
            s.xTitle = "Share"
            let els = made(s)
            let titles = els.filter { $0.chartPart == "axisTitle" }
            XCTAssertEqual(titles.count, 1)
            guard let title = titles.first else { continue }
            let ticks = els.filter { $0.chartPart == "axis" }
            XCTAssertEqual(ticks.count, 5)
            XCTAssertTrue(ticks.allSatisfy { title.y >= $0.y + $0.h - 1e-9 }, "\(kind)")
            XCTAssertEqual(title.x, 100, accuracy: 1e-9)
            XCTAssertEqual(title.w, 400, accuracy: 1e-9)
        }
    }

    func testTheSharedJsonRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("chart-percent")["json"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            var s = ChartSpec(id: "chart_t", kind: try XCTUnwrap(row["kind"] as? String), data: "A, 1")
            s.labelAs = row["labelAs"] as? String
            s.legendAt = row["legendAt"] as? String
            let data = try JSONEncoder().encode(s)
            let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let writes = try XCTUnwrap(row["writes"] as? [String: Any])
            XCTAssertEqual(written["labelAs"] as? String, writes["labelAs"] as? String, "\(row)")
            XCTAssertEqual(written["legendAt"] as? String, writes["legendAt"] as? String, "\(row)")
            // And it reads back saying the same.
            let back = try JSONDecoder().decode(ChartSpec.self, from: data)
            XCTAssertEqual(DataGraphics.labelAs(back), DataGraphics.labelAs(s), "\(row)")
        }
    }

    func testAPieReadsItsShareUnlessItsLabelsSayOtherwise() {
        let data = "Yes, 3\nNo, 1"
        XCTAssertEqual(made(spec(.pie, data, values: true)).filter { $0.chartPart == "value" }.map(\.text), ["75%", "25%"])
        XCTAssertEqual(made(spec(.pie, data, values: true, labelAs: "value")).filter { $0.chartPart == "value" }.map(\.text),
                       ["3", "1"])
        XCTAssertEqual(made(spec(.donut, data, values: true, labelAs: "both")).filter { $0.chartPart == "value" }.map(\.text),
                       ["3 (75%)", "1 (25%)"])
        XCTAssertEqual(made(spec(.funnel, data, labelAs: "percent")).filter { $0.chartPart == "value" }.map(\.text),
                       ["75%", "25%"])
    }

    func testTheReaderSaysWhatTheLabelsSay() {
        let pie = spec(.pie, "Yes, 3\nNo, 1", labelAs: "value")
        XCTAssertEqual(ChartSpeech.partLabel(pie, data: DataGraphics.parseChart(pie.data), part: "series:0", index: 0), "Yes: 3")
        let stack = spec(.stackedColumn100, "Q, N, S\nA, 1, 3", labelAs: "percent")
        XCTAssertEqual(ChartSpeech.partLabel(stack, data: DataGraphics.parseChart(stack.data), part: "series:0", index: 0),
                       "A, N: 25%")
        let plain = spec(.stackedColumn, "Q, N, S\nA, 1, 3")
        XCTAssertEqual(ChartSpeech.partLabel(plain, data: DataGraphics.parseChart(plain.data), part: "series:1", index: 0),
                       "A, S: 3")
    }

    // MARK: the legend

    func testALegendAlongTheTopOrDownTheRight() {
        let data = "Quarter, North, South\nQ1, 40, 20\nQ2, 30, 10"
        let top = made(spec(.column, data, legend: true, legendAt: "top"))
        let swatches = top.filter { $0.chartPart == "legend" && $0.type == .shape }
        XCTAssertEqual(swatches.map(\.y), [107, 107])
        // The plot sits under it.
        XCTAssertTrue(series(top).allSatisfy { $0.y >= 100 + 28.8 - 0.5 })
        let right = made(spec(.column, data, legend: true, legendAt: "right"))
        let stacked = right.filter { $0.chartPart == "legend" && $0.type == .shape }
        // 28% of the width, the entries one under another.
        XCTAssertEqual(stacked.map(\.x), [397, 397])
        XCTAssertEqual(stacked[1].y - stacked[0].y, 28.8, accuracy: 1)
        XCTAssertTrue(series(right).allSatisfy { $0.x + $0.w <= 500 - 112 + 0.5 })
    }

    // MARK: JSON

    func testTheKeysAreWrittenOnlyWhenSetAndReadLeniently() throws {
        var s = spec(.pie, "A, 1", labelAs: "both", legendAt: "right")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(s), encoding: .utf8))
        XCTAssertTrue(json.contains("\"labelAs\":\"both\""), json)
        XCTAssertTrue(json.contains("\"legendAt\":\"right\""), json)
        XCTAssertEqual(try JSONDecoder().decode(ChartSpec.self, from: Data(json.utf8)), s)
        s.labelAs = nil
        s.legendAt = "bottom"
        let plain = try XCTUnwrap(String(data: JSONEncoder().encode(s), encoding: .utf8))
        XCTAssertFalse(plain.contains("labelAs"), plain)
        XCTAssertFalse(plain.contains("legendAt"), plain)
        let odd = #"{"id":"c","kind":"pie","data":"A, 1","labelAs":"fraction","legendAt":"middle"}"#
        let read = try JSONDecoder().decode(ChartSpec.self, from: Data(odd.utf8))
        XCTAssertNil(read.labelAs)
        XCTAssertNil(read.legendAt)
    }
}
