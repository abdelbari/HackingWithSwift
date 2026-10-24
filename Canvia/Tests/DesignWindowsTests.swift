// Two windows on one design (DesignWindows): the rule the Android twin's
// DesignWindowsTest checks too.

import XCTest
@testable import Canvia

final class DesignWindowsTests: XCTestCase {

    func testTheFirstWindowEditsASecondShowsItReadOnlyUntilItIsLetGo() {
        let windows = DesignWindows()
        let a = DesignWindows.Window()
        let b = DesignWindows.Window()
        XCTAssertTrue(windows.open("d1", in: a))
        // Opened again in the same window, it is still its own.
        XCTAssertTrue(windows.open("d1", in: a))
        XCTAssertFalse(windows.open("d1", in: b))
        // Another design is b's to edit.
        XCTAssertTrue(windows.open("d2", in: b))
        // b closing what it only showed changes nothing.
        windows.close("d1", in: b)
        XCTAssertTrue(windows.isHeld("d1"))
        XCTAssertFalse(windows.open("d1", in: b))
        // Once a lets go, b opening it again edits it.
        windows.close("d1", in: a)
        XCTAssertFalse(windows.isHeld("d1"))
        XCTAssertTrue(windows.open("d1", in: b))
        XCTAssertFalse(windows.open("d1", in: a))
    }
}
