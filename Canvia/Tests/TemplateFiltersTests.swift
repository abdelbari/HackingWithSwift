// The template Filters sheet: the facets the generator writes into every
// template (the Android twin's TemplateSpecs carry the same), and the
// filter's rules, as the twin's TemplateFiltersTest has them.

import XCTest
@testable import Canvia

final class TemplateFiltersTests: XCTestCase {

    private func facets(_ id: String) throws -> TemplateFacets {
        try XCTUnwrap(ContentLibrary.templates.first { $0.id == id }?.facets, id)
    }

    // MARK: the generated facets

    func testEveryTemplateHasFacetsOfTheTwelveColours() {
        XCTAssertFalse(ContentLibrary.templates.isEmpty)
        for t in ContentLibrary.templates {
            guard let f = t.facets else { return XCTFail("\(t.id) has no facets") }
            XCTAssertLessThanOrEqual(f.colors.count, 3, t.id)
            XCTAssertEqual(Set(f.colors).count, f.colors.count, t.id)
            for c in f.colors { XCTAssertTrue(TemplateFilter.allColors.contains(c), "\(t.id): \(c)") }
            XCTAssertEqual(f.pages, t.pageCount, t.id)
        }
    }

    /// The same values the twin's generated specs carry, most colour first.
    func testSharedFacetsReadAsGenerated() throws {
        XCTAssertEqual(try facets("mega-sale-post"),
                       TemplateFacets(colors: ["purple", "pink", "yellow"], animated: false, photo: false, pages: 1))
        XCTAssertEqual(try facets("neon-nights-story"), TemplateFacets(colors: ["black"], photo: true, pages: 1))
        XCTAssertEqual(try facets("deck-seed-round-pitch"), TemplateFacets(colors: ["white", "black", "blue"], pages: 12))
        XCTAssertEqual(try facets("website-cafe-landing"), TemplateFacets(colors: ["white", "brown", "orange"], pages: 3))
        XCTAssertEqual(try facets("quarterly-review-title"), TemplateFacets(colors: ["white"], pages: 1))
    }

    func testFacetsReadLeniently() throws {
        let json = #"{"colors": ["blue", 3], "animated": "yes", "pages": 4}"#
        let read = try JSONDecoder().decode(TemplateFacets.self, from: Data(json.utf8))
        XCTAssertEqual(read, TemplateFacets(colors: [], animated: false, photo: false, pages: 4))
        let none = try JSONDecoder().decode(TemplateFacets.self, from: Data("{}".utf8))
        XCTAssertEqual(none, TemplateFacets())
    }

    // MARK: the filter

    func testAnEmptyFilterLetsEverythingThrough() {
        XCTAssertTrue(TemplateFilter().isEmpty)
        XCTAssertEqual(ContentLibrary.filteredTemplates(in: nil, matching: "").count, ContentLibrary.templates.count)
    }

    /// Any colour picked; animated and photo as asked; Set is more than
    /// one page, Single page one.
    func testAdmitsByAnyColourAndEachFlag() {
        let blueDeck = TemplateFacets(colors: ["blue", "white"], animated: false, photo: true, pages: 5)
        XCTAssertTrue(TemplateFilter(colors: ["red", "blue"]).admits(blueDeck))
        XCTAssertFalse(TemplateFilter(colors: ["red"]).admits(blueDeck))
        XCTAssertTrue(TemplateFilter(photo: true).admits(blueDeck))
        XCTAssertFalse(TemplateFilter(photo: false).admits(blueDeck))
        XCTAssertFalse(TemplateFilter(animated: true).admits(blueDeck))
        XCTAssertTrue(TemplateFilter(animated: false).admits(blueDeck))
        XCTAssertTrue(TemplateFilter(multiPage: true).admits(blueDeck))
        XCTAssertFalse(TemplateFilter(multiPage: false).admits(blueDeck))
        XCTAssertTrue(TemplateFilter(multiPage: false).admits(TemplateFacets(pages: 1)))
        XCTAssertFalse(TemplateFilter(colors: ["blue"], multiPage: false).admits(blueDeck))
    }

    func testLibraryFilterNarrowsByFacets() {
        let sets = ContentLibrary.filteredTemplates(in: nil, matching: "", facets: TemplateFilter(multiPage: true))
        XCTAssertFalse(sets.isEmpty)
        XCTAssertTrue(sets.allSatisfy { $0.pageCount > 1 })
        let photos = ContentLibrary.filteredTemplates(in: nil, matching: "", facets: TemplateFilter(photo: true)).map(\.id)
        XCTAssertTrue(photos.contains("neon-nights-story"))
        XCTAssertFalse(photos.contains("mega-sale-post"))
    }

    /// Colours in the sheet's order, then Animated, photos, pages; each
    /// chip's filter is the filter without it.
    func testChipsInTheSheetsOrder() {
        let filter = TemplateFilter(colors: ["white", "red"], animated: true, photo: false, multiPage: true)
        let chips = filter.chips
        XCTAssertEqual(chips.map(\.label), ["Red", "White", "Animated", "Without photos", "Set"])
        XCTAssertEqual(chips[0].without.colors, ["white"])
        XCTAssertNil(chips[2].without.animated)
        XCTAssertNil(chips[4].without.multiPage)
        XCTAssertEqual(TemplateFilter(multiPage: false).chips.map(\.label), ["Single page"])
        XCTAssertTrue(TemplateFilter().chips.isEmpty)
    }

    func testTwelveColoursEachWithASwatchAndAName() {
        XCTAssertEqual(TemplateFilter.allColors, ["red", "orange", "yellow", "green", "teal", "blue",
                                                  "purple", "pink", "brown", "black", "white", "grey"])
        for c in TemplateFilter.allColors {
            XCTAssertNotNil(TemplateFilter.swatches[c], c)
            XCTAssertFalse(TemplateFilter.colorName(c).isEmpty)
        }
        XCTAssertEqual(TemplateFilter.colorName("grey"), "Grey")
        XCTAssertEqual(TemplateFilter.noMatch, "No templates match those filters")
    }

    // MARK: the shared fixture

    private func filter(_ o: [String: Any]) -> TemplateFilter {
        TemplateFilter(colors: Set(o["colors"] as? [String] ?? []), animated: o["animated"] as? Bool,
                       photo: o["photo"] as? Bool, multiPage: o["multiPage"] as? Bool,
                       style: o["style"] as? String)
    }

    /// Shared: the facets the generator wrote, and what each filter lets
    /// through of the whole library in its order — the Android twin's
    /// fixtures/template-filters.json.
    func testTheSharedFixture() throws {
        let fixture = try SharedFixture.object("template-filters")
        let facets = try XCTUnwrap(fixture["facets"] as? [String: [String: Any]])
        for (id, want) in facets {
            let read = try JSONDecoder().decode(TemplateFacets.self, from: SharedFixture.encoded(want))
            XCTAssertEqual(try self.facets(id), read, id)
        }
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        for row in cases {
            let chosen = filter(row["filter"] as? [String: Any] ?? [:])
            let found = ContentLibrary.filteredTemplates(in: nil, matching: "", facets: chosen)
            XCTAssertEqual(found.count, row["count"] as? Int, "\(row)")
            let first = row["first"] as? [String] ?? []
            XCTAssertEqual(Array(found.prefix(first.count)).map(\.id), first, "\(row)")
        }
    }
}
