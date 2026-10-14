// Dashed and dotted borders on shapes, photos and frames: the shared
// intervals, the SVG and PowerPoint files, and Copy style, in rows the
// Android twin's tests hold too.

import XCTest
import CoreGraphics
@testable import Canvia

final class BorderStyleTests: XCTestCase {

    // MARK: dashed and dotted borders

    func testBorderIntervalsAreTheLinesScaledByTheWidth() {
        XCTAssertEqual(BorderDash.intervals("dashed", width: 4), [12, 8])
        XCTAssertEqual(BorderDash.phase("dashed", width: 4), 6)
        XCTAssertFalse(BorderDash.roundCaps("dashed"))
        XCTAssertEqual(BorderDash.intervals("dashed", width: 2), [6, 4])
        let dots = BorderDash.intervals("dotted", width: 4) ?? []
        XCTAssertEqual(dots.count, 2)
        XCTAssertEqual(dots[0], 0.01, accuracy: 1e-12)
        XCTAssertEqual(dots[1], 8.8, accuracy: 1e-12)
        XCTAssertEqual(BorderDash.phase("dotted", width: 4), 0.005, accuracy: 1e-12)
        XCTAssertTrue(BorderDash.roundCaps("dotted"))
        // Solid: no key, and a line's "solid" is none either.
        XCTAssertNil(BorderDash.intervals(nil, width: 4))
        XCTAssertNil(BorderDash.intervals("solid", width: 4))
        XCTAssertEqual(BorderDash.phase(nil, width: 4), 0)
        XCTAssertTrue(BorderDash.roundCaps(nil))
        XCTAssertNil(BorderDash.kept("solid"))
        XCTAssertEqual(BorderDash.styles.map(\.name), ["Solid", "Dashed", "Dotted"])
        XCTAssertEqual(BorderDash.name("dotted"), "Dotted")
    }

    @MainActor
    func testTheSVGDrawsADashedOrDottedBorder() {
        var d = Design(title: "s", width: 400, height: 300)
        var dashed = Element.shape("rect", w: 100, h: 50)
        dashed.stroke = "#ff0000"
        dashed.strokeWidth = 4
        dashed.dash = "dashed"
        var dotted = dashed
        dotted.id = "dotted"
        dotted.dash = "dotted"
        d.pages[0].elements = [dashed, dotted]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("stroke-linecap=\"butt\" stroke-dasharray=\"12 8\" stroke-dashoffset=\"6\""), svg)
        XCTAssertTrue(svg.contains("stroke-linecap=\"round\" stroke-dasharray=\"0.01 8.8\" stroke-dashoffset=\"0.005\""), svg)
        XCTAssertEqual(SVGExporter.borderDash(nil, width: 4), " stroke-linecap=\"round\"")
    }

    func testPowerPointNamesTheBordersDash() {
        var rect = Element.shape("rect", w: 100, h: 200)
        rect.stroke = "#000000"
        rect.strokeWidth = 2
        rect.dash = "dotted"
        var d = Design(title: "Deck", width: 800, height: 600)
        d.pages = [Page(elements: [rect])]
        let xml = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        // The Android twin's PptxWriterTest holds the same string.
        let dotted = "<a:ln w=\"19050\" cap=\"rnd\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill>"
            + "<a:prstDash val=\"sysDot\"/></a:ln>"
        XCTAssertTrue(xml.contains(dotted), xml)
        rect.dash = "dashed"
        d.pages = [Page(elements: [rect])]
        let dashed = PptxExporter.slide(design: d, page: d.pages[0], number: 1, previous: nil, firstImage: 1).xml
        XCTAssertTrue(dashed.contains("<a:ln w=\"19050\"><a:solidFill>"), dashed)
        XCTAssertEqual(PptxExporter.dashXML("dashed"), "<a:prstDash val=\"dash\"/>")
        XCTAssertEqual(PptxExporter.dashXML(nil), "")
    }

    func testCopyStyleCarriesABordersDashToShapesAndPhotos() {
        var source = Element.shape("rect")
        source.stroke = "#000000"
        source.strokeWidth = 3
        source.dash = "dashed"
        var photo = Element.image("media:x")
        DesignStore.apply(DesignStore.style(of: source), to: &photo)
        XCTAssertEqual(photo.dash, "dashed")
        var shape = Element.shape("circle")
        DesignStore.apply(DesignStore.style(of: Element.line()), to: &shape)
        XCTAssertNil(shape.dash, "a line's solid is no key on a shape")
        // Painted across kinds, a border keeps its dashes, as on Android.
        let painted = StylePaint.pasted(DesignStore.style(of: source), from: .shape, onto: Element.image("media:y"))
        XCTAssertEqual(painted.dash, "dashed")
        XCTAssertEqual(painted.stroke, "#000000")
        var dotted = Element.shape("circle")
        dotted.dash = "dotted"
        let solid = StylePaint.pasted(DesignStore.style(of: Element.image("media:z")), from: .image, onto: dotted)
        XCTAssertNil(solid.dash, "a photo with a solid border takes the dots away")
    }
}
