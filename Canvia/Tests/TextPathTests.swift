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

/// Shared (Fixtures/bent-text.json): glyph quads, the bands behind bent
/// words, and Highlight, Splice, word marks and links round a curve, along a
/// path and down a column.
final class BentTextTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("bent-text") }

    private func point(_ value: Any?) throws -> CGPoint {
        let xy = try XCTUnwrap(value as? [Double])
        return CGPoint(x: xy[0], y: xy[1])
    }

    private func number(_ row: [String: Any], _ key: String) throws -> Double {
        try XCTUnwrap(row[key] as? Double, key)
    }

    private func assertBounds(_ path: CGPath, _ expected: Any?, accuracy: Double = 0.05,
                              file: StaticString = #filePath, line: UInt = #line) throws {
        let want = try XCTUnwrap(expected as? [Double])
        let got = path.boundingBoxOfPath
        for (a, b) in zip([got.minX, got.minY, got.width, got.height].map(Double.init), want) {
            XCTAssertEqual(a, b, accuracy: accuracy, "\(got) against \(want)", file: file, line: line)
        }
    }

    func testAGlyphsQuadRunsAlongItsTangentFromDescentToAscent() throws {
        for row in try XCTUnwrap(fixture()["quads"] as? [[String: Any]]) {
            let quad = TextPaths.quad(origin: try point(row["origin"]), angle: try number(row, "angle"),
                                      advance: try number(row, "advance"), ascent: try number(row, "ascent"),
                                      descent: try number(row, "descent"))
            let want = try XCTUnwrap(row["quad"] as? [[Double]])
            for (got, corner) in zip(quad, want) {
                XCTAssertEqual(Double(got.x), corner[0], accuracy: 1e-3)
                XCTAssertEqual(Double(got.y), corner[1], accuracy: 1e-3)
            }
        }
    }

    func testACurvesBandIsTheSectorOverItsArc() throws {
        for row in try XCTUnwrap(fixture()["arcs"] as? [[String: Any]]) {
            let band = TextPaths.arcBand(centre: try point(row["centre"]), radius: try number(row, "radius"),
                                         from: try number(row, "from"), to: try number(row, "to"),
                                         ascent: try number(row, "ascent"), descent: try number(row, "descent"),
                                         pad: try number(row, "pad"))
            try assertBounds(band, row["bounds"])
        }
    }

    func testAPathsBandIsTheStripAlongIt() throws {
        for row in try XCTUnwrap(fixture()["strips"] as? [[String: Any]]) {
            let points = try XCTUnwrap(row["points"] as? [[Double]]).map { CGPoint(x: $0[0], y: $0[1]) }
            let line = CGMutablePath()
            line.addLines(between: points)
            let band = TextPaths.stripBand(PathWalker(line), from: try number(row, "from"), to: try number(row, "to"),
                                           ascent: try number(row, "ascent"), descent: try number(row, "descent"),
                                           pad: try number(row, "pad"))
            try assertBounds(band, row["bounds"], accuracy: 1e-3)
        }
    }

    func testAColumnsBandIsItsCellsGrownByThePad() throws {
        for row in try XCTUnwrap(fixture()["columns"] as? [[String: Any]]) {
            let box = try XCTUnwrap(row["box"] as? [Double])
            let band = TextPaths.columnBand(CGRect(x: box[0], y: box[1], width: box[2], height: box[3]),
                                            pad: try number(row, "pad"))
            try assertBounds(band, row["bounds"], accuracy: 1e-6)
        }
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

    private func elements() throws -> [(name: String, element: Element)] {
        try XCTUnwrap(fixture()["elements"] as? [[String: Any]]).map { row in
            (name: try XCTUnwrap(row["name"] as? String),
             element: try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(XCTUnwrap(row["element"]))))
        }
    }

    func testEveryLetterOfBentWordsIsPlacedAndItsBandsHoldThem() throws {
        for (name, el) in try elements() {
            let placed = TextPaths.glyphPlacements(el)
            // "Happy Birthday": thirteen letters, the space placed or not.
            XCTAssertGreaterThanOrEqual(placed.count, 13, name)
            XCTAssertTrue(placed.allSatisfy { (0..<14).contains($0.index) }, name)
            XCTAssertEqual(Set(placed.map(\.index)).count, placed.count, name)
            let bands = TextPaths.band(el, spread: 50, roundness: 40, range: nil)
            XCTAssertFalse(bands.isEmpty, name)
            let reach = bands.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
                .insetBy(dx: -10, dy: -10)
            for glyph in placed where glyph.index != 5 {
                XCTAssertTrue(reach.contains(glyph.centre), "\(name): letter \(glyph.index) outside its band")
            }
            // A word's own mark covers less than the whole band.
            let mark = TextPaths.band(el, pad: 3, corner: 6, range: NSRange(location: 0, length: 5))
            XCTAssertFalse(mark.isEmpty, name)
            let marked = mark.reduce(CGRect.null) { $0.union($1.boundingBoxOfPath) }
            XCTAssertLessThan(marked.width * marked.height, reach.width * reach.height, name)
        }
    }

    func testBentWordsLinksAndFindAreTheirLettersQuads() throws {
        for (name, el) in try elements() {
            let links = WordLinks.rects(for: el)
            XCTAssertEqual(links.count, 1, "\(name): Birthday is one word")
            XCTAssertEqual(links.first?.url, "https://example.com/")
            let birthday = TextPaths.glyphPlacements(el).filter { (6..<14).contains($0.index) }
            let around = WordLinks.bounds(of: birthday.map(\.quad))
            XCTAssertEqual(links.first.map { Double($0.rect.width) } ?? 0, Double(around.width), accuracy: 0.01, name)
            XCTAssertEqual(FindReplace.letterRects(of: NSRange(location: 0, length: 5), in: el).count, 5, name)
        }
    }

    func testTheSVGDrawsTheBandsAsPaths() throws {
        let highlighted = try XCTUnwrap(elements().first { $0.name == "curve50-highlight" }?.element)
        let markup = SVGExporter.bandMarkup(highlighted)
        // Highlight's band, then the word's mark.
        XCTAssertEqual(markup.components(separatedBy: "<path").count - 1, 2, markup)
        let spliced = try XCTUnwrap(elements().first { $0.name == "curve50-splice" }?.element)
        XCTAssertEqual(SVGExporter.bandMarkup(spliced).components(separatedBy: "<path").count - 1, 1)
    }
}
