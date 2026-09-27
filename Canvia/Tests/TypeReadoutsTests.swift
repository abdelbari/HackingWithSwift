// The type controls' readouts and ranges, in the Android twin's words.

import XCTest
@testable import Canvia

final class TypeReadoutsTests: XCTestCase {

    func testLetterSpacingRangeFollowsTheTypeSize() {
        let heading = TypeReadouts.letterSpacingRange(size: 200, current: 0)
        XCTAssertEqual(heading.lowerBound, -20)
        XCTAssertEqual(heading.upperBound, 100)
        let caption = TypeReadouts.letterSpacingRange(size: 12, current: 0)
        XCTAssertEqual(caption.lowerBound, -2, "never narrower than the old -2…20")
        XCTAssertEqual(caption.upperBound, 20)
        let wide = TypeReadouts.letterSpacingRange(size: 12, current: 64)
        XCTAssertEqual(wide.upperBound, 64, "what the box already has is always in reach")
    }

    func testReadouts() {
        XCTAssertEqual(TypeReadouts.letterSpacing(8, size: 80), "10%")
        XCTAssertEqual(TypeReadouts.letterSpacing(-4, size: 80), "-5%")
        XCTAssertEqual(TypeReadouts.lineHeight(1.25), "1.25")
        XCTAssertEqual(TypeReadouts.lineHeight(1.2), "1.20")
        XCTAssertEqual(TypeReadouts.paragraphSpacing(0.004), "None")
        XCTAssertEqual(TypeReadouts.paragraphSpacing(0.44), "0.4 em")
        XCTAssertEqual(TypeReadouts.lineHeightRange, 0.7...2.5)
    }

    func testAlignmentAndListAreSaidInWords() {
        XCTAssertEqual(TypeReadouts.alignment(nil), "Center")
        XCTAssertEqual(TypeReadouts.alignment("justify"), "Justify")
        XCTAssertEqual(TypeReadouts.listStyle("number"), "Numbers")
        XCTAssertEqual(TypeReadouts.listStyle(nil), "No list")
    }
}
