// Text along a path: the walker, the presets and the glyph layout.

import XCTest
import CoreGraphics
import CoreText
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
        // Straight text of this size is one line (~36) tall; centred on the
        // diagonal it climbs across a good part of the box as well.
        XCTAssertGreaterThan(d.height, 55)
        XCTAssertLessThan(d.height, 220)
        XCTAssertTrue(TextOutliner.followsAPath(diagonal))

        var circle = Element.text("Round and round and round we go", fontSize: 24, w: 300)
        circle.h = 300
        circle.textPath = TextPaths.preset("circle")?.data
        let c = try XCTUnwrap(TextOutliner.path(for: circle)).boundingBoxOfPath
        // Centred on the circle's far side, the text wraps round more than a
        // third of it: tall, and well wider than a line's height.
        XCTAssertGreaterThan(c.width, 200); XCTAssertGreaterThan(c.height, 100)
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

    /// A character set larger sits on the baseline the box's own metrics
    /// give its step, as on the Android twin: its own font's ascent and
    /// descent never move it.
    @MainActor
    func testALargerCharacterSitsOnTheBoxBaselineDownAColumn() throws {
        var el = Element.text("HH", fontSize: 30, w: 200)
        el.h = 300
        el.vertical = true
        el.setSpans([TextSpan(start: 1, end: 2, scale: 2)])
        let box = try XCTUnwrap(TextOutliner.path(for: el)).boundingBoxOfPath
        let font = FontLibrary.uiFont(family: "sans", size: 30, weight: 400, italic: false) as CTFont
        let step = 30 * 1.25
        let baseline = step + (step + Double(CTFontGetAscent(font)) - Double(CTFontGetDescent(font))) / 2
        XCTAssertEqual(Double(box.maxY), baseline, accuracy: 1)
    }
}

// MARK: bent words a glyph at a time

