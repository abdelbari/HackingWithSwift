// The keys held while dragging (CanvasGestures.modified): the shared rows of
// modifier-gestures.json — Shift's axis lock and 15° turns, ⌘ turning
// snapping off, ⌥ duplicating — Shift on a corner, and a copy dragged away
// as one Duplicate step. The Android twin's Gestures rows, row for row.

import XCTest
@testable import Canvia

final class ModifierGesturesTests: XCTestCase {

    func testTheSharedModifierRows() throws {
        let root = try SharedFixture.object("modifier-gestures")
        XCTAssertEqual(root["axisLockTravel"] as? Double, CanvasGestures.axisLockTravel)
        for row in try XCTUnwrap(root["modified"] as? [[String: Any]]) {
            let made = CanvasGestures.modified(shift: row["shift"] as? Bool ?? false, alt: row["alt"] as? Bool ?? false,
                                               command: row["command"] as? Bool ?? false)
            XCTAssertEqual(made.axisLock, row["axisLock"] as? Bool, "\(row)")
            XCTAssertEqual(made.rotateStep, row["rotateStep"] as? Double, "\(row)")
            XCTAssertEqual(made.snapOff, row["snapOff"] as? Bool, "\(row)")
            XCTAssertEqual(made.duplicate, row["duplicate"] as? Bool, "\(row)")
        }
        func axis(_ name: Any?) -> CanvasGestures.Axis? {
            switch name as? String {
            case "horizontal": return .horizontal
            case "vertical": return .vertical
            default: return nil
            }
        }
        for row in try XCTUnwrap(root["axis"] as? [[String: Any]]) {
            let made = CanvasGestures.lockedAxis(dx: row["dx"] as? Double ?? 0, dy: row["dy"] as? Double ?? 0,
                                                 zoom: row["zoom"] as? Double ?? 1, held: axis(row["held"]),
                                                 shift: row["shift"] as? Bool ?? false)
            XCTAssertEqual(made, axis(row["axis"]), "\(row)")
        }
        for row in try XCTUnwrap(root["turns"] as? [[String: Any]]) {
            let made = CanvasGestures.steppedAngle(row["degrees"] as? Double ?? 0, step: row["step"] as? Double ?? 0)
            XCTAssertEqual(made, row["turned"] as? Double ?? -1, accuracy: 1e-9, "\(row)")
        }
    }

    func testShiftFreesATextOrShapeCornerOnly() {
        XCTAssertTrue(CanvasGestures.cornerKeepsProportions(Element.text("A"), shift: false))
        XCTAssertFalse(CanvasGestures.cornerKeepsProportions(Element.text("A"), shift: true))
        XCTAssertFalse(CanvasGestures.cornerKeepsProportions(Element.shape("rect"), shift: true))
        XCTAssertTrue(CanvasGestures.cornerKeepsProportions(Element.image("media:a"), shift: true))
        XCTAssertFalse(CanvasGestures.cornerKeepsProportions(Element.line(), shift: false))
        XCTAssertEqual(CanvasGestures.constrained(dx: 5, dy: 3, to: .horizontal).dy, 0)
        XCTAssertEqual(CanvasGestures.constrained(dx: 5, dy: 3, to: .vertical).dx, 0)
    }

    @MainActor
    func testOptionDragLeavesTheOriginalAndMovesACopyAsOneDuplicate() {
        var d = Design(title: "Drag", width: 1080, height: 1080)
        var card = Element.shape("rect")
        card.x = 100
        card.y = 100
        d.pages = [Page(elements: [card])]
        let store = DesignStore(design: d)
        store.select(card.id)
        store.beginGesture()
        XCTAssertTrue(store.duplicateForDrag())
        let copy = store.page.elements[1]
        XCTAssertEqual(store.selection, [copy.id], "the copy, on top, is what moves")
        store.design.pages[0].elements[1].x += 50
        store.commit()
        XCTAssertEqual(store.page.elements.map(\.x), [100, 150])
        XCTAssertEqual(store.page.elements[0].id, card.id, "the original stays below the copy")
        XCTAssertEqual(store.undoLabel, "Duplicate")
        store.undo()
        XCTAssertEqual(store.page.elements.map(\.id), [card.id])
    }
}
