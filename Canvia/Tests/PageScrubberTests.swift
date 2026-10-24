// Round 34's page scrubber: when it shows, how long its thumb is, how a
// drag of it maps to the column — linearly, both ways — and what the
// bubble and VoiceOver say. The rows the Android twin's tests hold too.

import XCTest
@testable import Canvia

final class PageScrubberTests: XCTestCase {

    func testItShowsForSixPagesOrMoreInTheColumnOnly() {
        XCTAssertFalse(PageScrubber.shows(pages: 5, column: true, busy: false))
        XCTAssertTrue(PageScrubber.shows(pages: 6, column: true, busy: false))
        XCTAssertFalse(PageScrubber.shows(pages: 60, column: false, busy: false), "a page alone")
        XCTAssertFalse(PageScrubber.shows(pages: 60, column: true, busy: true), "typing, cropping or drawing")
        XCTAssertEqual(PageScrubber.shownSeconds, 1.5)
    }

    func testTheThumbIsTheShareOnScreenAndNeverLessThanAFingertip() {
        // A tenth of the column on screen: a tenth of the track.
        XCTAssertEqual(PageScrubber.thumbLength(visible: 1000, column: 10_000, track: 600), 60)
        // A sixtieth: held to 44 points.
        XCTAssertEqual(PageScrubber.thumbLength(visible: 1000, column: 60_000, track: 600), 44)
        // More on screen than the column: the whole track.
        XCTAssertEqual(PageScrubber.thumbLength(visible: 2000, column: 1000, track: 600), 600)
    }

    func testADragMapsLinearlyToTheColumnAndBack() {
        let visible = 1000.0, column = 10_000.0, track = 600.0
        // The thumb is 60 long, so it moves over 540; the view over 9000.
        XCTAssertEqual(PageScrubber.columnTop(thumbTop: 0, visible: visible, column: column, track: track), 0)
        XCTAssertEqual(PageScrubber.columnTop(thumbTop: 270, visible: visible, column: column, track: track), 4500)
        XCTAssertEqual(PageScrubber.columnTop(thumbTop: 540, visible: visible, column: column, track: track), 9000)
        // Past either end, held to the column.
        XCTAssertEqual(PageScrubber.columnTop(thumbTop: 900, visible: visible, column: column, track: track), 9000)
        XCTAssertEqual(PageScrubber.columnTop(thumbTop: -20, visible: visible, column: column, track: track), 0)
        XCTAssertEqual(PageScrubber.thumbTop(top: 4500, visible: visible, column: column, track: track), 270)
    }

    func testVoiceOverStepsAPageAtATimeHeldToTheEnds() {
        XCTAssertEqual(PageScrubber.stepped(36, by: 1, count: 60), 37)
        XCTAssertEqual(PageScrubber.stepped(59, by: 1, count: 60), 59)
        XCTAssertEqual(PageScrubber.stepped(0, by: -1, count: 60), 0)
        XCTAssertEqual(PageScrubber.spoken(36, count: 60), tr("%d of %d", 37, 60))
    }

    func testTheBubbleReadsAsThePagesHeader() {
        XCTAssertEqual(PageScrubber.bubble(36, title: "Title"), PageTitles.named(37, title: "Title"))
        XCTAssertEqual(PageScrubber.bubble(36, title: nil), tr("Page %d", 37))
    }
}
