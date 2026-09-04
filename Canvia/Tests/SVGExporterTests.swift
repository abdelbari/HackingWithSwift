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

    /// The group scales a 100-unit box onto the element, so a plain stroke
    /// width would be stretched by that factor — and by a different factor on
    /// each axis for a non-square element.
    @MainActor
    func testStrokesDoNotScaleWithTheShape() {
        var shape = Element.shape("rect", w: 400, h: 50)
        shape.stroke = "#000000"
        shape.strokeWidth = 6
        let svg = markup(design(elements: [shape]))
        XCTAssertTrue(svg.contains("stroke-width=\"6\""))
        XCTAssertTrue(svg.contains("vector-effect=\"non-scaling-stroke\""))
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
