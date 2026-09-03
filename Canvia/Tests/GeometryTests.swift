// Unit tests for the transform math — the same checks that cover the
// JavaScript sibling implementation (73 assertions, all passing there).
//
// These live OUTSIDE Canvia/Canvia/ so the synchronized-folder app target
// never compiles them. To run: File ▸ New ▸ Target ▸ Unit Testing Bundle,
// then drag this file into the new target.

import XCTest
import CoreGraphics
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
/// The identity the drag path relies on: it computes the union of the dragged
/// elements' bounding boxes once, at grab time, and merely translates it on
/// each touch move rather than looking every element up and re-deriving its
/// box. That is only sound if translating an element translates its AABB
/// exactly — including when the element is rotated.
final class DragUnionTests: XCTestCase {

    private func element(x: Double, y: Double, w: Double = 120, h: Double = 80,
                         rotation: Double = 0) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.x = x; el.y = y; el.rotation = rotation
        return el
    }

    func testTranslatingARotatedElementTranslatesItsAABB() {
        for rotation in [0.0, 23, 45, 90, 137, 250, 359] {
            let start = element(x: 100, y: 150, rotation: rotation)
            var moved = start
            moved.x += 37
            moved.y -= 61

            let translated = Geometry.aabb(start).offsetBy(dx: 37, dy: -61)
            let recomputed = Geometry.aabb(moved)

            XCTAssertEqual(translated.minX, recomputed.minX, accuracy: 0.0001,
                           "AABB drifted at \(rotation) degrees")
            XCTAssertEqual(translated.minY, recomputed.minY, accuracy: 0.0001)
            XCTAssertEqual(translated.width, recomputed.width, accuracy: 0.0001)
            XCTAssertEqual(translated.height, recomputed.height, accuracy: 0.0001)
        }
    }

    /// And that the union of translated boxes equals the translated union, so
    /// the shortcut holds for a multi-element drag too.
    func testUnionOfTranslatedBoxesEqualsTranslatedUnion() {
        let elements = [
            element(x: 0, y: 0, rotation: 0),
            element(x: 300, y: 90, w: 60, h: 200, rotation: 31),
            element(x: -80, y: 240, w: 150, h: 40, rotation: 300),
        ]
        let dx = 44.0, dy = 19.0

        let translatedUnion = Geometry.union(elements.map(Geometry.aabb))
            .offsetBy(dx: dx, dy: dy)
        let unionOfTranslated = Geometry.union(elements.map { el -> CGRect in
            var moved = el
            moved.x += dx
            moved.y += dy
            return Geometry.aabb(moved)
        })

        XCTAssertEqual(translatedUnion.minX, unionOfTranslated.minX, accuracy: 0.0001)
        XCTAssertEqual(translatedUnion.minY, unionOfTranslated.minY, accuracy: 0.0001)
        XCTAssertEqual(translatedUnion.width, unionOfTranslated.width, accuracy: 0.0001)
        XCTAssertEqual(translatedUnion.height, unionOfTranslated.height, accuracy: 0.0001)
    }
}

/// The zoom-dependent interaction constants. These regressed once already:
/// a screen-point threshold was capped in page units, which inverted its
/// meaning at the fit zoom every design opens at, so a tap moved the element.
final class TouchTests: XCTestCase {

