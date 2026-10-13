// Edit chart: which selections offer it, and Update — the chart drawn again
// from its new data in the box it filled, at its place in the stack, under
// its group, with its series colours, as one step. Copies are charts of
// their own.

import XCTest
@testable import Canvia

@MainActor
final class ChartEditingTests: XCTestCase {

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "chart", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    private let frame = CGRect(x: 100, y: 100, width: 600, height: 400)

    func testUpdateReplacesTheChartInPlaceAsOneStep() throws {
        let spec = ChartSpec(kind: "column", data: "Q, N, S\nQ1, 30, 20\nQ2, 50, 30")
        var chart = DataGraphics.chart(spec, in: frame, palette: ["#ff0000", "#00ff00"])
        // A series coloured by hand.
        let south = try XCTUnwrap(chart.firstIndex { $0.chartPart == "series:1" })
        chart[south].fill = .solid("#123456")
        let below = Element.shape("rect"), above = Element.shape("circle")
        let s = store([below] + chart + [above])
        let group = chart[0].group
        let box = Geometry.union(chart.map(Geometry.aabb))

        s.select(chart[0].id)
        XCTAssertEqual(s.selectedChart, spec, "a member selects the chart")
        var edited = spec
        edited.kind = "stackedColumn"
        edited.data = "Q, N, S\nQ1, 30, 20\nQ2, 50, 30\nQ3, 10, 10"
        edited.values = true
        XCTAssertTrue(s.updateChart(edited))

        let elements = s.page.elements
        XCTAssertEqual(elements.first?.id, below.id)
        XCTAssertEqual(elements.last?.id, above.id, "at the place of the lowest member")
        let made = Array(elements.dropFirst().dropLast())
        XCTAssertTrue(made.allSatisfy { $0.chart == edited })
        XCTAssertTrue(made.allSatisfy { $0.group == group }, "the group id kept")
        XCTAssertEqual(made.filter { $0.chartPart == "series:0" }.count, 3)
        XCTAssertTrue(made.filter { $0.chartPart == "series:1" }.allSatisfy { $0.fill?.color == "#123456" },
                      "the hand-set colour carries over by series")
        let after = Geometry.union(made.filter { $0.type == .shape }.map(Geometry.aabb))
        XCTAssertTrue(box.insetBy(dx: -1, dy: -1).contains(after), "drawn into the box the chart filled")
        XCTAssertEqual(s.selection, Set(made.map(\.id)))

        s.undo()
        XCTAssertEqual(s.page.elements.map(\.id), ([below] + chart + [above]).map(\.id), "one step")
    }

    func testOnlyAChartWithItsDataOffersEditChart() {
        // A chart from before charts were kept: a plain group.
        var a = Element.shape("rect"), b = Element.shape("rect")
        a.group = "grp_old"; b.group = "grp_old"
        let spec = ChartSpec(kind: "pie", data: "A, 1\nB, 2")
        var chart = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        let s = store([a, b] + chart)
        s.select(a.id)
        XCTAssertNil(s.selectedChart)
        s.select(chart[0].id)
        XCTAssertEqual(s.selectedChart?.id, spec.id)
        // Two charts at once are not one chart to edit.
        let other = DataGraphics.chart(ChartSpec(kind: "pie", data: "C, 3"), in: frame, palette: ["#ff0000"])
        s.applyToPage { $0.elements += other }
        s.selection = [chart[0].id, other[0].id]
        XCTAssertNil(s.selectedChart)
        // Nor is a locked one.
        chart[0].locked = true
        s.applyToPage { $0.elements[2] = chart[0] }
        s.selection = [chart[0].id]
        XCTAssertNil(s.selectedChart)
    }

    func testACopyOfAChartIsAChartOfItsOwn() {
        let spec = ChartSpec(kind: "column", data: "A, 1\nB, 2")
        let chart = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        let copies = Copies.of(chart, offset: 24)
        let ids = Set(copies.compactMap { $0.chart?.id })
        XCTAssertEqual(ids.count, 1, "the copies share one chart")
        XCTAssertNotEqual(ids.first, spec.id, "and it is not the original's")
        XCTAssertEqual(copies[0].chart?.data, spec.data)
    }

    func testSeriesPartsNameTheirNumber() {
        XCTAssertEqual(DesignStore.chartSeries("series:2"), 2)
        XCTAssertNil(DesignStore.chartSeries("label"))
        XCTAssertNil(DesignStore.chartSeries(nil))
        var line = Element.shape("rect")
        line.fill = .solid("#00000000"); line.stroke = "#abcdef"; line.strokeWidth = 4
        XCTAssertEqual(DesignStore.chartColour(of: line), .solid("#abcdef"), "a line's colour is its stroke")
    }
}
