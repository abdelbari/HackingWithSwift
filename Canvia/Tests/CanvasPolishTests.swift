// The canvas's small answers: what a snap guide lines things up with, and
// the names it uses to say so — the same words as the Android twin's.

import XCTest
@testable import Canvia

final class CanvasPolishTests: XCTestCase {

    // MARK: names

    func testColoursAreNamedAsAPersonWould() {
        XCTAssertEqual(ElementNames.colourName("#ff0000"), "red")
        XCTAssertEqual(ElementNames.colourName("#000000"), "black")
        XCTAssertEqual(ElementNames.colourName("#ffffff"), "white")
        XCTAssertEqual(ElementNames.colourName("#808080"), "grey")
        XCTAssertEqual(ElementNames.colourName("#14b8a6"), "teal")
        XCTAssertEqual(ElementNames.colourName("#8b4513"), "brown", "brown is dark orange")
        XCTAssertEqual(ElementNames.colourName("#ffc0cb"), "pink", "light red is pink")
        XCTAssertEqual(ElementNames.colourName("#00008b"), "dark blue")
        XCTAssertEqual(ElementNames.colourName("#8b5cf6"), "purple")
        XCTAssertEqual(ElementNames.colourName("#f00"), "red", "three digits read as six")
        XCTAssertEqual(ElementNames.colourName("#ff000080"), "red", "alpha is not a colour")
        XCTAssertEqual(ElementNames.colourName("nonsense"), "colour")
    }

    func testElementsAreNamedByWhatTheyAre() {
        var heading = Element.text("SUMMER SALE")
        heading.fontSize = 72
        XCTAssertEqual(ElementNames.name(of: heading), "Heading: SUMMER SALE")
        var body = Element.text("Doors at **eight**")
        body.fontSize = 18
        XCTAssertEqual(ElementNames.name(of: body), "Text: Doors at eight", "style marks are not words")
        XCTAssertEqual(ElementNames.name(of: Element.text("")), "Text")

        var circle = Element.shape("circle")
        circle.fill = .solid("#ff0000")
        XCTAssertEqual(ElementNames.name(of: circle), "Red circle")
        var clear = Element.shape("circle")
        clear.fill = .solid("#ff000022")
        XCTAssertEqual(ElementNames.name(of: clear), "Circle", "a see-through fill is no colour anyone sees")

        XCTAssertEqual(ElementNames.name(of: Element.image("media:x")), "Photo")
        var framed = Element.image("media:x")
        framed.maskShapeId = "circle"
        XCTAssertEqual(ElementNames.name(of: framed), "Photo in a circle frame")
        var empty = Element.image("media:x")
        empty.src = nil
        XCTAssertEqual(ElementNames.name(of: empty), "Empty photo frame")
        XCTAssertEqual(ElementNames.name(of: Element.image(CodeGenerator.source(for: "hi"))), "QR code")
    }

    func testAGuideSaysWhatItLinesUpWith() {
        var heading = Element.text("SUMMER SALE")
        heading.fontSize = 72
        XCTAssertEqual(ElementNames.guideLabel(.pageCentre, vertical: true, elements: []), "Centre of the page")
        XCTAssertEqual(ElementNames.guideLabel(.pageCentre, vertical: false, elements: []), "Middle of the page")
        XCTAssertEqual(ElementNames.guideLabel(.pageEdge, vertical: true, elements: []), "Edge of the page")
        XCTAssertEqual(ElementNames.guideLabel(.guide, vertical: false, elements: []), "Your guide")
        XCTAssertEqual(ElementNames.guideLabel(.element(heading.id), vertical: true, elements: [heading]),
                       "Lined up with heading: SUMMER SALE")
        XCTAssertEqual(ElementNames.guideLabel(.element("gone"), vertical: true, elements: [heading]), "Lined up")

        var long = Element.text("A much longer headline than fits")
        long.fontSize = 72
        XCTAssertEqual(ElementNames.shortName(of: long), "Heading: A much lon…")
    }

    // MARK: snap lines

    /// The old positions are unchanged, and each line knows where it came
    /// from. Where two share a place, the guide placed on purpose names it,
    /// then an element, then the page — as on the Android twin.
    func testSnapLinesKnowWhereTheyComeFrom() {
        var design = Design(title: "snap", width: 400, height: 400)
        design.guides = [Guide(vertical: true, position: 200)]
        var box = Element.shape("rect", w: 100, h: 100)
        box.x = 150; box.y = 20
        design.pages[0].elements = [box]
        let page = design.pages[0]
        let tagged = Geometry.taggedSnapLines(design: design, page: page, excluding: [])
        let plain = Geometry.snapLines(design: design, page: page, excluding: [])
        XCTAssertEqual(plain.x, tagged.x.map(\.position))
        XCTAssertEqual(plain.y, tagged.y.map(\.position))

        XCTAssertEqual(Geometry.snapSource(at: 200, in: tagged.x), .guide, "the guide, the centre and the box's middle share 200")
        XCTAssertEqual(Geometry.snapSource(at: 150, in: tagged.x), .element(box.id))
        XCTAssertEqual(Geometry.snapSource(at: 0, in: tagged.x), .pageEdge)
        XCTAssertEqual(Geometry.snapSource(at: 200, in: tagged.y), .pageCentre)
        XCTAssertEqual(Geometry.snapSource(at: 70, in: tagged.y), .element(box.id))
        XCTAssertNil(Geometry.snapSource(at: nil, in: tagged.x))
        XCTAssertNil(Geometry.snapSource(at: 13, in: tagged.x))

        // Moved over the page's centre, the snap lands there and says so.
        let moving = CGRect(x: 167, y: 300, width: 60, height: 50)
        let snap = Geometry.snap(box: moving, xLines: tagged.x.map(\.position), yLines: [], threshold: 6)
        XCTAssertEqual(snap.guideX, 200)
        XCTAssertEqual(Geometry.snapSource(at: snap.guideX, in: tagged.x), .guide)
    }
}
