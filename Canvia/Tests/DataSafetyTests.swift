// Keeping the person's work: saves that land whole or say they did not.

import XCTest
@testable import Canvia

final class DataSafetyTests: XCTestCase {

    private var ids: [String] = []

    override func tearDown() {
        for id in ids { DesignLibrary.delete(id: id) }
        ids = []
        super.tearDown()
    }

    private func saved(_ title: String) -> Design {
        let d = Design(title: title, width: 300, height: 200)
        XCTAssertTrue(DesignLibrary.save(d))
        ids.append(d.id)
        return d
    }

    // MARK: saving

    /// A save that cannot be written says so, and leaves the last good
    /// file where it was rather than half of a new one. JSON has no way to
    /// write a width that is not a number, so encoding fails here as a full
    /// disk fails on a phone.
    func testAFailedSaveIsReportedAndKeepsTheLastGoodFile() {
        var d = saved("Kept")
        d.title = "Never written"
        d.width = .nan
        XCTAssertFalse(DesignLibrary.save(d))
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.title, "Kept")
        XCTAssertEqual(DesignLibrary.load(id: d.id)?.width, 300)
    }

    @MainActor
    func testTheBannerSaysWhatTheAndroidTwinSays() {
        XCTAssertEqual(EditorView.saveFailedMessage,
                       "Couldn't save your changes. Your phone may be out of space. Canvia will keep trying.")
    }
}
