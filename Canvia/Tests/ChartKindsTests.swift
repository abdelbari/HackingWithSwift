// Round 31's charts: radar, bubble, funnel, pictogram, heat map and the
// progress dial, the format keys, and what a chart says to VoiceOver. The
// tables are the Android twin's ChartsTest, vector for vector — the same
// frame, every label 20 tall — so the same text makes the same chart on
// both phones.

import XCTest
@testable import Canvia

final class ChartKindsTests: XCTestCase {

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

    private func near(_ el: Element) -> [Double] { rect(el).map { ($0 * 1000).rounded() / 1000 } }

    private func series(_ els: [Element]) -> [Element] { els.filter { $0.chartPart?.hasPrefix("series:") == true } }

    // MARK: the new kinds

    func testTheNewKindsKeepTheirKeysLabelsAndOrder() {
        let kinds = Array(DataGraphics.ChartKind.allCases.dropFirst(11))
        XCTAssertEqual(kinds.map(\.rawValue), ["radar", "bubble", "funnel", "pictogram", "heatmap", "progressDial"])
        XCTAssertEqual(kinds.map(\.name), ["Radar", "Bubble", "Funnel", "Pictogram", "Heat map", "Progress dial"])
        XCTAssertEqual(kinds.filter(\.hasScale), [.radar, .bubble])
        XCTAssertTrue(DataGraphics.ChartKind.progressDial.isProgress)
        XCTAssertFalse(DataGraphics.ChartKind.heatmap.hasLegend)
    }

    func testTheSharedBubbleParseTable() {
        let data = DataGraphics.chartData("City, Size, Price, People\nA, 10, 20, 4\nB, 40, 5", kind: .bubble)
        XCTAssertEqual(data.names, ["Price"])
        XCTAssertEqual(data.rows.map(\.label), ["A", "B"])
        XCTAssertEqual(data.rows.map(\.values), [[10, 20, 4], [40, 5, 0]])
        XCTAssertEqual(DataGraphics.parseBubble("A, 1, 2, 3, 4, 5, 6").names, ["Series 1", "Series 2"])
    }

    func testTheSharedLayoutTableRadar() {
        let els = made(spec(.radar, "Skill, Ann, Bob\nA, 10, 5\nB, 5, 10\nC, 10, 10", gridlines: true))
        XCTAssertEqual(els.map(\.chartPart), ["grid", "grid", "grid", "grid", "series:0", "series:1", "label", "label", "label"])
        // Spokes from twelve o'clock in a box the plot's shorter side less a label's room each way.
        XCTAssertTrue(els.prefix(6).allSatisfy { rect($0) == [179, 129, 242, 242] })
        XCTAssertEqual(els[3].pathData, "M50 0 L93.3 75 L6.7 75 Z")
        XCTAssertEqual(els[4].pathData, "M50 0 L71.65 62.5 L6.7 75 Z")
        XCTAssertEqual(els[5].pathData, "M50 25 L93.3 75 L6.7 75 Z")
        XCTAssertEqual(els[4].opacity, 0.6)
        XCTAssertEqual(els[5].opacity, 0.6)
        XCTAssertEqual(els[4].stroke, "#ff0000")
        XCTAssertEqual(Array(near(els[6]).prefix(2)), [246, 104.4])
        XCTAssertEqual(els[4].altText, "Ann line, from 10 to 10")
    }

    func testTheSharedLayoutTableBubble() {
        let els = made(spec(.bubble, "A, 10, 20, 4\nB, 40, 5, 1"))
        XCTAssertEqual(els.map(\.chartPart), ["axis", "axis", "series:0", "series:0", "label", "label"])
        // The largest 15% of the plot's shorter side (271) across, the other by the root of its share.
        XCTAssertEqual(rect(els[2]), [180, 80, 41, 41])
        XCTAssertEqual(rect(els[3]), [490, 293, 21, 21])
        XCTAssertEqual(els[2].opacity, 0.75)
        XCTAssertEqual(els[2].altText, "A, Series 1: 10, 20, 4")
    }