/// Shared (Fixtures/bent-text.json, the Android twin's TextPathsTest reads it
/// too): each case's glyphs — round curves of 50, 180 and −120 degrees, along
/// a path and down columns — their quads, Highlight's band behind them all,
/// behind the highlight span and a word's marker over it, and the linked
/// letters' quads; then each case's element drawn here, with Highlight and
/// Splice.
final class BentTextTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("bent-text") }

    private func cases() throws -> [[String: Any]] { try XCTUnwrap(fixture()["cases"] as? [[String: Any]]) }

    private func point(_ value: Any?) throws -> CGPoint {
        let xy = try XCTUnwrap(value as? [Double])
        return CGPoint(x: xy[0], y: xy[1])
    }

    private func number(_ row: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap(row[key] as? Double, key)
    }

    private func spanRange(_ row: [String: Any], _ key: String) throws -> Range<Int> {
        let ends = try XCTUnwrap(row[key] as? [Int], key)
        return ends[0]..<ends[1]
    }

    private func assertBounds(_ got: CGRect, _ expected: Any?, accuracy: Double, _ label: String,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let want = try XCTUnwrap(expected as? [Double])
        for (a, b) in zip([got.minX, got.minY, got.width, got.height].map(Double.init), want) {
            XCTAssertEqual(a, b, accuracy: accuracy, "\(label): \(got) against \(want)", file: file, line: line)
        }
    }

    /// A case's glyphs as this phone keeps them: the baseline's start, the
    /// fixture's being its middle.
    private typealias Placed = (glyph: TextPaths.GlyphPlacement, column: Int, middle: CGPoint)

    private func glyphs(_ row: [String: Any], in fixture: [String: Any]) throws -> [Placed] {
        let advance = try number(fixture, "advance"), ascent = try number(fixture, "ascent")
        let descent = try number(fixture, "descent")
        return try XCTUnwrap(row["glyphs"] as? [[String: Any]]).map { g in
            let angle = try number(g, "angle")
            let a = angle * .pi / 180
            let middle = CGPoint(x: try number(g, "x"), y: try number(g, "y"))
            let origin = CGPoint(x: Double(middle.x) - advance / 2 * cos(a), y: Double(middle.y) - advance / 2 * sin(a))
            let glyph = TextPaths.GlyphPlacement(index: try XCTUnwrap(g["start"] as? Int), origin: origin, angle: angle,
                                                 advance: advance, ascent: ascent, descent: descent)
            return (glyph, try XCTUnwrap(g["column"] as? Int), middle)
        }
    }

    /// What a case's words run along, as the outliner records it.
    private func spine(_ row: [String: Any], _ placed: [Placed]) throws -> TextPaths.Spine {
        if let radius = row["radius"] as? Double {
            let r = abs(radius)
            let extents = placed.map { p -> TextPaths.Extent in
                let a = p.glyph.angle * .pi / 180, half = p.glyph.advance / 2 / r
                return TextPaths.Extent(index: p.glyph.index, from: a - half, to: a + half)
            }
            return .arc(centre: try point(row["centre"]), radius: radius, glyphs: extents)
        }
        if let route = row["route"] as? [[Double]] {
            let line = CGMutablePath()
            line.addLines(between: route.map { CGPoint(x: $0[0], y: $0[1]) })
            let walker = PathWalker(line)
            let extents = placed.map { p -> TextPaths.Extent in
                let distance = along(walker.points, p.middle)
                return TextPaths.Extent(index: p.glyph.index, from: distance - p.glyph.advance / 2,
                                        to: distance + p.glyph.advance / 2)
            }
            return .path(walker, glyphs: extents)
        }
        return .columns(placed.map { p in
            TextPaths.Cell(index: p.glyph.index, column: p.column, rect: WordLinks.bounds(of: [p.glyph.quad]))
        })
    }

    /// How far along `points` the nearest point to `p` is.
    private func along(_ points: [CGPoint], _ p: CGPoint) -> Double {
        var best = Double.infinity, at = 0.0, walked = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
            let length = hypot(dx, dy)
            let t = length == 0 ? 0 : min(max((Double(p.x - a.x) * dx + Double(p.y - a.y) * dy) / (length * length), 0), 1)
            let d = hypot(Double(a.x) + t * dx - Double(p.x), Double(a.y) + t * dy - Double(p.y))
            if d < best { best = d; at = walked + t * length }
            walked += length
        }
        return at
    }

    /// The bounds of the bands over `only` (all for nil), `pad` past the letters.
    private func bandBounds(_ spine: TextPaths.Spine, only: Range<Int>?, pad: Double, in fixture: [String: Any]) throws -> [CGRect] {
        TextPaths.spineBands(spine, only: only.map { Set($0) }, ascent: try number(fixture, "ascent"),
                             descent: try number(fixture, "descent"), pad: pad)
            .map { $0.core(0).boundingBoxOfPath }
    }

    func testTheSharedGlyphsQuadsAndBandsAreWhereTheFixturePutsThem() throws {
        let rows = try fixture()
        for row in try cases() {
            let name = try XCTUnwrap(row["name"] as? String)
            let placed = try glyphs(row, in: rows)
            // The linked letters' quads.
            let linked = try spanRange(row, "link")
            let quads = placed.filter { linked.contains($0.glyph.index) }.map(\.glyph.quad)
            let want = try XCTUnwrap(row["linkQuads"] as? [[[Double]]])
            XCTAssertEqual(quads.count, want.count, name)
            for (quad, corners) in zip(quads, want) {
                for (got, corner) in zip(quad, corners) {
                    XCTAssertEqual(Double(got.x), corner[0], accuracy: 1e-4, name)
                    XCTAssertEqual(Double(got.y), corner[1], accuracy: 1e-4, name)
                }
            }
            // An arc's bands are true arcs here and fine polygons there.
            let accuracy = row["radius"] == nil ? 1e-3 : 0.1
            let runs = try spine(row, placed)
            let pad = TextPaths.highlightPad(fontSize: 40, spread: 50)
            let span = try spanRange(row, "highlight")
            let sets: [(String, Range<Int>?, Double)] = [("band", nil, pad), ("spanBand", span, pad),
                                                         ("markBand", span, 40 * Spans.highlightPadEm)]
            for (key, only, reach) in sets {
                let got = try bandBounds(runs, only: only, pad: reach, in: rows)
                let expected = try XCTUnwrap(row[key] as? [[Double]])
                XCTAssertEqual(got.count, expected.count, "\(name) \(key)")
                for (rect, bounds) in zip(got, expected) { try assertBounds(rect, bounds, accuracy: accuracy, "\(name) \(key)") }
            }
        }
    }

    func testHighlightsPadIsTheSharedSpreadRule() throws {
        for row in try XCTUnwrap(fixture()["pads"] as? [[String: Any]]) {
            XCTAssertEqual(TextPaths.highlightPad(fontSize: try number(row, "fontSize"), spread: try number(row, "spread")),
                           try number(row, "pad"), accuracy: 1e-9)
        }
    }

    func testRoundingKeepsTheBandWithinItsSquareCornersAndRoundsThem() {
        let square = TextPaths.columnBand(CGRect(x: 0, y: 0, width: 40, height: 100), pad: 0)
        let core = TextPaths.columnBand(CGRect(x: 0, y: 0, width: 40, height: 100), pad: -10)
        let round = TextPaths.rounded(core, radius: 10)
        XCTAssertEqual(round.boundingBoxOfPath.width, 40, accuracy: 0.01)
        XCTAssertEqual(round.boundingBoxOfPath.height, 100, accuracy: 0.01)
        XCTAssertTrue(square.contains(CGPoint(x: 1, y: 1)))
        XCTAssertFalse(round.contains(CGPoint(x: 1, y: 1)), "the corner is cut round")
        XCTAssertTrue(round.contains(CGPoint(x: 20, y: 50)))
    }

    /// Each case's element as this phone sets it, with Highlight, and with
    /// Splice in its place.
    private func elements() throws -> [(name: String, row: [String: Any], element: Element)] {
        try cases().map { row in
            (name: try XCTUnwrap(row["name"] as? String), row: row,
             element: try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(XCTUnwrap(row["element"]))))
        }
    }

    func testEveryLetterOfBentWordsIsPlacedAndItsBandsHoldThem() throws {
        for (name, row, highlighted) in try elements() {
            var spliced = highlighted
            spliced.effect?.type = "splice"
            for el in [highlighted, spliced] {
                let words = (RichText.strip(el.text ?? "") as NSString).length
                let plain = Array(RichText.strip(el.text ?? "").utf16)
                let placed = TextPaths.glyphPlacements(el)
                XCTAssertFalse(placed.isEmpty, name)
                XCTAssertTrue(placed.allSatisfy { (0..<words).contains($0.index) }, name)
                XCTAssertEqual(Set(placed.map(\.index)).count, placed.count, name)
                let bands = TextPaths.band(el, spread: 50, roundness: 40, range: nil)
                XCTAssertFalse(bands.isEmpty, name)
                let reach = bands.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }.insetBy(dx: -10, dy: -10)
                // Every letter, a space aside, inside it.
                for glyph in placed where plain[glyph.index] != 32 {
                    XCTAssertTrue(reach.contains(glyph.centre), "\(name): letter \(glyph.index) outside its band")
                }
                // The span's own marker covers less than the whole band.
                let span = try spanRange(row, "highlight")
                let mark = TextPaths.band(el, pad: 3, corner: 6, range: NSRange(location: span.lowerBound, length: span.count))
                XCTAssertFalse(mark.isEmpty, name)
                let marked = mark.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
                XCTAssertLessThan(marked.width * marked.height, reach.width * reach.height, name)
            }
        }
    }

    func testBentWordsLinksAndFindAreTheirLettersQuads() throws {
        for (name, row, el) in try elements() {
            let links = WordLinks.rects(for: el)
            XCTAssertEqual(links.count, 1, "\(name): the link is one word")
            XCTAssertEqual(links.first?.url, "https://example.com/")
            let linked = try spanRange(row, "link")
            let letters = TextPaths.glyphPlacements(el).filter { linked.contains($0.index) }
            let around = WordLinks.bounds(of: letters.map(\.quad))
            XCTAssertEqual(links.first.map { Double($0.rect.width) } ?? 0, Double(around.width), accuracy: 0.01, name)
            let span = try spanRange(row, "highlight")
            XCTAssertEqual(FindReplace.letterRects(of: NSRange(location: span.lowerBound, length: span.count), in: el).count,
                           span.count, name)
        }
    }

    func testTheSVGDrawsTheBandsAsPaths() throws {
        let highlighted = try XCTUnwrap(elements().first { $0.name == "curve 50" }?.element)
        let markup = SVGExporter.bandMarkup(highlighted)
        // Highlight's band, then the word's mark.
        XCTAssertEqual(markup.components(separatedBy: "<path").count - 1, 2, markup)
        var spliced = highlighted
        spliced.effect?.type = "splice"
        XCTAssertEqual(SVGExporter.bandMarkup(spliced).components(separatedBy: "<path").count - 1, 1)
    }
}
