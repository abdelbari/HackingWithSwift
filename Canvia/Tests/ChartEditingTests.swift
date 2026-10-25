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

    /// The Android twin's "Update keeps a chart grouped inside a group,
    /// and that group's turn": the chart stays its own level, and Update
    /// selects that level, not the heading beside it.
    func testUpdateKeepsAChartGroupedInsideAGroupAndThatGroupsTurn() throws {
        let spec = ChartSpec(kind: "column", data: "A, 10\nB, 5")
        var chart = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        let inner = try XCTUnwrap(chart.first?.group)
        for i in chart.indices {
            chart[i].group = "outer"
            chart[i].subgroups = [inner]
            chart[i].groupTurn = 30
        }
        var title = Element.text("Sales")
        title.group = "outer"
        title.groupTurn = 30
        let s = store(chart + [title])
        var edited = spec
        edited.data = "A, 10\nB, 5\nC, 7"
        XCTAssertTrue(s.updateChart(edited))
        let made = s.page.elements.filter { $0.chart == edited }
        XCTAssertFalse(made.isEmpty)
        XCTAssertTrue(made.allSatisfy { Groups.chain($0) == ["outer", inner] && $0.groupTurn == 30 })
        XCTAssertEqual(s.selection, Set(made.map(\.id)), "the chart's own level")
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
        var sankey = Element.shape("rect")
        sankey.chart = ChartSpec(kind: "sankey", data: "A, 1")
        s.applyToPage { $0.elements.append(sankey) }
        s.select(sankey.id)
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

    func testAnUpdatesPaletteKeepsEachSeriesPlaceAndGivesTheRestColoursTheChartDoesNotShow() {
        let p = ["#aa0000", "#00aa00", "#0000aa", "#aaaa00"]
        XCTAssertEqual(DataGraphics.keepingPalette(p, colours: [0: .solid("#00aa00")]),
                       ["#00aa00", "#aa0000", "#0000aa", "#aaaa00"])
        XCTAssertEqual(DataGraphics.keepingPalette(p, colours: [0: .solid("#aa0000"), 2: .solid("#0000aa")]),
                       ["#aa0000", "#00aa00", "#0000aa", "#aaaa00"])
        XCTAssertEqual(DataGraphics.keepingPalette(p, colours: [:]), p)
        var all: [Int: Paint] = [:]
        for (i, c) in p.enumerated() { all[i] = .solid(c) }
        XCTAssertEqual(DataGraphics.keepingPalette(p, colours: all), p)
    }

    func testARowAddedOnUpdateTakesTheColourANewChartGivesItNotOneTheChartShows() {
        let blank = store([])
        let fresh = DataGraphics.palette(for: blank.design, page: blank.page)
        let spec = ChartSpec(kind: "column", data: "Spring, 40\nSummer, 65\nAutumn, 30\nWinter, 20")
        let chart = DataGraphics.chart(spec, in: frame, palette: fresh)
        let s = store(chart)
        var colours: [Int: Paint] = [:]
        for el in chart {
            guard let n = DesignStore.chartSeries(el.chartPart), colours[n] == nil,
                  let paint = DesignStore.chartColour(of: el) else { continue }
            colours[n] = paint
        }
        XCTAssertEqual(DataGraphics.palette(updating: spec.id, design: s.design, page: s.page, colours: colours, brand: nil), fresh,
                       "its own bars and labels are not the design's colours")
        var five = spec
        five.data = "Spring, 40\nSummer, 65\nAutumn, 30\nWinter, 20\nMore, 50"
        XCTAssertTrue(s.updateChart(five))
        let elements = s.page.elements
        func colour(_ n: Int) -> String {
            elements.first { $0.chartPart == "series:\(n)" }?.fill?.color ?? ""
        }
        XCTAssertEqual(colour(4), "#f9ed69")
        XCTAssertEqual((0...3).map(colour), Array(fresh.prefix(4)))
    }

    func testAProgressBarMadeAnotherKindOnUpdateStaysOnThePage() {
        let bar = ChartSpec(kind: "progressBar", data: "72")
        let twenty: (Element) -> Double = { _ in 20 }
        let made = DataGraphics.chart(bar, in: CGRect(x: 108, y: -300, width: 864, height: 1152), palette: ["#ff0000"],
                                      heightFor: twenty)
        let bounds = Geometry.union(made.map(\.frame))
        let filling = DataGraphics.frameFilling(bar, bounds: bounds, heightFor: twenty)
        XCTAssertLessThan(filling.minY, 0)
        // The same kind is drawn where it was, in the frame it was drawn in.
        XCTAssertEqual(DataGraphics.updateFrame(bar, to: bar, bounds: bounds, width: 1080, height: 1920, heightFor: twenty),
                       filling)
        var column = bar
        column.kind = "column"
        XCTAssertEqual(DataGraphics.updateFrame(bar, to: column, bounds: bounds, width: 1080, height: 1920, heightFor: twenty),
                       CGRect(x: filling.minX, y: 0, width: filling.width, height: filling.height))
        // Kept to a page smaller than the frame.
        var pie = bar
        pie.kind = "pie"
        XCTAssertEqual(DataGraphics.updateFrame(bar, to: pie, bounds: bounds, width: 500, height: 400, heightFor: twenty),
                       CGRect(x: 0, y: 0, width: 500, height: 400))
    }

    func testUpdateLeavesAChartTurnedFadedLinkedAnimatedAndTimedAsItWas() {
        let spec = ChartSpec(kind: "column", data: "A, 10\nB, 5")
        let upright = DataGraphics.chart(spec, in: frame, palette: ["#ff0000"])
        let box = Geometry.union(upright.map(\.frame))
        let enter = ElementAnimation(kind: "rise", delay: 0, duration: 0.6)
        let turned = Geometry.rotate(upright, around: CGPoint(x: box.midX, y: box.midY), by: 30).map { el -> Element in
            var out = el
            out.opacity = 0.5
            out.link = "https://example.com"
            out.animation = enter
            out.timing = ElementTiming(start: 0, end: 2)
            return out
        }
        let s = store(turned)
        XCTAssertTrue(s.updateChart(spec))
        let made = s.page.elements
        XCTAssertEqual(made.count, turned.count)
        XCTAssertTrue(made.allSatisfy { $0.rotation == 30 && $0.opacity == 0.5 })
        XCTAssertTrue(made.allSatisfy { $0.link == "https://example.com" && $0.animation == enter })
        XCTAssertTrue(made.allSatisfy { $0.timing == ElementTiming(start: 0, end: 2) })
        // Where it was, mark for mark.
        for (a, b) in zip(turned, made) {
            XCTAssertEqual(a.x, b.x, accuracy: 2)
            XCTAssertEqual(a.y, b.y, accuracy: 2)
            XCTAssertEqual(a.w, b.w, accuracy: 2)
            XCTAssertEqual(a.h, b.h, accuracy: 2)
        }
        // Parts turned differently are no turn of the whole.
        XCTAssertEqual(DataGraphics.turn(of: [turned[0], upright[1]]), 0)
        XCTAssertEqual(DataGraphics.turn(of: turned), 30)
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
