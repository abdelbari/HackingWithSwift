// Changing a shape into another in place keeps everything but the shape,
// leaves drawn strokes, traced outlines and locked shapes alone, and records
// nothing when nothing changes.

import XCTest
@testable import Canvia

@MainActor
final class ShapeSwapTests: XCTestCase {

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "swap", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    func testAShapeBecomesAnotherKeepingItsLook() {
        var rect = Element.shape("rect", w: 300, h: 120)
        rect.x = 40; rect.y = 60
        rect.fill = .solid("#e11d48")
        rect.stroke = "#111111"; rect.strokeWidth = 6
        rect.opacity = 0.8
        let s = store([rect])
        s.select(rect.id)
        s.swapShape(to: "circle")
        let after = try? XCTUnwrap(s.element(rect.id))
        XCTAssertEqual(after?.shapeId, "circle")
        XCTAssertEqual(after?.x, 40); XCTAssertEqual(after?.y, 60)
        XCTAssertEqual(after?.w, 300); XCTAssertEqual(after?.h, 120)
        XCTAssertEqual(after?.fill, .solid("#e11d48"))
        XCTAssertEqual(after?.stroke, "#111111")
        XCTAssertEqual(after?.strokeWidth, 6)
        XCTAssertEqual(after?.opacity, 0.8)
        s.undo()
        XCTAssertEqual(s.element(rect.id)?.shapeId, "rect", "one step")
    }

    func testOwnGeometryAndLockedShapesAreLeftAlone() {
        var traced = Element.shape("rect")
        traced.pathData = "M0 0 L100 0 L50 100 Z"
        var locked = Element.shape("rect")
        locked.locked = true
        XCTAssertFalse(DesignStore.swapsShape(traced))
        XCTAssertTrue(DesignStore.swapsShape(Element.shape("star")))
        let s = store([traced, locked])
        s.selection = [traced.id, locked.id]
        s.swapShape(to: "circle")
        XCTAssertEqual(s.element(traced.id)?.shapeId, "rect")
        XCTAssertEqual(s.element(locked.id)?.shapeId, "rect")
        XCTAssertFalse(s.canUndo, "nothing changed, so nothing was recorded")
    }
}
