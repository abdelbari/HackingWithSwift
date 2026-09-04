// What VoiceOver is told about a canvas element.

import XCTest
@testable import Canvia

final class CanvasAccessibilityTests: XCTestCase {

    private let design = Design(title: "a11y", width: 1000, height: 500)

    func testEachKindHasAName() {
        XCTAssertEqual(CanvasAccessibility.label(for: Element.text("Summer sale")), "Text: Summer sale")
        XCTAssertEqual(CanvasAccessibility.label(for: Element.text("   ")), "Empty text")
        XCTAssertTrue(CanvasAccessibility.label(for: Element.shape("rect")).hasSuffix(" shape"))
        XCTAssertEqual(CanvasAccessibility.label(for: Element.image("asset:x")), "Photo")
        XCTAssertEqual(CanvasAccessibility.label(for: Element.sticker("🎉")), "Sticker 🎉")
        var line = Element(); line.type = .line
        XCTAssertEqual(CanvasAccessibility.label(for: line), "Line")
    }

    func testLongTextIsClipped() {
        let long = String(repeating: "a", count: 200)
        let label = CanvasAccessibility.label(for: Element.text(long))
        XCTAssertTrue(label.hasSuffix("…"))
        XCTAssertLessThan(label.count, 100)
    }

    func testTheValueIsInPercentagesOfThePage() {
        var el = Element.shape("rect", w: 500, h: 100)
        el.x = 100; el.y = 250
        XCTAssertEqual(CanvasAccessibility.value(for: el, design: design),
                       "at 10% across, 50% down; 50% wide, 20% tall")
        el.rotation = 45
        el.locked = true
        XCTAssertEqual(CanvasAccessibility.value(for: el, design: design),
                       "at 10% across, 50% down; 50% wide, 20% tall; rotated 45 degrees; locked")
    }

    func testANudgeIsAHundredthOfTheLongSide() {
        XCTAssertEqual(CanvasAccessibility.nudge(for: design), 10)
    }
}
