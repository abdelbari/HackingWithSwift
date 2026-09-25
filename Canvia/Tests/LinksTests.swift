// Links on elements: what is typed read as a link, the one under a tap, and
// the link carried into the PDF and SVG. The Android twin's LinksTest checks
// the same readings, so the two phones agree on what a link is.

import XCTest
import PDFKit
@testable import Canvia

final class LinksTests: XCTestCase {

    func testWhatIsTypedBecomesALinkAReaderCanFollow() {
        XCTAssertEqual(Links.normalized("canvia.app"), "https://canvia.app")
        XCTAssertEqual(Links.normalized("  canvia.app/pricing?x=1 "), "https://canvia.app/pricing?x=1")
        XCTAssertEqual(Links.normalized("http://example.com"), "http://example.com")
        XCTAssertEqual(Links.normalized("hello@canvia.app"), "mailto:hello@canvia.app")
        XCTAssertEqual(Links.normalized("+44 1234 567890"), "tel:+441234567890")
        XCTAssertEqual(Links.normalized("mailto:x@y.z"), "mailto:x@y.z")
        XCTAssertNil(Links.normalized("just words"))
        XCTAssertNil(Links.normalized("https://"))
        XCTAssertNil(Links.normalized(""))
        XCTAssertEqual(Links.shown("https://canvia.app/pricing/"), "canvia.app/pricing")
    }

    func testATapFindsTheTopmostLinkedElementTurnedOrNot() {
        var under = Element.shape("rect", w: 200, h: 200)
        under.link = "https://under"
        var over = Element.shape("rect", w: 100, h: 20)
        over.x = 50; over.y = 90; over.rotation = 90
        over.link = "https://over"
        var plain = Element.shape("rect")
        plain.x = 500; plain.y = 500
        var design = Design()
        design.pages = [Page(elements: [under, over, plain])]
        let page = design.pages[0]
        XCTAssertEqual(Links.at(design: design, page: page, point: CGPoint(x: 100, y: 60)), "https://over")
        XCTAssertEqual(Links.at(design: design, page: page, point: CGPoint(x: 10, y: 10)), "https://under")
        XCTAssertNil(Links.at(design: design, page: page, point: CGPoint(x: 550, y: 550)))
        XCTAssertEqual(Links.areas(design: design, page: page).count, 2)
    }

    func testALinkSurvivesTheFileRoundTrip() throws {
        var el = Element.shape("rect")
        el.link = "https://canvia.app"
        let data = try JSONEncoder().encode(el)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data).link, "https://canvia.app")
    }

    /// The link is clickable over the element's area in the PDF, measured in
    /// points from the page's top-left as PDFKit reports it flipped.
    @MainActor
    func testThePDFCarriesTheLinkOverTheElement() throws {
        var design = Design(title: "Links", width: 800, height: 600)
        var el = Element.shape("rect", w: 200, h: 100)
        el.x = 80; el.y = 40
        el.link = "https://canvia.app"
        design.pages = [Page(elements: [el])]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("links-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try DesignExporter.exportPDF(design: design, to: url)
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let link = try XCTUnwrap(page.annotations.first { $0.url != nil })
        XCTAssertEqual(link.url?.absoluteString, "https://canvia.app")
        // 800x600 px is 600x450 pt; the element is 60,30 150x75 pt, from the
        // bottom 450 - 30 - 75 = 345.
        XCTAssertEqual(link.bounds.minX, 60, accuracy: 1)
        XCTAssertEqual(link.bounds.minY, 345, accuracy: 1)
        XCTAssertEqual(link.bounds.width, 150, accuracy: 1)
        XCTAssertEqual(link.bounds.height, 75, accuracy: 1)
    }

    @MainActor
    func testTheSVGWrapsALinkedElementInAnAnchor() {
        var design = Design(title: "Links", width: 400, height: 300)
        var el = Element.shape("rect", w: 100, h: 100)
        el.link = "https://canvia.app/?a=1&b=2"
        design.pages = [Page(elements: [el])]
        let svg = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertTrue(svg.contains("<a href=\"https://canvia.app/?a=1&amp;b=2\""), svg)
        let parser = XMLParser(data: Data(svg.utf8))
        XCTAssertTrue(parser.parse(), "the exported SVG is not well-formed XML")
    }
}
