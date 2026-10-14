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

    /// Android's UnitsTest readout rows, verbatim: the number alone, its
    /// unit after it (Units.suffix).
    func testAReadoutIsInTheDesignsUnitToATenthOfAMillimetreOrAHundredthOfACentimetreOrInch() {
        // (pixels, unit, dpi, readout)
        let rows: [(Double, String, Double, String)] = [
            (2480, "mm", 300, "210"),
            (1169, "mm", 300, "99"),
            (12.5 / 25.4 * 300, "mm", 300, "12.5"),
            (40 / 25.4 * 300, "mm", 300, "40"),
            (1, "mm", 300, "0.1"),
            (0, "mm", 300, "0"),
            (-1, "mm", 300, "-0.1"),
            // Too small to show is nought, never minus nought.
            (-0.1, "mm", 300, "0"),
            (96, "mm", 96, "25.4"),
            (2480, "cm", 300, "21"),
            (1000, "cm", 300, "8.47"),
            (2550, "in", 300, "8.5"),
            (100, "in", 300, "0.33"),
            // Pixels are whole, halves up, as the readouts always were.
            (120.4, "px", 300, "120"),
            (120.5, "px", 300, "121"),
            (-3.6, "px", 300, "-4"),
            (-120.5, "px", 300, "-120"),
        ]
        for (px, unit, dpi, text) in rows {
            XCTAssertEqual(Units.readout(px, design(unit, dpi: dpi)), text, "\(px) \(unit)")
        }
        XCTAssertEqual(Units.suffix(design("mm", dpi: 300)), " mm")
        XCTAssertEqual(Units.suffix(design("in", dpi: 300)), " in")
        XCTAssertEqual(Units.suffix(design("px", dpi: 300)), "")
    }

    func testAUnitWithNoDpiIsAt300() {
        XCTAssertEqual(Units.readout(118.11, design("mm")), "10")
        XCTAssertEqual(Units.readout(-147.6378, design("mm", dpi: 300)), "-12.5")
    }

    func testPixelsReadAsTheyAlwaysDid() {
        XCTAssertEqual(Units.readout(width: 120.9, height: 48, design(nil)), "120 × 48", "the size badge cuts")
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

    /// Android's nudge rows: the steps in the design's unit, and the pixels
    /// they move by, unrounded.
    func testNudgeStepsAreInTheDesignsUnitAndMoveByTheirPixels() {
        XCTAssertEqual(Units.nudgeSteps("mm"), [0.1, 1, 10])
        XCTAssertEqual(Units.nudgeSteps("cm"), [0.01, 0.1, 1])
        XCTAssertEqual(Units.nudgeSteps("in"), [0.01, 0.1, 1])
        XCTAssertEqual(Units.nudgeSteps("px"), [1, 10, 100])
        XCTAssertEqual(Units.nudgeSteps(nil), [1, 10, 100])
        XCTAssertEqual(Units.stepPixels(1, design("mm", dpi: 300)), 300 / 25.4, accuracy: 1e-9)
        XCTAssertEqual(Units.stepPixels(0.1, design("in", dpi: 300)), 30, accuracy: 1e-9)
        XCTAssertEqual(Units.stepPixels(10, design("px", dpi: 300)), 10)
        XCTAssertEqual(Units.stepPixels(0.1, design("mm", dpi: 300)), 300 / 254, accuracy: 1e-9, "0.1 mm, not rounded to a pixel")
    }

    // MARK: typed lengths

    /// Android's typedLength rows, verbatim: whole pixels for paper, as
    /// typed for pixels.
    func testATypedPositionIsReadInTheDesignsUnitAsWholePixelsForPaper() {
        // (typed, unit, pixels or nil)
        let rows: [(String, String, Double?)] = [
            ("12.5", "mm", 148),
            (" 12,5 mm ", "mm", 148),
            ("-3", "mm", -35),
            ("8.5in", "in", 2550),
            ("2.1", "cm", 248),
            ("120 px", "px", 120),
            ("120.5", "px", 120.5),
            // Only the design's own unit may follow the number.
            ("120 px", "mm", nil),
            ("mm", "mm", nil),
            ("abc", "px", nil),
            ("", "px", nil),
        ]
        for (typed, unit, px) in rows {
            XCTAssertEqual(Units.typedLength(typed, design(unit, dpi: 300)), px, "\(typed) in \(unit)")
        }
        // A half below nought goes up too, as Android's floor(x + 0.5).
        XCTAssertEqual(Units.typedLength("-0.5", design("in", dpi: 3)), -1)
    }

    func testArrowKeysTakeTheSmallestStepOrTheMiddleWithShift() {
        XCTAssertEqual(Units.arrowStep(design(nil), shift: false), 1)
        XCTAssertEqual(Units.arrowStep(design(nil), shift: true), 10)
        let a4 = design("mm", dpi: 300)
        XCTAssertEqual(Units.arrowStep(a4, shift: false), 300 / 254, accuracy: 1e-9)
        XCTAssertEqual(Units.arrowStep(a4, shift: true), 3000 / 254, accuracy: 1e-9)
        XCTAssertEqual(Units.readout(Units.arrowStep(a4, shift: false), a4) + Units.suffix(a4), "0.1 mm")
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
        // Whole pixels, as Android's Units.typedLength makes them.
        XCTAssertEqual(Guides.typedPosition("12.5", limit: 2480, unit: "mm", dpi: 300), 148)
        XCTAssertEqual(Guides.typedPosition("12,5 mm", limit: 2480, unit: "mm", dpi: 300), 148)
        XCTAssertEqual(Guides.typedPosition("1 in", limit: 2480, unit: "in", dpi: 300), 300)
        XCTAssertEqual(Guides.typedPosition("500", limit: 2480, unit: "mm", dpi: 300), 2480, "kept on the page")
        XCTAssertEqual(Guides.typedPosition("120 px", limit: 400), 120, "pixels as before")
        XCTAssertEqual(Guides.typedPosition("120.5", limit: 400), 120.5, "pixels as typed")
        XCTAssertNil(Guides.typedPosition("left", limit: 400, unit: "mm", dpi: 300))
    }
}
