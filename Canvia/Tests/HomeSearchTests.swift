// Home's search over designs' words, and its Type and Edited chips: the
// shelf's "text" and "type" (DesignLibrary.searchText, typeOf), the
// snippet a result shows, and how the chips narrow the shelf — the same
// cases as the Android twin's ShelfTest.

import XCTest
@testable import Canvia

final class HomeSearchTests: XCTestCase {

    private let fair = "join us for the school fair with games, a raffle and a bake sale on saturday at noon in the main hall with music"

    private func card(_ id: String, _ title: String, text: String = "", type: String? = nil,
                      at: Double = 0, damaged: Bool = false, w: Double = 1080, h: Double = 1080) -> RecentDesign {
        RecentDesign(id: id, title: title, width: w, height: h, pages: 1, updatedAt: at,
                     damaged: damaged, text: text, type: type)
    }

    // MARK: the words kept

    /// Every text box and shape with words, page by page; hidden ones,
    /// caption boxes, page titles and notes left out; markers stripped,
    /// spaces made one, lower-cased and accents off.
    func testSearchTextIsTheVisibleWordsFolded() {
        var design = Design(title: "Fête", width: 1080, height: 1080)
        var heading = Element.text("Café  **Crème**\nOpen")
        heading.id = "a"
        var hidden = Element.text("Secret")
        hidden.hidden = true
        var shape = Element.shape("rect")
        shape.text = "Bake Sale"
        var captions = Element.text("Spoken words")
        captions.captions = Captions(cues: [CaptionCue(start: 0, end: 1, text: "Spoken words")])
        design.pages = [Page(elements: [heading, hidden]), Page(elements: [shape, captions])]
        design.pages[0].title = "Cover"
        design.pages[0].notes = "Say hello"
        XCTAssertEqual(DesignLibrary.searchText(design), "cafe creme open bake sale")
    }

    func testSearchTextIsCutAtFourThousand() {
        var design = Design()
        design.pages = [Page(elements: [Element.text(String(repeating: "word ", count: 2000))])]
        let text = DesignLibrary.searchText(design)
        XCTAssertEqual(text.utf16.count, DesignLibrary.searchTextLimit)
        XCTAssertTrue(text.hasPrefix("word word"))
    }

    /// A whiteboard; the paper type of a design on paper; the pixel type of
    /// exactly its size; else none.
    func testTypeOfADesign() throws {
        let story = try XCTUnwrap(SizePreset.byId("insta-story"))
        XCTAssertEqual(DesignLibrary.typeOf(story.makeDesign()), "insta-story")
        let a4 = try XCTUnwrap(SizePreset.byId("a4"))
        XCTAssertEqual(DesignLibrary.typeOf(a4.makeDesign()), "a4")
        XCTAssertNil(DesignLibrary.typeOf(Design(width: 1234, height: 567)))
        let board = try XCTUnwrap(SizePreset.byId(Whiteboards.presetId))
        XCTAssertEqual(DesignLibrary.typeOf(board.makeDesign()), Whiteboards.presetId)
        XCTAssertEqual(DesignLibrary.typeOf(Design(width: 1366, height: 768)), "website")
    }

    // MARK: matching and snippets

    func testTitleMatchesComeBeforeTextMatches() {
        let designs = [
            card("a", "Flyer", text: "a bake sale on saturday", at: 3),
            card("b", "Bake sale poster", at: 1),
            card("c", "Menu", text: "pasta", at: 5),
            card("d", "Notes", text: "bake sale leftovers", at: 2),
        ]
        let found = DesignLibrary.filter(designs, query: "Bake Sale", sort: .recent, folder: nil,
                                         type: .all, edited: .any, now: 10, startOfToday: 0)
        XCTAssertEqual(found.map(\.id), ["b", "a", "d"])
        XCTAssertEqual(DesignLibrary.filter(designs, query: "", sort: .recent, folder: nil,
                                            type: .all, edited: .any, now: 10, startOfToday: 0).map(\.id),
                       ["c", "a", "d", "b"])
    }

    func testTextMatchFoldsTheQuery() {
        XCTAssertTrue(DesignLibrary.matchesText(card("a", "x", text: "cafe creme"), query: " Café "))
        XCTAssertFalse(DesignLibrary.matchesText(card("a", "x", text: "cafe creme"), query: "  "))
    }

    /// Thirty either side, cut at spaces, "…" where it was cut; the match's
    /// place to bold.
    func testSnippetAroundTheMatch() {
        XCTAssertEqual(DesignLibrary.snippet(fair, query: "Bake sale"),
                       DesignLibrary.Snippet(text: "…with games, a raffle and a bake sale on saturday at noon in the…", start: 28, end: 37))
        XCTAssertEqual(DesignLibrary.snippet("bake sale today", query: "Bake"),
                       DesignLibrary.Snippet(text: "bake sale today", start: 0, end: 4))
        XCTAssertEqual(DesignLibrary.snippet(fair, query: "music"),
                       DesignLibrary.Snippet(text: "…noon in the main hall with music", start: 28, end: 33))
        XCTAssertNil(DesignLibrary.snippet(fair, query: "concert"))
        XCTAssertNil(DesignLibrary.snippet(fair, query: " "))
    }

    // MARK: Type and Edited