    private func shape(w: Double, h: Double, type: ElementType = .shape) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.type = type
        return el
    }

    /// The load-bearing property: a threshold expressed in screen points must
    /// survive the round trip into page units and back out at ANY zoom.
    func testDragSlopIsConstantOnScreen() {
        for zoom in [0.1, 0.31, 0.5, 1.0, 2.0, 4.0] {
            let pageDistance = Touch.pageUnits(Touch.dragSlop, zoom: zoom)
            XCTAssertEqual(pageDistance * zoom, Touch.dragSlop, accuracy: 0.0001,
                           "drag slop drifted at zoom \(zoom)")
        }
    }

    /// The specific bug: at the fit zoom for a 1080-wide design on a phone the
    /// old form yielded ~2 page units, i.e. ~0.6pt on glass.
    func testDragSlopAtFitZoomIsNotHairTrigger() {
        let fitZoom = 0.31
        let pageDistance = Touch.pageUnits(Touch.dragSlop, zoom: fitZoom)
        XCTAssertGreaterThan(pageDistance * fitZoom, 8,
                             "a tap at fit zoom would still register as a drag")
    }

    func testHitTargetNeverBelowAppleMinimum() {
        // A default line is 8 units tall; at fit zoom that is a 2.5pt sliver.
        let thin = shape(w: 300, h: 8, type: .line)
        for zoom in [0.2, 0.31, 1.0] {
            let floor = Touch.pageUnits(Touch.minTarget, zoom: zoom)
            XCTAssertGreaterThanOrEqual(max(thin.h, floor) * zoom, Touch.minTarget - 0.001,
                                        "hit target too small at zoom \(zoom)")
        }
    }

    func testHandlesVanishOnTinyElements() {
        // 62pt on screen: eight 34pt targets would cover the whole element.
        XCTAssertTrue(Touch.handleSet(for: shape(w: 200, h: 200), zoom: 0.2).isEmpty)
    }

    func testHandlesDropToCornersWhenTight() {
        let handles = Touch.handleSet(for: shape(w: 200, h: 200), zoom: 0.5)
        XCTAssertFalse(handles.isEmpty)
        XCTAssertTrue(handles.allSatisfy(\.isCorner), "edge handles crowd a 100pt box")
    }

    func testHandlesFullSetWhenRoomy() {
        let handles = Touch.handleSet(for: shape(w: 400, h: 400), zoom: 1.0)
        XCTAssertEqual(Set(handles), Set(Handle.allCases))
    }

    /// A line only ever resizes along its length, at any size that shows handles.
    func testLineKeepsOnlyEndHandles() {
        let line = shape(w: 600, h: 8, type: .line)
        XCTAssertEqual(Set(Touch.handleSet(for: line, zoom: 1.0)), [])
        let tall = shape(w: 600, h: 200, type: .line)
        XCTAssertTrue(Touch.handleSet(for: tall, zoom: 1.0).allSatisfy { $0 == .e || $0 == .w })
    }
}

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

    /// Sorting by leading edge does not put the element with the greatest
    /// trailing edge last, so span must come from the true union.
    func testDistributePreservesOuterBoundsWithAWideMiddleElement() {
        let s = store()
        for (x, w) in [(0.0, 60.0), (100.0, 300.0), (500.0, 60.0)] {
            var el = Element.shape("rect", w: w, h: 50)
            el.x = x; el.y = 0
            s.applyToPage { $0.elements.append(el) }
        }
        s.selectAll()
        let leftBefore = s.page.elements.map(\.x).min()!
        let rightBefore = s.page.elements.map { $0.x + $0.w }.max()!

        s.distributeSelected(.horizontal)

        XCTAssertEqual(s.page.elements.map(\.x).min()!, leftBefore, accuracy: 0.001)
        XCTAssertEqual(s.page.elements.map { $0.x + $0.w }.max()!, rightBefore, accuracy: 0.001,
                       "the outermost edge must not be dragged inward")
    }

    func testLockedElementsAreNotDeletedAndStaySelected() {
        let s = store()
        var free = Element.shape("rect"), locked = Element.shape("circle")
        free.x = 0; locked.x = 200; locked.locked = true
        s.applyToPage { $0.elements.append(contentsOf: [free, locked]) }
        s.selection = [free.id, locked.id]

        s.deleteSelected()
        XCTAssertNil(s.element(free.id))
        XCTAssertNotNil(s.element(locked.id), "a locked element must survive delete")
        XCTAssertEqual(s.selection, [locked.id], "and stay selected, so it's visibly what remained")

        let stepsBefore = s.canUndo
        s.deleteSelected()          // nothing removable now
        XCTAssertTrue(stepsBefore)
        s.undo()
        XCTAssertNotNil(s.element(free.id), "the no-op delete must not have recorded a step")
    }

    func testPastedCopiesAreUnlocked() {
        let s = store()
        var locked = Element.shape("rect")
        locked.locked = true
        s.applyToPage { $0.elements.append(locked) }
        s.selection = [locked.id]
        s.copySelected()
        s.paste()
        XCTAssertFalse(s.selectedElements.contains { $0.locked },
                       "a pasted element the user cannot move is a dead end")
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
