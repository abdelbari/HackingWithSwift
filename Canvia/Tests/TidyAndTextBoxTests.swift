// Tidy up, nudging, the selection's numeric box, and text boxes that are
// taller than their text or sized by it.

import XCTest
@testable import Canvia

@MainActor
final class TidyAndTextBoxTests: XCTestCase {

    private func rect(_ x: Double, _ y: Double, w: Double = 100, h: Double = 50) -> Element {
        var e = Element.shape("rect", w: w, h: h); e.x = x; e.y = y; return e
    }

    private func store(_ els: [Element]) -> DesignStore {
        var d = Design(title: "tidy", width: 1000, height: 1000)
        d.pages[0].elements = els
        return DesignStore(design: d)
    }

    // MARK: tidy

    func testARowIsLeftToRightEvenlyGappedAndVerticallyCentred() {
        let els = [rect(300, 10, w: 60, h: 40), rect(40, 200, w: 100, h: 80), rect(170, 90, w: 20, h: 20)]
        let tidy = Geometry.tidy(els, mode: .row, gap: 10)
        // Sorted by x: 40 (100 wide), 170 (20), 300 (60) → 40…140, 150…170, 180…240.
        let byX = tidy.sorted { $0.x < $1.x }
        XCTAssertEqual(byX.map(\.x), [40, 150, 180])
        let union = Geometry.union(els.map(Geometry.aabb))
        for e in tidy { XCTAssertEqual(e.center.y, union.midY, accuracy: 0.001) }
    }

    func testAColumnIsTopToBottomAndHorizontallyCentred() {
        let els = [rect(0, 300, w: 40, h: 60), rect(500, 0, w: 100, h: 100), rect(200, 150, w: 20, h: 20)]
        let tidy = Geometry.tidy(els, mode: .column, gap: 20)
        let byY = tidy.sorted { $0.y < $1.y }
        XCTAssertEqual(byY.map(\.y), [0, 120, 160])
        let union = Geometry.union(els.map(Geometry.aabb))
        for e in tidy { XCTAssertEqual(e.center.x, union.midX, accuracy: 0.001) }
    }

    func testAGridIsSquareishWithCellsTheSizeOfTheLargest() {
        let els = (0..<5).map { rect(Double($0) * 37, Double($0 % 2) * 300, w: 50, h: 30) }
        let tidy = Geometry.tidy(els, mode: .grid, gap: 10)
        // 5 → 3 columns, 2 rows; cells 50×30 plus a 10 gap.
        let xs = Set(tidy.map { $0.x.rounded() }), ys = Set(tidy.map { $0.y.rounded() })
        XCTAssertEqual(xs, [0, 60, 120])
        XCTAssertEqual(ys, [0, 40])
        for (i, a) in tidy.enumerated() {
            for b in tidy.dropFirst(i + 1) {
                XCTAssertFalse(a.frame.insetBy(dx: 1, dy: 1).intersects(b.frame))
            }
        }
    }

    func testTidyIsOneUndoStepAndSkipsLocked() {
        var locked = rect(900, 900); locked.locked = true
        let s = store([rect(0, 0), rect(500, 300), locked])
        s.selectAll()
        s.selection.insert(locked.id)
        s.tidySelected(.row)
        XCTAssertEqual(s.page.elements[2].x, 900, "locked stays put")
        XCTAssertNotEqual(s.page.elements[1].y, 300)
        s.undo()
        XCTAssertEqual(s.page.elements[1].y, 300)
    }

    // MARK: nudge and numeric

    func testNudgeMovesTheSelectionAsOneUndoStep() {
        let s = store([rect(0, 0), rect(200, 0)])
        s.selectAll()
        s.nudgeSelected(dx: 10, dy: -5)
        XCTAssertEqual(s.page.elements.map(\.x), [10, 210])
        XCTAssertEqual(s.page.elements.map(\.y), [-5, -5])
        s.undo()
        XCTAssertEqual(s.page.elements.map(\.x), [0, 200])
        s.nudgeSelected(dx: 0, dy: 0)
        XCTAssertFalse(s.canRedo == false && s.canUndo, "a zero nudge records nothing")
    }

