// Round 29's smart spacing: gap matching (Geometry.matchingGap) — a third
// card added to a row lands at the gap the first two have, the equal gaps
// bracketed — and size matching while resizing (Geometry.matchingSize). The
// Android twin's SmartSpacingTest holds the same vectors.

import XCTest
import CoreGraphics
@testable import Canvia

final class SmartSpacingTests: XCTestCase {

    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: x, y: y, width: w, height: h)
    }

    private func el(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        return el
    }

    // Two cards in a row, 50 apart.
    private var a: CGRect { box(0, 0, 100, 100) }
    private var b: CGRect { box(150, 0, 100, 100) }

    func testAThirdCardInARowLandsAtTheGapTheFirstTwoHave() {
        let m = Geometry.matchingGap(moving: box(297, 10, 100, 80), siblings: [a, b], threshold: 6)
        XCTAssertEqual(m.dx, 3, accuracy: 1e-9)
        XCTAssertEqual(m.gapX, 50)
        XCTAssertEqual(m.dy, 0, accuracy: 1e-9)
        XCTAssertNil(m.gapY)
        // Both gaps bracketed: the row's and the new one.
        XCTAssertEqual(m.pairs.count, 2)
        XCTAssertTrue(m.pairs.allSatisfy { $0.alongX && abs($0.gap - 50) < 1e-9 })
        let ends = m.pairs.map { [$0.ends.from, $0.ends.to] }
        XCTAssertTrue(ends.contains([CGPoint(x: 100, y: 50), CGPoint(x: 150, y: 50)]))
        XCTAssertTrue(ends.contains([CGPoint(x: 250, y: 50), CGPoint(x: 300, y: 50)]))
    }

    func testBeforeTheRowTooAndOnlyWithinReach() {
        // Left of the first card: its gap after it is matched.
        let before = Geometry.matchingGap(moving: box(-155, 0, 100, 100), siblings: [a, b], threshold: 6)
        XCTAssertEqual(before.dx, 5, accuracy: 1e-9)
        XCTAssertEqual(before.gapX, 50)
        // 10 off is out of reach.
        let far = Geometry.matchingGap(moving: box(290, 0, 100, 100), siblings: [a, b], threshold: 6)
        XCTAssertNil(far.gapX)
        XCTAssertEqual(far.dx, 0, accuracy: 1e-9)
        XCTAssertTrue(far.pairs.isEmpty)
    }

    func testAColumnMatchesDownwardAndABoxNotBesideTheRowMatchesNothing() {
        let top = box(0, 0, 100, 60)
        let middle = box(0, 100, 100, 60)
        let m = Geometry.matchingGap(moving: box(20, 198, 60, 60), siblings: [top, middle], threshold: 6)
        XCTAssertEqual(m.dy, 2, accuracy: 1e-9)
        XCTAssertEqual(m.gapY, 40)
        XCTAssertNil(m.gapX)
        // Below the row and beside nothing in it: there is no neighbour.
        XCTAssertNil(Geometry.matchingGap(moving: box(400, 300, 50, 50), siblings: [a, b], threshold: 6).gapX)
        // With nothing in a row there is no gap to match.
        XCTAssertNil(Geometry.matchingGap(moving: box(105, 0, 50, 50), siblings: [a], threshold: 6).gapX)
    }

    func testTheSmallerShiftWinsTheSideBeforeItOnATie() {
        // Gaps of 20 and 50 in the row; the moving box sits 48 after b and
        // 22 before c — to 50 is a shift of 2, and to 20 too: the side
        // before it wins, and the gap said is 50.
        let c = box(420, 0, 100, 100)
        let row = [a, b, box(-120, 0, 100, 100)]
        let m = Geometry.matchingGap(moving: box(298, 0, 100, 100), siblings: row + [c], threshold: 6)
        XCTAssertEqual(m.dx, 2, accuracy: 1e-9)
        XCTAssertEqual(m.gapX, 50)
    }

    func testNeighboursTouchingAreNotAGap() {
        let pairs = Geometry.gapPairs([a, box(100, 0, 50, 50), box(300, 0, 10, 10)], alongX: true)
        XCTAssertEqual(pairs.map(\.gap), [150])
    }

    func testTheSiblingsNeighboursWorkedOutOnceGiveTheGapsAFreshScanDoes() {
        // A card let go between the two: their gap is no longer a gap, its
        // own to each are — the row's in the siblings' order, its own last.
        let between = box(125, 0, 100, 100)
        let siblings = [a, box(250, 0, 100, 100)]
        let rows = Geometry.neighbours(siblings, alongX: true)
        let columns = Geometry.neighbours(siblings, alongX: false)
        let pairs = Geometry.equalGapPairs(between, siblings: siblings, alongX: true, near: rows)
        XCTAssertEqual(pairs.map(\.gap), [25, 25])
        XCTAssertEqual(pairs.first?.a, a)
        XCTAssertEqual(pairs.first?.b, between)
        XCTAssertEqual(pairs.last?.a, between)
        XCTAssertEqual(pairs, Geometry.equalGapPairs(between, siblings: siblings, alongX: true))
        // A neighbour touching a card keeps it: the moving box, further on,
        // is not that card's next, so its gap to it is never bracketed.
        let touched = box(100.2, 0, 100, 100)
        let far = box(-300.2, 0, 100, 100)
        let row = [far, a, touched, box(500.2, 0, 100, 100)]
        let moving = box(300.2, 0, 100, 100)
        let equal = Geometry.equalGapPairs(moving, siblings: row, alongX: true,
                                           near: Geometry.neighbours(row, alongX: true))
        XCTAssertEqual(equal.map { ($0.gap * 1e6).rounded() / 1e6 }, [100, 100])
        XCTAssertEqual(equal, Geometry.equalGapPairs(moving, siblings: row, alongX: true))
        // And matching finds the same gap either way.
        let fresh = Geometry.matchingGap(moving: box(297, 10, 100, 80), siblings: siblings, threshold: 6)
        let cached = Geometry.matchingGap(moving: box(297, 10, 100, 80), siblings: siblings, threshold: 6,
                                          nearX: rows, nearY: columns)
        XCTAssertEqual(fresh.dx, cached.dx, accuracy: 1e-9)
        XCTAssertEqual(fresh.gapX, cached.gapX)
        XCTAssertEqual(fresh.pairs, cached.pairs)
    }

    func testSizesAreMatchedOnlyByAnElementSquareToThePageAndNeverALine() {
        var square = el("s", 0, 0, 100, 40)
        XCTAssertTrue(Geometry.matchesSizes(square))
        square.rotation = 360
        XCTAssertTrue(Geometry.matchesSizes(square))
        square.rotation = -720
        XCTAssertTrue(Geometry.matchesSizes(square))
        // A quarter turn beside a sibling of its width matches nothing.
        square.rotation = 90
        XCTAssertFalse(Geometry.matchesSizes(square))
        square.rotation = 180
        XCTAssertFalse(Geometry.matchesSizes(square))
        square.rotation = 15
        XCTAssertFalse(Geometry.matchesSizes(square))
        var line = Element.line(w: 100)
        line.h = 4
        XCTAssertFalse(Geometry.matchesSizes(line))
    }

    func testASideResizedToAnothersWidthSnapsToItAndSaysWhich() {
        let siblings = [el("card", 0, 200, 100, 40), el("other", 300, 200, 100, 70), el("wide", 0, 400, 300, 50)]
        let m = Geometry.matchingSize(box(0, 0, 97, 60), handle: .e, siblings: siblings, threshold: 6)
        XCTAssertEqual(m.w, 100, accuracy: 1e-9)
        XCTAssertEqual(m.h, 60, accuracy: 1e-9)
        XCTAssertEqual(m.widthOf, ["card", "other"])
        XCTAssertTrue(m.heightOf.isEmpty)
        // The top handle stretches only the height: 67 to 70.
        let tall = Geometry.matchingSize(box(0, 0, 97, 67), handle: .n, siblings: siblings, threshold: 6)
        XCTAssertEqual(tall.w, 97, accuracy: 1e-9)
        XCTAssertEqual(tall.h, 70, accuracy: 1e-9)
        XCTAssertEqual(tall.heightOf, ["other"])
        // Out of reach: as it was.
        let none = Geometry.matchingSize(box(0, 0, 120, 60), handle: .e, siblings: siblings, threshold: 6)
        XCTAssertEqual(none.w, 120, accuracy: 1e-9)
        XCTAssertTrue(none.widthOf.isEmpty)
    }

    func testACornerKeepingProportionsMatchesOneSideAndScalesTheOther() {
        let siblings = [el("card", 0, 200, 100, 40)]
        let m = Geometry.matchingSize(box(0, 0, 98, 49), handle: .se, siblings: siblings, threshold: 6, proportional: true)
        XCTAssertEqual(m.w, 100, accuracy: 1e-9)
        XCTAssertEqual(m.h, 50, accuracy: 1e-9)
        XCTAssertEqual(m.widthOf, ["card"])
        XCTAssertTrue(m.heightOf.isEmpty)
        // A stretching corner matches both on their own.
        let both = Geometry.matchingSize(box(0, 0, 98, 43), handle: .se, siblings: siblings, threshold: 6)
        XCTAssertEqual(both.w, 100, accuracy: 1e-9)
        XCTAssertEqual(both.h, 40, accuracy: 1e-9)
    }
}
