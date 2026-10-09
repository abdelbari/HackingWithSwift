// Pages and Resize, as the Android twin has them: a typed size is checked
// rather than clamped, a Scale says what it did with its Undo, a note typed
// is one Undo, and a page's row reads whole to VoiceOver.

import XCTest
@testable import Canvia

final class PagesAndResizeParityTests: XCTestCase {

    // MARK: custom size for Resize

    func testBothSidesInRangeMakeASize() throws {
        let size = try XCTUnwrap(CustomSizes.size(width: "1080", height: "1920"))
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
        XCTAssertEqual(CustomSizes.resizeTitle(width: "1080", height: "1920"), "Resize to 1080 × 1920")
    }

    func testASideOutOfRangeIsRefusedRatherThanClamped() {
        XCTAssertNil(CustomSizes.size(width: "39", height: "1000"))
        XCTAssertNil(CustomSizes.size(width: "1000", height: "4001"))
        XCTAssertNil(CustomSizes.size(width: "", height: "1000"))
        XCTAssertEqual(CustomSizes.resizeTitle(width: "8000", height: "8000"), "Enter a size from 40 to 4000")
    }

    func testTheRangeEndsAreAllowed() {
        XCTAssertNotNil(CustomSizes.size(width: "40", height: "4000"))
    }

    // MARK: resize says so

    @MainActor
    func testScalingTheDesignOffersUndo() {
        let store = DesignStore(design: Design(title: "r", width: 1080, height: 1080))
        let before = store.haptic.serial
        store.resizeDesign(width: 1080, height: 1920)
        XCTAssertEqual(store.announcement, "Resized to 1080 × 1920")
        XCTAssertTrue(store.announcementUndoes)
        XCTAssertEqual(store.haptic.kind, .confirm)
        XCTAssertGreaterThan(store.haptic.serial, before)
    }

    @MainActor
    func testResizingToTheSameSizeSaysNothing() {
        let store = DesignStore(design: Design(title: "r", width: 1080, height: 1080))
        store.resizeDesign(width: 1080, height: 1080)
        XCTAssertNil(store.announcement)
    }

    // MARK: notes

    /// What the notes sheet does as a note is typed: every keystroke under
    /// one open step, closed once.
    @MainActor
    func testANoteTypedIsOneUndo() {
        let store = DesignStore(design: Design(title: "n", width: 400, height: 300))
        for text in ["H", "Hi", "Hi t", "Hi there"] {
            store.beginGesture()
            store.design.pages[store.pageIndex].notes = text
        }
        store.commit()
        XCTAssertEqual(store.page.notes, "Hi there")
        store.undo()
        XCTAssertNil(store.page.notes)
        XCTAssertFalse(store.canUndo)
    }

    // MARK: organiser rows

    @MainActor
    func testAPageRowReadsWhole() {
        XCTAssertEqual(PageOrganizerSheet.spokenRow(number: 3, title: nil, current: true, elements: 4, notes: "Thank the team"),
                       "Page 3, current, 4 elements, Thank the team")
        XCTAssertEqual(PageOrganizerSheet.spokenRow(number: 1, title: nil, current: false, elements: 1, notes: nil),
                       "Page 1, 1 element")
        XCTAssertEqual(PageOrganizerSheet.spokenRow(number: 2, title: nil, current: false, elements: 0, notes: ""),
                       "Page 2, 0 elements")
    }
}
