// Text on a curve.
//
// The arc is one circle: the line's own advance width fixes the radius, so a
// wider angle means a tighter circle and the letters keep their size. That is
// the difference between type on a curve and type that has been squashed, and
// it is what the geometry below is checking.
//
// Everything here is decided by CoreText metrics and trigonometry, so it is
// all assertable without looking at anything.

import XCTest
import CoreGraphics
import CoreText
@testable import Canvia

final class CurvedTextTests: XCTestCase {

    private func text(_ body: String = "CURVED HEADLINE",
                      curve: Double? = nil, size: Double = 40, w: Double = 500) -> Element {
        var el = Element()
        el.type = .text
        el.text = body
        el.fontSize = size
        el.w = w
        el.curve = curve
        el.h = FontLibrary.layoutHeight(for: el)
        return el
    }

    // MARK: dispatch

    /// A curve too small to see must not take the curved path: the radius it
    /// implies is enormous and the arithmetic loses precision long before the
    /// difference becomes visible.
    func testTinyCurvesStayStraight() throws {
        let straight = try XCTUnwrap(TextOutliner.path(for: text(curve: nil)))
        let nearlyStraight = try XCTUnwrap(TextOutliner.path(for: text(curve: 0.2)))
        XCTAssertEqual(nearlyStraight.boundingBox.height, straight.boundingBox.height, accuracy: 0.5)
    }

    func testACurvedElementProducesACurvedPath() throws {
        XCTAssertNotNil(TextOutliner.curvedPath(for: text(curve: 90), degrees: 90))
    }

    func testEmptyTextCurvesToNothing() {
        XCTAssertNil(TextOutliner.curvedPath(for: text("", curve: 90), degrees: 90))
        XCTAssertNil(TextOutliner.curvedPath(for: text("   ", curve: 90), degrees: 90))
    }

    // MARK: the shape of the arc

    /// Bending a line makes it shorter across and taller down. A curve that
    /// left the bounding box alone would not be bending anything.
    func testCurvingMakesTheTextShorterAndTaller() throws {
        let straight = try XCTUnwrap(TextOutliner.path(for: text())).boundingBox
        let curved = try XCTUnwrap(TextOutliner.curvedPath(for: text(curve: 120), degrees: 120)).boundingBox
        XCTAssertLessThan(curved.width, straight.width, "the arc is no narrower than the flat line")
        XCTAssertGreaterThan(curved.height, straight.height * 2, "the arc is barely taller than flat")
    }

    /// More angle, tighter circle, taller arc — monotonically.
    func testDeeperCurvesAreTaller() throws {
        var previous = 0.0
        for degrees in [30.0, 60, 90, 120, 150, 180] {
            let height = try XCTUnwrap(TextOutliner.curvedSize(for: text(), degrees: degrees)).height
            XCTAssertGreaterThan(height, previous, "\(degrees)° is not taller than the angle before it")
            previous = height
        }
    }

    /// A positive angle arcs up like a rainbow, a negative one down like a
    /// valley. The baselines are mirror images; the boxes are not, and must
    /// not be: the letters stand on the baseline in both, so on the rainbow
    /// they point outward from the circle and on the valley inward. The
    /// rainbow's tilted end letters therefore reach further out, and it is
    /// the wider and taller of the two — by less than a glyph's height,
    /// which is all that difference can be.
    func testAValleyIsTheRainbowsBaselineNotItsBox() throws {
        let size = 40.0
        let up = try XCTUnwrap(TextOutliner.curvedSize(for: text(size: size), degrees: 120))
        let down = try XCTUnwrap(TextOutliner.curvedSize(for: text(size: size), degrees: -120))
        XCTAssertGreaterThan(up.width, down.width, "the valley's end letters lean outward")
        XCTAssertGreaterThanOrEqual(up.height, down.height - 1)
        XCTAssertLessThan(up.width - down.width, size * 2)
        XCTAssertLessThan(up.height - down.height, size * 2)
        // Whatever the letters do, both are bent: a real valley is far taller
        // than the flat line it came from.
        let flat = try XCTUnwrap(TextOutliner.path(for: text(size: size))).boundingBox
        XCTAssertGreaterThan(down.height, flat.height * 2)
    }

    /// The letters keep their size. If the glyphs were being scaled to fit an
    /// angle rather than placed along it, a full semicircle would shrink them.
    func testLettersKeepTheirSizeAtEveryAngle() throws {
        // One wide glyph, so its own ink is most of the path's extent.
        let flat = try XCTUnwrap(TextOutliner.path(for: text("M", w: 200))).boundingBox
        for degrees in [45.0, 90, 150] {
            let bent = try XCTUnwrap(
                TextOutliner.curvedPath(for: text("M", curve: degrees, w: 200), degrees: degrees)
            ).boundingBox
            XCTAssertEqual(bent.height, flat.height, accuracy: flat.height * 0.35,
                           "the glyph changed size at \(degrees)°")
        }
    }

    // MARK: placement