    func testTheSelectionBoxMovesAndScalesTheWhole() {
        let s = store([rect(0, 0, w: 100, h: 100), rect(200, 100, w: 100, h: 100)])
        s.selectAll()
        XCTAssertEqual(s.selectionBox, CGRect(x: 0, y: 0, width: 300, height: 200))
        s.setSelectionBox(CGRect(x: 50, y: 50, width: 300, height: 200))
        XCTAssertEqual(s.page.elements[0].x, 50); XCTAssertEqual(s.page.elements[1].y, 150)
        s.setSelectionBox(CGRect(x: 50, y: 50, width: 600, height: 400))
        XCTAssertEqual(s.page.elements[1].w, 200, accuracy: 0.001)
        XCTAssertEqual(s.page.elements[1].x, 450, accuracy: 0.001)
        s.rotateSelection(by: 90)
        XCTAssertEqual(s.page.elements[0].rotation, 90, accuracy: 0.001)
        XCTAssertEqual(s.selectionBox?.midX ?? 0, 350, accuracy: 0.01, "turning about the centre keeps the centre")
    }

    // MARK: text boxes

    func testFittedTypeFillsTheBoxWithoutSpilling() {
        var el = Element.text("Big", fontSize: 12, w: 300)
        el.h = 120
        el.fitText = true
        let size = FontLibrary.fittingFontSize(for: el)
        XCTAssertGreaterThan(size, 40, "a 300×120 box holds far more than 12pt")
        var probe = el; probe.fitText = nil; probe.fontSize = size
        XCTAssertLessThanOrEqual(FontLibrary.measuredHeight(for: probe), 120)
        XCTAssertLessThanOrEqual(FontLibrary.naturalWidth(for: probe), 300)
        probe.fontSize = size + 8
        XCTAssertTrue(FontLibrary.measuredHeight(for: probe) > 120 || FontLibrary.naturalWidth(for: probe) > 300,
                      "the fit is not the largest that fits")
        XCTAssertEqual(FontLibrary.layoutHeight(for: el), 120, "a fitted box keeps its height")
    }

    func testAnAlignedBoxMayBeTallerThanItsTextButNeverShorter() {
        var el = Element.text("Hi", fontSize: 20, w: 200)
        let measured = FontLibrary.measuredHeight(for: el)
        el.vAlign = "bottom"
        el.h = 300
        XCTAssertEqual(FontLibrary.layoutHeight(for: el), 300)
        el.h = 5
        XCTAssertEqual(FontLibrary.layoutHeight(for: el), measured)
    }

    func testShrinkWrapClosesTheBoxOntoTheText() {
        var el = Element.text("Hi", fontSize: 20, w: 400)
        el.vAlign = "middle"; el.h = 300
        let s = store([el])
        s.selectAll()
        s.shrinkWrapText()
        let wrapped = s.page.elements[0]
        XCTAssertNil(wrapped.vAlign)
        XCTAssertLessThan(wrapped.w, 100, "two letters need nothing like 400 points")
        XCTAssertEqual(wrapped.h, FontLibrary.measuredHeight(for: wrapped), accuracy: 0.001)
    }

    func testJustifyAndParagraphSpacingReachTheParagraphStyle() throws {
        var el = Element.text("a b\nc d", fontSize: 20, w: 300)
        el.align = "justify"
        el.paragraphSpacing = 0.5
        let p = try XCTUnwrap(FontLibrary.attributes(for: el)[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(p.alignment, .justified)
        XCTAssertEqual(p.paragraphSpacing, 10, accuracy: 0.001)
        var plain = el; plain.paragraphSpacing = nil
        XCTAssertGreaterThan(FontLibrary.measuredHeight(for: el), FontLibrary.measuredHeight(for: plain),
                             "space after the first paragraph makes two lines taller")
    }
}
