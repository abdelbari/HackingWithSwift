// A whole SVG brought in as a graphic: its parts, where they land, how
// they are painted, and what is left out, from files the Android twin's
// tests read too.

import XCTest
import CoreGraphics
@testable import Canvia

final class SvgImportTests: XCTestCase {

    /// A red rectangle by a class rule, and a half see-through blue circle
    /// with a green border by an id rule, in a moved group — and words,
    /// which do not come in.
    private let styled = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 50">
      <style>.a{fill:#ff0000} /* the back */ #b{stroke:#00ff00;stroke-width:2}</style>
      <rect id="Back" x="0" y="0" width="100" height="50" class="a"/>
      <g transform="translate(50 25)">
        <circle id="b" cx="0" cy="0" r="10" fill="blue" opacity="0.5"/>
      </g>
      <text x="0" y="10">Hi</text>
    </svg>
    """

    /// A square with a hole, filled with a gradient taken from another, a
    /// half see-through triangle, a line, and a picture, which does not
    /// come in.
    private let gradients = """
    <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="200" height="100">
      <defs>
        <linearGradient id="g1"><stop offset="0" stop-color="#ff0000"/><stop offset="100%" style="stop-color:#0000ff;stop-opacity:0.5"/></linearGradient>
        <linearGradient id="g2" xlink:href="#g1" x1="0" y1="0" x2="0" y2="1"/>
      </defs>
      <path d="M0 0H100V100H0Z M25 25H75V75H25Z" fill="url(#g2)" fill-rule="evenodd"/>
      <polygon points="100,0 200,0 150,100" fill="#0f0" fill-opacity="0.5"/>
      <line x1="0" y1="50" x2="200" y2="50" stroke="black" stroke-width="4"/>
      <image href="x.png" width="10" height="10"/>
    </svg>
    """

    func testEveryShapeIsAPartFittedToFourTenthsOfThePageAndCentred() throws {
        let graphic = try XCTUnwrap(SvgImport.graphic(styled, pageWidth: 1000, pageHeight: 800))
        XCTAssertTrue(graphic.skipped, "the words were left out")
        let parts = graphic.elements
        XCTAssertEqual(parts.count, 2)
        // The viewBox, 100 by 50, at 320 by 160 in the middle of the page.
        let back = parts[0]
        XCTAssertEqual(back.x, 340)
        XCTAssertEqual(back.y, 320)
        XCTAssertEqual(back.w, 320)
        XCTAssertEqual(back.h, 160)
        XCTAssertEqual(back.type, .shape)
        XCTAssertEqual(back.fill, .solid("#ff0000"))
        XCTAssertNil(back.stroke)
        XCTAssertEqual(back.layerName, "Back")
        XCTAssertEqual(back.opacity, 1)
        let dot = parts[1]
        XCTAssertEqual(dot.x, 468)
        XCTAssertEqual(dot.y, 368)
        XCTAssertEqual(dot.w, 64)
        XCTAssertEqual(dot.h, 64)
        XCTAssertEqual(dot.fill, .solid("#0000ff"))
        XCTAssertEqual(dot.stroke, "#00ff00")
        XCTAssertEqual(dot.strokeWidth, 6.4)
        XCTAssertEqual(dot.opacity, 0.5)
        XCTAssertEqual(dot.layerName, "b")
        // One graphic: one group.
        XCTAssertNotNil(back.group)
        XCTAssertEqual(back.group, dot.group)
        XCTAssertNil(back.fillRule)
        XCTAssertTrue(back.pathData?.hasSuffix("Z") == true, back.pathData ?? "")
    }

    func testGradientsHolesSeeThroughFillsAndLines() throws {
        let graphic = try XCTUnwrap(SvgImport.graphic(gradients, pageWidth: 1000, pageHeight: 800))
        XCTAssertTrue(graphic.skipped, "the picture was left out")
        let parts = graphic.elements
        XCTAssertEqual(parts.count, 3)
        // No viewBox: its width and height, 200 by 100, at 320 by 160.
        let square = parts[0]
        XCTAssertEqual(square.x, 340)
        XCTAssertEqual(square.y, 320)
        XCTAssertEqual(square.w, 160)
        XCTAssertEqual(square.h, 160)
        XCTAssertEqual(square.fillRule, "evenodd")
        XCTAssertEqual(square.fill?.kind, "gradient")
        XCTAssertNil(square.fill?.gradientKind)
        XCTAssertEqual(square.fill?.angle, 180, "top to bottom")
        XCTAssertEqual(square.fill?.stops, [GradientStop(offset: 0, color: "#ff0000"),
                                             GradientStop(offset: 1, color: "#0000ff80")])
        let triangle = parts[1]
        XCTAssertEqual(triangle.x, 500)
        XCTAssertEqual(triangle.y, 320)
        XCTAssertEqual(triangle.fill, .solid("#00ff0080"))
        XCTAssertNil(triangle.layerName)
        // A line has no inside, and a flat box is as tall as its stroke.
        let line = parts[2]
        XCTAssertEqual(line.fill?.kind, "none")
        XCTAssertEqual(line.stroke, "#000000")
        XCTAssertEqual(line.strokeWidth, 6.4)
        XCTAssertEqual(line.x, 340)
        XCTAssertEqual(line.w, 320)
        XCTAssertEqual(line.y, 396.8)
        XCTAssertEqual(line.h, 6.4)
        XCTAssertEqual(line.pathData, "M0 50L100 50")
    }

    func testAFileWithEverythingDrawnSaysNothingWasLeftOut() throws {
        let svg = ##"<svg viewBox="0 0 10 10"><g fill="#123456"><ellipse cx="5" cy="5" rx="5" ry="2"/></g></svg>"##
        let graphic = try XCTUnwrap(SvgImport.graphic(svg, pageWidth: 100, pageHeight: 100))
        XCTAssertFalse(graphic.skipped)
        XCTAssertEqual(graphic.elements.count, 1)
        XCTAssertEqual(graphic.elements[0].fill, .solid("#123456"), "a group's fill passes down")
        XCTAssertEqual(graphic.elements[0].w, 40)
        XCTAssertEqual(graphic.elements[0].h, 16)
    }

    func testNothingDrawableTooBigOrNoSVGIsNil() {
        XCTAssertNil(SvgImport.graphic(#"<svg xmlns="http://www.w3.org/2000/svg"><text>Hi</text></svg>"#,
                                       pageWidth: 100, pageHeight: 100))
        XCTAssertNil(SvgImport.graphic("<html/>", pageWidth: 100, pageHeight: 100))
        XCTAssertNil(SvgImport.graphic("<svg", pageWidth: 100, pageHeight: 100))
        XCTAssertNil(SvgImport.graphic(#"<svg><rect width="10" height="10" fill="none"/></svg>"#,
                                       pageWidth: 100, pageHeight: 100), "nothing that shows")
        let padding = String(repeating: " ", count: SvgImport.maxBytes)
        XCTAssertNil(SvgImport.graphic(#"<svg><rect width="10" height="10"/>"# + padding + "</svg>",
                                       pageWidth: 100, pageHeight: 100))
    }

    func testPartsPastTheLimitAreLeftOutAndSaidToBe() throws {
        let rects = (0..<(SvgImport.maxParts + 1)).map { "<rect x=\"\($0)\" width=\"1\" height=\"1\"/>" }.joined()
        let graphic = try XCTUnwrap(SvgImport.graphic("<svg>\(rects)</svg>", pageWidth: 1000, pageHeight: 1000))
        XCTAssertEqual(graphic.elements.count, 600)
        XCTAssertTrue(graphic.skipped)
        XCTAssertEqual(SvgImport.partialNote, "Some parts of this SVG couldn't be brought in")
    }

    // MARK: values

    func testTransformsApplyInsideThoseWrittenBefore() {
        func moved(_ text: String, _ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x, y: y).applying(SvgImport.transform(text))
        }
        XCTAssertEqual(moved("translate(10 20) scale(2)", 1, 1), CGPoint(x: 12, y: 22))
        XCTAssertEqual(moved("matrix(1 0 0 1 5 6)", 1, 1), CGPoint(x: 6, y: 7))
        let turned = moved("rotate(90 10 10)", 20, 10)
        XCTAssertEqual(turned.x, 10, accuracy: 1e-9)
        XCTAssertEqual(turned.y, 20, accuracy: 1e-9)
        let skewed = moved("skewX(45)", 0, 10)
        XCTAssertEqual(skewed.x, 10, accuracy: 1e-9)
        XCTAssertEqual(skewed.y, 10, accuracy: 1e-9)
        XCTAssertEqual(moved("", 3, 4), CGPoint(x: 3, y: 4))
    }

    func testNumbersColoursAndLengths() {
        XCTAssertEqual(SvgImport.numbers("1,2 3-4 5e-1 .5.5"), [1, 2, 3, -4, 0.5, 0.5, 0.5])
        XCTAssertEqual(SvgImport.colour("#F0A", current: "#000000"), "#ff00aa")
        XCTAssertEqual(SvgImport.colour("rgb(255, 0, 0)", current: "#000000"), "#ff0000")
        XCTAssertEqual(SvgImport.colour("rgba(0,0,255,0.5)", current: "#000000"), "#0000ff80")
        XCTAssertEqual(SvgImport.colour("Red", current: "#000000"), "#ff0000")
        XCTAssertEqual(SvgImport.colour("currentColor", current: "#123456"), "#123456")
        XCTAssertNil(SvgImport.colour("none", current: "#000000"))
        XCTAssertEqual(SvgImport.hex("#ff0000", alpha: 0.5), "#ff000080")
        XCTAssertEqual(SvgImport.hex("#ff000080", alpha: 1), "#ff000080")
        XCTAssertEqual(SvgImport.length("12px"), 12)
        XCTAssertEqual(SvgImport.length("1in"), 96)
        XCTAssertNil(SvgImport.length("50%"))
        XCTAssertEqual(SvgImport.fraction("40%"), 0.4)
        XCTAssertEqual(SvgImport.declarations("fill: #f00 ;stroke:blue"), ["fill": "#f00", "stroke": "blue"])
    }

    func testAPathWithExponentsReadsThem() {
        let box = SVGPath.path("M0 0L1e1 0L10 2e1Z").boundingBoxOfPath
        XCTAssertEqual(box.width, 10)
        XCTAssertEqual(box.height, 20)
    }

    // MARK: even-odd

    @MainActor
    func testAnEvenOddFillIsWrittenToTheSVG() {
        var d = Design(title: "s", width: 400, height: 300)
        var ring = Element.shape("rect", w: 100, h: 100)
        ring.pathData = "M0 0H100V100H0Z M25 25H75V75H25Z"
        ring.fillRule = "evenodd"
        d.pages[0].elements = [ring, Element.shape("circle")]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertEqual(svg.components(separatedBy: "fill-rule=\"evenodd\"").count, 2, svg)
    }

    func testFillRuleIsWrittenOnlyWhenEvenOdd() throws {
        var e = Element.shape("rect")
        e.fillRule = "evenodd"
        let json = String(decoding: try JSONEncoder().encode(e), as: UTF8.self)
        XCTAssertTrue(json.contains("\"fillRule\":\"evenodd\""), json)
        let plain = String(decoding: try JSONEncoder().encode(Element.shape("rect")), as: UTF8.self)
        XCTAssertFalse(plain.contains("fillRule"))
        let read = try JSONDecoder().decode(Element.self, from: Data(#"{"type":"shape","fillRule":"nonzero"}"#.utf8))
        XCTAssertNil(read.fillRule)
        let odd = try JSONDecoder().decode(Element.self, from: Data(#"{"type":"shape","fillRule":"evenodd"}"#.utf8))
        XCTAssertEqual(odd.fillRule, "evenodd")
    }

    // MARK: kept among your uploads

    func testAnSVGIsKeptAmongTheUploadsButIsNoPicture() throws {
        let data = Data(#"<svg viewBox="0 0 1 1"><rect width="1" height="1"/></svg>"#.utf8)
        let id = try XCTUnwrap(MediaStore.storeGraphic(data))
        defer { MediaStore.delete(id) }
        XCTAssertTrue(MediaStore.isGraphic(id))
        XCTAssertEqual(MediaStore.graphicURL(id).pathExtension, "svg")
        XCTAssertNil(MediaStore.load(id))
        XCTAssertFalse(MediaStore.all().contains(id), "not offered as a background photo")
        XCTAssertTrue(MediaStore.extensions.contains("svg"), "swept, backed up and listed with the uploads")
    }
}
