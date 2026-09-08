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
}
