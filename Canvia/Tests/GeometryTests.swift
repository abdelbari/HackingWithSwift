// Unit tests for the transform math — the same checks that cover the
// JavaScript sibling implementation (73 assertions, all passing there).
//
// These live OUTSIDE Canvia/Canvia/ so the synchronized-folder app target
// never compiles them. To run: File ▸ New ▸ Target ▸ Unit Testing Bundle,
// then drag this file into the new target.

import XCTest
@testable import Canvia

final class GeometryTests: XCTestCase {

    private func element(x: Double = 100, y: Double = 150,
                         w: Double = 200, h: Double = 120,
                         rotation: Double = 0) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.x = x; el.y = y; el.rotation = rotation
        return el
    }

    /// The load-bearing invariant: resizing from any handle, at any rotation,
    /// must leave the opposite anchor exactly where it was.
    func testResizeKeepsOppositeAnchorFixed() {
        for rotation in [0.0, 17, 45, 90, 133, 270, 359] {
            for handle in Handle.allCases {
                let el = element(rotation: rotation)
                let anchorBefore = Geometry.handlePoint(el, handle.opposite)
                let grab = Geometry.handlePoint(el, handle)
                let next = Geometry.resize(el, handle: handle,
                                           to: CGPoint(x: grab.x + 37, y: grab.y - 22),
                                           proportional: false)
                var after = el
                after.x = next.minX; after.y = next.minY
                after.w = next.width; after.h = next.height
                let anchorAfter = Geometry.handlePoint(after, handle.opposite)
                XCTAssertEqual(anchorBefore.x, anchorAfter.x, accuracy: 0.01,
                               "x drifted for \(handle) at \(rotation)°")
                XCTAssertEqual(anchorBefore.y, anchorAfter.y, accuracy: 0.01,
                               "y drifted for \(handle) at \(rotation)°")
            }
        }
    }

    func testProportionalCornerResizeKeepsAspect() {
        let el = element(x: 0, y: 0, w: 300, h: 150, rotation: 30)
        let grab = Geometry.handlePoint(el, .se)
        let next = Geometry.resize(el, handle: .se,
                                   to: CGPoint(x: grab.x + 120, y: grab.y + 10),
                                   proportional: true)
        XCTAssertEqual(next.width / next.height, 2, accuracy: 0.01)
    }

    /// Dragging a handle past its anchor must clamp, never flip the element.
    func testResizeClampsInsteadOfFlipping() {
        let el = element(x: 100, y: 100, w: 200, h: 100)
        let anchor = Geometry.handlePoint(el, .w)
        let next = Geometry.resize(el, handle: .e,
                                   to: CGPoint(x: anchor.x - 500, y: anchor.y),
                                   proportional: false)
        XCTAssertEqual(next.width, 8, accuracy: 0.001)
        XCTAssertEqual(next.height, 100, accuracy: 0.001)
    }

    func testEdgeHandleLeavesOtherAxisAlone() {
        let el = element(x: 50, y: 60, w: 180, h: 90, rotation: 77)
        let grab = Geometry.handlePoint(el, .n)
        let next = Geometry.resize(el, handle: .n,
                                   to: CGPoint(x: grab.x + 5, y: grab.y - 40),
                                   proportional: false)
        XCTAssertEqual(next.width, el.w, accuracy: 0.01)
    }

    func testRotateRoundTrip() {
        let center = CGPoint(x: 50, y: 50)
        let p = Geometry.rotate(CGPoint(x: 10, y: 20), around: center, degrees: 123)
        let back = Geometry.rotate(p, around: center, degrees: -123)
        XCTAssertEqual(back.x, 10, accuracy: 0.0001)
        XCTAssertEqual(back.y, 20, accuracy: 0.0001)
    }

    func testRotatedBoundingBoxExpands() {
        let box = Geometry.aabb(element(x: 0, y: 0, w: 100, h: 100, rotation: 45))
        XCTAssertEqual(box.width, 100 * 2.0.squareRoot(), accuracy: 0.1)
        XCTAssertEqual(box.height, 100 * 2.0.squareRoot(), accuracy: 0.1)
    }

    func testHitTestRespectsRotation() {
        // Rotated 90°, this wide bar becomes a vertical bar through (50, 50).
        let el = element(x: 0, y: 40, w: 100, h: 20, rotation: 90)
        XCTAssertTrue(Geometry.hits(el, point: CGPoint(x: 50, y: 10)))
        XCTAssertFalse(Geometry.hits(el, point: CGPoint(x: 95, y: 45)))
    }

    func testSnapPicksNearestLineWithinThreshold() {
        let snapped = Geometry.snap(box: CGRect(x: 96, y: 200, width: 50, height: 50),
                                    xLines: [100], yLines: [], threshold: 6)
        XCTAssertEqual(snapped.dx, 4, accuracy: 0.001)
        XCTAssertEqual(snapped.guideX, 100)

        // Edges/center at 60, 85, 110 — all further than 6 from the line.
        let missed = Geometry.snap(box: CGRect(x: 60, y: 200, width: 50, height: 50),
                                   xLines: [100], yLines: [], threshold: 6)
        XCTAssertEqual(missed.dx, 0)
        XCTAssertNil(missed.guideX)
    }

    func testAngleSnapping() {
        XCTAssertEqual(Geometry.snapAngle(43), 45, accuracy: 0.001)
        XCTAssertEqual(Geometry.snapAngle(30), 30, accuracy: 0.001)
        XCTAssertEqual(Geometry.snapAngle(357), 0, accuracy: 0.001)
    }
}

