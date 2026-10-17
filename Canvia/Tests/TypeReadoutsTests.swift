// The type controls' readouts and ranges, in the Android twin's words.

import XCTest
@testable import Canvia

final class TypeReadoutsTests: XCTestCase {

    /// Shared rows: letter spacing −0.2…0.8 of the size, never narrower
    /// than −2…20, widened to what the box has — the Android twin's
    /// TextBoxesTest, row for row.
    func testLetterSpacingRangeFollowsTheTypeSize() {
        // size, current, low, high
        let rows: [(Double, Double, Double, Double)] = [
            (200, 0, -40, 160),
            (12, 0, -2.4, 20),
            (5, 0, -2, 20),
            (12, 64, -2.4, 64),
            (100, -50, -50, 80),
        ]
        for (size, current, low, high) in rows {
            let range = TypeReadouts.letterSpacingRange(size: size, current: current)
            XCTAssertEqual(range.lowerBound, low, accuracy: 1e-9, "\(size), \(current)")
            XCTAssertEqual(range.upperBound, high, accuracy: 1e-9, "\(size), \(current)")
        }
    }

    /// Shared rows: what each spacing readout takes when it is typed, as on
    /// the Android twin.
    func testTypedSpacingIsReadAsItsReadoutShowsIt() {
        // typed, size, letter spacing
        let letters: [(String, Double, Double)] = [
            ("12", 50, 6), ("-5%", 40, -2), ("12.6", 100, 13), ("-90", 100, -20), ("900", 10, 8), ("0", 42, 0),
        ]
        for (typed, size, spacing) in letters {
            XCTAssertEqual(TypeReadouts.typedLetterSpacing(typed, size: size) ?? .nan, spacing, accuracy: 1e-9, typed)
        }
        XCTAssertNil(TypeReadouts.typedLetterSpacing("wide", size: 42))
        // typed, line spacing
        let lines: [(String, Double)] = [("1.4", 1.4), ("1,25", 1.25), ("0.2", 0.5), ("3", 2.5), (" 1.234 ", 1.23), ("0.5", 0.5)]
        for (typed, value) in lines {
            XCTAssertEqual(TypeReadouts.typedLineHeight(typed) ?? .nan, value, accuracy: 1e-9, typed)
        }
        XCTAssertNil(TypeReadouts.typedLineHeight(""))
        // typed, paragraph spacing in ems
        let paragraphs: [(String, Double)] = [("0.5", 0.5), ("0,44", 0.4), ("-1", 0), ("5", 2), ("1.25", 1.3)]
        for (typed, value) in paragraphs {
            XCTAssertEqual(TypeReadouts.typedParagraphSpacing(typed) ?? .nan, value, accuracy: 1e-9, typed)
        }
        XCTAssertNil(TypeReadouts.typedParagraphSpacing("NaN"))
        XCTAssertEqual(TypeReadouts.sizeRange, 1...800)
    }

    /// Shared rows: a type size typed or set is kept to one decimal place,
    /// a half up at the hundredth, within 1 to 800 — half points for print
    /// work — a decimal comma read as a point; the Android twin's
    /// TextBoxesTest, row for row.
    func testTypeSizesKeepOneDecimalPlace() {
        // typed, size
        let rows: [(String, Double)] = [
            ("12.5", 12.5), ("12.54", 12.5), ("12.55", 12.6), ("0.4", 1), ("12,5", 12.5), ("24", 24),
            (" 36 ", 36), ("900", 800), ("10.44", 10.4), ("10.46", 10.5),
        ]
        for (typed, size) in rows {
            XCTAssertEqual(TypeReadouts.typedSize(typed) ?? .nan, size, accuracy: 1e-9, typed)
        }
        XCTAssertNil(TypeReadouts.typedSize("big"))
        XCTAssertNil(TypeReadouts.typedSize(""))
        XCTAssertEqual(TypeReadouts.wholeSize(12.55), 12.6, accuracy: 1e-9)
        XCTAssertEqual(TypeReadouts.wholeSize(12.54), 12.5, accuracy: 1e-9)
        XCTAssertEqual(TypeReadouts.wholeSize(0.4), 1)
        XCTAssertEqual(TypeReadouts.wholeSize(1000), 800)
        // The readout shows the decimal, and a whole number without ".0".
        XCTAssertEqual(TypeReadouts.fontSize(12.5), "12.5")
        XCTAssertEqual(TypeReadouts.fontSize(12), "12")
        XCTAssertEqual(TypeReadouts.fontSize(12.04), "12")
        XCTAssertEqual(TypeReadouts.fontSize(12.96), "13")
        XCTAssertEqual(TypeReadouts.fontSize(nil), "Mixed")
        // The sizes a deck is given carry the half point: 12.5 px is 9.375 pt,
        // 938 hundredths.
        XCTAssertEqual(PptxExporter.fontSize(12.5), 938)
    }

    func testReadouts() {
        XCTAssertEqual(TypeReadouts.letterSpacing(8, size: 80), "10%")
        XCTAssertEqual(TypeReadouts.letterSpacing(-4, size: 80), "-5%")
        XCTAssertEqual(TypeReadouts.lineHeight(1.25), "1.25")
        XCTAssertEqual(TypeReadouts.lineHeight(1.2), "1.20")
        XCTAssertEqual(TypeReadouts.paragraphSpacing(0.004), "None")
        XCTAssertEqual(TypeReadouts.paragraphSpacing(0.44), "0.4 em")
        XCTAssertEqual(TypeReadouts.lineHeightRange, 0.5...2.5)
    }

    func testAlignmentAndListAreSaidInWords() {
        XCTAssertEqual(TypeReadouts.alignment(nil), "Center")
        XCTAssertEqual(TypeReadouts.alignment("justify"), "Justify")
        XCTAssertEqual(TypeReadouts.listStyle("number"), "Numbers")
        XCTAssertEqual(TypeReadouts.listStyle(nil), "No list")
    }
}
