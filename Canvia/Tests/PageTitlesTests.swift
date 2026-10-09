// Page titles, as the Android twin has them: written only when there is one,
// trimmed and cut at 60 characters, shown where pages are listed and typed
// as one Undo. The same cases as the Android twin's tests.

import XCTest
@testable import Canvia

final class PageTitlesTests: XCTestCase {

    private func json(_ page: Page) throws -> [String: Any] {
        let data = try JSONEncoder().encode(page)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: the file

    /// Every design made before either existed.
    func testAnOldPageIsShownAndUntitledAndWrittenWithoutEitherKey() throws {
        let page = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","elements":[],"notes":"Hi"}"#.utf8))
        XCTAssertNil(page.hidden)
        XCTAssertNil(page.title)
        let written = try json(page)
        XCTAssertNil(written["hidden"])
        XCTAssertNil(written["title"])
        XCTAssertEqual(written["notes"] as? String, "Hi")
    }

    func testHiddenAndTitleRoundTrip() throws {
        let page = try JSONDecoder().decode(Page.self,
                                            from: Data(#"{"id":"p1","hidden":true,"title":"Intro"}"#.utf8))
        XCTAssertEqual(page.hidden, true)
        XCTAssertEqual(page.title, "Intro")
        let written = try json(page)
        XCTAssertEqual(written["hidden"] as? Bool, true)
        XCTAssertEqual(written["title"] as? String, "Intro")
        let back = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(back, page)
    }

    func testABlankTitleRemovesTheKey() throws {
        var page = Page()
        page.title = "Intro"
        page.title = PageTitles.cleaned("  ")
        XCTAssertNil(page.title)
        XCTAssertNil(try json(page)["title"])
        page.title = "  "
        XCTAssertNil(try json(page)["title"], "a blank title is never written")
        let read = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","title":"   "}"#.utf8))
        XCTAssertNil(read.title)
    }

    /// The page's title is its own: the design's title is untouched.
    func testThePageTitleIsNotTheDesignTitle() throws {
        var d = Design(title: "Pitch deck")
        d.pages[0].title = "Intro"
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.title, "Pitch deck")
        XCTAssertEqual(back.pages[0].title, "Intro")
    }

    // MARK: what a title keeps

    func testATitleIsTrimmedAndCutAtSixtyCharacters() {
        XCTAssertEqual(PageTitles.cleaned("  Intro  "), "Intro")
        let long = String(repeating: "a", count: 75)
        XCTAssertEqual(PageTitles.cleaned("  " + long), String(repeating: "a", count: 60))
        XCTAssertEqual(PageTitles.maxLength, 60)
        XCTAssertNil(PageTitles.cleaned(""))
        XCTAssertNil(PageTitles.cleaned(" \n "))
    }

    // MARK: where it shows

    func testATitleFollowsThePageNumber() {
        XCTAssertEqual(PageTitles.named(2, title: "Intro"), "Page 2 · Intro")
        XCTAssertEqual(PageTitles.named(2, title: nil), "Page 2")
        XCTAssertEqual(PageTitles.named(2, title: " "), "Page 2")
        XCTAssertEqual(PageTitles.counter(2, of: 5, title: "Intro"), "2 / 5 · Intro")
        XCTAssertEqual(PageTitles.counter(2, of: 5, title: nil), "2 / 5")
    }

    @MainActor
    func testVoiceOverSaysTheTitleAfterTheNumber() {
        XCTAssertEqual(PagesBar.spokenThumb(number: 2, title: "Intro", current: true, hidden: true),
                       "Page 2, Intro, current, hidden")
        XCTAssertEqual(PageOrganizerSheet.spokenRow(number: 2, title: "Intro", current: false, hidden: false,
                                                    elements: 3, notes: "Welcome"),
                       "Page 2, Intro, 3 elements, Welcome")
    }

    // MARK: typing it

    /// What the notes sheet does as a title is typed: every keystroke under
    /// one open step, closed once.
    @MainActor
    func testATitleTypedIsOneUndo() {
        let store = DesignStore(design: Design(title: "t", width: 400, height: 300))
        for text in ["I", "In", "Intr", "Intro "] {
            store.beginGesture()
            store.design.pages[store.pageIndex].title = PageTitles.cleaned(text)
        }
        store.commit()
        XCTAssertEqual(store.page.title, "Intro")
        XCTAssertEqual(store.design.title, "t", "the design keeps its own name")
        store.undo()
        XCTAssertNil(store.page.title)
        XCTAssertFalse(store.canUndo)
    }
}