    func testTheSharedLayoutTableFunnel() {
        let els = made(spec(.funnel, "Visits, 100\nLeads, 50\nSales, 20"))
        let stages = series(els)
        XCTAssertEqual(stages.map(rect), [[212, 105, 288, 90], [212, 205, 288, 90], [212, 305, 288, 90]])
        XCTAssertEqual(stages.map(\.pathData), ["M0 0 L100 0 L75 100 L25 100 Z", "M25 0 L75 0 L60 100 L40 100 Z",
                                                "M40 0 L60 0 L60 100 L40 100 Z"])
        XCTAssertEqual(stages.map(\.chartPart), ["series:0", "series:1", "series:2"])
        // Values inside, always; labels to the left.
        XCTAssertEqual(els.filter { $0.chartPart == "value" }.map(\.text), ["100", "50", "20"])
        XCTAssertEqual(els.filter { $0.chartPart == "label" }.map(\.text), ["Visits", "Leads", "Sales"])
        XCTAssertEqual(stages[1].altText, "Leads: 50")
    }

    func testTheSharedLayoutTablePictogram() throws {
        let els = made(spec(.pictogram, "A, 3.5\nB, 2"))
        let first = els.filter { $0.y == 162 && $0.type == .shape }
        // Ten icons a row, 26 square every 28.8 from x 212: three whole, a half, six faint.
        XCTAssertEqual(first.count, 11)
        XCTAssertEqual(first.prefix(6).map(\.x), [213, 242, 271, 300, 300, 329])
        XCTAssertEqual(first.prefix(6).map(\.chartPart), ["series:0", "series:0", "series:0", "axis", "series:0", "axis"])
        let person = try XCTUnwrap(IconLibrary.icon("person")).path
        XCTAssertEqual(first[0].pathData, person)
        XCTAssertEqual(first[4].pathData, DataGraphics.clippedPath(person, upTo: 50))
        XCTAssertEqual(first.filter { $0.chartPart == "series:0" }.count, 4)
        XCTAssertEqual(first.filter { $0.chartPart == "axis" }.count, 7)
        // Each icon is 1 while no value passes 10, else a tenth of the largest.
        XCTAssertEqual(series(made(spec(.pictogram, "A, 200\nB, 50"))).count, 10 + 3)
        // The icon is the chart's own when it names one.
        var star = spec(.pictogram, "A, 1")
        star.icon = "star"
        XCTAssertEqual(series(made(star)).first?.pathData, try XCTUnwrap(IconLibrary.icon("star")).path)
    }

    func testTheSharedLayoutTableHeatMap() {
        let els = made(spec(.heatmap, "Day, AM, PM\nMon, 0, 10\nTue, 5, 10"))
        let cells = els.filter { $0.chartPart == "series:0" }
        XCTAssertEqual(cells.map(rect), [[213, 130, 142, 134], [357, 130, 142, 134], [213, 265, 142, 134], [357, 265, 142, 134]])
        // Series 0's colour, from 15% for the least to 100% for the most.
        XCTAssertEqual(cells.map(\.opacity), [0.15, 1, 0.575, 1])
        XCTAssertTrue(cells.allSatisfy { $0.fill?.color == "#ff0000" })
        XCTAssertEqual(els.filter { $0.chartPart == "label" }.map(\.text), ["AM", "PM", "Mon", "Tue"])
        XCTAssertEqual(cells[2].altText, "Tue, AM: 5")
        // No legend: its shades are its key.
        XCTAssertFalse(made(spec(.heatmap, "Day, AM, PM\nMon, 0, 10", legend: true)).contains { $0.chartPart == "legend" })
    }

    func testTheSharedLayoutTableProgressDial() {
        let els = made(spec(.progressDial, "72"))
        XCTAssertEqual(els.map(\.chartPart), ["axis", "series:0", "value"])
        XCTAssertEqual(rect(els[0]), [150, 100, 300, 300])
        // A 240° arc from the lower left, 72% of it filled.
        XCTAssertEqual(els[0].pathData, "M15.36 70 L6.7 75 A50 50 0 1 1 93.3 75 L84.64 70 A40 40 0 1 0 15.36 70 Z")
        XCTAssertEqual(els[1].pathData, "M15.36 70 L6.7 75 A50 50 0 0 1 89.83 19.77 L81.86 25.82 A40 40 0 0 0 15.36 70 Z")
        XCTAssertEqual(els[2].text, "72%")
        XCTAssertEqual(DataGraphics.chartSummary(DataGraphics.parseChart("72"), kind: .progressDial),
                       DataGraphics.chartSummary(DataGraphics.parseChart("72"), kind: .progressRing))
    }

