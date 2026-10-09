// The edges of a box being resized snapping to the lines a move snaps to:
// a side's one edge, a free corner's two, and a shape-keeping corner's one
// axis, whichever needs the smaller correction.

import XCTest
@testable import Canvia

final class ResizeSnapTests: XCTestCase {

    private func box(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.x = x
        el.y = y
        return el
    }

    /// A side moves one edge, and that edge lands on a line within reach;
    /// the edge across from it stays put.
    func testASideSnapsItsMovingEdge() {
        let moving = CGRect(x: 100, y: 100, width: 296, height: 80)
        let snap = Geometry.snapResize(moving, handle: .e, xLines: [0, 400, 1000], yLines: [0, 140],
                                       threshold: 6, proportional: false, minSize: 8)
        XCTAssertEqual(snap.box, CGRect(x: 100, y: 100, width: 300, height: 80))
        XCTAssertEqual(snap.guideX, 400)
        XCTAssertNil(snap.guideY, "a side moves no edge across, so nothing snaps there")
    }

    func testANearSideSnapsAndKeepsTheFarEdge() {
        let moving = CGRect(x: 53, y: 0, width: 147, height: 50)
        let snap = Geometry.snapResize(moving, handle: .w, xLines: [50], yLines: [],
                                       threshold: 6, proportional: false, minSize: 8)
        XCTAssertEqual(snap.box.minX, 50)
        XCTAssertEqual(snap.box.maxX, 200)
        XCTAssertEqual(snap.guideX, 50)
    }

    /// A free corner moves two edges, and each snaps on its own axis.
    func testAFreeCornerSnapsBothEdges() {
        let moving = CGRect(x: 100, y: 100, width: 203, height: 197)
        let snap = Geometry.snapResize(moving, handle: .se, xLines: [300], yLines: [300],
                                       threshold: 6, proportional: false, minSize: 8)
        XCTAssertEqual(snap.box, CGRect(x: 100, y: 100, width: 200, height: 200))
        XCTAssertEqual(snap.guideX, 300)
        XCTAssertEqual(snap.guideY, 300)
    }

    /// A corner keeping the shape snaps one axis only — the one needing the
    /// smaller correction — and the other follows through the shape.
    func testAShapeKeepingCornerSnapsTheNearerAxisOnly() {
        // 2:1. The right edge is 4 short of 500, the bottom 1 past 297.
        let moving = CGRect(x: 100, y: 100, width: 396, height: 198)
        let snap = Geometry.snapResize(moving, handle: .se, xLines: [500], yLines: [297],
                                       threshold: 6, proportional: true, minSize: 8)
        XCTAssertEqual(snap.guideY, 297)
        XCTAssertNil(snap.guideX)
        XCTAssertEqual(snap.box.maxY, 297, accuracy: 1e-9)
        XCTAssertEqual(snap.box.width / snap.box.height, 2, accuracy: 1e-9)
        XCTAssertEqual(snap.box.minX, 100)
        XCTAssertEqual(snap.box.minY, 100)
    }

    /// From the top-left corner, the bottom-right stays anchored.
    func testATopLeftCornerKeepsTheBottomRightAnchored() {
        let moving = CGRect(x: 102, y: 150, width: 198, height: 150)
        let snap = Geometry.snapResize(moving, handle: .nw, xLines: [100], yLines: [],
                                       threshold: 6, proportional: true, minSize: 8)
        XCTAssertEqual(snap.guideX, 100)
        XCTAssertEqual(snap.box.maxX, 300, accuracy: 1e-9)
        XCTAssertEqual(snap.box.maxY, 300, accuracy: 1e-9)
        XCTAssertEqual(snap.box.width / snap.box.height, 198.0 / 150.0, accuracy: 1e-9)
    }

