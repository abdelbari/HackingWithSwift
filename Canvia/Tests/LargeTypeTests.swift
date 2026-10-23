// Larger Text in the editor's chrome: where the space-limited rows stop
// growing, and where a toolbar item goes to its icon alone.

import XCTest
import SwiftUI
@testable import Canvia

final class LargeTypeTests: XCTestCase {

    func testTheCrowdedRowsStopAtAccessibility2() {
        XCTAssertEqual(LargeType.chromeCap, .accessibility2)
    }

    func testAToolbarItemIsItsIconAlonePastXXXLarge() {
        XCTAssertFalse(LargeType.iconOnly(.large))
        XCTAssertFalse(LargeType.iconOnly(.xxxLarge))
        XCTAssertTrue(LargeType.iconOnly(.accessibility1))
        XCTAssertTrue(LargeType.iconOnly(.accessibility5))
    }
}
