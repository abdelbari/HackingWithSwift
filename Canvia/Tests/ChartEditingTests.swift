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
        XCTAssertTrue(box.insetBy(dx: -2, dy: -2).contains(after), "drawn into the box the chart filled")
        XCTAssertEqual(s.selection, Set(made.map(\.id)))

        s.undo()
        XCTAssertEqual(s.page.elements.map(\.id), ([below] + chart + [above]).map(\.id), "one step")
    }

    func testUpdateSelectsTheWholeGroupAsAndroidDoes() {
        let spec = ChartSpec(kind: "column", data: "A, 10\nB, 5")
        let chart = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        var title = Element.text("Sales")
        title.group = chart[0].group
        let other = Element.shape("rect")
        let s = store([other] + chart + [title])
        var edited = spec
        edited.kind = "bar"
        edited.data = "A, 10\nB, 5\nC, 7"
        XCTAssertTrue(s.updateChart(edited))
        let made = s.page.elements.filter { $0.chart == edited }
        XCTAssertEqual(s.selection, Set(made.map(\.id) + [title.id]), "the title grouped with it too")
    }

    /// A chart never fills its frame to the edge, so drawn again into the
    /// box it left it would shrink at every Update; it is drawn into the
    /// frame that fills that box instead.
    func testUpdatingWithNoChangeKeepsTheChartsBox() {
        for spec in [ChartSpec(kind: "bar", data: "A, 10\nB, 20\nC, 5\nD, 15"),
                     ChartSpec(kind: "progressBar", data: "72"),
                     ChartSpec(kind: "line", data: "Q, N, S\nQ1, 30, 20\nQ2, 50, 30", legend: true, values: true)] {
            let chart = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
            let s = store(chart)
            let box = Geometry.union(chart.map(Geometry.aabb))
            XCTAssertTrue(s.updateChart(spec), spec.kind)
            let after = Geometry.union(s.page.elements.map(Geometry.aabb))
            XCTAssertEqual(after.minX, box.minX, accuracy: 2, spec.kind)
            XCTAssertEqual(after.minY, box.minY, accuracy: 2, spec.kind)
            XCTAssertEqual(after.width, box.width, accuracy: 2, spec.kind)
            XCTAssertEqual(after.height, box.height, accuracy: 2, spec.kind)
        }
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
        // A locked one still offers Edit chart, which says how to unlock it.
        XCTAssertFalse(s.chartIsLocked(spec.id))
        chart[1].locked = true
        s.applyToPage { $0.elements[3] = chart[1] }
        s.selection = [chart[0].id]
        XCTAssertEqual(s.selectedChart?.id, spec.id)
        XCTAssertTrue(s.chartIsLocked(spec.id))
        // A kind from a newer build is kept as it is, not edited as another.
        var radar = Element.shape("rect")
        radar.chart = ChartSpec(kind: "radar", data: "A, 1")
        s.applyToPage { $0.elements.append(radar) }
        s.select(radar.id)
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

    func testAChartHiddenWholeStaysHiddenThroughUpdate() {
        let spec = ChartSpec(kind: "column", data: "A, 10\nB, 5")
        var edited = spec
        edited.kind = "bar"
        edited.data = "A, 10\nB, 5\nC, 7"
        var hidden = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        for i in hidden.indices { hidden[i].hidden = true }
        let s = store(hidden)
        XCTAssertTrue(s.updateChart(edited))
        XCTAssertTrue(s.page.elements.allSatisfy(\.isHidden), "hidden whole, it stays hidden")

        var partly = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        partly[0].hidden = true
        let t = store(partly)
        XCTAssertTrue(t.updateChart(edited))
        XCTAssertFalse(t.page.elements.contains(where: \.isHidden), "partly hidden, it comes back whole")
    }

    func testAChartAndATableCopiedTogetherAreEachOneOfTheirOwn() throws {
        let spec = ChartSpec(kind: "column", data: "A, 10\nB, 5")
        let chart = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        let table = DataGraphics.table(DataGraphics.parseTable("Item, Qty\nCoffee, 2"), in: frame, accent: "#ff0000",
                                       heightFor: { _ in 20 })
        let tableId = try XCTUnwrap(table.first?.table?.id)
        let copies = Copies.of(chart + table, offset: 24)
        let copiedChart = Array(copies.prefix(chart.count))
        let copiedTable = Array(copies.dropFirst(chart.count))
        let chartIds = Set(copiedChart.compactMap { $0.chart?.id })
        XCTAssertEqual(chartIds.count, 1)
        XCTAssertNotEqual(chartIds.first, spec.id)
        XCTAssertTrue(copiedChart.allSatisfy { $0.chart != nil })
        let tableIds = Set(copiedTable.compactMap { $0.table?.id })
        XCTAssertEqual(tableIds.count, 1)
        XCTAssertNotEqual(tableIds.first, tableId)
        XCTAssertEqual(copiedTable.filter { $0.table != nil }.count, table.count)
        XCTAssertTrue(copiedTable.allSatisfy { $0.chart == nil })
    }
}
