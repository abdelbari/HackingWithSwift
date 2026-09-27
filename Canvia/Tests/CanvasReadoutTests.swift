// What the canvas says while things are dragged, and after copy, cut and
// delete — the Android twin's words, part for part.

import XCTest
@testable import Canvia

@MainActor
final class CanvasReadoutTests: XCTestCase {

    func testAMoveReadsBothAxesAndMarksTheHeldOne() {
        let runs = Readouts.move(x: 120.4, y: 48, heldX: true, heldY: false, gapX: nil, gapY: nil)
        XCTAssertEqual(Readouts.text(runs), "● x 120  ·  y 48")
        XCTAssertEqual(runs.first, BadgeRun(text: "● ", accent: true))
        XCTAssertFalse(runs.contains { $0.accent && $0.text.contains("y") })
    }

    func testEqualGapsSayWhichWay() {
        let across = Readouts.move(x: 0, y: 0, heldX: false, heldY: false, gapX: 24, gapY: nil)
        XCTAssertEqual(Readouts.text(across), "x 0  ·  y 0  ↔ 24")
        let both = Readouts.move(x: 0, y: 0, heldX: false, heldY: true, gapX: 24, gapY: 12)
        XCTAssertEqual(Readouts.text(both), "x 0  ·  ● y 0  ↔ 24  ↕ 12")
        XCTAssertEqual(both.last, BadgeRun(text: "  ↕ 12", accent: true))
    }

    func testTypeSizeReadsInTenths() {
        XCTAssertEqual(Readouts.typeSize(42), "Size 42")
        XCTAssertEqual(Readouts.typeSize(42.46), "Size 42.5")
        XCTAssertEqual(Readouts.tenths(6.04), "6")
    }

    func testASnappedAngleIsPickedOut() {
        XCTAssertEqual(Readouts.angle(45, snapped: true), [BadgeRun(text: "45°", accent: true)])
        XCTAssertEqual(Readouts.angle(47.6, snapped: false), [BadgeRun(text: "47°", accent: false)])
    }

    // MARK: copy, cut, delete

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "clipboard", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    func testCopySaysSoAndOffersNoUndo() {
        let a = Element.shape("rect"), b = Element.shape("circle")
        let s = store([a, b])
        s.selection = [a.id, b.id]
        s.copySelected()
        XCTAssertEqual(s.announcement, "Copied 2 things")
        XCTAssertFalse(s.announcementUndoes)
    }

    func testCutSaysCutNotDeleted() {
        let a = Element.shape("rect")
        let s = store([a])
        s.selection = [a.id]
        s.cutSelected()
        XCTAssertEqual(s.announcement, "Cut")
        XCTAssertTrue(s.announcementUndoes)
        XCTAssertTrue(s.page.elements.isEmpty)
        s.undo()
        XCTAssertEqual(s.page.elements.count, 1)
    }

    func testDeleteUsesTheSameWordsAsAndroid() {
        let a = Element.shape("rect"), b = Element.shape("circle")
        let s = store([a, b])
        s.selection = [a.id, b.id]
        s.deleteSelected()
        XCTAssertEqual(s.announcement, "Deleted 2 things")
    }

    func testDeletingOnlyLockedThingsIsRefusedAndFelt() {
        var a = Element.shape("rect")
        a.locked = true
        let s = store([a])
        s.selection = [a.id]
        let before = s.haptic.serial
        s.deleteSelected()
        XCTAssertEqual(s.haptic.kind, .reject)
        XCTAssertEqual(s.haptic.serial, before + 1)
        XCTAssertEqual(s.page.elements.count, 1)
    }

    func testGuidesAreFeltAsTheyComeAndGo() {
        let s = store([])
        s.addGuide(vertical: true)
        XCTAssertEqual(s.haptic.kind, .confirm)
        s.removeGuide(s.design.guides[0].id)
        XCTAssertEqual(s.haptic.kind, .tick)
        XCTAssertTrue(s.design.guides.isEmpty)
    }
}