    func testTheNewKindsSummaryTable() {
        let table: [(text: String, kind: DataGraphics.ChartKind, words: String)] = [
            ("A, 1, 2, 3\nB, 4, 5, 6", .bubble, "2 bubbles, coloured from this page."),
            ("Visits, 100\nLeads, 50", .funnel, "2 stages, in the order typed."),
            ("A, 3", .pictogram, "1 row of up to 10 icons."),
            ("Day, AM, PM\nMon, 0, 10", .heatmap, "1 row × 2 series, shaded by value."),
            ("Skill, Ann, Bob\nA, 1, 2", .radar, "1 row × 2 series, coloured from this page."),
        ]
        for row in table {
            XCTAssertEqual(DataGraphics.chartSummary(DataGraphics.chartData(row.text, kind: row.kind), kind: row.kind),
                           row.words, row.text)
        }
    }

    func testAPictogramsPartIconIsItsIconCutAtTheShare() {
        XCTAssertEqual(DataGraphics.clippedPath("M0 0 L100 0 L100 100 L0 100 Z", upTo: 50), "M0 0 L50 0 L50 100 L0 100 Z")
        // A piece wholly past the cut goes; one wholly before stays.
        XCTAssertEqual(DataGraphics.clippedPath("M0 0 L10 0 L10 10 Z M60 0 L70 0 L70 10 Z", upTo: 50), "M0 0 L10 0 L10 10 Z")
        // A curve is flattened to eight steps.
        XCTAssertEqual(DataGraphics.clippedPath("M0 0 C0 50 50 50 50 0 Z", upTo: 100).components(separatedBy: " L").count, 9)
    }

    // MARK: format

    func testTheSharedFormatTable() {
        let base = spec(.column, "A, 1")
        func with(_ change: (inout ChartSpec) -> Void) -> ChartSpec {
            var s = base
            change(&s)
            return s
        }
        let table: [(ChartSpec, [(Double, String)])] = [
            (base, [(1234.5, "1234.5"), (40, "40"), (0.004, "0")]),
            (with { $0.prefix = "$" }, [(1234.5, "$1234.5"), (-5, "-$5")]),
            (with { $0.suffix = "%"; $0.decimals = 1 }, [(12, "12.0%"), (0.25, "0.3%"), (-0.01, "0.0%")]),
            (with { $0.decimals = 2 }, [(1234567.891, "1,234,567.89"), (2.675, "2.67"), (999.995, "1,000.00")]),
            (with { $0.decimals = 0 }, [(1500.5, "1,501"), (0.5, "1"), (999, "999")]),
            (with { $0.compact = true }, [(999, "999"), (1200, "1.2k"), (1000, "1k"), (3_450_000, "3.5M"), (2e9, "2B"),
                                          (7.25e12, "7.3T"), (12.5, "12.5")]),
            (with { $0.compact = true; $0.decimals = 2; $0.prefix = "€" }, [(1234, "€1.23k"), (5, "€5.00")]),
            (with { $0.prefix = "$"; $0.decimals = 0 }, [(1e14, "$1e14"), (.infinity, "∞")]),
        ]
        let was = DataGraphics.grouping
        DataGraphics.grouping = { "," }
        defer { DataGraphics.grouping = was }
        for (s, cases) in table {
            for (v, text) in cases { XCTAssertEqual(DataGraphics.formatValue(v, s), text, "\(v)") }
        }
        // The grouping follows the app's language; the point stays a ".".
        DataGraphics.grouping = { "." }
        XCTAssertEqual(DataGraphics.formatValue(1234567.8, with { $0.decimals = 1 }), "1.234.567.8")
        XCTAssertEqual(DataGraphics.groupingSeparator(for: "de"), ".")
        XCTAssertEqual(DataGraphics.groupingSeparator(for: "en"), ",")
    }