    /// The arc has to sit inside the box the element reports, or it hangs
    /// outside its own selection rectangle and gets clipped on export.
    func testTheArcSitsInsideTheElementBox() throws {
        for degrees in [45.0, 120, 180, -120] {
            var el = text(curve: degrees)
            if let size = TextOutliner.curvedSize(for: el, degrees: degrees) {
                el.w = max(el.w, size.width)
                el.h = size.height
            }
            let box = try XCTUnwrap(TextOutliner.path(for: el)).boundingBox
            XCTAssertGreaterThanOrEqual(box.minX, -1, "\(degrees)° starts left of the element")
            XCTAssertGreaterThanOrEqual(box.minY, -1, "\(degrees)° starts above the element")
            XCTAssertLessThanOrEqual(box.maxX, el.w + 1, "\(degrees)° runs past the width")
            XCTAssertLessThanOrEqual(box.maxY, el.h + 1, "\(degrees)° runs past the height")
        }
    }

    // MARK: the model

    /// The curve is a document field, so it has to survive a save and load
    /// like everything else — a design reopened flat is a design lost.
    func testTheCurveSurvivesAJSONRoundTrip() throws {
        var el = text(curve: 135)
        el.color = "#ff0066"
        let data = try JSONEncoder().encode(el)
        let restored = try JSONDecoder().decode(Element.self, from: data)
        XCTAssertEqual(restored.curve, 135)
        XCTAssertEqual(restored, el)
    }

    /// An older document has no curve field at all and must decode straight.
    func testADocumentWithoutACurveDecodesStraight() throws {
        let json = #"{"id":"el_1","type":"text","text":"Hi","w":200,"h":50,"fontSize":40}"#
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertNil(el.curve)
    }

    // MARK: export