    /// Out of reach, or a snap that would squeeze the box under its least
    /// size or turn it inside out, leaves the box as the finger has it.
    func testNoSnapOutOfReachOrUnderTheLeastSize() {
        let moving = CGRect(x: 100, y: 100, width: 50, height: 50)
        let far = Geometry.snapResize(moving, handle: .e, xLines: [170], yLines: [],
                                      threshold: 6, proportional: false, minSize: 8)
        XCTAssertEqual(far.box, moving)
        XCTAssertNil(far.guideX)
        let small = CGRect(x: 100, y: 100, width: 10, height: 50)
        let squeezed = Geometry.snapResize(small, handle: .e, xLines: [105], yLines: [],
                                           threshold: 6, proportional: false, minSize: 8)
        XCTAssertEqual(squeezed.box, small)
        XCTAssertNil(squeezed.guideX)
    }

    /// The nearer of two lines in reach wins, as a move's snap picks.
    func testTheNearerLineWins() {
        let moving = CGRect(x: 0, y: 0, width: 100, height: 100)
        let snap = Geometry.snapResize(moving, handle: .s, xLines: [], yLines: [96, 103],
                                       threshold: 6, proportional: false, minSize: 8)
        XCTAssertEqual(snap.guideY, 103)
        XCTAssertEqual(snap.box.height, 103)
    }

    /// Turned a quarter, a side snaps the edge the turn has put it on, as on
    /// the Android twin: the right side of a box turned 90° is its bottom on
    /// the page, and its left side, at the top, stays put. Turned off the
    /// square, nothing snaps.
    func testAQuarterTurnedSideSnapsTheEdgeItMovesOnThePage() throws {
        // 200 × 100 about (200, 150): on the page, 150 to 250 across and 50
        // to 250 down.
        let frame = CGRect(x: 100, y: 100, width: 200, height: 100)
        let snap = try XCTUnwrap(Geometry.snapTurnedResize(frame, rotation: 90, handle: .e, xLines: [], yLines: [253],
                                                           threshold: 6, proportional: false, minSize: 8))
        XCTAssertEqual(snap.guideY, 253)
        XCTAssertNil(snap.guideX)
        XCTAssertEqual(snap.box.width, 203, accuracy: 1e-9)
        XCTAssertEqual(snap.box.height, 100, accuracy: 1e-9)
        XCTAssertEqual(snap.box.midX, 200, accuracy: 1e-9)
        XCTAssertEqual(snap.box.midY, 151.5, accuracy: 1e-9)

        let up = try XCTUnwrap(Geometry.snapTurnedResize(frame, rotation: -90, handle: .e, xLines: [], yLines: [47],
                                                         threshold: 6, proportional: false, minSize: 8))
        XCTAssertEqual(up.guideY, 47, "turned back a quarter, the right side is the top")
        let half = try XCTUnwrap(Geometry.snapTurnedResize(frame, rotation: 180, handle: .e, xLines: [97], yLines: [],
                                                           threshold: 6, proportional: false, minSize: 8))
        XCTAssertEqual(half.box, CGRect(x: 97, y: 100, width: 203, height: 100), "turned half, the right side is the left")
        XCTAssertNil(Geometry.snapTurnedResize(frame, rotation: 30, handle: .e, xLines: [], yLines: [253],
                                               threshold: 6, proportional: false, minSize: 8))
    }

    /// The lines are a move's: the page, other elements, the grid.
    func testAResizeSnapsToAnotherElementsEdge() {
        let other = box(500, 0, 100, 100)
        var design = Design(title: "snap", width: 1000, height: 1000)
        design.pages[0].elements = [other]
        let lines = Geometry.snapLines(design: design, page: design.pages[0], excluding: [])
        let snap = Geometry.snapResize(CGRect(x: 100, y: 300, width: 397, height: 100), handle: .e,
                                       xLines: lines.x, yLines: lines.y,
                                       threshold: 6, proportional: false, minSize: 8)
        XCTAssertEqual(snap.box.maxX, 500)
    }
}
