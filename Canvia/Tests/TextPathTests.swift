// Text along a path: the walker, the presets and the glyph layout.

import XCTest
import CoreGraphics
@testable import Canvia

final class TextPathTests: XCTestCase {

    func testWalkerMeasuresAndLocatesAlongAPolyline() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 100, y: 0))
        path.addLine(to: CGPoint(x: 100, y: 50))
        let w = PathWalker(path)
        XCTAssertEqual(w.length, 150, accuracy: 0.001)
        let mid = w.locate(50)
        XCTAssertEqual(mid.point.x, 50, accuracy: 0.001); XCTAssertEqual(mid.angle, 0, accuracy: 0.001)
        let down = w.locate(125)
        XCTAssertEqual(down.point.x, 100, accuracy: 0.001); XCTAssertEqual(down.point.y, 25, accuracy: 0.001)
        XCTAssertEqual(down.angle, .pi / 2, accuracy: 0.001)
        // Clamped at both ends.
        XCTAssertEqual(w.locate(-5).point, CGPoint(x: 0, y: 0))
        XCTAssertEqual(w.locate(500).point.y, 50, accuracy: 0.001)
    }

    func testWalkerFlattensCurvesToTheirLength() {
        // A quarter circle of radius 100 is ~157.08 long.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 100))
        path.addCurve(to: CGPoint(x: 100, y: 0), control1: CGPoint(x: 0, y: 44.77), control2: CGPoint(x: 44.77, y: 0))
        XCTAssertEqual(PathWalker(path, segments: 64).length, 157.08, accuracy: 0.5)
        XCTAssertEqual(PathWalker(CGMutablePath()).length, 0)
    }

    func testPresetsParseAndSpanTheBox() {
        for p in TextPaths.presets {
            let cg = SVGPath.scaledPath(p.data, to: CGSize(width: 200, height: 100))
            let w = PathWalker(cg)
            XCTAssertGreaterThan(w.length, 100, p.id)
            let box = cg.boundingBoxOfPath
            XCTAssertGreaterThan(box.width, 150, p.id)
        }
        XCTAssertEqual(TextPaths.preset("wave")?.name, "Wave")
        XCTAssertNil(TextPaths.preset("nope"))
    }

    @MainActor
    func testTextOnADiagonalClimbsAndOnACircleWraps() throws {
        var diagonal = Element.text("Along the line", fontSize: 30, w: 400)
        diagonal.h = 200
        diagonal.textPath = TextPaths.preset("rise")?.data
        let d = try XCTUnwrap(TextOutliner.path(for: diagonal)).boundingBoxOfPath
        // Straight text of this size is one line tall; on the diagonal it
        // spans most of the box's height too.
        XCTAssertGreaterThan(d.height, 100)
        XCTAssertLessThan(d.height, 220)
        XCTAssertTrue(TextOutliner.followsAPath(diagonal))

        var circle = Element.text("Round and round and round we go", fontSize: 24, w: 300)
        circle.h = 300
        circle.textPath = TextPaths.preset("circle")?.data
        let c = try XCTUnwrap(TextOutliner.path(for: circle)).boundingBoxOfPath
        XCTAssertGreaterThan(c.width, 200); XCTAssertGreaterThan(c.height, 200)
        // The box is kept: measurement does not collapse a path box to a line.
        XCTAssertEqual(FontLibrary.layoutHeight(for: circle), 300)
    }

    @MainActor
    func testAPathBeatsACurveAndAnEmptyPathIsStraight() throws {
        var el = Element.text("Hello", fontSize: 30, w: 300)
        el.h = 120
        el.curve = 90
        el.textPath = ""
        XCTAssertTrue(TextOutliner.followsAPath(el), "the curve still applies")
        el.curve = nil
        XCTAssertFalse(TextOutliner.followsAPath(el))
        let straight = try XCTUnwrap(TextOutliner.path(for: el)).boundingBoxOfPath
        XCTAssertLessThan(straight.height, 40)
    }

    @MainActor
    func testTheSVGOutlinesPathText() {
        var d = Design(title: "p", width: 400, height: 300)
        var el = Element.text("Wavy words", fontSize: 30, w: 300)
        el.h = 150; el.textPath = TextPaths.preset("wave")?.data
        d.pages[0].elements = [el]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<path d=\"M"), svg.prefix(200).description)
    }
}

final class VerticalTextTests: XCTestCase {

    @MainActor
    func testVerticalTextStacksDownAColumn() throws {
        var el = Element.text("縦書き", fontSize: 40, w: 200)
        el.h = 240
        el.vertical = true
        let box = try XCTUnwrap(TextOutliner.path(for: el)).boundingBoxOfPath
        XCTAssertGreaterThan(box.height, box.width * 2, "\(box)")
        XCTAssertGreaterThan(box.height, 100)
        // Centred across the box.
        XCTAssertEqual(box.midX, 100, accuracy: 12)
        XCTAssertTrue(TextOutliner.followsAPath(el))
        XCTAssertEqual(FontLibrary.layoutHeight(for: el), 240)
    }

    @MainActor
    func testLatinStacksUprightAndNewlinesStartColumns() throws {
        var one = Element.text("ABC", fontSize: 30, w: 200); one.h = 300; one.vertical = true
        var two = Element.text("ABC\nDEF", fontSize: 30, w: 200); two.h = 300; two.vertical = true
        let a = try XCTUnwrap(TextOutliner.path(for: one)).boundingBoxOfPath
        let b = try XCTUnwrap(TextOutliner.path(for: two)).boundingBoxOfPath
        XCTAssertGreaterThan(a.height, a.width)
        XCTAssertGreaterThan(b.width, a.width + 20, "a second column sits beside the first")
        XCTAssertEqual(a.height, b.height, accuracy: 2)
    }

    @MainActor
    func testAColumnTooTallWrapsToTheNextColumn() throws {
        var el = Element.text("ABCDEFGH", fontSize: 30, w: 300); el.h = 120; el.vertical = true
        // 120 / (30 * 1.25) = 3 rows per column → 3 columns.
        let box = try XCTUnwrap(TextOutliner.path(for: el)).boundingBoxOfPath
        XCTAssertGreaterThan(box.width, 80)
        XCTAssertLessThanOrEqual(box.height, 120 + 5)
    }
}
