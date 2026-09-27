// SVG export.
//
// Two things are worth asserting and one is not. Worth asserting: that the
// file is well-formed XML — a broken tag makes the whole export useless and is
// invisible in a string comparison — and that each element kind arrives in the
// form that keeps it editable downstream, which is the entire reason to offer
// this format rather than a PNG.
//
// Not worth asserting: the exact markup. Pinning byte-for-byte output makes
// every attribute reorder a test failure and proves nothing about whether the
// file opens.

import XCTest
import CoreGraphics
import UIKit
@testable import Canvia

final class SVGExporterTests: XCTestCase {

    // MARK: fixtures

    private func design(width: Double = 800, height: Double = 600,
                        elements: [Element] = [],
                        background: Background = .color("#101820")) -> Design {
        var d = Design(title: "SVG fixture", width: width, height: height)
        d.pages = [Page(background: background, elements: elements)]
        return d
    }

    @MainActor
    private func markup(_ d: Design) -> String {
        SVGExporter.svg(design: d, page: d.pages[0])
    }

    private func text(_ body: String = "Hello", w: Double = 300, h: Double = 80) -> Element {
        var el = Element()
        el.type = .text
        el.text = body
        el.w = w
        el.h = h
        el.fontSize = 40
        el.color = "#ff0066"
        return el
    }

    /// Well-formedness, checked by an actual XML parser rather than by
    /// eyeballing angle brackets.
    private func isWellFormed(_ svg: String) -> Bool {
        guard let data = svg.data(using: .utf8) else { return false }
        let parser = XMLParser(data: data)
        return parser.parse()
    }

    private func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    // MARK: document

    @MainActor
    func testTheDocumentIsWellFormedXML() {
        var shape = Element.shape("rect", w: 200, h: 120)
        shape.x = 40; shape.y = 60
        let svg = markup(design(elements: [shape, text()]))
        XCTAssertTrue(isWellFormed(svg), "the exported SVG is not well-formed XML")
    }

    /// A viewBox that does not match the page means everything downstream is
    /// scaled wrong, silently.
    @MainActor
    func testTheViewBoxIsThePageSize() {
        let svg = markup(design(width: 1080, height: 1350))
        XCTAssertTrue(svg.contains("viewBox=\"0 0 1080 1350\""), svg.prefix(300).description)
        XCTAssertTrue(svg.contains("width=\"1080\""))
        XCTAssertTrue(svg.contains("height=\"1350\""))
    }

    @MainActor
    func testEveryElementGetsItsOwnGroup() {
        let elements = [Element.shape("rect", w: 10, h: 10),
                        Element.shape("ellipse", w: 10, h: 10),
                        text()]
        let svg = markup(design(elements: elements))
        // One <g …> per element at the top level, plus the inner group each
        // shape and text block carries — so at least one per element.
        XCTAssertGreaterThanOrEqual(count("<g", in: svg), elements.count)
    }

    @MainActor
    func testAColourBackgroundIsARect() {
        let svg = markup(design(background: .color("#123456")))
        XCTAssertTrue(svg.contains("fill=\"#123456\""))
    }

    // MARK: shapes

    @MainActor
    func testShapesAreRealPaths() {
        var shape = Element.shape("rect", w: 200, h: 100)
        shape.fill = .solid("#00ff88")
        shape.x = 10; shape.y = 20
        let svg = markup(design(elements: [shape]))
        XCTAssertTrue(svg.contains("<path d=\""), "a shape did not export as a path")
        XCTAssertTrue(svg.contains("fill=\"#00ff88\""))
        XCTAssertTrue(svg.contains("translate(10 20)"))
        XCTAssertTrue(isWellFormed(svg))
    }

    @MainActor
    func testAGradientFillBecomesALinearGradientInDefs() {
        var shape = Element.shape("rect", w: 200, h: 100)
        shape.fill = Paint(kind: "gradient", color: nil, angle: 90,
                           stops: [GradientStop(offset: 0, color: "#ff0000"),
                                   GradientStop(offset: 1, color: "#0000ff")])
        let svg = markup(design(elements: [shape]))
        XCTAssertTrue(svg.contains("<defs>"))
        XCTAssertTrue(svg.contains("<linearGradient"))
        XCTAssertTrue(svg.contains("stop-color=\"#ff0000\""))
        XCTAssertTrue(svg.contains("stop-color=\"#0000ff\""))
        XCTAssertTrue(svg.contains("fill=\"url(#grad0)\""))
        XCTAssertTrue(isWellFormed(svg))
    }

