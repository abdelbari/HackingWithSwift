// Lists, indents and gradient text.

import XCTest
import SwiftUI
@testable import Canvia

final class TextListTests: XCTestCase {

    private func text(_ body: String, list: String? = nil, indent: Int? = nil) -> Element {
        var el = Element.text(body, fontSize: 20, w: 300)
        el.listStyle = list
        el.indent = indent
        el.h = FontLibrary.layoutHeight(for: el)
        return el
    }

    // MARK: markers

    func testEachListStyleHasItsMarker() {
        XCTAssertEqual(FontLibrary.listMarker(style: "bullet", index: 7), "•  ")
        XCTAssertEqual(FontLibrary.listMarker(style: "number", index: 7), "7.  ")
        XCTAssertEqual(FontLibrary.listMarker(style: "letter", index: 1), "a.  ")
        XCTAssertEqual(FontLibrary.listMarker(style: "letter", index: 26), "z.  ")
        XCTAssertEqual(FontLibrary.listMarker(style: "letter", index: 27), "aa.  ")
        XCTAssertEqual(FontLibrary.listMarker(style: "letter", index: 28), "ab.  ")
        XCTAssertNil(FontLibrary.listMarker(style: "none", index: 1))
        XCTAssertNil(FontLibrary.listMarker(style: nil, index: 1))
    }

    func testNumberingSkipsBlankLinesWithoutCountingThem() {
        let el = text("Eggs\n\nMilk\nBread", list: "number")
        XCTAssertEqual(FontLibrary.displayText(for: el), "1.  Eggs\n\n2.  Milk\n3.  Bread")
        XCTAssertEqual(FontLibrary.displayText(for: text("Eggs\nMilk", list: "letter")), "a.  Eggs\nb.  Milk")
        XCTAssertEqual(FontLibrary.displayText(for: text("Eggs", list: nil)), "Eggs")
    }

    // MARK: indents

    func testIndentPushesTheParagraphInAndAListHangs() throws {
        let plain = FontLibrary.attributes(for: text("Hello"))
        let indented = FontLibrary.attributes(for: text("Hello", indent: 2))
        let listed = FontLibrary.attributes(for: text("Hello", list: "bullet", indent: 1))
        let p0 = try XCTUnwrap(plain[.paragraphStyle] as? NSParagraphStyle)
        let p2 = try XCTUnwrap(indented[.paragraphStyle] as? NSParagraphStyle)
        let pl = try XCTUnwrap(listed[.paragraphStyle] as? NSParagraphStyle)
        XCTAssertEqual(p0.firstLineHeadIndent, 0)
        XCTAssertEqual(p2.firstLineHeadIndent, 2 * 20 * FontLibrary.indentEm, accuracy: 0.001)
        XCTAssertEqual(p2.headIndent, p2.firstLineHeadIndent, "no list: wrapped lines align with the first")
        XCTAssertEqual(pl.headIndent - pl.firstLineHeadIndent, 20 * FontLibrary.markerEm, accuracy: 0.001,
                       "a list hangs its wrapped lines under the text, not the marker")
    }

    func testIndentLevelIsClamped() {
        XCTAssertEqual(FontLibrary.indentLevel(of: text("x", indent: 9)), FontLibrary.maxIndent)
        XCTAssertEqual(FontLibrary.indentLevel(of: text("x", indent: -3)), 0)
    }

    func testAnIndentedParagraphWrapsSoonerAndSoGrowsTaller() {
        let long = String(repeating: "word ", count: 30)
        let flat = FontLibrary.measuredHeight(for: text(long))
        let deep = FontLibrary.measuredHeight(for: text(long, indent: 4))
        XCTAssertGreaterThan(deep, flat)
    }

    // MARK: gradient text

    /// Red at the top, blue at the bottom (CSS 180°). The top rows of ink
    /// have to be redder than the bottom rows — the one thing a flipped mask
    /// or mirrored gradient gets wrong while still drawing letters.
    @MainActor
    func testAVerticalGradientRunsTopToBottomOnTheLetters() throws {
        var el = Element.text("MMMM", fontSize: 80, w: 300)
        el.color = "#000000"
        el.textFill = Paint(kind: "gradient", color: nil, angle: 180,
                            stops: [GradientStop(offset: 0, color: "#ff0000"),
                                    GradientStop(offset: 1, color: "#0000ff")])
        el.h = FontLibrary.layoutHeight(for: el)
        let renderer = ImageRenderer(content: TextElementView(element: el))
        renderer.scale = 1
        let cg = try XCTUnwrap(renderer.cgImage)
        let (top, bottom) = try inkRows(cg)
        XCTAssertGreaterThan(top.r, top.b + 80, "the top of the letters is not red")
        XCTAssertGreaterThan(bottom.b, bottom.r + 80, "the bottom of the letters is not blue")
    }

    /// Mean colour of the first and last rows that carry ink.
    private func inkRows(_ cg: CGImage) throws -> (top: (r: Double, b: Double), bottom: (r: Double, b: Double)) {
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        try px.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        func row(_ y: Int) -> (r: Double, b: Double, ink: Int) {
            var r = 0.0, b = 0.0, n = 0
            for x in 0..<w {
                let i = (y * w + x) * 4
                if px[i + 3] > 200 { r += Double(px[i]); b += Double(px[i + 2]); n += 1 }
            }
            return n == 0 ? (0, 0, 0) : (r / Double(n), b / Double(n), n)
        }
        // Row 0 of a CGImage is the top; the context above draws it as-is.
        let inky = (0..<h).filter { row($0).ink >= 8 }
        let first = try XCTUnwrap(inky.first), last = try XCTUnwrap(inky.last)
        XCTAssertGreaterThan(last - first, 20, "not enough ink to judge")
        let t = row(first + 2), bo = row(last - 2)
        return ((t.r, t.b), (bo.r, bo.b))
    }
}
