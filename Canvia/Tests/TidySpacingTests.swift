// Round 32's spacing after Tidy up, with the rows the Android twin's tests
// hold too: which selections read as a tidied row, column or grid and at
// what gap (Geometry.tidyLayout), how they are laid out again at another,
// and the store's Spacing step.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class TidySpacingTests: XCTestCase {

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        return el
    }

    private func layout(_ elements: [Element]) -> Geometry.TidyLayout? {
        Geometry.tidyLayout(elements)
    }

    func testTheLayoutRows() {
        // (boxes as x, y, w, h) -> mode and gap, or none.
        typealias Row = ([(Double, Double, Double, Double)], Geometry.TidyMode?, Double)
        let rows: [Row] = [
            ([(0, 0, 100, 100), (124, 0, 100, 100), (248, 0, 100, 100)], .row, 24),
            // Level by their middles, whatever their heights.
            ([(0, 0, 100, 100), (130, 25, 100, 50)], .row, 30),
            ([(0, 0, 100, 100), (0, 120, 100, 100), (0, 240, 100, 100)], .column, 20),
            ([(0, 0, 100, 100), (110, 0, 100, 100), (0, 110, 100, 100), (110, 110, 100, 100)], .grid, 10),
            // Five: three across, then two.
            ([(0, 0, 100, 100), (110, 0, 100, 100), (220, 0, 100, 100), (0, 110, 100, 100), (110, 110, 100, 100)], .grid, 10),
            // Within half a unit.
            ([(0, 0, 100, 100), (124, 0, 100, 100), (248.4, 0.3, 100, 100)], .row, 24),
            // Touching: a gap of 0.
            ([(0, 0, 100, 100), (100, 0, 100, 100)], .row, 0),
            // Gaps that differ, overlapping, out of line, one alone: none.
            ([(0, 0, 100, 100), (124, 0, 100, 100), (260, 0, 100, 100)], nil, 0),
            ([(0, 0, 100, 100), (90, 0, 100, 100)], nil, 0),
            ([(0, 0, 100, 100), (130, 5, 100, 100)], nil, 0),
            ([(0, 0, 100, 100)], nil, 0),
            // Four in a grid with gaps across and down that differ.
            ([(0, 0, 100, 100), (110, 0, 100, 100), (0, 130, 100, 100), (110, 130, 100, 100)], nil, 0),
        ]
        for (n, row) in rows.enumerated() {
            let elements = row.0.enumerated().map { i, b in box("e\(i)", x: b.0, y: b.1, w: b.2, h: b.3) }
            let found = layout(elements)
            XCTAssertEqual(found?.mode, row.1, "row \(n)")
            if let found, row.1 != nil { XCTAssertEqual(found.gap, row.2, accuracy: 0.5, "row \(n)") }
        }
        XCTAssertEqual(Geometry.tidyTolerance, 0.5)

        // Android's TidySpacingTest row: gaps of 20 and 20.4 are within half
        // a unit, and the gap is their mean.
        let near = [box("a", x: 0, y: 0, w: 100, h: 50), box("b", x: 120, y: 0, w: 100, h: 50),
                    box("c", x: 240.4, y: 0, w: 100, h: 50)]
        XCTAssertEqual(layout(near)?.mode, .row)
        XCTAssertEqual(layout(near)?.gap ?? 0, 20.2, accuracy: 1e-9)
        XCTAssertNil(layout([box("a", x: 0, y: 0, w: 100, h: 50), box("b", x: 120, y: 0, w: 100, h: 50),
                             box("c", x: 241, y: 0, w: 100, h: 50)]))
    }

    func testTidyUpIsRecognisedAtItsGap() {
        let messy = [box("a", x: 300, y: 40, w: 80, h: 60), box("b", x: 0, y: 0, w: 120, h: 90),
                     box("c", x: 150, y: 200, w: 60, h: 60), box("d", x: 500, y: 300, w: 100, h: 40)]
        for mode in [Geometry.TidyMode.row, .column, .grid] {
            let tidied = Geometry.tidy(messy, mode: mode, gap: 22)
            XCTAssertEqual(layout(tidied), Geometry.TidyLayout(mode: mode, gap: 22), "\(mode)")
        }
    }

    func testRespacingKeepsTheFirstPlaceAndEveryGapEqual() {
        let row = [box("a", x: 0, y: 0), box("b", x: 124, y: 0), box("c", x: 248, y: 0)]
        let wider = Geometry.respaced(row, gap: 40)
        XCTAssertEqual(wider?.map(\.x), [0, 140, 280])
        XCTAssertEqual(wider.flatMap(layout), Geometry.TidyLayout(mode: .row, gap: 40))
        XCTAssertEqual(Geometry.respaced(row, gap: -5)?.map(\.x), [0, 100, 200], "never under 0")

        let column = [box("a", x: 50, y: 10), box("b", x: 50, y: 130)]
        XCTAssertEqual(Geometry.respaced(column, gap: 0)?.map(\.y), [10, 110])

        let grid = [box("a", x: 0, y: 0), box("b", x: 110, y: 0), box("c", x: 0, y: 110), box("d", x: 110, y: 110)]
        let spaced = Geometry.respaced(grid, gap: 30)
        XCTAssertEqual(spaced?.map(\.x), [0, 130, 0, 130])
        XCTAssertEqual(spaced?.map(\.y), [0, 0, 130, 130])

        XCTAssertNil(Geometry.respaced([box("a", x: 0, y: 0), box("b", x: 124, y: 0), box("c", x: 260, y: 0)], gap: 10))
    }

    func testTheGapHandlesSitInTheMiddleOfEachGap() {
        let row = [box("b", x: 124, y: 0), box("a", x: 0, y: 0), box("c", x: 248, y: 0)]
        XCTAssertEqual(Geometry.tidyGapHandles(row), [CGPoint(x: 112, y: 50), CGPoint(x: 236, y: 50)])
        let column = [box("a", x: 0, y: 0), box("b", x: 0, y: 120)]
        XCTAssertEqual(Geometry.tidyGapHandles(column), [CGPoint(x: 50, y: 110)])
        let grid = [box("a", x: 0, y: 0), box("b", x: 110, y: 0), box("c", x: 0, y: 110), box("d", x: 110, y: 110)]
        XCTAssertEqual(Geometry.tidyGapHandles(grid), [], "a grid has the slider only")
    }

    func testTheSliderRunsToAQuarterOfTheShorterSide() {
        XCTAssertEqual(Geometry.tidySpacingRange(page: CGSize(width: 1080, height: 1920)), 0...270)
        XCTAssertEqual(Geometry.defaultTidyGap(page: CGSize(width: 1080, height: 1920)), 22)
    }

    // MARK: the store

    func testSpacingIsOneStepNamedSpacing() {
        var d = Design(title: "tidy", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: [box("a", x: 0, y: 0), box("b", x: 300, y: 40), box("c", x: 600, y: 10)])]
        let s = DesignStore(design: d)
        s.selection = ["a", "b", "c"]
        XCTAssertNil(s.tidyLayout)
        s.tidySelected(.row)
        XCTAssertEqual(s.tidyLayout, Geometry.TidyLayout(mode: .row, gap: 22), "today's default gap")
        s.tidySelected(.row, gap: 40)
        XCTAssertEqual(s.tidyLayout?.gap ?? 0, 40, accuracy: 0.001)

        s.setTidySpacingLive(10)
        s.setTidySpacingLive(16)
        s.commitSpacing()
        XCTAssertEqual(s.tidyLayout?.gap ?? 0, 16, accuracy: 0.001)
        XCTAssertEqual(s.undoLabel, "Spacing")
        s.undo()
        XCTAssertEqual(s.tidyLayout?.gap ?? 0, 40, accuracy: 0.001, "the whole drag was one step")
    }

    /// Android's TidySpacingTest row: one held in place among a tidied row
    /// is left out of Spacing.
    func testOneHeldInPlaceAmongATidiedRowIsLeftOutOfSpacing() {
        var held = box("d", x: 600, y: 500)
        held.lockPosition = true
        var d = Design(title: "tidy", width: 1080, height: 1080)
        d.pages = [Page(id: "p1", elements: [box("a", x: 0, y: 0), box("b", x: 124, y: 0), box("c", x: 248, y: 0), held])]
        let s = DesignStore(design: d)
        s.selection = ["a", "b", "c", "d"]
        XCTAssertEqual(s.tidyLayout, Geometry.TidyLayout(mode: .row, gap: 24))
        s.setTidySpacingLive(40)
        s.commitSpacing()
        XCTAssertEqual(s.tidyLayout?.gap ?? 0, 40, accuracy: 0.001)
        XCTAssertEqual(s.page.elements.first { $0.id == "d" }, held)
    }
}
