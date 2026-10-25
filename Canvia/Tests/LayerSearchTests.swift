// Layers' search, kind chips and All pages (LayerSearch): the shared rows
// of layer-search.json, a section a page with hits, and the count VoiceOver
// says. The Android twin's LayerSearchTest, row for row.

import XCTest
@testable import Canvia

final class LayerSearchTests: XCTestCase {

    func testTheSharedLayerSearchRows() throws {
        let root = try SharedFixture.object("layer-search")
        let elements = try JSONDecoder().decode([Element].self,
                                                from: SharedFixture.encoded(try XCTUnwrap(root["elements"])))
        for row in try XCTUnwrap(root["rows"] as? [[String: Any]]) {
            let kinds = Set(((row["kinds"] as? [String]) ?? []).compactMap(LayerSearch.KindChip.init(rawValue:)))
            let query = row["query"] as? String ?? ""
            let ids = elements.filter { LayerSearch.matches($0, query: query, kinds: kinds) }.map(\.id)
            XCTAssertEqual(ids, row["ids"] as? [String], "\(row)")
        }
    }

    func testAllPagesListsEveryPageWithHitsAndSaysHowMany() {
        var d = Design(title: "Deck", width: 1080, height: 1080)
        d.pages = [Page(elements: [Element.text("Intro")]), Page(elements: [Element.shape("rect")]),
                   Page(elements: [Element.text("Intro again"), Element.text("Outro")])]
        var query = LayerSearch.Query(text: "intro")
        XCTAssertTrue(query.narrows)
        let here = LayerSearch.hits(d.pages, current: 1, query: query, only: nil)
        XCTAssertEqual(here.map(\.page), [1], "This page keeps its section, empty")
        XCTAssertEqual(here.first?.ids, [])
        query.allPages = true
        let all = LayerSearch.hits(d.pages, current: 1, query: query, only: nil)
        XCTAssertEqual(all.map(\.page), [0, 2])
        XCTAssertEqual(LayerSearch.spokenCount(all), "2 layers found on 2 pages")
        XCTAssertEqual(LayerSearch.spokenCount([LayerSearch.PageHits(page: 0, ids: ["a"])]), "1 layer found on 1 page")
        XCTAssertEqual(LayerSearch.spokenCount(here), "No layers found")
        var titled = Page()
        titled.title = "Intro"
        XCTAssertEqual(LayerSearch.heading(titled, number: 3), "Page 3 - Intro")
        XCTAssertEqual(LayerSearch.heading(Page(), number: 1), "Page 1")
        XCTAssertEqual(LayerSearch.KindChip.allCases.map(\.rawValue),
                       ["Text", "Photos and videos", "Shapes and lines", "Graphics", "Groups", "Hidden", "Locked"])
    }
}