/// Store behaviour that is easy to regress: one gesture is one undo step,
/// and copies must never stay welded to the source's group.
final class DesignStoreTests: XCTestCase {

    private func store() -> DesignStore {
        DesignStore(design: Design(title: "Test", width: 1000, height: 1000))
    }

    func testDragCoalescesIntoOneUndoStep() {
        let s = store()
        s.add(Element.shape("rect"))          // add() centres it on the page
        let afterAdd = s.page.elements.count
        let originalX = s.page.elements[0].x

        s.beginGesture()
        for i in 1...20 { s.design.pages[0].elements[0].x = originalX + Double(i) }
        s.commit()

        XCTAssertEqual(s.page.elements[0].x, originalX + 20, accuracy: 0.001)
        s.undo()
        XCTAssertEqual(s.page.elements[0].x, originalX, accuracy: 0.001,
                       "the whole drag should undo at once")
        XCTAssertEqual(s.page.elements.count, afterAdd)
    }

    func testCommitWithoutGestureRecordsNothing() {
        let s = store()
        s.add(Element.shape("rect"))         // the one real history step
        s.design.title = "Renamed"
        s.commit()                           // no beginGesture — must no-op

        s.undo()
        XCTAssertTrue(s.page.elements.isEmpty,
                      "undo must roll back the add, proving the bare commit recorded nothing")
        XCTAssertFalse(s.canUndo, "only one step should ever have been recorded")
    }

    func testDuplicateBreaksTheSourceGroupWeld() {
        let s = store()
        var a = Element.shape("rect"), b = Element.shape("circle")
        a.x = 10; b.x = 200
        s.applyToPage { $0.elements.append(contentsOf: [a, b]) }
        s.selection = [a.id, b.id]
        s.groupSelected()
        let sourceGroup = s.element(a.id)?.group
        XCTAssertNotNil(sourceGroup)

        s.duplicateSelected()
        let copies = s.selectedElements
        XCTAssertEqual(copies.count, 2)
        let copyGroups = Set(copies.compactMap(\.group))
        XCTAssertEqual(copyGroups.count, 1, "copies stay grouped with each other")
        XCTAssertNotEqual(copyGroups.first, sourceGroup, "…but not with the source")
    }

    func testDistributeEvenlyPinsOutermostElements() {
        let s = store()
        for x in [0.0, 140, 300, 500] {
            var el = Element.shape("rect", w: 60, h: 60)
            el.x = x; el.y = 0
            s.applyToPage { $0.elements.append(el) }
        }
        s.selectAll()
        let before = s.page.elements.map(\.x).sorted()
        s.distributeSelected(.horizontal)
        let after = s.page.elements.map(\.x).sorted()

        XCTAssertEqual(after.first!, before.first!, accuracy: 0.001)
        XCTAssertEqual(after.last!, before.last!, accuracy: 0.001)
        let gaps = zip(after, after.dropFirst()).map { $1 - $0 }
        for gap in gaps.dropFirst() {
            XCTAssertEqual(gap, gaps[0], accuracy: 0.001, "spacing should be even")
        }
    }

    func testPasteOffsetsEachTimeAndKeepsOriginal() {
        let s = store()
        var el = Element.shape("rect")
        el.x = 100; el.y = 100
        s.applyToPage { $0.elements.append(el) }
        s.selection = [el.id]

        s.copySelected()
        s.paste()
        s.paste()

        XCTAssertEqual(s.page.elements.count, 3)
        let xs = s.page.elements.map(\.x).sorted()
        XCTAssertEqual(xs, [100, 124, 148])
    }
}
