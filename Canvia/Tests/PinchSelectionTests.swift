// Round 32's pinch and twist on the selection, with the rows the Android
// twin's GesturesTest and GeometryTest hold too: when two fingers work the
// selection rather than the view, and what Geometry.pinched makes of text,
// a photo, a group and something locked.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class PinchSelectionTests: XCTestCase {

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     rotation: Double = 0, group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.rotation = rotation
        el.group = group
        return el
    }

    private func pinches(_ a: CGPoint, _ b: CGPoint, _ selected: [Element], zoom: Double = 1,
                         pageLocked: Bool = false, busy: Bool = false) -> Bool {
        CanvasGestures.pinchesSelection(a, b, selected: selected, zoom: zoom, pageLocked: pageLocked, busy: busy)
    }

    // MARK: the gesture

    func testTwoFingersOnTheSelectionWorkIt() {
        let one = box("a", x: 100, y: 100)
        XCTAssertTrue(pinches(CGPoint(x: 120, y: 120), CGPoint(x: 180, y: 180), [one]))
        XCTAssertFalse(pinches(CGPoint(x: 120, y: 120), CGPoint(x: 400, y: 400), [one]), "one finger off it")
        XCTAssertFalse(pinches(CGPoint(x: 120, y: 120), CGPoint(x: 180, y: 180), []), "nothing selected")

        // Widened by the fingertip's 44 points on screen, 22 each side.
        let small = box("s", x: 100, y: 100, w: 10, h: 10)
        XCTAssertTrue(pinches(CGPoint(x: 85, y: 85), CGPoint(x: 120, y: 120), [small]))
        XCTAssertFalse(pinches(CGPoint(x: 85, y: 85), CGPoint(x: 120, y: 120), [small], zoom: 2),
                       "zoomed in, the same target is half as much of the page")

        // Android's GesturesTest rows: a 100 x 50 box turned 90°, standing
        // 50 wide and 100 tall about 150,125, with a reach of 20 (44 points
        // at 2.2 times).
        let upright = box("u", x: 100, y: 100, w: 100, h: 50, rotation: 90)
        let rows: [(CGPoint, CGPoint, Bool)] = [
            (CGPoint(x: 150, y: 85), CGPoint(x: 150, y: 165), true),
            // Off its turned body, though inside its upright box.
            (CGPoint(x: 150, y: 85), CGPoint(x: 195, y: 125), false),
            // Within the fingertip's reach (20: 10 either side) of its edge.
            (CGPoint(x: 134, y: 125), CGPoint(x: 150, y: 184), true),
            (CGPoint(x: 134, y: 125), CGPoint(x: 150, y: 186), false),
            // One finger off it altogether.
            (CGPoint(x: 150, y: 125), CGPoint(x: 400, y: 400), false),
        ]
        for (a, b, expected) in rows {
            XCTAssertEqual(pinches(a, b, [upright], zoom: 2.2), expected, "\(a) \(b)")
        }

        // In its turned frame.
        let turned = box("t", x: 100, y: 100, w: 200, h: 100, rotation: 90)
        XCTAssertTrue(pinches(CGPoint(x: 200, y: 60), CGPoint(x: 200, y: 240), [turned]))
        XCTAssertFalse(pinches(CGPoint(x: 110, y: 150), CGPoint(x: 200, y: 150), [turned]))

        // Several: the box round them.
        let a = box("a", x: 0, y: 0), b = box("b", x: 300, y: 0)
        XCTAssertTrue(pinches(CGPoint(x: 50, y: 50), CGPoint(x: 350, y: 50), [a, b]))
        XCTAssertFalse(pinches(CGPoint(x: 50, y: 50), CGPoint(x: 50, y: 150), [a, b]))
    }

    func testThePinchIsRefusedWhereNothingMayChange() {
        let at = (CGPoint(x: 120, y: 120), CGPoint(x: 180, y: 180))
        var locked = box("a", x: 100, y: 100)
        locked.locked = true
        XCTAssertFalse(pinches(at.0, at.1, [locked]))
        var pinned = box("a", x: 100, y: 100)
        pinned.lockPosition = true
        XCTAssertFalse(pinches(at.0, at.1, [pinned]))
        let free = box("a", x: 100, y: 100)
        XCTAssertFalse(pinches(at.0, at.1, [free], pageLocked: true), "a locked page")
        XCTAssertFalse(pinches(at.0, at.1, [free], busy: true), "crop, typing, draw, erase or brush")
        XCTAssertEqual(CanvasGestures.twoFingerInput(at.0, at.1, selected: [free], zoom: 1, pageLocked: false, busy: false),
                       .twoFingersOnSelection)
        XCTAssertEqual(CanvasGestures.twoFingerInput(at.0, at.1, selected: [locked], zoom: 1, pageLocked: false, busy: false),
                       .twoFingers)
        XCTAssertEqual(CanvasGestures.pinchSelectionKey, "canvia.pinchSelection")
    }

    // MARK: Geometry.pinched

    func testTextScalesItsType() {
        var text = Element.text("Hi", fontSize: 24, w: 200)
        text.id = "t"
        text.x = 0; text.y = 0; text.h = 30
        text.letterSpacing = 2
        let out = Geometry.pinched([text], centre: text.center, scale: 2, turnDeg: 0)[0]
        XCTAssertEqual(out.w, 400, accuracy: 1e-9)
        XCTAssertEqual(out.h, 60, accuracy: 1e-9)
        XCTAssertEqual(out.x, -100, accuracy: 1e-9)
        XCTAssertEqual(out.y, -15, accuracy: 1e-9)
        XCTAssertEqual(out.fontSize, 48)
        XCTAssertEqual(out.letterSpacing ?? 0, 4, accuracy: 1e-9)
        // The type to a tenth of a point, on both phones: 24 by 1.3333 is 32.
        XCTAssertEqual(Geometry.pinched([text], centre: text.center, scale: 1.3333, turnDeg: 0)[0].fontSize, 32)

        // Never under 4 points of type: a pinch to a quarter stops at half.
        var tiny = text
        tiny.fontSize = 8
        tiny.h = 20
        let least = Geometry.pinched([tiny], centre: tiny.center, scale: 0.25, turnDeg: 0)[0]
        XCTAssertEqual(least.fontSize, Geometry.minFontSize)
        XCTAssertEqual(least.w, 100, accuracy: 1e-9)
        XCTAssertEqual(least.h, 10, accuracy: 1e-9)
    }

    func testAPhotoScalesEvenlyAndTurns() {
        var photo = Element.image("photo.jpg", w: 400, h: 300)
        photo.id = "p"
        photo.cropX = 0.3
        let out = Geometry.pinched([photo], centre: photo.center, scale: 0.5, turnDeg: 30)[0]
        XCTAssertEqual(out.w, 200, accuracy: 1e-9)
        XCTAssertEqual(out.h, 150, accuracy: 1e-9)
        XCTAssertEqual(out.x, 100, accuracy: 1e-9)
        XCTAssertEqual(out.y, 75, accuracy: 1e-9)
        XCTAssertEqual(out.rotation, 30, accuracy: 1e-9)
        XCTAssertEqual(out.cropX, 0.3, "its crop is all proportions")
    }

    func testAGroupScalesAndTurnsAboutItsMiddle() {
        let a = box("a", x: 0, y: 0, group: "g"), b = box("b", x: 200, y: 0, group: "g")
        let turned = Geometry.pinched([a, b], centre: CGPoint(x: 150, y: 50), scale: 1, turnDeg: 90)
        XCTAssertEqual(turned[0].x, 100, accuracy: 1e-9)
        XCTAssertEqual(turned[0].y, -100, accuracy: 1e-9)
        XCTAssertEqual(turned[1].x, 100, accuracy: 1e-9)
        XCTAssertEqual(turned[1].y, 100, accuracy: 1e-9)
        XCTAssertEqual(turned.map(\.rotation), [90, 90])
        XCTAssertEqual(turned.map(\.groupTurn), [90, 90], "the group keeps its turn")

        let grown = Geometry.pinched([a, b], centre: CGPoint(x: 150, y: 50), scale: 2, turnDeg: 0)
        XCTAssertEqual(grown[0].x, -150, accuracy: 1e-9)
        XCTAssertEqual(grown[0].w, 200, accuracy: 1e-9)
        XCTAssertEqual(grown[1].x, 250, accuracy: 1e-9)
        XCTAssertEqual(grown.map(\.groupTurn), [nil, nil], "not turned, no turn written")

        // Two things of no one group keep their turns — Android's row.
        var tilted = a
        tilted.groupTurn = 10
        let loose = box("c", x: 400, y: 0)
        XCTAssertEqual(Geometry.pinched([tilted, loose], centre: CGPoint(x: 150, y: 50), scale: 1, turnDeg: 90)[0].groupTurn, 10)
    }

    func testSomethingLockedStaysPut() {
        var locked = box("l", x: 0, y: 0)
        locked.locked = true
        let free = box("f", x: 200, y: 0)
        let out = Geometry.pinched([locked, free], centre: CGPoint(x: 150, y: 50), scale: 2, turnDeg: 45)
        XCTAssertEqual(out[0], locked)
        XCTAssertEqual(out[1].w, 200, accuracy: 1e-9)
        XCTAssertEqual(out[1].rotation, 45, accuracy: 1e-9)
        XCTAssertEqual(Geometry.pinched([locked], centre: .zero, scale: 3, turnDeg: 10), [locked])
    }

    // MARK: the store

    private func store(_ elements: [Element], locked: Bool = false) -> DesignStore {
        var d = Design(title: "pinch", width: 1080, height: 1080)
        var page = Page(id: "p1", elements: elements)
        page.locked = locked ? true : nil
        d.pages = [page]
        return DesignStore(design: d)
    }

    func testThePinchIsOneStepNamedResizeOrTurn() {
        let s = store([box("a", x: 100, y: 100)])
        s.select("a")
        guard var session = s.beginPinch() else { return XCTFail("the pinch should begin") }
        s.pinchSelection(&session, scale: 1.2, turn: 0)
        s.pinchSelection(&session, scale: 1.5, turn: 2)
        s.endPinch(session)
        XCTAssertEqual(s.undoLabel, "Resize")
        XCTAssertEqual(s.element("a")?.w ?? 0, 150, accuracy: 1e-9)
        XCTAssertEqual(s.element("a")?.rotation, 0, "2° is held on the snap at 0")
        XCTAssertNil(s.badge)

        guard var turning = s.beginPinch() else { return XCTFail("the pinch should begin") }
        s.pinchSelection(&turning, scale: 1, turn: 30)
        XCTAssertEqual(s.badge, "150 × 150 · 30°")
        s.endPinch(turning)
        XCTAssertEqual(s.undoLabel, "Turn")
        s.undo()
        XCTAssertEqual(s.element("a")?.rotation, 0)
        XCTAssertEqual(s.element("a")?.w ?? 0, 150, accuracy: 1e-9, "the turn was its own step")
    }

    func testALockedPageOrElementIsNotPinched() {
        let page = store([box("a", x: 100, y: 100)], locked: true)
        page.selection = ["a"]
        XCTAssertNil(page.beginPinch())
        var el = box("a", x: 100, y: 100)
        el.locked = true
        let s = store([el])
        s.selection = ["a"]
        XCTAssertNil(s.beginPinch())
    }
}
