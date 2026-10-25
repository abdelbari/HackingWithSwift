// Template search, as both phones run it: the shared cases
// (templates/search-cases.json — each query's first results in order, how
// many it finds and what it was corrected to) and the steps one at a time.
// The Android twin's TemplateSearchTest, row for row.

import XCTest
@testable import Canvia

final class TemplateSearchTests: XCTestCase {

    func testEverySharedCaseFindsTheSameTemplatesInTheSameOrder() throws {
        let cases = try XCTUnwrap(try JSONSerialization.jsonObject(with: SharedFixture.data("search-cases")) as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(cases.count, 15)
        for c in cases {
            let query = try XCTUnwrap(c["query"] as? String)
            let r = TemplateSearch.search(query)
            let expected = c["expectedIdsInOrder"] as? [String] ?? []
            XCTAssertEqual(Array(r.templates.prefix(expected.count)).map(\.id), expected, query)
            XCTAssertEqual(r.templates.count, c["count"] as? Int, query)
            XCTAssertEqual(r.correctedTo, c["correctedTo"] as? String, query)
        }
    }

    func testWordsAreNormalisedStopWordsDroppedAndPluralsStemmed() {
        XCTAssertEqual(TemplateSearch.tokens("The Café-Menu"), ["cafe", "menu"])
        XCTAssertEqual(TemplateSearch.tokens("my Valentine's card template"), ["valentines", "card"])
        XCTAssertEqual(TemplateSearch.stem("invitations"), "invitation")
        XCTAssertEqual(TemplateSearch.stem("parties"), "party")
        XCTAssertEqual(TemplateSearch.stem("boxes"), "box")
        XCTAssertEqual(TemplateSearch.stem("resumes"), "resume")
        XCTAssertEqual(TemplateSearch.stem("class"), "class")
        XCTAssertEqual(TemplateSearch.stem("children"), "child")
        XCTAssertTrue(TemplateSearch.tokens("templates").isEmpty)
    }

    func testTyposAreMeasuredByDamerauLevenshteinASwapCountingOnce() {
        XCTAssertEqual(TemplateSearch.distance("brithday", "birthday"), 1)
        XCTAssertEqual(TemplateSearch.distance("invitaton", "invitation"), 1)
        XCTAssertEqual(TemplateSearch.distance("halowen", "halloween"), 2)
        let words = ["birthday": 9, "birthdays": 0, "poster": 30]
        XCTAssertEqual(TemplateSearch.nearest("brithday", in: words), "birthday")
        // A short word may be one letter out, no more.
        XCTAssertNil(TemplateSearch.nearest("pstr", in: words))
    }

    func testAColourWordIsAFilterUnlessTheNameSaysIt() {
        let blue = TemplateSearch.search("blue").templates
        XCTAssertFalse(blue.isEmpty)
        XCTAssertTrue(blue.allSatisfy { $0.shownFacets.colors.contains("blue") || TemplateSearch.tokens($0.name).contains("blue") })
        XCTAssertTrue(TemplateSearch.search("black friday").templates.contains { $0.id == "black-friday-insta-post" })
    }

    func testNothingFoundByItsOwnWordsIsCorrectedAndThatCanBeRefused() {
        XCTAssertEqual(TemplateSearch.search("brithday").correctedTo, "birthday")
        XCTAssertTrue(TemplateSearch.search("brithday", correct: false).templates.isEmpty)
        XCTAssertTrue(TemplateSearch.search("   ").templates.isEmpty)
        XCTAssertEqual(TemplateSearch.showingFor("birthday"), "Showing results for “birthday”")
        XCTAssertEqual(TemplateSearch.searchInstead(" brithday "), "Search instead for “brithday”")
    }

    func testFiltersStillApplyAnOccasionAmongThemAndRecentlyUsedRankHigher() {
        let elegant = TemplateSearch.search("invitation", filter: TemplateFilter(style: "elegant")).templates
        XCTAssertTrue(!elegant.isEmpty && elegant.allSatisfy { $0.shownFacets.style == "elegant" })
        let halloween = TemplateSearch.search("poster", filter: TemplateFilter(occasion: "halloween")).templates
        XCTAssertEqual(halloween.map(\.id), ["halloween-poster", "halloween-poster-v2"])
        let plain = TemplateSearch.search("halloween").templates.map(\.id)
        let boosted = TemplateSearch.search("halloween", recent: ["halloween-poster-v2"]).templates.map(\.id)
        XCTAssertEqual(boosted.first, "halloween-poster-v2")
        XCTAssertEqual(Set(plain), Set(boosted))
    }

    func testCompletionsFinishTheLastWordFromTheVocabularyTheCommonestFirst() {
        let words = ["birthday": 9, "birth": 2, "bird": 1, "brunch": 4, "unused": 0]
        XCTAssertEqual(TemplateSearch.completions("blue bir", limit: 5, words: words),
                       ["blue birthday", "blue birth", "blue bird"])
        XCTAssertEqual(TemplateSearch.completions("birt", limit: 5, words: words), ["birthday", "birth"])
        XCTAssertTrue(TemplateSearch.completions("b", limit: 5, words: words).isEmpty)
        XCTAssertTrue(TemplateSearch.completions("bir ", limit: 5, words: words).isEmpty)
        XCTAssertEqual(TemplateSearch.completions("hal").first, "halloween")
        XCTAssertLessThanOrEqual(TemplateSearch.completions("hal").count, TemplateSearch.completionLimit)
    }

    func testSynonymsAreSharedAndReadEitherWayRound() throws {
        let shared = try XCTUnwrap(try JSONSerialization.jsonObject(with: SharedFixture.data("search-synonyms"))
            as? [String: [String]])
        XCTAssertEqual(TemplateSearch.synonyms, shared)
        XCTAssertEqual(TemplateSearch.synonyms["bday"], ["birthday"])
        // "invitation" finds what "invite" names, and "invite" what "invitation" does.
        let invite = Set(TemplateSearch.search("invite").templates.map(\.id))
        let invitation = Set(TemplateSearch.search("invitation").templates.map(\.id))
        XCTAssertEqual(invite, invitation)
    }

    /// Home's editor tab finds them the same way, among those it shows.
    func testTheEditorsTemplatesAreFoundTheSameWay() {
        let found = ContentLibrary.editorTemplates(width: 1, height: 1, everySize: true, matching: "bday")
        XCTAssertEqual(found.map(\.id), TemplateSearch.search("bday").templates.map(\.id))
    }
}
