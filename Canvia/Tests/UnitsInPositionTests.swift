// Where things sit and how big they are, in the design's own unit: the
// shared readout (Units.readout), the nudge steps and the arrow keys, the
// canvas readouts and a guide's typed place — the same rows as the Android
// twin's tests.

import XCTest
@testable import Canvia

final class UnitsInPositionTests: XCTestCase {

    private func design(_ unit: String?, dpi: Double? = nil) -> Design {
        var d = Design(title: "u", width: 2480, height: 3508)
        d.unit = unit
        d.dpi = dpi
        return d
    }

    // MARK: Units.readout

    func testALengthReadsInTheDesignsUnit() {
        let a4 = design("mm", dpi: 300)
        XCTAssertEqual(Units.readout(147.6378, a4), "12.5 mm")
        XCTAssertEqual(Units.readout(472.4409, a4), "40 mm")
        XCTAssertEqual(Units.readout(2480, a4), "210 mm", "209.97 to a tenth")
        XCTAssertEqual(Units.readout(1, a4), "0.1 mm")
        XCTAssertEqual(Units.readout(300, design("cm", dpi: 300)), "2.54 cm")
        XCTAssertEqual(Units.readout(300, design("in", dpi: 300)), "1 in")
        XCTAssertEqual(Units.readout(100, design("in", dpi: 300)), "0.33 in")
        XCTAssertEqual(Units.readout(118.11, design("mm")), "10 mm", "a unit with no dpi is at 300")
        XCTAssertEqual(Units.readout(-147.6378, a4), "-12.5 mm")
    }

    func testPixelsReadAsTheyAlwaysDid() {
        let px = design(nil)
        XCTAssertEqual(Units.readout(120.4, px), "120")
        XCTAssertEqual(Units.readout(120.5, px), "121")
        XCTAssertEqual(Units.readout(width: 120.9, height: 48, px), "120 × 48", "the size badge cuts")
    }

    func testASizeReadsWithItsUnitOnce() {
        let a4 = design("mm", dpi: 300)
        XCTAssertEqual(Units.readout(width: 2480, height: 1169.2913, a4), "210 × 99 mm")
        XCTAssertEqual(Units.readout(width: 2480, height: 3508, design("cm", dpi: 300)), "21 × 29.7 cm")
    }

    func testDecimalsAreTrimmed() {
        XCTAssertEqual(Units.decimal(12.04, unit: "mm"), "12")
        XCTAssertEqual(Units.decimal(12.25, unit: "cm"), "12.25")
        XCTAssertEqual(Units.decimal(12.2, unit: "in"), "12.2")
        XCTAssertEqual(Units.decimal(0.004, unit: "in"), "0")
        XCTAssertEqual(Units.places("mm"), 1)
        XCTAssertEqual(Units.places("cm"), 2)
        XCTAssertEqual(Units.places("in"), 2)
        XCTAssertEqual(Units.places(nil), 0)
    }

    // MARK: nudges

    func testNudgeStepsAreInTheDesignsUnit() {
        XCTAssertEqual(Units.nudgeSteps(nil), [1, 10, 100])
        XCTAssertEqual(Units.nudgeSteps("mm"), [0.1, 1, 10])
        XCTAssertEqual(Units.nudgeSteps("cm"), [0.01, 0.1, 1])
        XCTAssertEqual(Units.nudgeSteps("in"), [0.01, 0.1, 1])
        let a4 = design("mm", dpi: 300)
        XCTAssertEqual(Units.stepPixels(0.1, a4), 300 / 254, accuracy: 1e-9, "0.1 mm, not rounded to a pixel")
        XCTAssertEqual(Units.stepPixels(1, design("in", dpi: 300)), 300, accuracy: 1e-9)
        XCTAssertEqual(Units.stepPixels(10, design(nil)), 10)
    }

    func testArrowKeysTakeTheSmallestStepOrTheMiddleWithShift() {
        XCTAssertEqual(Units.arrowStep(design(nil), shift: false), 1)
        XCTAssertEqual(Units.arrowStep(design(nil), shift: true), 10)
        let a4 = design("mm", dpi: 300)
        XCTAssertEqual(Units.arrowStep(a4, shift: false), 300 / 254, accuracy: 1e-9)
        XCTAssertEqual(Units.arrowStep(a4, shift: true), 3000 / 254, accuracy: 1e-9)
        XCTAssertEqual(Units.readout(Units.arrowStep(a4, shift: false), a4), "0.1 mm")
    }

    // MARK: readouts

    func testTheMoveReadoutIsInTheDesignsUnit() {
        let a4 = design("mm", dpi: 300)
        let runs = Readouts.move(x: 147.6378, y: 472.4409, heldX: false, heldY: false, gapX: nil, gapY: nil, in: a4)
        XCTAssertEqual(Readouts.text(runs), "x 12.5 mm  ·  y 40 mm")
        let px = Readouts.move(x: 120.4, y: 48, heldX: false, heldY: false, gapX: 24, gapY: nil, in: design(nil))
        XCTAssertEqual(Readouts.text(px), "x 120  ·  y 48  ↔ 24")
    }

    // MARK: guides

    func testAGuidesPlaceIsTypedInTheDesignsUnit() {
        XCTAssertEqual(Guides.typedPosition("12.5", limit: 2480, unit: "mm", dpi: 300) ?? 0, 147.6378, accuracy: 1e-3)
        XCTAssertEqual(Guides.typedPosition("12,5 mm", limit: 2480, unit: "mm", dpi: 300) ?? 0, 147.6378, accuracy: 1e-3)
        XCTAssertEqual(Guides.typedPosition("1 in", limit: 2480, unit: "in", dpi: 300), 300)
        XCTAssertEqual(Guides.typedPosition("500", limit: 2480, unit: "mm", dpi: 300), 2480, "kept on the page")
        XCTAssertEqual(Guides.typedPosition("120 px", limit: 400), 120, "pixels as before")
        XCTAssertNil(Guides.typedPosition("left", limit: 400, unit: "mm", dpi: 300))
    }
}
