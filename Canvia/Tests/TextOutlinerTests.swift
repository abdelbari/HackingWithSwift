// Glyph outlining.
//
// The load-bearing property is placement, not shape: CoreText lays glyphs out
// in a y-up space whose origin is the bottom-left of the text box, and every
// consumer of this — SVG, and anything drawn on the canvas — works y-down from
// the top-left. Getting the flip wrong produces text that is upside down or
// off the element entirely, which no assertion about "is there a path" would
// catch.

import XCTest
import CoreGraphics
@testable import Canvia

final class TextOutlinerTests: XCTestCase {

    private func text(_ body: String, w: Double = 400, size: Double = 40) -> Element {
        var el = Element()
        el.type = .text
        el.text = body
        el.w = w
        el.fontSize = size
        el.h = FontLibrary.measuredHeight(for: el)
        return el
    }

    func testOutliningProducesAPath() throws {
        let path = try XCTUnwrap(TextOutliner.path(for: text("Hamburgevons")))
        XCTAssertFalse(path.isEmpty)
    }

    /// Placement. The outlines have to sit inside the element's own box, in
    /// the element's own space — origin top-left, y downward.
    func testOutlinesSitInsideTheElementBox() throws {
        let el = text("Hamburgevons")
        let path = try XCTUnwrap(TextOutliner.path(for: el))
        let box = path.boundingBox
        XCTAssertGreaterThanOrEqual(box.minX, -1, "text starts left of the element")
        XCTAssertGreaterThanOrEqual(box.minY, -1, "text starts above the element — the flip is wrong")
        XCTAssertLessThanOrEqual(box.maxX, el.w + 1, "text runs past the element's width")
        // A few points of slack: font metrics differ by a hair between SDKs,
        // and the failure this guards against — an unflipped block — misses by
        // most of the element's height, not by two points.
        XCTAssertLessThanOrEqual(box.maxY, el.h + 4, "text runs past the element's height")
    }

    /// Upside-down text still fits the box, so fitting is not enough: the
    /// glyphs' ink has to sit below the box's top by roughly the ascender, and
    /// the block has to grow downward as lines are added.
    func testASecondLineIsBelowTheFirst() throws {
        let one = text("Hg")
        let two = text("Hg\nHg")
        let first = try XCTUnwrap(TextOutliner.path(for: one)).boundingBox
        let second = try XCTUnwrap(TextOutliner.path(for: two)).boundingBox
        XCTAssertEqual(second.minY, first.minY, accuracy: 2,
                       "the first line moved when a second was added")
        XCTAssertGreaterThan(second.maxY, first.maxY + one.fontSize! * 0.5,
                             "the second line is not below the first")
    }

    func testWiderTextMakesAWiderPath() throws {
        let short = try XCTUnwrap(TextOutliner.path(for: text("i"))).boundingBox
        let long = try XCTUnwrap(TextOutliner.path(for: text("Hamburgevons"))).boundingBox
        XCTAssertGreaterThan(long.width, short.width)
    }

    func testEmptyTextOutlinesToNothing() {
        XCTAssertNil(TextOutliner.path(for: text("")))
        var zeroWidth = text("Hello")
        zeroWidth.w = 0
        XCTAssertNil(TextOutliner.path(for: zeroWidth))
    }

    /// Whitespace has no ink, so there is nothing to outline — and returning
    /// an empty path here would put `d=""` into the SVG.
    func testWhitespaceOnlyTextOutlinesToNothing() {
        XCTAssertNil(TextOutliner.path(for: text("   ")))
    }

    // MARK: path data

    func testPathDataIsValidSVG() throws {
        let path = try XCTUnwrap(TextOutliner.path(for: text("Ao")))
        let d = TextOutliner.svgPathData(path)
        XCTAssertTrue(d.hasPrefix("M"), "path data must start with a move")
        XCTAssertTrue(d.contains("Z"), "glyph outlines must close their subpaths")
        XCTAssertFalse(d.contains("nan"))
        XCTAssertFalse(d.contains("inf"))
        // Only the command letters SVG defines for this subset.
        let allowed = Set("MLQCZ0123456789.- ")
        XCTAssertTrue(d.allSatisfy { allowed.contains($0) }, "unexpected character in path data")
    }

    func testMoreGlyphsMakeLongerPathData() throws {
        let short = TextOutliner.svgPathData(try XCTUnwrap(TextOutliner.path(for: text("A"))))
        let long = TextOutliner.svgPathData(try XCTUnwrap(TextOutliner.path(for: text("ABCDEFGH"))))
        XCTAssertGreaterThan(long.count, short.count)
    }

    func testRoundingKeepsCoordinatesShort() throws {
        let path = try XCTUnwrap(TextOutliner.path(for: text("Hamburgevons")))
        let d = TextOutliner.svgPathData(path, precision: 2)
        for token in d.split(whereSeparator: { "MLQCZ ".contains($0) }) {
            let decimals = token.split(separator: ".").last.map { $0.count } ?? 0
            XCTAssertLessThanOrEqual(decimals, 2, "coordinate \(token) kept too many decimals")
        }
    }
}