    func testTypeChipsByCategory() {
        let deck = card("deck", "Deck", type: "presentation")
        let post = card("post", "Post", type: "insta-post")
        let board = card("board", "Board", type: Whiteboards.presetId)
        let odd = card("odd", "Odd")
        let broken = card("broken", "Damaged design", damaged: true)
        let all = [deck, post, board, odd, broken]
        func ids(_ type: DesignLibrary.TypeFilter) -> [String] { all.filter(type.admits).map(\.id) }
        XCTAssertEqual(ids(.all), ["deck", "post", "board", "odd", "broken"])
        XCTAssertEqual(ids(.presentations), ["deck", "broken"])
        XCTAssertEqual(ids(.social), ["post", "broken"])
        XCTAssertEqual(ids(.whiteboards), ["board", "broken"])
        XCTAssertEqual(ids(.print), ["broken"])
        XCTAssertEqual(DesignLibrary.TypeFilter.allCases.map(\.label),
                       ["All", "Presentations", "Social", "Video", "Print", "Documents", "Whiteboards"])
    }

    func testEditedChipsByDay() {
        let day = DesignLibrary.dayMillis
        let now = 100 * day
        let midnight = now - 3 * 3600 * 1000
        let designs = [
            card("now", "A", at: now - 1000),
            card("yesterday", "B", at: midnight - 1000),
            card("tenDays", "C", at: now - 10 * day),
            card("old", "D", at: now - 40 * day),
            card("broken", "E", at: 0, damaged: true),
        ]
        func ids(_ edited: DesignLibrary.Edited) -> [String] {
            designs.filter { edited.admits($0, now: now, startOfToday: midnight) }.map(\.id)
        }
        XCTAssertEqual(ids(.any).count, 5)
        XCTAssertEqual(ids(.today), ["now", "broken"])
        XCTAssertEqual(ids(.week), ["now", "yesterday", "broken"])
        XCTAssertEqual(ids(.month), ["now", "yesterday", "tenDays", "broken"])
        XCTAssertEqual(ids(.older), ["old", "broken"])
        XCTAssertEqual(DesignLibrary.Edited.allCases.map(\.label),
                       ["Any time", "Today", "Past 7 days", "Past 30 days", "Older"])
    }

    /// The chips combine with the folder and the search.
    func testChipsCombineWithFolderAndSearch() {
        var inFolder = card("a", "Deck one", type: "presentation", at: 5)
        inFolder.folder = "Work"
        let outside = card("b", "Deck two", type: "presentation", at: 4)
        let post = card("c", "Post", text: "deck chairs", type: "insta-post", at: 3)
        let found = DesignLibrary.filter([inFolder, outside, post], query: "deck", sort: .recent, folder: nil,
                                         type: .presentations, edited: .any, now: 10, startOfToday: 0)
        XCTAssertEqual(found.map(\.id), ["a", "b"])
        let filed = DesignLibrary.filter([inFolder, outside, post], query: "deck", sort: .recent, folder: "Work",
                                         type: .all, edited: .any, now: 10, startOfToday: 0)
        XCTAssertEqual(filed.map(\.id), ["a"])
    }

    /// The shelf keeps the words and the type, and an entry from before
    /// they were kept reads as none.
    func testShelfEntryKeepsWordsAndType() throws {
        var design = SizePreset.byId("presentation")?.makeDesign() ?? Design()
        design.pages = [Page(elements: [Element.text("Quarterly Review")])]
        let entry = DesignLibrary.ShelfEntry(design, id: design.id, modified: 1)
        XCTAssertEqual(entry.text, "quarterly review")
        XCTAssertEqual(entry.type, "presentation")
        let json = try String(decoding: JSONEncoder().encode(entry), as: UTF8.self)
        XCTAssertTrue(json.contains("\"text\""))
        XCTAssertTrue(json.contains("\"type\""))
        let old = #"{"id":"x","title":"T","width":1,"height":1,"pages":1,"updatedAt":0,"createdAt":0,"modified":1}"#
        let read = try JSONDecoder().decode(DesignLibrary.ShelfEntry.self, from: Data(old.utf8))
        XCTAssertNil(read.text)
    }

    // MARK: the shared fixture

    /// Shared: the shelf's search, Type and Edited, and the snippets — the
    /// Android twin's fixtures/shelf-search.json.
    func testTheSharedFixture() throws {
        let fixture = try SharedFixture.object("shelf-search")
        let now = try XCTUnwrap(fixture["now"] as? Double)
        let midnight = try XCTUnwrap(fixture["startOfToday"] as? Double)
        let items = try XCTUnwrap(fixture["items"] as? [[String: Any]]).map { o in
            RecentDesign(id: o["id"] as? String ?? "", title: o["title"] as? String ?? "",
                         width: o["width"] as? Double ?? 0, height: o["height"] as? Double ?? 0,
                         pages: o["pages"] as? Int ?? 0, updatedAt: o["updatedAt"] as? Double ?? 0,
                         damaged: o["damaged"] as? Bool ?? false, text: o["text"] as? String ?? "",
                         type: o["type"] as? String)
        }
        for row in try XCTUnwrap(fixture["cases"] as? [[String: Any]]) {
            let type = try XCTUnwrap(DesignLibrary.TypeFilter(rawValue: row["type"] as? String ?? ""))
            let edited = try XCTUnwrap(DesignLibrary.Edited(rawValue: row["edited"] as? String ?? ""))
            let found = DesignLibrary.filter(items, query: row["query"] as? String ?? "", sort: .recent, folder: nil,
                                             type: type, edited: edited, now: now, startOfToday: midnight)
            XCTAssertEqual(found.map(\.id), row["expect"] as? [String], "\(row)")
        }
        for row in try XCTUnwrap(fixture["snippets"] as? [[String: Any]]) {
            let got = DesignLibrary.snippet(row["text"] as? String ?? "", query: row["query"] as? String ?? "")
            if let text = row["snippet"] as? String {
                XCTAssertEqual(got, DesignLibrary.Snippet(text: text, start: row["start"] as? Int ?? -1,
                                                          end: row["end"] as? Int ?? -1), "\(row)")
            } else {
                XCTAssertNil(got, "\(row)")
            }
        }
    }
}