    /// The path is written at the element's own size, so a plain stroke
    /// width is the width on the page, however the file is shown — no
    /// scaled 100-unit box, and nothing that relies on vector-effect.
    @MainActor
    func testStrokesDoNotScaleWithTheShape() {
        var shape = Element.shape("rect", w: 400, h: 50)
        shape.stroke = "#000000"
        shape.strokeWidth = 6
        let svg = markup(design(elements: [shape]))
        XCTAssertTrue(svg.contains("stroke-width=\"6\""))
        XCTAssertFalse(svg.contains("vector-effect"))
        XCTAssertFalse(svg.contains("scale("))
        XCTAssertTrue(svg.contains("<g transform=\"translate(0 0)\"><path d=\"M0 0L400 0L400 50L0 50Z\""), svg)
    }

    /// A drawn path keeps its width whichever way its box was stretched, and
    /// only numbers from it reach the file.
    @MainActor
    func testADrawnPathIsWrittenAtItsSize() {
        var pen = Element.shape("rect", w: 600, h: 200)
        pen.pathData = "M0 0Q10 10 20 20\""
        pen.fill = Paint.clear
        pen.stroke = "#000000"
        pen.strokeWidth = 6
        let svg = markup(design(elements: [pen]))
        XCTAssertTrue(svg.contains("<path d=\"M0 0Q60 20 120 40\" fill=\"none\" stroke=\"#000000\" stroke-width=\"6\""), svg)
    }

    /// Clamped once to half the shorter side and used on both axes, as the
    /// canvas draws it: a pill made shorter keeps round ends.
    @MainActor
    func testACornerRadiusIsRoundAtTheElementsSize() {
        var pill = Element.shape("rect", w: 340, h: 60)
        pill.radius = 44
        let svg = markup(design(elements: [pill]))
        XCTAssertTrue(svg.contains("d=\"M30,0H310A30,30 0 0 1 340,30V30A30,30 0 0 1 310,60H30A30,30 0 0 1 0,30V30A30,30 0 0 1 30,0Z\""), svg)
    }

    // MARK: gradients