    /// Curved text still has to reach SVG as outlines — it is the one kind of
    /// text that could not be written as <text> even if we wanted to.
    @MainActor
    func testCurvedTextExportsAsOutlines() {
        var design = Design(title: "curve", width: 800, height: 600)
        var el = text(curve: 120)
        el.x = 100; el.y = 100
        design.pages = [Page(background: .color("#ffffff"), elements: [el])]
        let svg = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertFalse(svg.contains("<text"))
        XCTAssertTrue(svg.contains("<path d=\"M"))
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    // MARK: words' own styles

    /// The fixture both phones check: "**Sale** today" curved 90° draws Sale
    /// bold, so its outline is wider than plain "Sale today" on the same
    /// curve — and curvedSize, which the box is sized by, takes it in.
    func testABoldWordStaysBoldOnACurve() throws {
        let plain = text("Sale today", curve: 90)
        let bold = text("**Sale** today", curve: 90)
        let plainWidth = try XCTUnwrap(TextOutliner.path(for: plain)).boundingBox.width
        let boldWidth = try XCTUnwrap(TextOutliner.path(for: bold)).boundingBox.width
        XCTAssertGreaterThan(boldWidth, plainWidth)
        let plainSize = try XCTUnwrap(TextOutliner.curvedSize(for: plain, degrees: 90))
        let boldSize = try XCTUnwrap(TextOutliner.curvedSize(for: bold, degrees: 90))
        XCTAssertGreaterThan(boldSize.width, plainSize.width)
    }

    /// A word set twice the size stays twice the size round the curve, and
    /// the box grows to hold it.
    func testALargerWordTakesItsRoomOnACurve() throws {
        let plain = text("Sale today", curve: 90)
        var sized = plain
        sized.setSpans([TextSpan(start: 0, end: 4, scale: 2)])
        let plainSize = try XCTUnwrap(TextOutliner.curvedSize(for: plain, degrees: 90))
        let sizedSize = try XCTUnwrap(TextOutliner.curvedSize(for: sized, degrees: 90))
        XCTAssertGreaterThan(sizedSize.width, plainSize.width)
        XCTAssertGreaterThan(sizedSize.height, plainSize.height)
        XCTAssertGreaterThan(FontLibrary.layoutHeight(for: sized), FontLibrary.layoutHeight(for: plain))
    }

    /// An underline or a strike follows the curve under or through its
    /// words: on a valley the underline hangs below the lowest letters.
    func testUnderlinesAndStrikesFollowTheCurve() throws {
        let plain = try XCTUnwrap(TextOutliner.curvedSize(for: text("SALE NOW"), degrees: -90))
        let underlined = try XCTUnwrap(TextOutliner.curvedSize(for: text("__SALE NOW__"), degrees: -90))
        XCTAssertGreaterThan(underlined.height, plain.height, "the underline below the baseline")
        let struck = try XCTUnwrap(TextOutliner.path(for: text("~~SALE~~ NOW", curve: 90)))
        let bare = try XCTUnwrap(TextOutliner.path(for: text("SALE NOW", curve: 90)))
        XCTAssertNotEqual(TextOutliner.svgPathData(struck), TextOutliner.svgPathData(bare), "the strike is drawn")
    }

    /// An underline runs on through the spaces between words, as on the
    /// Android twin: a space has no outline but keeps its rule.
    func testAnUnderlineRunsThroughSpacesAlongAPath() throws {
        var el = text("__I I__", w: 600)
        el.textPath = "M0 50 L100 50"
        el.h = 100
        let path = try XCTUnwrap(TextOutliner.path(for: el))
        let font = FontLibrary.uiFont(family: nil, size: 40, weight: 400, italic: false) as CTFont
        let y = 50 + Double(CTFontGetDescent(font)) / 2
        let box = path.boundingBox
        var x = Double(box.minX) + 1
        while x < Double(box.maxX) - 1 {
            XCTAssertTrue(path.contains(CGPoint(x: x, y: y)), "the underline at \(x)")
            x += 1
        }
    }

    /// Text along a path keeps a word's bold, as round a curve.
    func testABoldWordStaysBoldAlongAPath() throws {
        var plain = text("Sale today", w: 600)
        plain.textPath = "M0 50 L100 50"
        plain.h = 100
        var bold = plain
        bold.text = "**Sale** today"
        let plainWidth = try XCTUnwrap(TextOutliner.path(for: plain)).boundingBox.width
        let boldWidth = try XCTUnwrap(TextOutliner.path(for: bold)).boundingBox.width
        XCTAssertGreaterThan(boldWidth, plainWidth)
    }

    // MARK: a full ring

    /// Shared row: 'BADGE • BADGE • ' curved 360 — its letters equally
    /// spaced round the ring, summing to 360° less one space, so the last
    /// and the first stand a space apart. The trailing space is trimmed as
    /// the outliner trims it; the gap stands for it.
    func testAFullRingLeavesOneSpaceBetweenItsEnds() {
        let words = Array("BADGE • BADGE •")
        let advances = words.map { _ in 10.0 }
        let angles = TextPaths.arcAngles(advances, space: 10, degrees: 360)
        XCTAssertEqual(angles.count, 15)
        let steps = zip(angles, angles.dropFirst()).map { $1 - $0 }
        for step in steps { XCTAssertEqual(step, 22.5, accuracy: 1e-9) }
        // The letters' own arcs, end to end, are 360 less one space.
        XCTAssertEqual(steps.reduce(0, +) + 22.5, 360 - 22.5, accuracy: 1e-9)
        XCTAssertEqual((angles.first ?? 0) + (angles.last ?? 0), 0, accuracy: 1e-9, "centred on the top")
        // Turned, every letter moves by the same.
        let turned = TextPaths.arcAngles(advances, space: 10, degrees: 360, start: 90)
        for (a, b) in zip(angles, turned) { XCTAssertEqual(b - a, 90, accuracy: 1e-9) }
        // At half a ring and below there is no gap.
        XCTAssertEqual(TextPaths.arcLength(width: 150, space: 10, degrees: 180), 150)
        XCTAssertEqual(TextPaths.arcLength(width: 150, space: 10, degrees: -270), 155)
        XCTAssertEqual(TextPaths.arcLength(width: 150, space: 10, degrees: 360), 160)
    }

    /// Shared rows: the slider snaps at ±180 and ±360, the Rotate slider
    /// shows past half a ring, and a stored curve past ±180 reads as it is.
    func testTheCurveReachesARing() throws {
        XCTAssertEqual(TextPaths.snappedCurve(357), 360)
        XCTAssertEqual(TextPaths.snappedCurve(-183), -180)
        XCTAssertEqual(TextPaths.snappedCurve(170), 170)
        XCTAssertFalse(TextPaths.showsRotate(180))
        XCTAssertTrue(TextPaths.showsRotate(-181))
        XCTAssertFalse(TextPaths.showsRotate(nil))
        let json = #"{"id":"el_1","type":"text","text":"Hi","w":200,"h":50,"curve":270,"curveStart":45}"#
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertEqual(el.curve, 270)
        XCTAssertEqual(el.curveStart, 45)
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.curveStart, 45)
        let far = #"{"id":"el_1","type":"text","text":"Hi","w":200,"h":50,"curve":500,"curveStart":0}"#
        let held = try JSONDecoder().decode(Element.self, from: Data(far.utf8))
        XCTAssertEqual(held.curve, 360)
        XCTAssertNil(held.curveStart, "no turn is no key")
    }

    /// From half a ring the box is the ring's square, and turning the ring
    /// never moves its circle.
    func testARingStandsInItsSquare() throws {
        let el = text("BADGE • BADGE • ", curve: 360)
        let size = try XCTUnwrap(TextOutliner.curvedSize(for: el, degrees: 360))
        XCTAssertEqual(size.width, size.height)
        var ring = el
        ring.w = size.width
        ring.h = size.height
        let still = try XCTUnwrap(TextOutliner.path(for: ring)).boundingBox
        ring.curveStart = 90
        let turned = try XCTUnwrap(TextOutliner.path(for: ring)).boundingBox
        XCTAssertLessThanOrEqual(still.maxX, size.width + 1)
        XCTAssertLessThanOrEqual(turned.maxY, size.height + 1)
        XCTAssertEqual(still.midX, turned.midX, accuracy: 40 * 0.75, "the ring's centre stays put")
    }
}
