// Hidden pages, as the Android twin has them: the flag on the page written
// only when true, Present stepping over hidden pages, hiding as one Undo,
// and exports of every page — files, PDF, video — leaving them out. The
// same cases as the Android twin's tests.

import XCTest
import CoreGraphics
@testable import Canvia

final class HiddenPagesTests: XCTestCase {

    private func json(_ page: Page) throws -> [String: Any] {
        let data = try JSONEncoder().encode(page)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func design(hidden: [Bool]) -> Design {
        var d = Design(title: "h", width: 400, height: 300)
        d.pages = hidden.map { flag in
            var p = Page()
            p.hidden = flag ? true : nil
            return p
        }
        return d
    }

    // MARK: the file

    func testAPageWithoutTheKeyIsShownAndWrittenWithoutIt() throws {
        let page = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","elements":[]}"#.utf8))
        XCTAssertNil(page.hidden)
        XCTAssertNil(try json(page)["hidden"])
    }

    func testHiddenRoundTrips() throws {
        let page = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","hidden":true}"#.utf8))
        XCTAssertEqual(page.hidden, true)
        XCTAssertEqual(try json(page)["hidden"] as? Bool, true)
        let back = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(back.hidden, true)
    }

    func testShowingAPageAgainRemovesTheKey() throws {
        var page = Page()
        page.hidden = true
        page.hidden = false
        XCTAssertNil(try json(page)["hidden"], "false is never written: shown is the key's absence")
        let read = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p1","hidden":false}"#.utf8))
        XCTAssertNil(read.hidden)
    }

    /// The rest of the page is written as it always was.
    func testTheOtherKeysAreStillWritten() throws {
        var page = Page(notes: "Say hello")
        page.usesMaster = false
        page.holdSeconds = 4
        page.width = 1080
        let back = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(back, page)
        XCTAssertEqual(try json(page)["usesMaster"] as? Bool, false)
    }

    // MARK: which pages are shown

    func testVisibleIndicesSkipHiddenPages() {
        XCTAssertEqual(design(hidden: [false, true, false, true]).visiblePageIndices, [0, 2])
        XCTAssertEqual(design(hidden: [true, true]).visiblePageIndices, [])
    }

    // MARK: present

    func testPresentStepsOverHiddenPages() {
        let visible = design(hidden: [false, true, false, true, false]).visiblePageIndices
        XCTAssertEqual(PageVisibility.next(after: 0, in: visible), 2)
        XCTAssertEqual(PageVisibility.next(after: 2, in: visible), 4)
        XCTAssertNil(PageVisibility.next(after: 4, in: visible))
        XCTAssertEqual(PageVisibility.previous(before: 4, in: visible), 2)
        XCTAssertEqual(PageVisibility.previous(before: 2, in: visible), 0)
        XCTAssertNil(PageVisibility.previous(before: 0, in: visible))
    }

    func testPresentStartsOnTheNextShownPageElseThePreviousOne() {
        let visible = design(hidden: [false, true, false, true]).visiblePageIndices
        XCTAssertEqual(PageVisibility.start(at: 2, in: visible), 2, "a shown page starts where it is")
        XCTAssertEqual(PageVisibility.start(at: 1, in: visible), 2, "a hidden page starts at the next shown one")
        XCTAssertEqual(PageVisibility.start(at: 3, in: visible), 2, "none after it: the one before")
        XCTAssertNil(PageVisibility.start(at: 0, in: design(hidden: [true, true]).visiblePageIndices))
    }

    // MARK: the editor

    @MainActor
    func testHidingAPageIsOneUndo() {
        let store = DesignStore(design: design(hidden: [false, false]))
        store.setPageHidden(true)
        XCTAssertEqual(store.design.pages[0].hidden, true)
        XCTAssertEqual(store.design.visiblePageIndices, [1])
        store.setPageHidden(false)
        XCTAssertNil(store.design.pages[0].hidden, "shown is nil, never false")
        store.undo()
        XCTAssertEqual(store.design.pages[0].hidden, true)
        store.undo()
        XCTAssertNil(store.design.pages[0].hidden)
        XCTAssertFalse(store.canUndo)
    }

    @MainActor
    func testTheOrganizerHidesSeveralPagesInOneStep() {
        let store = DesignStore(design: design(hidden: [false, false, false]))
        let ids: Set<String> = [store.design.pages[0].id, store.design.pages[2].id]
        store.setPagesHidden(ids, hidden: true)
        XCTAssertEqual(store.design.visiblePageIndices, [1])
        store.setPagesHidden(ids, hidden: false)
        XCTAssertEqual(store.design.visiblePageIndices, [0, 1, 2])
        store.undo()
        XCTAssertEqual(store.design.visiblePageIndices, [1])
        store.undo()
        XCTAssertFalse(store.canUndo)
    }

    /// A duplicate of a hidden page is hidden too: it is the same page again.
    @MainActor
    func testADuplicatedHiddenPageStaysHidden() {
        let store = DesignStore(design: design(hidden: [true, false]))
        store.duplicatePage()
        XCTAssertEqual(store.design.pages[1].hidden, true)
    }

    // MARK: what VoiceOver says

    @MainActor
    func testAHiddenPageSaysSo() {
        XCTAssertEqual(PagesBar.spokenThumb(number: 2, current: true, hidden: true), "Page 2, current, hidden")
        XCTAssertEqual(PagesBar.spokenThumb(number: 3, current: false, hidden: false), "Page 3")
        XCTAssertEqual(PageOrganizerSheet.spokenRow(number: 2, current: false, hidden: true, elements: 1, notes: nil),
                       "Page 2, hidden, 1 element")
    }
}

// MARK: - exports

@MainActor
final class HiddenPageExportTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func design(hidden: [Bool]) -> Design {
        var d = Design(title: "hidden", width: 120, height: 90)
        d.pages = hidden.map { flag in
            var p = Page(background: .color("#3355ff"), elements: [Element.shape("rect", w: 40, h: 30)])
            p.hidden = flag ? true : nil
            return p
        }
        return d
    }

