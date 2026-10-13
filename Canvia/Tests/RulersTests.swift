// Rulers along the canvas: their ticks and labels in the design's unit, and
// the guides pulled out of them and dragged back. The rows are the Android
// twin's RulersTest.

import XCTest
@testable import Canvia

final class RulersTests: XCTestCase {

    /// (points to a unit, step): 1, 2 or 5 times ten to a power, the
    /// labelled ticks 48 points apart or more.
    func testARulersLabelledTicksAre125TimesTenToAPower48PointsApartOrMore() {
        let rows: [(zoom: Double, step: Double)] = [
            (1, 50), (0.5, 100), (0.25, 200), (0.1, 500), (0.04, 2000),
            (2, 50), (4, 20), (10, 5), (24, 2), (48, 1), (47.9, 2),
            (100, 0.5), (240, 0.2), (1000, 0.05),
        ]
        for row in rows {
            XCTAssertEqual(Guides.rulerStep(row.zoom), row.step, "at \(row.zoom) points a unit")
            XCTAssertGreaterThanOrEqual(Guides.rulerStep(row.zoom) * row.zoom, Guides.rulerMajorGap - 1e-9)
        }
        XCTAssertEqual(Guides.rulerStep(0), 1)
        XCTAssertEqual(Guides.rulerStep(.nan), 1)
        XCTAssertEqual(Guides.rulerThickness, 20)
    }

    func testTicksRunFromThePagesZeroFiveToAStepTheLabelledOnesOnTheStep() {
        let ticks = Guides.rulerTicks(from: -25, to: 60, step: 50)
        XCTAssertEqual(ticks.map(\.value), [-20, -10, 0, 10, 20, 30, 40, 50, 60])
        XCTAssertEqual(ticks.filter(\.major).map(\.value), [0, 50])
        let fine = Guides.rulerTicks(from: 0, to: 1, step: 0.5)
        XCTAssertEqual(fine.map { ($0.value * 10).rounded() / 10 }, [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1])
        XCTAssertEqual(fine.filter(\.major).map(\.value), [0, 0.5, 1])
        XCTAssertTrue(Guides.rulerTicks(from: 10, to: 0, step: 5).isEmpty)
        XCTAssertTrue(Guides.rulerTicks(from: 0, to: 10, step: 0).isEmpty)
    }

    func testALabelledTickIsWrittenWholeOrToTheStepsPlaces() {
        XCTAssertEqual(Guides.rulerLabel(100, step: 50), "100")
        XCTAssertEqual(Guides.rulerLabel(-50, step: 50), "-50")
        XCTAssertEqual(Guides.rulerLabel(-0.0, step: 1), "0")
        XCTAssertEqual(Guides.rulerLabel(1.5, step: 0.5), "1.5")
        XCTAssertEqual(Guides.rulerLabel(0.2 * 1, step: 0.2), "0.2")
        XCTAssertEqual(Guides.rulerLabel(0.05, step: 0.05), "0.05")
        XCTAssertEqual(Guides.rulerLabel(-0.0000001, step: 0.5), "0.0")
    }

    /// Rulers count in the design's unit: pixels one to one, paper at its
    /// dpi.
    func testRulersCountInTheDesignsUnit() {
        var d = Design(title: "r", width: 1000, height: 500)
        XCTAssertEqual(Guides.rulerUnit(d).unit, "px")
        XCTAssertEqual(Guides.rulerUnit(d).pixels, 1)
        d.unit = "mm"
        XCTAssertEqual(Guides.rulerUnit(d).unit, "mm")
        XCTAssertEqual(Guides.rulerUnit(d).pixels, 300 / 25.4, accuracy: 1e-12, "paper without a dpi is at 300")
        d.unit = "in"
        d.dpi = 150
        XCTAssertEqual(Guides.rulerUnit(d).pixels, 150)
        d.unit = "cm"
        XCTAssertEqual(Guides.rulerUnit(d).pixels, 150 / 2.54, accuracy: 1e-12)
    }

    /// Over the ruler is within its 20 points of the view's edge, or past it.
    func testAPointIsOverTheRulerWithinItsThicknessOfTheViewsEdge() {
        XCTAssertTrue(Guides.onRuler(10, viewportStart: 0, zoom: 1))
        XCTAssertFalse(Guides.onRuler(25, viewportStart: 0, zoom: 1))
        XCTAssertFalse(Guides.onRuler(5, viewportStart: 0, zoom: 4), "20 points in is off it")
        XCTAssertTrue(Guides.onRuler(-3, viewportStart: 0, zoom: 1), "past the edge")
        XCTAssertTrue(Guides.onRuler(130, viewportStart: 100, zoom: 0.5))
        XCTAssertFalse(Guides.onRuler(150, viewportStart: 100, zoom: 0.5))
    }

    /// A guide pulled out of a ruler lands on an element's line near it,
    /// else on a whole unit, to the half pixel, and on the page.
    func testAGuidePulledOutOfARulerSnapsToWholeUnitsAndElements() {
        XCTAssertEqual(Guides.rulerGuidePosition(123.4, lines: [], threshold: 6, unitPixels: 1, limit: 1000), 123)
        // 100 px at 300 dpi is 8.47 mm: 8 mm is 94.49 px, 94.5 to the half pixel.
        XCTAssertEqual(Guides.rulerGuidePosition(100, lines: [], threshold: 6, unitPixels: 300 / 25.4, limit: 2480), 94.5)
        XCTAssertEqual(Guides.rulerGuidePosition(127, lines: [130, 200], threshold: 6, unitPixels: 1, limit: 1000), 130)
        XCTAssertEqual(Guides.rulerGuidePosition(120, lines: [130], threshold: 6, unitPixels: 1, limit: 1000), 120)
        XCTAssertEqual(Guides.rulerGuidePosition(-40, lines: [], threshold: 6, unitPixels: 1, limit: 1000), 0)
        XCTAssertEqual(Guides.rulerGuidePosition(1200, lines: [], threshold: 6, unitPixels: 1, limit: 1000), 1000)
    }

    /// Pulled out and let go, a guide is one step through addGuide; dragged
    /// back onto its ruler, it goes in the same step as the drag.
    @MainActor
    func testAGuidePulledOutIsOneStepAndOneDraggedBackGoes() {
        let store = DesignStore(design: Design(title: "r", width: 1000, height: 500))
        store.addGuide(vertical: false, at: Guides.rulerGuidePosition(212.3, lines: [], threshold: 6,
                                                                        unitPixels: 1, limit: 500))
        XCTAssertEqual(store.design.guides.map(\.position), [212])
        let id = store.design.guides[0].id
        store.moveGuideTransient(id, to: 40)
        store.removeGuide(id)
        XCTAssertTrue(store.design.guides.isEmpty)
        store.undo()
        XCTAssertEqual(store.design.guides.map(\.position), [212], "the drag and the removal are one step")
        store.undo()
        XCTAssertTrue(store.design.guides.isEmpty)
    }
}
