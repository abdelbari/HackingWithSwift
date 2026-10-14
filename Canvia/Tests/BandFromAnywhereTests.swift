// Round 29's band from anywhere, with the rows the Android twin's
// GesturesTest holds too: a backdrop — locked, or covering nine tenths of
// the page — and the workspace start a band; a band leaves out what is
// locked and the backdrop it began on unless that is all it caught; one
// from the workspace is held to the page; a locked page still refuses.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class BandFromAnywhereTests: XCTestCase {

    private func box(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                     group: String? = nil, locked: Bool = false) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.group = group
        el.locked = locked
        return el
    }

    // MARK: the band from anywhere

    func testABackdropIsLockedOrCoversNineTenthsOfThePageAndIsNotSelected() {
        let page = CGSize(width: 1000, height: 1000)
        // Full bleed, and hanging off every edge: it covers the page.
        XCTAssertTrue(CanvasGestures.isBackdrop(box("p", -50, -50, 1100, 1100), page: page, selection: []))
        // Exactly 90%, and just under.
        XCTAssertTrue(CanvasGestures.isBackdrop(box("p", 0, 0, 1000, 900), page: page, selection: []))
        XCTAssertFalse(CanvasGestures.isBackdrop(box("p", 0, 0, 1000, 899), page: page, selection: []))
        // Locked, whatever its size — but not locked in place only.
        XCTAssertTrue(CanvasGestures.isBackdrop(box("l", 10, 10, 50, 50, locked: true), page: page, selection: []))
        var pinned = box("q", 10, 10, 50, 50)
        pinned.lockPosition = true
        XCTAssertFalse(CanvasGestures.isBackdrop(pinned, page: page, selection: []))
        // Selected, it is the selection: a hold takes it out instead.
        XCTAssertFalse(CanvasGestures.isBackdrop(box("p", 0, 0, 1000, 1000), page: page, selection: ["p"]))
        // Hidden, it is not there.
        var hidden = box("p", 0, 0, 1000, 1000)
        hidden.hidden = true
        XCTAssertFalse(CanvasGestures.isBackdrop(hidden, page: page, selection: []))
        XCTAssertEqual(CanvasGestures.backdropCover, 0.9)
    }

    func testABandCatchesWhatItTouchesButTheLockedAndItsBackdropUnlessThatIsAll() {
        let photo = box("photo", 0, 0, 1000, 1000)
        let logo = box("logo", 100, 100, 100, 100, locked: true)
        let title = box("title", 300, 300, 200, 50, group: "g")
        let subtitle = box("sub", 300, 800, 200, 50, group: "g")
        let all = [photo, logo, title, subtitle]
        // Over the title: the title and its group, not the photo or the logo.
        XCTAssertEqual(CanvasGestures.bandCaught(all, rect: CGRect(x: 50, y: 50, width: 400, height: 300), startedOn: "photo"),
                       ["title", "sub"])
        // Over nothing but the photo it started on: the photo.
        XCTAssertEqual(CanvasGestures.bandCaught(all, rect: CGRect(x: 600, y: 50, width: 100, height: 100), startedOn: "photo"),
                       ["photo"])
        // Started on the locked logo, the photo under it is what it catches;
        // with nothing else there, the logo.
        XCTAssertEqual(CanvasGestures.bandCaught(all, rect: CGRect(x: 110, y: 110, width: 20, height: 20), startedOn: "logo"),
                       ["photo"])
        XCTAssertEqual(CanvasGestures.bandCaught([logo, title], rect: CGRect(x: 110, y: 110, width: 20, height: 20), startedOn: "logo"),
                       ["logo"])
        // From the empty page, the photo is caught like anything else.
        XCTAssertEqual(CanvasGestures.bandCaught(all, rect: CGRect(x: 50, y: 50, width: 400, height: 300), startedOn: nil),
                       ["photo", "title", "sub"])
        XCTAssertTrue(CanvasGestures.bandCaught(all, rect: CGRect(x: 50, y: 50, width: 0, height: 0), startedOn: nil).isEmpty)
    }

    func testABandFromTheWorkspaceIsHeldToThePageItIsDrawnOver() {
        let page = CGSize(width: 1000, height: 500)
        XCTAssertEqual(CanvasGestures.clampedBand(from: CGPoint(x: -80, y: 100), to: CGPoint(x: 400, y: 900), page: page),
                       CGRect(x: 0, y: 100, width: 400, height: 400))
        XCTAssertEqual(CanvasGestures.clampedBand(from: CGPoint(x: 1200, y: -30), to: CGPoint(x: 600, y: 700), page: page),
                       CGRect(x: 600, y: 0, width: 400, height: 500))
        XCTAssertEqual(CanvasGestures.onPage(CGPoint(x: 1500, y: -1), page: page), CGPoint(x: 1000, y: 0))
    }

    func testTheStoresBandLeavesItsBackdropOutAndALockedPageRefuses() {
        var d = Design(title: "band", width: 1000, height: 1000)
        d.pages = [Page(id: "p1", elements: [box("photo", 0, 0, 1000, 1000), box("title", 300, 300, 200, 50)])]
        let s = DesignStore(design: d)
        s.select(within: CGRect(x: 250, y: 250, width: 100, height: 100), startedOn: "photo")
        XCTAssertEqual(s.selection, ["title"])
        s.select(within: CGRect(x: 600, y: 600, width: 100, height: 100), startedOn: "photo")
        XCTAssertEqual(s.selection, ["photo"])
        s.select(nil)
        s.setPageLocked(true)
        s.select(within: CGRect(x: 250, y: 250, width: 100, height: 100), startedOn: "photo")
        XCTAssertTrue(s.selection.isEmpty, "a locked page still refuses")
    }
}
