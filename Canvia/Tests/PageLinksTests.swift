// Round 32's links to a page of the design, with the rows the Android twin's
// LinksTest holds too: "page:<page id>" read and kept only while that page
// is there, through the file both ways, said as "Link to page 3, Pricing",
// and in every export — a GoTo in the PDF, a slide jump in PowerPoint, an
// anchor on the web page — but never when the page has gone.

import XCTest
import PDFKit
@testable import Canvia

final class PageLinksTests: XCTestCase {

    /// Three pages, the third titled Pricing, a box on the first linked to
    /// the third.
    private func deck(link: String = "page:p3") -> Design {
        var box = Element.shape("rect", w: 200, h: 100)
        box.id = "button"
        box.x = 80; box.y = 40
        box.link = link
        var d = Design(title: "Deck", width: 800, height: 600)
        var pricing = Page(id: "p3", elements: [])
        pricing.title = "Pricing"
        d.pages = [Page(id: "p1", elements: [box]), Page(id: "p2", elements: []), pricing]
        return d
    }

    func testAPageLinkIsReadOnlyWhileThePageIsThere() {
        let d = deck()
        XCTAssertEqual(Links.normalized("page:p3", in: d), "page:p3")
        XCTAssertEqual(Links.normalized(" page:p2 ", in: d), "page:p2")
        // "page:" in small letters only, on both phones.
        XCTAssertNil(Links.normalized("PAGE:p2", in: d))
        XCTAssertNil(Links.pageId("Page:p3"))
        XCTAssertNil(Links.normalized("page:gone", in: d))
        XCTAssertNil(Links.normalized("page:", in: d))
        XCTAssertNil(Links.normalized("page:a b", in: d))
        // A file being read, with no design to ask, keeps it as it is.
        XCTAssertEqual(Links.normalized("page:anything"), "page:anything")
        XCTAssertEqual(Links.pageLink("p2"), "page:p2")
        XCTAssertEqual(Links.pageId("page:p2"), "p2")
        XCTAssertNil(Links.pageId("https://canvia.app"))
        XCTAssertEqual(Links.pageIndex("page:p3", in: d), 2)
        XCTAssertTrue(Links.isFollowable("page:p3", in: d))
        XCTAssertTrue(Links.isFollowable("https://canvia.app", in: d))
        XCTAssertFalse(Links.isFollowable("page:gone", in: d))
        XCTAssertTrue(Links.isDangling("page:gone", in: d))
        XCTAssertFalse(Links.isDangling("https://canvia.app", in: d))
        // Never one of the four kinds an export follows out of the file.
        XCTAssertNil(Links.followable("page:p3"))
    }

    func testAPageLinkIsSaidByItsPage() {
        let d = deck()
        XCTAssertEqual(Links.spoken("page:p3", in: d), "Link to page 3, Pricing")
        XCTAssertEqual(Links.spoken("page:p2", in: d), "Link to page 2")
        XCTAssertEqual(Links.spoken("page:gone", in: d), "Page removed")
        XCTAssertNil(Links.spoken("https://canvia.app", in: d))
        XCTAssertEqual(Links.label("page:p3", in: d), "Page 3 · Pricing")
        XCTAssertEqual(Links.label("page:gone", in: d), "Page removed")
        XCTAssertEqual(Links.label("https://canvia.app/", in: d), "canvia.app")
    }

    func testAPageLinkSurvivesTheFileRoundTrip() throws {
        let d = deck()
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(Design.self, from: data)
        XCTAssertEqual(back.pages[0].elements[0].link, "page:p3")
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"link\":\"page:p3\""), json)
        // Kept by its page's id, so moving the pages keeps the target.
        var moved = back
        moved.pages.swapAt(1, 2)
        XCTAssertEqual(Links.pageIndex("page:p3", in: moved), 1)
    }

    func testOnlyAPageInTheFileIsAnExportedTarget() {
        let d = deck()
        let page = d.pages[0]
        XCTAssertEqual(Links.exportAreas(design: d, page: page, pages: ["p1", "p2", "p3"]).map(\.target), [.page("p3")])
        XCTAssertTrue(Links.exportAreas(design: d, page: page, pages: ["p1", "p2"]).isEmpty, "the page is not in the file")
        let gone = deck(link: "page:gone")
        XCTAssertTrue(Links.exportAreas(design: gone, page: gone.pages[0], pages: ["p1", "p2", "p3"]).isEmpty, "dangling")
        XCTAssertNil(Links.at(design: gone, page: gone.pages[0], point: CGPoint(x: 100, y: 60)))
        XCTAssertEqual(Links.at(design: d, page: page, point: CGPoint(x: 100, y: 60)), "page:p3")
    }

    /// The PDF carries an internal link over the box, to the third page,
    /// not an address; a dangling one carries nothing.
    @MainActor
    func testThePDFGoesToThePage() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("page-links-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await DesignExporter.exportPDF(design: deck(), to: url)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 3)
        let first = try XCTUnwrap(document.page(at: 0))
        let link = try XCTUnwrap(first.annotations.first { $0.url == nil && $0.type == "Link" })
        XCTAssertNil(link.url)
        let target = link.destination?.page ?? (link.action as? PDFActionGoTo)?.destination.page
        XCTAssertEqual(target.map { document.index(for: $0) }, 2)
        XCTAssertEqual(link.bounds.minX, 60, accuracy: 1)

        let dangling = FileManager.default.temporaryDirectory.appendingPathComponent("dangling-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: dangling) }
        try await DesignExporter.exportPDF(design: deck(link: "page:gone"), to: dangling)
        let page = try XCTUnwrap(PDFDocument(url: dangling)?.page(at: 0))
        XCTAssertTrue(page.annotations.filter { $0.type == "Link" }.isEmpty)
    }

    @MainActor
    func testPowerPointJumpsToTheSlide() {
        let d = deck()
        let slides = PptxExporter.deck(design: d, indices: [0, 1, 2])
        XCTAssertTrue(slides[0].xml.contains("action=\"ppaction://hlinksldjump\""), slides[0].xml)
        XCTAssertTrue(slides[0].rels.contains("relationships/slide\" Target=\"slide3.xml\""), slides[0].rels)
        // A deck without the page has no jump to it.
        let fewer = PptxExporter.deck(design: d, indices: [0, 1])
        XCTAssertFalse(fewer[0].xml.contains("hlinkClick"))
    }

    @MainActor
    func testTheWebPageAnchorsToTheSection() {
        let d = deck()
        let html = HTMLExporter.html(d, pages: [0, 1, 2], settings: HTMLExporter.Settings(nav: false),
                                     svg: nil, poster: { _ in nil })
        XCTAssertTrue(html.contains("<a href=\"#page-3\" xlink:href=\"#page-3\">"), html)
        // An SVG of its own has nowhere to go.
        XCTAssertFalse(SVGExporter.svg(design: d, page: d.pages[0]).contains("<a "))
    }
}
