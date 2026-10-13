// Present on a second screen: the presenter's timer as it reads, the page
// coming and "End of presentation", the page grid leaving hidden pages
// out, the notes' A− and A+, the pointer's place on the page, and the
// screen attached and taken away. The same cases as the Android twin's
// tests.

import XCTest
import CoreGraphics
import UIKit
@testable import Canvia

final class PresenterViewTests: XCTestCase {

    private func design(hidden: [Bool]) -> Design {
        var d = Design(title: "p", width: 400, height: 300)
        d.pages = hidden.map { flag in
            var p = Page()
            p.hidden = flag ? true : nil
            return p
        }
        return d
    }

    // MARK: the timer

    func testTimerFormatting() {
        XCTAssertEqual(Presenter.clockText(0), "0:00")
        XCTAssertEqual(Presenter.clockText(59), "0:59")
        XCTAssertEqual(Presenter.clockText(725), "12:05")
        XCTAssertEqual(Presenter.clockText(3599), "59:59")
        XCTAssertEqual(Presenter.clockText(3723), "1:02:03")
        XCTAssertEqual(Presenter.clockText(-5), "0:00")
        XCTAssertEqual(Presenter.clockText(59.9), "0:59", "whole seconds, rounded down")
        XCTAssertEqual(Presenter.clockText(600), "10:00")
        XCTAssertEqual(Presenter.clockText(3600), "1:00:00", "hours once there is one")
        XCTAssertEqual(Presenter.clockText(36_000), "10:00:00")
        XCTAssertEqual(Presenter.clockText(-4), "0:00", "nothing below nought")
        XCTAssertEqual(Presenter.clockText(.nan), "0:00")
    }

    @MainActor
    func testTheTimeOnAPageSitsBesideItsHold() {
        XCTAssertEqual(Presenter.pageTime(7, hold: 2.5), "0:07 · holds 2.5 s")
        var d = design(hidden: [false])
        d.pages[0].holdSeconds = 12
        let session = PresentSession(design: d)
        XCTAssertEqual(Presenter.pageTime(65, hold: session.holdSeconds(session.page)), "1:05 · holds 12.0 s")
        XCTAssertEqual(Presenter.pageTime(0, hold: 0.5), "0:00 · holds 0.5 s", "a hold under a second still said")
    }

