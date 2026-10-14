// Round 29's VoiceOver transforms, with the rows the Android twin's
// ReaderTransformsTest holds too: Make larger and Make smaller a tenth about
// the centre, a text's type scaling and a line growing along its length,
// the turns onto multiples of fifteen degrees, each one step, and none for
// what is locked in place.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class ReaderTransformsTests: XCTestCase {

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

    // MARK: VoiceOver's transforms

    func testTurningGoesToTheNextMultipleOfFifteenEitherWay() {
        XCTAssertEqual(CanvasAccessibility.turned(0, clockwise: true), 15, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(7, clockwise: true), 15, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(15, clockwise: true), 30, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(350, clockwise: true), 0, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(0, clockwise: false), 345, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(7, clockwise: false), 0, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(15, clockwise: false), 0, accuracy: 1e-9)
        // A hundred-thousandth short of a multiple is not on it; a hair is.
        XCTAssertEqual(CanvasAccessibility.turned(29.99999, clockwise: true), 30, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(29.99999, clockwise: false), 15, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(30.0000000001, clockwise: true), 45, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turned(30.0000000001, clockwise: false), 15, accuracy: 1e-9)
        XCTAssertEqual(CanvasAccessibility.turnStep, 15)
    }

    func testLargerAndSmallerAreATenthAboutTheCentreKeepingProportions() throws {
        var photo = Element.image("img:a", w: 200, h: 100)
        photo.id = "p"
        photo.x = 100
        photo.y = 100
        photo.rotation = 30
        let larger = try XCTUnwrap(CanvasAccessibility.scaled(photo, larger: true))
        XCTAssertEqual(larger.w, 220, accuracy: 1e-9)
        XCTAssertEqual(larger.h, 110, accuracy: 1e-9)
        XCTAssertEqual(larger.rotation, 30)
        XCTAssertEqual(larger.center.x, photo.center.x, accuracy: 1e-9)
        XCTAssertEqual(larger.center.y, photo.center.y, accuracy: 1e-9)
        let smaller = try XCTUnwrap(CanvasAccessibility.scaled(photo, larger: false))
        XCTAssertEqual(smaller.w, 180, accuracy: 1e-9)
        XCTAssertEqual(smaller.h, 90, accuracy: 1e-9)
    }

    func testTextScalesItsTypeAndALineGrowsAlongItsLength() throws {
        var text = Element.text("Hello", fontSize: 40, w: 300)
        text.id = "t"
        text.h = 50
        let larger = try XCTUnwrap(CanvasAccessibility.scaled(text, larger: true))
        XCTAssertEqual(try XCTUnwrap(larger.fontSize), 44, accuracy: 1e-9)
        XCTAssertEqual(larger.w, 330, accuracy: 1e-9)
        XCTAssertEqual(larger.center.x, 150, accuracy: 1e-9)
        var line = Element.line(w: 200)
        line.id = "l"
        line.h = 10
        let longer = try XCTUnwrap(CanvasAccessibility.scaled(line, larger: true))
        XCTAssertEqual(longer.w, 220, accuracy: 1e-9)
        XCTAssertEqual(longer.h, 10, accuracy: 1e-9)
        XCTAssertEqual(longer.center.x, 100, accuracy: 1e-9)
        // At its least already, nothing to make smaller.
        let least = box("tiny", 0, 0, 8, 8)
        XCTAssertNil(CanvasAccessibility.scaled(least, larger: false))
    }

    func testSmallerStopsWhereASideOrTheTypeWouldGoUnderItsLeastKeepingProportions() throws {
        // A thin divider is at its least across already: nothing changes,
        // rather than it getting shorter and no thinner.
        XCTAssertNil(CanvasAccessibility.scaled(box("d", 0, 0, 300, 8), larger: false))
        XCTAssertNil(CanvasAccessibility.scaled(box("s", 0, 0, 8, 8), larger: false))
        // Under its least already, smaller leaves it as it is.
        XCTAssertNil(CanvasAccessibility.scaled(box("u", 0, 0, 5, 5), larger: false))
        // Small type, still above its least, takes the whole tenth.
        var small = Element.text("Hi", fontSize: 6.5, w: 13)
        small.id = "a"
        small.h = 10
        let smaller = try XCTUnwrap(CanvasAccessibility.scaled(small, larger: false))
        XCTAssertEqual(try XCTUnwrap(smaller.fontSize), 5.85, accuracy: 1e-9)
        XCTAssertEqual(smaller.w, 11.7, accuracy: 1e-9)
        XCTAssertEqual(smaller.h, 9, accuracy: 1e-9)
        // Type a little over its least stops on it, the box with it.
        var least = Element.text("Hi", fontSize: 4.2, w: 100)
        least.id = "b"
        least.h = 20
        let floored = try XCTUnwrap(CanvasAccessibility.scaled(least, larger: false))
        XCTAssertEqual(try XCTUnwrap(floored.fontSize), 4, accuracy: 1e-9)
        XCTAssertEqual(floored.w, 100 * 4 / 4.2, accuracy: 1e-9)
        // A line shortens to the least and keeps its thickness.
        var line = Element.line(w: 8.5)
        line.id = "l"
        line.h = 4
        let shorter = try XCTUnwrap(CanvasAccessibility.scaled(line, larger: false))
        XCTAssertEqual(shorter.w, 8, accuracy: 1e-9)
        XCTAssertEqual(shorter.h, 4, accuracy: 1e-9)
    }

    func testEachIsOneStepSelectsFirstAndLeavesWhatIsLockedInPlace() {
        var d = Design(title: "reader", width: 1000, height: 1000)
        var pinned = box("pinned", 500, 500, 100, 100)
        pinned.lockPosition = true
        d.pages = [Page(id: "p1", elements: [box("a", 0, 0, 100, 100), pinned])]
        let s = DesignStore(design: d)
        XCTAssertTrue(s.resizeForScreenReader("a", larger: true))
        XCTAssertEqual(s.selection, ["a"])
        XCTAssertEqual(s.element("a")?.w ?? 0, 110, accuracy: 1e-9)
        XCTAssertTrue(s.turnForScreenReader("a", clockwise: true))
        XCTAssertEqual(s.element("a")?.rotation, 15)
        s.undo()
        XCTAssertEqual(s.element("a")?.rotation, 0, "one step each")
        XCTAssertEqual(s.element("a")?.w ?? 0, 110, accuracy: 1e-9)
        XCTAssertFalse(s.resizeForScreenReader("pinned", larger: true))
        XCTAssertFalse(s.turnForScreenReader("pinned", clockwise: true))
        XCTAssertEqual(s.element("pinned")?.w, 100)
        XCTAssertTrue(CanvasAccessibility.value(for: s.element("a")!, design: s.design).contains("11% wide"))
    }

    func testAnElbowedLineIsNotTurned() {
        var d = Design(title: "reader", width: 1000, height: 1000)
        var elbow = Element.line(w: 200)
        elbow.id = "e"
        elbow.lineType = "elbow"
        d.pages = [Page(id: "p1", elements: [elbow])]
        let s = DesignStore(design: d)
        XCTAssertFalse(s.turnForScreenReader("e", clockwise: true))
        XCTAssertEqual(s.element("e")?.rotation, 0)
    }
}