    /// In the box's own pixels from side to side, as a LinearGradient's unit
    /// points land on it — not stretched from a unit square, which turns the
    /// bands the other way on a tall page. The numbers the Android twin
    /// writes.
    func testALinearGradientRunsAcrossTheBoxInItsOwnPixels() {
        let stops = [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 1, color: "#0000FF")]
        XCTAssertEqual(
            SVGExporter.gradientDef(id: "g", paint: Paint(kind: "gradient", color: nil, angle: 90, stops: stops),
                                    left: 0, top: 0, width: 100, height: 100),
            "<linearGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" x1=\"0\" y1=\"50\" x2=\"100\" y2=\"50\">" +
            "<stop offset=\"0\" stop-color=\"#ff0000\"/><stop offset=\"1\" stop-color=\"#0000FF\"/></linearGradient>")
        let diagonal = SVGExporter.gradientDef(id: "g", paint: Paint(kind: "gradient", color: nil, angle: 135, stops: stops),
                                               left: 0, top: 0, width: 200, height: 100)
        XCTAssertTrue(diagonal.contains("x1=\"29.28932\" y1=\"14.64466\" x2=\"170.71068\" y2=\"85.35534\""), diagonal)
        let partOfTheBox = SVGExporter.gradientDef(id: "g", paint: Paint(kind: "gradient", color: nil, angle: 90, stops: stops),
                                                   left: 0, top: 20, width: 200, height: 80)
        XCTAssertTrue(partOfTheBox.contains("x1=\"0\" y1=\"60\" x2=\"200\" y2=\"60\""), partOfTheBox)
    }

    func testARadialGradientReachesTheSidesOrForLettersTheLongerOne() {
        var radial = Paint(kind: "gradient", color: nil, angle: 0,
                           stops: [GradientStop(offset: 0, color: "#ffffff"), GradientStop(offset: 1, color: "#000000")])
        radial.gradientKind = "radial"
        let ellipse = SVGExporter.gradientDef(id: "g", paint: radial, left: 0, top: 0, width: 100, height: 50)
        XCTAssertTrue(ellipse.hasPrefix("<radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"0\" cy=\"0\" r=\"1\" " +
                                        "gradientTransform=\"translate(50 25) scale(50 25)\">"), ellipse)
        let circle = SVGExporter.gradientDef(id: "g", paint: radial, left: 0, top: 20, width: 100, height: 50, circular: true)
        XCTAssertTrue(circle.hasPrefix("<radialGradient id=\"g\" gradientUnits=\"userSpaceOnUse\" cx=\"50\" cy=\"45\" r=\"50\">"), circle)
    }

    /// Gradient letters are painted over the text's part of the box, as the
    /// canvas paints them, never over the letters' own ink.
    @MainActor
    func testGradientLettersSpanTheTextBoxNotTheirInk() {
        var sale = text("SALE", w: 600, h: 100)
        sale.textFill = Paint(kind: "gradient", color: nil, angle: 90,
                              stops: [GradientStop(offset: 0, color: "#ff00aa"), GradientStop(offset: 1, color: "#0000ff")])
        let svg = markup(design(elements: [sale]))
        XCTAssertTrue(svg.contains("<linearGradient id=\"textgrad0\" gradientUnits=\"userSpaceOnUse\" x1=\"0\""), svg)
        XCTAssertTrue(svg.contains("x2=\"600\""), svg)
        XCTAssertTrue(isWellFormed(svg))
    }

    // MARK: shadows

    /// A flat line's box has no height, and a filter region that is a share
    /// of it has no room: the line would not be drawn at all.
    @MainActor
    func testAShadowsRegionIsTheBoxPaddedByItsReach() {
        var line = Element.line(w: 300)
        line.x = 10; line.y = 20; line.h = 0
        line.shadow = Shadow()
        let svg = markup(design(elements: [line]))
        XCTAssertTrue(svg.contains("<filter id=\"shadow0\" filterUnits=\"userSpaceOnUse\" x=\"-54\" y=\"-44\" width=\"428\" height=\"128\">"), svg)
        var glow = text("Hi", w: 100, h: 30)
        glow.shadow = Shadow(color: "#ffffff", opacity: 0.9, blur: 60, offsetX: -10, offsetY: 4)
        XCTAssertTrue(SVGExporter.shadowDef(id: "s", shadow: glow.shadow!, element: glow)
            .hasPrefix("<filter id=\"s\" filterUnits=\"userSpaceOnUse\" x=\"-100\" y=\"-100\" width=\"300\" height=\"230\">"))
    }

    // MARK: text

    /// The whole reason text is outlined: the faces this app uses ship with
    /// iOS and are not on the machine opening the file.
    @MainActor
    func testTextIsOutlinedRatherThanLeftAsText() {
        let svg = markup(design(elements: [text("Outline me")]))
        XCTAssertFalse(svg.contains("<text"), "text was exported as <text> and will substitute")
        XCTAssertTrue(svg.contains("fill=\"#ff0066\""))
        XCTAssertTrue(svg.contains("<path d=\"M"), "no glyph outlines in the export")
        XCTAssertTrue(isWellFormed(svg))
    }

    @MainActor
    func testEmptyTextExportsNothingRatherThanABrokenTag() {
        let svg = markup(design(elements: [text("")]))
        XCTAssertTrue(isWellFormed(svg))
        XCTAssertFalse(svg.contains("d=\"\""))
    }

    // MARK: lines

    /// Drawn as LineElementView draws them: the arrowhead's tip on the end
    /// and the stroke stopping short of it, dots a thickness in, dashes
    /// round-capped. The numbers the Android twin writes.
    @MainActor
    func testLineEndsAreWhereTheCanvasDrawsThem() {
        var line = Element.line(w: 300)
        line.x = 10; line.y = 20
        line.dash = "dashed"
        line.startCap = "dot"
        line.endCap = "arrow"
        let svg = markup(design(elements: [line]))
        XCTAssertTrue(svg.contains(
            "<line x1=\"10\" y1=\"24\" x2=\"299.2\" y2=\"24\" stroke=\"#1f2430\" stroke-width=\"4\" stroke-linecap=\"round\" stroke-dasharray=\"12 8\"/>" +
            "<circle cx=\"14\" cy=\"24\" r=\"5.6\" fill=\"#1f2430\"/>" +
            "<path d=\"M310 24L298 16.8L298 31.2Z\" fill=\"#1f2430\"/>"), svg)

        var thin = Element.line(w: 300)
        thin.x = 10; thin.y = 20
        thin.thickness = 2
        thin.dash = "dotted"
        thin.startCap = "arrow"
        thin.endCap = "dot"
        let thinSVG = markup(design(elements: [thin]))
        XCTAssertTrue(thinSVG.contains(
            "<line x1=\"19\" y1=\"24\" x2=\"310\" y2=\"24\" stroke=\"#1f2430\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-dasharray=\"0 4.4\"/>" +
            "<path d=\"M10 24L20 18L20 30Z\" fill=\"#1f2430\"/>" +
            "<circle cx=\"308\" cy=\"24\" r=\"5\" fill=\"#1f2430\"/>"), thinSVG)
    }

    @MainActor
    func testLinesExportAsStrokedLines() {
        var line = Element.line(w: 300)
        line.x = 20; line.y = 40
        line.color = "#334455"
        line.thickness = 8
        line.dash = "dashed"
        line.endCap = "arrow"
        let svg = markup(design(elements: [line]))
        XCTAssertTrue(svg.contains("<line"))
        XCTAssertTrue(svg.contains("stroke=\"#334455\""))
        XCTAssertTrue(svg.contains("stroke-width=\"8\""))
        XCTAssertTrue(svg.contains("stroke-dasharray="))
        XCTAssertTrue(svg.contains("<path d=\"M"), "the arrow head is missing")
        XCTAssertTrue(isWellFormed(svg))
    }

    // MARK: transforms

    @MainActor
    func testRotationFlipAndOpacityLandOnTheGroup() {
        var shape = Element.shape("rect", w: 100, h: 100)
        shape.x = 50; shape.y = 50
        shape.rotation = 30
        shape.flipH = true
        shape.opacity = 0.4
        let svg = markup(design(elements: [shape]))
        XCTAssertTrue(svg.contains("rotate(30 100 100)"), "rotation is not about the element's centre")
        XCTAssertTrue(svg.contains("scale(-1 1)"))
        XCTAssertTrue(svg.contains("opacity=\"0.4\""))
    }

    @MainActor
    func testAnUntransformedElementCarriesNoTransformAttribute() {
        let svg = markup(design(elements: [Element.shape("rect", w: 100, h: 100)]))
        XCTAssertFalse(svg.contains("rotate("))
        XCTAssertFalse(svg.contains("opacity=\""))
    }

    // MARK: escaping and numbers

    func testMarkupUnsafeCharactersAreEscaped() {
        XCTAssertEqual(SVGExporter.escape("a & b < c > d \" e ' f"),
                       "a &amp; b &lt; c &gt; d &quot; e &apos; f")
    }

    /// One character XML cannot hold and no reader opens the file: a pasted
    /// soft line break, a form feed, a stray control, the two non-characters.
    func testCharactersXMLCannotHoldAreLeftOut() {
        XCTAssertEqual(SVGExporter.escape("a\u{0B}b\tc\u{0C}\nd\u{01}\re\u{FFFE}\u{FFFF}\u{00}"), "ab\tc\nd\re")
        XCTAssertEqual(SVGExporter.escape("\u{1F600} é \u{7F} \u{FFFD}"), "\u{1F600} é \u{7F} \u{FFFD}")
    }

    @MainActor
    func testAnAltTextWithAControlCharacterStillParses() {
        var shape = Element.shape("rect", w: 100, h: 100)
        shape.altText = "Menu\u{0B}prices"
        let svg = markup(design(elements: [shape]))
        XCTAssertTrue(svg.contains("<title>Menuprices</title>"), svg)
        XCTAssertTrue(isWellFormed(svg))
    }

    /// Whole numbers come out whole. "100.0" is legal SVG but it doubles the
    /// size of a path with a few thousand coordinates in it.
    func testWholeNumbersAreWrittenWithoutADecimalPoint() {
        XCTAssertEqual(SVGExporter.num(100), "100")
        XCTAssertEqual(SVGExporter.num(-0), "0")
        XCTAssertEqual(SVGExporter.num(12.5), "12.5")
        XCTAssertEqual(SVGExporter.num(Double.infinity), "0")
        XCTAssertEqual(SVGExporter.num(Double.nan), "0")
    }

    // MARK: images

    /// Images bake through their own view, so whatever the canvas showed —
    /// crop, filter, corner radius — is what lands in the file.
    @MainActor
    func testImagesEmbedAsData() throws {
        let photo = try XCTUnwrap(PhotoLibrary.photos.first)
        var el = Element.image("asset:\(photo.id)", w: 200, h: 150)
        el.x = 30; el.y = 40
        let svg = markup(design(elements: [el]))
        XCTAssertTrue(svg.contains("<image"))
        XCTAssertTrue(svg.contains("data:image/png;base64,"))
        XCTAssertTrue(svg.contains("x=\"30\""))
        XCTAssertTrue(isWellFormed(svg))
    }
}
