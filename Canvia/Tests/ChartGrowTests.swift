// A chart growing in — bars rising, slices sweeping, lines drawing on —
// and read as data: the shared timing table, the sweep of a slice, Grow
// picked on a chart, Check accessibility's chart colours and the PDF's one
// figure a chart. The rows are the Android twin's ElementAnimationTest,
// AccessibilityAuditTest and PdfMetadataTest.

import XCTest
@testable import Canvia

final class ChartGrowTests: XCTestCase {

    private func chart(_ kind: DataGraphics.ChartKind, _ data: String, values: Bool = false) -> [Element] {
        DataGraphics.chart(ChartSpec(id: "chart_g", kind: kind.rawValue, data: data, values: values),
                           in: CGRect(x: 0, y: 0, width: 400, height: 300), palette: ["#ff0000", "#00ff00"],
                           heightFor: { _ in 20 })
    }

    private func part(_ els: [Element], _ name: String) -> Element {
        els.first { $0.chartPart == name } ?? Element()
    }

    func testGrowTheSharedTimingTable() {
        let grow = ElementAnimation(kind: ElementAnimation.grow, delay: 0, duration: 1)
        let columns = chart(.column, "Q, N, S\nA, 4, 2", values: true)
        let first = part(columns, "series:0")
        let second = part(columns, "series:1")
        let value = part(columns, "value")
        // Series 0 from the delay, eased as progress eases: 1 - (1 - 0.5)^3.
        let a = grow.state(at: 0.5, el: first)
        XCTAssertEqual([a.scaleX, a.scaleY, a.anchorX, a.anchorY], [1, 0.875, 0.5, 1])
        // Series 1 starts 0.08 s later and is in by the same end.
        XCTAssertEqual(grow.state(at: 0.5, el: second).scaleY, 1 - pow(1 - 0.42 / 0.92, 3), accuracy: 1e-9)
        XCTAssertEqual(grow.state(at: 0, el: second).scaleY, 0)
        // Labels and values fade in over the last 30%.
        XCTAssertEqual([0, 0.7, 0.85].map { (grow.state(at: $0, el: value).opacity * 1e9).rounded() / 1e9 }, [0, 0, 0.5])
        for el in columns { XCTAssertEqual(grow.state(at: 1, el: el), .settled) }
        // Bars from their left end; slices and rings sweep; lines draw on; points pop.
        let bar = grow.state(at: 0.5, el: part(chart(.bar, "A, 4"), "series:0"))
        XCTAssertEqual([bar.scaleX, bar.scaleY, bar.anchorX], [0.875, 1, 0])
        XCTAssertEqual(grow.state(at: 0.5, el: part(chart(.pie, "A, 1\nB, 1"), "series:0")).sweep, 0.875, accuracy: 1e-9)
        XCTAssertEqual(grow.state(at: 0.5, el: part(chart(.line, "A, 1\nB, 3"), "series:0")).reveal, 0.875, accuracy: 1e-9)
        let dot = grow.state(at: 0.5, el: part(chart(.scatter, "A, 1, 2"), "series:0"))
        XCTAssertEqual([dot.opacity, dot.scale], [1, 0.4 + 0.6 * 0.875])
        // Gridlines and axes fade in over the whole; anything not a chart fades in.
        XCTAssertEqual(grow.state(at: 0.5, el: part(chart(.scatter, "A, 1, 2"), "axis")).opacity, 0.875, accuracy: 1e-9)
        let fade = ElementAnimation(kind: "fade", delay: 0, duration: 1).state(at: 0.5)
        XCTAssertEqual(grow.state(at: 0.5, el: Element.text("Hi")), fade)
        XCTAssertEqual(grow.state(at: 0.5), fade)
        XCTAssertEqual(ElementAnimation.name(ElementAnimation.grow), "Grow")
        XCTAssertEqual(ElementAnimation.kinds.first, ElementAnimation.grow)
    }

    func testGrowASliceIsDrawnToTheShareOfItsSweepReached() {
        let slices = chart(.donut, "A, 1\nB, 3").filter { $0.chartPart?.hasPrefix("series:") == true }
        XCTAssertEqual(DataGraphics.swept(slices[1], share: 0.5).pathData,
                       DataGraphics.wedge(from: -Double.pi / 2 + Double.pi / 2, sweep: 2 * Double.pi * 0.75 * 0.5,
                                          inner: DataGraphics.donutHole))
        XCTAssertEqual(DataGraphics.swept(slices[1], share: 1), slices[1])
        let dial = part(chart(.progressDial, "50"), "series:0")
        XCTAssertEqual(DataGraphics.swept(dial, share: 0.5).pathData,
                       DataGraphics.wedge(from: Double.pi * 5 / 6, sweep: Double.pi * 4 / 3 * 0.5 * 0.5, inner: DataGraphics.ringHole))
    }