    // MARK: which pages

    func testAllPagesSkipsHiddenPages() {
        let d = design(hidden: [false, true, false, true])
        XCTAssertEqual(DesignExporter.PageRange.all.indices(in: d, current: 0), [0, 2])
        XCTAssertEqual(DesignExporter.PageRange.range(1, 3).indices(in: d, current: 0), [2])
        XCTAssertEqual(DesignExporter.PageRange.all.indices(in: design(hidden: [true, true]), current: 0), [])
    }

    func testThisPageIsExportedEvenWhenHidden() {
        let d = design(hidden: [false, true, false])
        XCTAssertEqual(DesignExporter.PageRange.current.indices(in: d, current: 1), [1])
    }

    func testTheSheetSaysHowManyAreLeftOut() {
        XCTAssertEqual(PageVisibility.allPages(total: 5, hidden: 2), "All 5 pages, 2 hidden left out")
        XCTAssertEqual(PageVisibility.allPages(total: 5, hidden: 0), "All 5 pages")
    }

    // MARK: files

    /// Each file keeps its page's own number, so page 3 is still "-3" with
    /// page 2 hidden.
    func testAllPagesWritesOnlyTheShownPagesUnderTheirOwnNumbers() async throws {
        let urls = try await DesignExporter.exportPages(design: design(hidden: [false, true, false]), range: .all,
                                                        current: 0, format: .png, scale: 1)
        written = urls
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls[0].lastPathComponent.contains("-1."), urls[0].lastPathComponent)
        XCTAssertTrue(urls[1].lastPathComponent.contains("-3."), urls[1].lastPathComponent)
    }

    func testThePDFOfAllPagesLeavesHiddenPagesOut() async throws {
        let d = design(hidden: [false, true, false, false])
        let url = DesignExporter.fileURL(for: d, ext: "pdf", suffix: "-hidden")
        written = [url]
        try await DesignExporter.exportPDF(design: d, range: .all, current: 0, to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 3)
    }

    // MARK: video

    func testTheVideoTimelineLeavesHiddenPagesOut() {
        var d = design(hidden: [false, true, false])
        d.pages[1].holdSeconds = 6
        var settings = MovieExporter.Settings()
        settings.secondsPerPage = 2
        settings.fps = 10
        let timeline = MovieExporter.timeline(design: d, pages: d.visiblePageIndices, settings: settings)
        XCTAssertEqual(timeline.count, 2, "one fewer page than the design")
        XCTAssertEqual(timeline.map(\.start), [0, 20])
        XCTAssertEqual(MovieExporter.timeline(design: d, settings: settings), timeline)
        XCTAssertEqual(MovieExporter.seconds(design: d, settings: settings), 4, accuracy: 0.001,
                       "the hidden page's six seconds are not in the film, nor under its music")
    }

    /// The pages a video is drawn from are the pages shown, in order.
    func testTheVideoIsDrawnFromTheShownPagesOnly() throws {
        let d = design(hidden: [true, false, false])
        let images = MovieExporter.pageImages(design: d, size: CGSize(width: 120, height: 90))
        guard !images.isEmpty else { throw XCTSkip("the page renderer produced nothing in this environment") }
        XCTAssertEqual(images.count, 2)
    }
}
