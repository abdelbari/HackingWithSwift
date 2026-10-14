// A whole SVG brought in as a graphic: its parts, where they land, how
// they are painted, and what is left out. The files and numbers are the
// Android twin's SvgImportTest's too: the same file makes the same elements
// on either phone.

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
        XCTAssertEqual(dot.pathData, "M100 50C100 77.61 77.61 100 50 100C22.39 100 0 77.61 0 50C0 22.39 22.39 0 50 0C77.61 0 100 22.39 100 50Z")
        XCTAssertEqual(dot.fill, .solid("#0000ff"))
        XCTAssertEqual(dot.stroke, "#00ff00")
        XCTAssertEqual(dot.strokeWidth, 6.4)
        XCTAssertEqual(dot.opacity, 0.5)
        XCTAssertEqual(dot.layerName, "b")
        // One graphic: one group.
        XCTAssertNotNil(back.group)
        XCTAssertEqual(back.group, dot.group)
        XCTAssertNil(back.fillRule)
        XCTAssertEqual(back.pathData, "M0 0L100 0L100 100L0 100Z")
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

    private func graphic(_ svg: String, _ width: Double, _ height: Double) -> SvgImport.Graphic? {
        SvgImport.graphic(svg, pageWidth: width, pageHeight: height)
    }

    private func frame(_ el: Element) -> [Double] { [el.x, el.y, el.w, el.h].map { Double($0) } }

    func testTheViewBoxIsWhatIsFittedAndALonePartHasNoGroup() throws {
        let one = try XCTUnwrap(graphic(#"<svg viewBox="0 0 100 100"><circle cx="50" cy="50" r="10"/></svg>"#, 1000, 1000))
        XCTAssertEqual(one.elements.count, 1)
        // The viewBox is 400 across, so the circle is 80.
        XCTAssertEqual(frame(one.elements[0]), [460, 460, 80, 80])
        XCTAssertNil(one.elements[0].group)
        XCTAssertFalse(one.skipped)
        let rect = try XCTUnwrap(graphic(#"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#, 1000, 1000))
        XCTAssertNil(rect.elements[0].group)
        XCTAssertEqual(rect.elements[0].fill, .solid("#000000"))
    }

    func testPreserveAspectRatioNoneStretchesTheViewBoxFirst() throws {
        let doc = #"<svg viewBox="0 0 10 10" width="200" height="100" preserveAspectRatio="none"><rect width="10" height="10"/></svg>"#
        XCTAssertEqual(frame(try XCTUnwrap(graphic(doc, 1000, 1000)).elements[0]), [300, 400, 400, 200])
        // Without it, the viewBox alone.
        let plain = doc.replacingOccurrences(of: #" preserveAspectRatio="none""#, with: "")
        XCTAssertEqual(frame(try XCTUnwrap(graphic(plain, 1000, 1000)).elements[0]), [300, 300, 400, 400])
    }

    func testNoViewBoxAndNoSizeFitsWhatIsDrawn() throws {
        let doc = #"<svg><rect x="10" y="10" width="20" height="10" fill="red"/><rect x="30" y="20" width="10" height="10" fill="blue"/></svg>"#
        let parts = try XCTUnwrap(graphic(doc, 1000, 500)).elements
        // 30 by 20 drawn, at 200 by 133.33.
        XCTAssertEqual(frame(parts[0]), [400, 183.33, 133.33, 66.67])
        XCTAssertEqual(frame(parts[1]), [533.33, 250, 66.67, 66.67])
    }

    func testTransformsOnGroupsAndShapesAreFollowed() throws {
        let doc = """
        <svg viewBox="0 0 200 200"><g transform="translate(100 0) scale(2)">
        <rect x="0" y="0" width="10" height="10" transform="rotate(45 5 5)" fill="#000"/></g></svg>
        """
        let diamond = try XCTUnwrap(graphic(doc, 1000, 500)).elements[0]
        // Turned an eighth, the square stands on a corner.
        XCTAssertEqual(diamond.pathData, "M50 0L100 50L50 100L0 50Z")
        XCTAssertEqual(frame(diamond), [495.86, 145.86, 28.28, 28.28])
        XCTAssertEqual(diamond.fill, .solid("#000000"))
    }

    func testStylesComeFromAttributesThenClassAndIdRulesThenTheInlineStyle() throws {
        let doc = """
        <svg viewBox="0 0 30 10"><style>.a { fill: #ff0000; } #b { fill: rgb(0, 0, 255) } .thin, .a { stroke-width: 3 }</style>
        <g fill="#00ff00" stroke="#000000" opacity="0.5">
          <rect class="a" width="10" height="10"/>
          <rect id="b" class="a" x="10" width="10" height="10"/>
          <rect x="20" width="10" height="10" style="fill:#123456;fill-opacity:0.5" opacity="0.5"/>
        </g></svg>
        """
        let parts = try XCTUnwrap(graphic(doc, 1000, 500)).elements
        XCTAssertEqual(parts.map(\.fill), [.solid("#ff0000"), .solid("#0000ff"), .solid("#12345680")])
        // The group's border is inherited; .a's width is the rule's.
        XCTAssertEqual(parts[0].stroke, "#000000")
        XCTAssertEqual(parts[0].strokeWidth, 20)
        XCTAssertEqual(parts[2].strokeWidth, 6.67)
        // The group's opacity, and the shape's own times it.
        XCTAssertEqual(parts[0].opacity, 0.5)
        XCTAssertEqual(parts[2].opacity, 0.25)
    }

    func testClassRulesApplyInTheSheetsOrderNotTheClassLists() throws {
        let doc = """
        <svg viewBox="0 0 10 10"><style>.a{fill:#0000ff} .b{fill:#ff0000} g .a{fill:#00ff00}</style>
        <rect class="b a" width="10" height="10"/></svg>
        """
        XCTAssertEqual(try XCTUnwrap(graphic(doc, 100, 100)).elements[0].fill, .solid("#ff0000"))
    }

    func testARadialGradientHasNoAngle() throws {
        let doc = """
        <svg viewBox="0 0 10 10"><defs>
        <linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff0000"/><stop offset="100%" stop-color="#0000ff" stop-opacity="0.5"/></linearGradient>
        <radialGradient id="r" href="#g"/></defs>
        <path fill="url(#g)" fill-rule="evenodd" d="M0 0H10V10H0Z M2 2H8V8H2Z"/>
        <circle cx="5" cy="5" r="2" fill="url(#r)"/></svg>
        """
        let parts = try XCTUnwrap(graphic(doc, 1000, 500)).elements
        XCTAssertEqual(parts[0].fill?.angle, 180)
        XCTAssertEqual(parts[0].fill?.stops?.map(\.color), ["#ff0000", "#0000ff80"])
        XCTAssertEqual(parts[0].fillRule, "evenodd")
        XCTAssertNil(parts[1].fillRule)
        XCTAssertEqual(parts[1].fill?.gradientKind, "radial")
        XCTAssertNil(parts[1].fill?.angle)
        XCTAssertEqual(parts[1].fill?.stops?.map(\.offset), [0, 1])
    }

    func testAGradientsEndsAndTransformComeDownItsHrefChainAndItsUnitsTurnItWithTheShape() throws {
        let defs = """
        <defs>
        <linearGradient id="a"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient>
        <linearGradient id="b" href="#a" x1="0" y1="0" x2="0" y2="1"/>
        <linearGradient id="c" href="#b"/>
        <linearGradient id="d" href="#a" gradientTransform="rotate(90)"/>
        <linearGradient id="e" href="#a" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="10" y2="0"/>
        <linearGradient id="f" href="#a" x1="0" y1="0" x2="10" y2="0"/>
        <linearGradient id="h" href="#a" gradientTransform="rotate(45)"/></defs>
        """
        func angle(_ fill: String, _ transform: String = "") throws -> Double? {
            let doc = "<svg viewBox=\"0 0 10 10\">\(defs)<g transform=\"\(transform)\">"
                + "<rect width=\"10\" height=\"10\" fill=\"url(#\(fill))\"/></g></svg>"
            return try XCTUnwrap(graphic(doc, 100, 100)).elements[0].fill?.angle
        }
        XCTAssertEqual(try angle("b"), 180)
        XCTAssertEqual(try angle("c"), 180)
        XCTAssertEqual(try angle("d"), 180)
        XCTAssertEqual(try angle("e"), 90)
        XCTAssertEqual(try angle("e", "rotate(90 5 5)"), 180)
        // In the shape's own box, its transforms do not turn it.
        XCTAssertEqual(try angle("f", "rotate(90 5 5)"), 90)
        XCTAssertEqual(try angle("h"), 135)
    }

    func testColoursAlphaAUrlsFallbackAndLengthsInUnits() throws {
        XCTAssertEqual(SvgImport.colour("#f008", current: "#000000"), "#ff000088")
        XCTAssertEqual(SvgImport.colour("#ff000080", current: "#000000"), "#ff000080")
        XCTAssertEqual(SvgImport.colour("rgb(50%, 100%, 0%)", current: "#000000"), "#80ff00")
        XCTAssertEqual(SvgImport.colour("orangered", current: "#000000"), "#ff4500")
        XCTAssertEqual(SvgImport.colour("plum", current: "#000000"), "#dda0dd")
        XCTAssertNil(SvgImport.colour("#ff000", current: "#000000"))
        XCTAssertEqual(SvgImport.hex("#ff000080", alpha: 0.5), "#ff000040")
        XCTAssertEqual(SvgImport.length("12pt"), 16)
        let doc = """
        <svg viewBox="0 0 10 10">
          <rect width="10" height="10" fill="#ff000080"/>
          <rect width="10" height="10" fill="rgba(0,0,255,0.5)"/>
          <rect width="10" height="10" fill="url(#missing) #00ff00" stroke="#000" stroke-width="3pt"/>
        </svg>
        """
        let read = try XCTUnwrap(graphic(doc, 100, 100))
        XCTAssertFalse(read.skipped, "a fallback is drawn instead")
        XCTAssertEqual(read.elements.map(\.fill), [.solid("#ff000080"), .solid("#0000ff80"), .solid("#00ff00")])
        // 3pt is 4 units; each unit 4 on this page.
        XCTAssertEqual(read.elements[2].strokeWidth, 16)
        // A url to nothing, with no fallback, is said to be left out.
        let missing = ##"<svg viewBox="0 0 10 10"><rect width="10" height="10" fill="url(#missing)" stroke="red"/></svg>"##
        XCTAssertEqual(graphic(missing, 100, 100)?.skipped, true)
    }

    func testAWhollySeeThroughFillIsNone() throws {
        let doc = """
        <svg viewBox="0 0 10 10"><rect width="10" height="10" fill-opacity="0"/><rect width="5" height="5" fill="#ff000000"/><rect width="10" height="10" fill="red"/></svg>
        """
        XCTAssertEqual(try XCTUnwrap(graphic(doc, 100, 100)).elements.map(\.fill), [.solid("#ff0000")])
    }

    func testLinesAndOutlinesAreStrokesWithNoFill() throws {
        let doc = """
        <svg viewBox="0 0 10 10"><line x1="0" y1="0" x2="10" y2="10" stroke="black" stroke-width="2"/>
        <polyline points="0,10 5,0 10,10" fill="none" stroke="#e5484d"/></svg>
        """
        let parts = try XCTUnwrap(graphic(doc, 1000, 500)).elements
        XCTAssertEqual(parts[0].fill?.kind, "none")
        XCTAssertEqual(parts[0].stroke, "#000000")
        XCTAssertEqual(parts[0].strokeWidth, 40)
        XCTAssertEqual(parts[0].pathData, "M0 0L100 100")
        XCTAssertEqual(parts[1].fill?.kind, "none")
        XCTAssertEqual(parts[1].stroke, "#e5484d")
        XCTAssertEqual(parts[1].pathData, "M0 100L50 0L100 100")
    }

    func testAMaskedFilteredOrClippedShapeIsDrawnWithoutItAndSaidToBe() throws {
        let doc = """
        <svg viewBox="0 0 10 10"><rect width="10" height="10"/><circle r="3" cx="5" cy="5" filter="url(#f)"/><rect width="2" height="2" style="clip-path:url(#c)"/></svg>
        """
        let filtered = try XCTUnwrap(graphic(doc, 1000, 500))
        XCTAssertTrue(filtered.skipped)
        XCTAssertEqual(filtered.elements.count, 3)
    }

    func testWhatIsNeverDrawnIsNotSaidToBeLeftOut() throws {
        // An unused clip path and words in defs, a hidden text.
        let doc = """
        <svg viewBox="0 0 10 10"><defs><clipPath id="c"><rect width="5" height="5"/></clipPath><text>x</text></defs>
        <clipPath id="d"><rect width="5" height="5"/></clipPath><text display="none">y</text><rect width="10" height="10"/></svg>
        """
        let read = try XCTUnwrap(graphic(doc, 100, 100))
        XCTAssertFalse(read.skipped)
        XCTAssertEqual(read.elements.count, 1)
    }

    func testNothingDrawableTooBigOrNoSVGIsNil() {
        XCTAssertNil(SvgImport.graphic(#"<svg xmlns="http://www.w3.org/2000/svg"><text>Hi</text></svg>"#,
                                       pageWidth: 100, pageHeight: 100))
        XCTAssertNil(SvgImport.graphic("<html/>", pageWidth: 100, pageHeight: 100))
        XCTAssertNil(SvgImport.graphic("<svg", pageWidth: 100, pageHeight: 100))
        XCTAssertNil(SvgImport.graphic(#"<svg><rect width="10" height="10" fill="none"/></svg>"#,
                                       pageWidth: 100, pageHeight: 100), "nothing that shows")
        XCTAssertNil(graphic(#"<html><svg><rect width="1" height="1"/></svg></html>"#, 1000, 500))
        XCTAssertNil(graphic(#"<svg viewBox="0 0 10 10"><path d="M5 5"/><rect width="5" height="5" visibility="hidden"/></svg>"#,
                             1000, 500), "a path that only moves, and a hidden shape")
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