    func testGrowPickedOnAChartGivesEveryPartOneDelayAndDuration() throws {
        let parts = chart(.column, "A, 4\nB, 2")
        let text = Element.text("After")
        let applied = ElementAnimation.applied(parts + [text], kind: ElementAnimation.grow)
        XCTAssertTrue(applied.dropLast().allSatisfy {
            $0.animation == ElementAnimation(kind: ElementAnimation.grow, delay: 0, duration: ElementAnimation.growDuration)
        })
        XCTAssertEqual(applied.last?.animation?.delay, 0.15)
        XCTAssertTrue(ElementAnimation.canGrow(parts))
        XCTAssertFalse(ElementAnimation.canGrow([text]))
        // Kept in the file as {kind, delay, duration}.
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(applied[0]), encoding: .utf8))
        XCTAssertTrue(json.contains(#""kind":"grow""#), json)
        // Other kinds as they always were: 0.15 s apart, 0.6 s each.
        let faded = ElementAnimation.applied(parts, kind: "fade")
        XCTAssertEqual(faded.map { $0.animation?.delay ?? -1 }, parts.indices.map { Double($0) * 0.15 })
    }

    func testAChartGrowsInThroughTheTimelineTheCanvasPresentAndVideoRead() {
        var bar = part(chart(.column, "A, 4"), "series:0")
        bar.animation = ElementAnimation(kind: ElementAnimation.grow, delay: 0, duration: 1)
        let state = Timeline.motion(of: bar, time: 0.5, hold: 5, exitTime: nil, text: nil)
        XCTAssertEqual(state.scaleY, 0.875, accuracy: 1e-9)
        XCTAssertFalse(state.showsNothing)
        XCTAssertTrue(Timeline.motion(of: bar, time: 0, hold: 5, exitTime: nil, text: nil).showsNothing)
    }

    // MARK: read as data

    private func design(_ elements: [Element]) -> Design {
        var d = Design(title: "Chart", width: 1080, height: 1080)
        d.pages = [Page(background: .color("#ffffff"), elements: elements)]
        return d
    }

    private func audited(_ kind: DataGraphics.ChartKind, legend: Bool = false, values: Bool = false) -> [Element] {
        DataGraphics.chart(ChartSpec(kind: kind.rawValue, data: "Q, N, S\nA, 1, 2\nB, 3, 4", legend: legend, values: values),
                           in: CGRect(x: 100, y: 100, width: 400, height: 300), palette: ["#ff0000", "#0000ff"],
                           heightFor: { _ in 20 })
    }

    func testAChartWhoseColoursAloneTellItsSeriesApartIsFoundOnce() {
        let bare = audited(.column)
        let found = AccessibilityAudit.findings(design(bare)).filter { $0.kind == .chartColours }
        XCTAssertEqual(found.map(\.elementId), [bare.first?.id])
        XCTAssertEqual(found.first?.message, "Chart colours carry meaning")
        for said in [audited(.column, legend: true), audited(.pie, values: true), audited(.progressRing), audited(.funnel)] {
            XCTAssertFalse(AccessibilityAudit.findings(design(said)).contains { $0.kind == .chartColours })
        }
        // A kind this build does not know (a newer build's) is not judged.
        let unknown = bare.map { el -> Element in
            var out = el
            out.chart?.kind = "hologram"
            return out
        }
        XCTAssertFalse(AccessibilityAudit.findings(design(unknown)).contains { $0.kind == .chartColours })
    }

    func testAChartIsOneFigureItsSummaryItsAltText() {
        let made = DataGraphics.chart(ChartSpec(id: "chart_p", kind: "column", data: "Q, N, S\nA, 1, 2\nB, 3, 4"),
                                      in: CGRect(x: 100, y: 100, width: 400, height: 300), palette: ["#ff0000", "#0000ff"],
                                      heightFor: { _ in 20 })
        let d = design(made)
        let figures = PDFMetadata.figures(d, page: d.pages[0])
        XCTAssertEqual(figures.map(\.alt), ["Column chart, 2 series, 2 categories, values 1 to 4"])
        let box = Geometry.union(made.map { Geometry.aabb($0) })
        XCTAssertEqual(figures.first.map { [$0.x, $0.y, $0.w, $0.h] }, [box.minX, box.minY, box.width, box.height])
    }

    func testVoiceOverMeetsAChartAsOneStopThatStepsThroughItsValues() {
        let made = audited(.column)
        let order = CanvasAccessibility.readingOrder(made, pageHeight: 1080)
        let stops = CanvasAccessibility.chartStops(made, order: order)
        XCTAssertEqual(stops.heads.count, 1)
        XCTAssertEqual(stops.heads.count + stops.hidden.count, made.count)
        let head = made.first { stops.heads.contains($0.id) } ?? Element()
        XCTAssertEqual(CanvasAccessibility.label(for: head, on: made), "Column chart, 2 series, 2 categories, values 1 to 4")
        let id = head.chart?.id ?? ""
        XCTAssertEqual(CanvasAccessibility.values(ofChart: id, in: made), ["A, N: 1", "A, S: 2", "B, N: 3", "B, S: 4"])
        XCTAssertEqual(CanvasAccessibility.steppedValue(nil, count: 4, forward: true), 0)
        XCTAssertEqual(CanvasAccessibility.steppedValue(nil, count: 4, forward: false), 3)
        XCTAssertEqual(CanvasAccessibility.steppedValue(3, count: 4, forward: true), 3)
        XCTAssertEqual(CanvasAccessibility.steppedValue(1, count: 4, forward: false), 0)
        XCTAssertNil(CanvasAccessibility.steppedValue(nil, count: 0, forward: true))
    }
}