    func testTheTimerPausesAndResets() {
        let t0 = Date(timeIntervalSince1970: 1000)
        var timer = PresenterTimer(startingAt: t0)
        XCTAssertFalse(timer.paused)
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(65)), 65, accuracy: 1e-9)
        timer.toggle(at: t0.addingTimeInterval(65))
        XCTAssertTrue(timer.paused)
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(100)), 65, accuracy: 1e-9, "paused, it stands still")
        timer.toggle(at: t0.addingTimeInterval(100))
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(110)), 75, accuracy: 1e-9, "it runs on from where it stood")
        timer.reset(at: t0.addingTimeInterval(110))
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(115)), 5, accuracy: 1e-9, "reset while running runs on from 0:00")
        timer.toggle(at: t0.addingTimeInterval(120))
        timer.reset(at: t0.addingTimeInterval(130))
        XCTAssertTrue(timer.paused, "reset while paused stays paused")
        XCTAssertEqual(timer.elapsed(at: t0.addingTimeInterval(200)), 0, accuracy: 1e-9)
    }

    // MARK: the page coming

    func testNextVisiblePageLookup() {
        let visible = design(hidden: [false, true, false, true, false]).visiblePageIndices
        XCTAssertEqual(Presenter.next(after: 0, in: visible), 2, "a hidden page is stepped over")
        XCTAssertEqual(Presenter.next(after: 2, in: visible), 4)
        XCTAssertEqual(Presenter.next(after: 1, in: visible), 2)
        XCTAssertNil(Presenter.next(after: 4, in: visible), "after the last page: End of presentation")
        XCTAssertNil(Presenter.next(after: 0, in: design(hidden: [false, true, true]).visiblePageIndices),
                     "only hidden pages after it: End of presentation")
        XCTAssertEqual(Presenter.endOfPresentation, "End of presentation")
    }

    func testThePageGridLeavesHiddenPagesOut() {
        XCTAssertEqual(Presenter.gridPages(design(hidden: [false, true, false, true, false])), [0, 2, 4])
        XCTAssertEqual(Presenter.gridPages(design(hidden: [false, false])), [0, 1])
        XCTAssertEqual(Presenter.gridPages(design(hidden: [true])), [])
    }

    // MARK: notes

    func testNotesTextSteps() {
        XCTAssertEqual(Presenter.defaultNotesSize, 20)
        XCTAssertEqual(Presenter.notesSize(20, steps: -1), 18)
        XCTAssertEqual(Presenter.notesSize(20, steps: 1), 22)
        XCTAssertEqual(Presenter.notesSize(14, steps: -1), 14, "never below 14")
        XCTAssertEqual(Presenter.notesSize(15, steps: -1), 14)
        XCTAssertEqual(Presenter.notesSize(40, steps: 1), 40, "never above 40")
        XCTAssertEqual(Presenter.notesSize(39, steps: 1), 40)
        XCTAssertEqual(Presenter.notesSize(38, steps: 5), 40)
    }

    // MARK: the pointer

    func testThePointerLandsAtThePagesOwnCoordinates() throws {
        // A 100 × 50 page fitted to a 200 × 200 view: twice the size, with
        // 50 points of black above and below.
        let view = CGSize(width: 200, height: 200)
        let page = CGSize(width: 100, height: 50)
        let middle = try XCTUnwrap(Presenter.pagePoint(CGPoint(x: 100, y: 100), in: view, page: page))
        XCTAssertEqual(middle.x, 50, accuracy: 1e-9)
        XCTAssertEqual(middle.y, 25, accuracy: 1e-9)
        let corner = try XCTUnwrap(Presenter.pagePoint(CGPoint(x: 0, y: 50), in: view, page: page))
        XCTAssertEqual(corner.x, 0, accuracy: 1e-9, "the page's edge counts as on it")
        XCTAssertEqual(corner.y, 0, accuracy: 1e-9)
        XCTAssertNil(Presenter.pagePoint(CGPoint(x: 100, y: 20), in: view, page: page), "off the page: no dot")
        XCTAssertNil(Presenter.pagePoint(CGPoint(x: 100, y: 151), in: view, page: page))
    }

    func testThePointerIsTheSameShareOfThePageOnEveryScreen() {
        XCTAssertEqual(Presenter.pointerDiameter(page: CGSize(width: 1920, height: 1080)), 32.4, accuracy: 1e-9)
        XCTAssertEqual(Presenter.pointerDiameter(page: CGSize(width: 1080, height: 1920)), 32.4, accuracy: 1e-9)
    }

    // MARK: the talk

    @MainActor
    func testOneSessionHoldsThePageBothScreensDraw() {
        var d = design(hidden: [false, false])
        d.pages[1].holdSeconds = 7
        let session = PresentSession(design: d)
        XCTAssertEqual(session.page.id, d.pages[0].id)
        session.index = 1
        XCTAssertEqual(session.page.id, d.pages[1].id)
        XCTAssertEqual(session.holdSeconds(session.page), 7)
        XCTAssertNil(session.pointer)
        XCTAssertNil(session.heldAt(session.page), "nothing leaves: never held")
    }

    @MainActor
    func testTheScreenShowsTheTalkOnlyWhileOneIsOn() {
        let display = ExternalDisplay.shared
        let session = PresentSession(design: design(hidden: [false]))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertFalse(display.attached)
        display.attach(window)
        XCTAssertTrue(display.attached, "a screen attached: Present shows the console")
        XCTAssertTrue(window.isHidden, "no talk on: the screen is left to the system")
        display.session = session
        XCTAssertFalse(window.isHidden, "a talk on: the slides on the screen")
        display.detach(window)
        XCTAssertFalse(display.attached, "taken away: the phone presents again")
        XCTAssertTrue(display.session === session, "on the same talk, and so the same page")
        display.session = nil
    }
}
