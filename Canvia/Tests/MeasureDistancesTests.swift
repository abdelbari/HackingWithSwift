// Round 33's distances while moving: from each side of the moving box to
// the nearest facing edge — a neighbour beside it, or else the page's edge
// (Geometry.nearestDistances) — the Android twin's rows, and the store's
// hold to measure, its Show distances switch and what VoiceOver says.

import XCTest
import CoreGraphics
@testable import Canvia

final class MeasureDistancesTests: XCTestCase {

    private let page = CGSize(width: 1000, height: 800)

    private func distance(_ out: [Geometry.Distance], _ side: Geometry.Side) -> Double? {
        out.first { $0.side == side }?.distance
    }

    /// Shared rows: alone on the page, each side measures to the page's edge.
    func testAloneItMeasuresToThePageEdges() {
        let out = Geometry.nearestDistances(moving: CGRect(x: 100, y: 200, width: 300, height: 100), others: [], page: page)
        XCTAssertEqual(out.map(\.side), [.left, .top, .right, .bottom])
        XCTAssertEqual(out.map(\.distance), [100, 200, 600, 500])
        XCTAssertEqual(out[0].from, CGPoint(x: 100, y: 250))
        XCTAssertEqual(out[0].to, CGPoint(x: 0, y: 250))
        XCTAssertEqual(out[3].from, CGPoint(x: 250, y: 300))
        XCTAssertEqual(out[3].to, CGPoint(x: 250, y: 800))
    }

    /// Shared rows: a neighbour overlapping across a side is measured to,
    /// the nearest winning; one that does not overlap is passed over.
    func testTheNearestFacingNeighbourWins() {
        let moving = CGRect(x: 400, y: 300, width: 200, height: 100)
        let others = [
            CGRect(x: 100, y: 350, width: 100, height: 100),   // left, 200 away, overlaps 350–400
            CGRect(x: 250, y: 320, width: 100, height: 40),    // left, 50 away: nearer
            CGRect(x: 700, y: 500, width: 100, height: 100),   // right but below it: passed over
            CGRect(x: 450, y: 100, width: 50, height: 120),    // above, 80 away
        ]
        let out = Geometry.nearestDistances(moving: moving, others: others, page: page)
        XCTAssertEqual(distance(out, .left), 50)
        XCTAssertEqual(out.first { $0.side == .left }?.to, CGPoint(x: 350, y: 340), "through the shared span 320–360")
        XCTAssertEqual(distance(out, .right), 400, "the page edge")
        XCTAssertEqual(distance(out, .top), 80)
        XCTAssertEqual(out.first { $0.side == .top }?.from, CGPoint(x: 475, y: 300))
        XCTAssertEqual(distance(out, .bottom), 400)
    }

    /// Shared rows: one overlapping the moving box faces none of its sides,
    /// and a side past the page's edge with no neighbour has no distance.
    func testOverlapsAndPastThePageEdge() {
        let moving = CGRect(x: -50, y: 100, width: 200, height: 100)
        let out = Geometry.nearestDistances(moving: moving, others: [CGRect(x: 100, y: 120, width: 100, height: 20)], page: page)
        XCTAssertNil(distance(out, .left), "past the page's left edge")
        XCTAssertEqual(distance(out, .right), 850, "the overlapping box is passed over")
        XCTAssertEqual(out.map(\.side), [.top, .right, .bottom])
        let touching = Geometry.nearestDistances(moving: CGRect(x: 100, y: 0, width: 100, height: 100),
                                                 others: [CGRect(x: 200, y: 50, width: 10, height: 10)], page: page)
        XCTAssertEqual(distance(touching, .right), 0, "a neighbour touching it is 0 away")
        XCTAssertEqual(distance(touching, .top), 0, "and so is the page's edge")
    }

    func testAnEqualGapKeepsItsBracket() {
        let gap = Geometry.GapPair(a: CGRect(x: 0, y: 0, width: 100, height: 100),
                                   b: CGRect(x: 150, y: 0, width: 100, height: 100), alongX: true)
        let across = Geometry.Distance(side: .left, from: .zero, to: .zero, distance: 50)
        let down = Geometry.Distance(side: .top, from: .zero, to: .zero, distance: 50)
        XCTAssertTrue(Geometry.isEqualGap(across, [gap]))
        XCTAssertFalse(Geometry.isEqualGap(down, [gap]), "a gap across is no gap down")
    }

    @MainActor
    func testHoldToMeasureFollowsTheSwitchAndLeavesOutWhatIsHidden() throws {
        let defaults = UserDefaults.standard
        let was = defaults.object(forKey: AccessibilityPrefs.showDistancesKey)
        defer { defaults.set(was, forKey: AccessibilityPrefs.showDistancesKey) }
        defaults.removeObject(forKey: AccessibilityPrefs.showDistancesKey)
        XCTAssertTrue(AccessibilityPrefs.showsDistances(), "on unless turned off")
        XCTAssertEqual(AccessibilityPrefs.showDistancesKey, "canvia.showDistances")

        var d = Design(title: "measure", width: 1000, height: 800)
        var a = Element.shape("rect", w: 100, h: 100)
        a.id = "a"; a.x = 400; a.y = 300
        var b = Element.shape("rect", w: 100, h: 100)
        b.id = "b"; b.x = 200; b.y = 300
        var c = Element.shape("rect", w: 100, h: 100)
        c.id = "c"; c.x = 320; c.y = 300; c.hidden = true
        d.pages = [Page(elements: [a, b, c])]
        let s = DesignStore(design: d)
        s.select("a")
        s.measureSelection(true)
        XCTAssertEqual(s.distanceMarks.first { $0.side == .left }?.distance, 100, "to b; c is hidden")
        XCTAssertEqual(s.spokenDistances, "Left 100, Top 300, Right 500, Bottom 400", "in pixels, no unit said")
        s.measureSelection(false)
        XCTAssertTrue(s.distanceMarks.isEmpty)
        defaults.set(false, forKey: AccessibilityPrefs.showDistancesKey)
        s.measureSelection(true)
        XCTAssertTrue(s.distanceMarks.isEmpty, "Show distances off")
    }

    @MainActor
    func testWhatIsMoreThanAScreenAwayIsLeftOut() {
        var d = Design(title: "far", width: 10000, height: 1000)
        var near = Element.shape("rect", w: 100, h: 100)
        near.id = "near"; near.x = 300
        var far = Element.shape("rect", w: 100, h: 100)
        far.id = "far"; far.x = 9000
        d.pages = [Page(elements: [near, far])]
        let s = DesignStore(design: d)
        s.viewport = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        XCTAssertEqual(s.distanceNeighbours(excluding: []).count, 1, "a screen beyond the view is as far as it reaches")
    }
}