    func testTheFormatKeysAreWrittenOnlyWhenSetAndReadBack() throws {
        func keys(_ spec: ChartSpec) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(spec)) as? [String: Any]
            return Set(try XCTUnwrap(object).keys)
        }
        var s = spec(.column, "A, 1")
        s.prefix = "$"; s.suffix = "pts"; s.decimals = 2; s.compact = true; s.xTitle = "Month"; s.yTitle = "Sales"
        s.gap = 0.5; s.roundBars = true; s.lineWidth = 6; s.points = true; s.hole = 0.4; s.icon = "star"
        XCTAssertEqual(try keys(s), ["id", "kind", "data", "prefix", "suffix", "decimals", "compact", "xTitle", "yTitle",
                                     "hole", "gap", "roundBars", "lineWidth", "points", "icon"])
        let el = try XCTUnwrap(made(s).first)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el)).chart, s)
        // Defaults are not written: none, the bar gap's own, the person icon.
        var plain = spec(.column, "A, 1")
        plain.gap = DataGraphics.defaultGap
        plain.icon = "person"
        XCTAssertEqual(try keys(plain), ["id", "kind", "data"])
        // Read within their ranges: 4 characters, 0…3 places, 0.3…0.85, 0…0.8, 1…12.
        let android = #"{"id":"c","kind":"donut","data":"1","prefix":"USD $","decimals":7,"hole":0.95,"gap":2,"lineWidth":40}"#
        let read = try JSONDecoder().decode(ChartSpec.self, from: Data(android.utf8))
        XCTAssertEqual(read.prefix, "USD ")
        XCTAssertEqual(read.decimals, 3)
        XCTAssertEqual(read.hole, 0.85)
        XCTAssertEqual(read.gap, 0.8)
        XCTAssertEqual(read.lineWidth, 12)
    }

    func testTheSharedLayoutTableTitlesGapAndRoundBars() {
        var s = spec(.column, "A, 10\nB, 5")
        s.xTitle = "Month"; s.yTitle = "Sales"; s.roundBars = true; s.gap = 0.5
        let els = made(s)
        let bars = series(els)
        // The plot starts after the y title's strip (28.8) and stops above the x title's.
        XCTAssertEqual(bars.map(rect), [[175, 100, 93, 242], [361, 221, 93, 121]])
        XCTAssertEqual(bars[0].corners, [23.25, 23.25, 0, 0])
        let titles = els.filter { $0.chartPart == "axisTitle" }
        XCTAssertEqual(titles.map(\.text), ["Month", "Sales"])
        XCTAssertEqual(near(titles[0]), [128.8, 375.6, 371.2, 20])
        XCTAssertEqual(near(titles[1]), [-21.2, 225.6, 271.2, 20])
        XCTAssertEqual(titles.map(\.rotation), [0, -90])
        // A turned chart is turned as a whole, its y title a quarter further.
        XCTAssertEqual(DataGraphics.turn(of: els), 0)
        let box = Geometry.union(els.map(\.frame))
        let turned = Geometry.rotate(els, around: CGPoint(x: box.midX, y: box.midY), by: 30)
        XCTAssertEqual(DataGraphics.turn(of: turned), 30, accuracy: 1e-9)
        // A kind with no axes has no titles.
        var pie = spec(.pie, "A, 1")
        pie.xTitle = "x"; pie.yTitle = "y"
        XCTAssertFalse(made(pie).contains { $0.chartPart == "axisTitle" })
        // Stacked: only each stack's top segment is rounded.
        var stacked = spec(.stackedColumn, "Q, N, S\nA, 4, 6")
        stacked.roundBars = true
        XCTAssertEqual(made(stacked).filter { $0.type == .shape }.map { $0.corners != nil }, [false, true])
    }

    func testTheSharedLayoutTableHoleLineWeightAndPoints() {
        var donut = spec(.donut, "A, 1")
        donut.hole = 0.3
        XCTAssertTrue(made(donut)[0].pathData?.contains("A15 15") == true)
        XCTAssertEqual(DataGraphics.hole(of: spec(.progressRing, "1")), DataGraphics.ringHole)
        XCTAssertEqual(DataGraphics.hole(of: spec(.donut, "1")), DataGraphics.donutHole)
        // A weight of 6 on a frame 300 short is 6; 12 on one 150 short, 6.
        var line = spec(.line, "A, 10\nB, 5")
        line.lineWidth = 6
        line.points = true
        let els = made(line)
        XCTAssertEqual(els[0].strokeWidth, 6)
        var twelve = spec(.line, "1")
        twelve.lineWidth = 12
        XCTAssertEqual(DataGraphics.lineWeight(twelve, frame: CGRect(x: 0, y: 0, width: 400, height: 150), fallback: 2), 6)
        // Dots two and a half times the weight across, on each point.
        let dots = els.filter { $0.shapeId == "circle" }
        XCTAssertEqual(dots.map(rect), [[93, 93, 15, 15], [493, 228, 15, 15]])
        XCTAssertEqual(dots.map(\.altText), ["A, Series 1: 10", "B, Series 1: 5"])
    }

    func testTheFormatSurvivesAnEditOfTheChartsWords() throws {
        var s = spec(.column, "A, 1")
        s.prefix = "$"
        s.roundBars = true
        let els = made(s)
        var before = Design(title: "chart", width: 1000, height: 1000)
        before.pages[0].elements = els
        var after = before
        let label = try XCTUnwrap(els.firstIndex { $0.type == .text })
        after.pages[0].elements[label].fontFamily = "serif"
        let kept = try XCTUnwrap(DataGraphics.styleKept(after, since: before).pages[0].elements[0].chart)
        XCTAssertEqual(kept.font, "serif")
        XCTAssertEqual(kept.prefix, "$")
        XCTAssertTrue(kept.roundBars)
    }

    // MARK: what VoiceOver says

    func testChartSpeechSummaryAndPartLabels() {
        let s = spec(.column, "Quarter, North, South, East\nQ1, 0, 20, 5\nQ2, 84, 30, 120\nQ3, 40, 10, 5\nQ4, 1, 2, 3")
        let data = DataGraphics.parseChart(s.data)
        XCTAssertEqual(ChartSpeech.summary(s, data: data), "Column chart, 3 series, 4 categories, values 0 to 120")
        XCTAssertEqual(ChartSpeech.partLabel(s, data: data, part: "series:0", index: 1), "Q2, North: 84")
        XCTAssertNil(ChartSpeech.partLabel(s, data: data, part: "label", index: 1))
        let line = spec(.line, "Month, Sales\nJan, 40\nFeb, 70\nMar, 96")
        XCTAssertEqual(ChartSpeech.partLabel(line, data: DataGraphics.parseChart(line.data), part: "series:0", index: -1),
                       "Sales line, from 40 to 96")
        let pie = spec(.pie, "Yes, 3\nNo, 1")
        XCTAssertEqual(ChartSpeech.partLabel(pie, data: DataGraphics.parseChart(pie.data), part: "series:0", index: 0), "Yes: 75%")
        XCTAssertEqual(ChartSpeech.summary(spec(.progressRing, "72"), data: DataGraphics.parseChart("72")), "Progress ring chart, 72%")
        // Every series part of every kind says what it is; the reader steps through them in order.
        let all = "Quarter, North, South\nQ1, 40, 20\nQ2, 30, 10"
        for kind in DataGraphics.ChartKind.allCases {
            let els = made(spec(kind, all))
            let parts = series(els)
            XCTAssertTrue(!parts.isEmpty && parts.allSatisfy { !($0.altText ?? "").isEmpty }, kind.rawValue)
            XCTAssertEqual(ChartSpeech.stops(els).count, parts.count, kind.rawValue)
            // Any part of a chart is named by its chart's summary.
            XCTAssertEqual(ElementNames.name(of: els[0]),
                           ChartSpeech.summary(spec(kind, all), data: DataGraphics.chartData(all, kind: kind)), kind.rawValue)
        }
    }
}
