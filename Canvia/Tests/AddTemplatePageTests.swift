// Round 29's "Add as new page": a template's page goes in after the page
// open, at its size, as one undo step and shown, overwriting nothing — so a
// locked page does not stop it — and a tap adds a page where this page has
// something on it. The cases are the Android twin's StartOverTest's.

import XCTest
@testable import Canvia

@MainActor
final class AddTemplatePageTests: XCTestCase {

    private func storeWithOneShape() -> DesignStore {
        var d = Design(title: "Poster", width: 1080, height: 1080)
        var oval = Element.shape("oval", w: 100, h: 100)
        oval.id = "oval"
        d.pages = [Page(id: "p1", elements: [oval])]
        return DesignStore(design: d)
    }

    private var template: Template { ContentLibrary.templates.first { $0.pageCount == 1 }! }

    func testATemplatePageGoesInAfterThePageAtItsSizeOverwritingNothing() {
        let first = Page(id: "a", elements: [Element.shape("oval", w: 100, h: 100)])
        var second = Page(id: "b")
        second.width = 1920
        second.height = 1080
        var design = Design(title: "Deck", width: 1080, height: 1080)
        design.pages = [first, second]
        var made = Page(id: "t", elements: [Element.shape("rect", w: 100, h: 100)])
        made.width = 500
        made.height = 700

        let after = DesignStore.insertedTemplatePage(design, page: made, at: 1)
        XCTAssertEqual(after.pages.map(\.id), ["a", "t", "b"])
        // The size of the page it follows: none of its own, the design's.
        XCTAssertNil(after.pages[1].width)
        XCTAssertNil(after.pages[1].height)
        XCTAssertEqual(after.pages[0], first)
        XCTAssertEqual(after.pages[1].elements, made.elements)

        // After a page of its own size, that size.
        let last = DesignStore.insertedTemplatePage(design, page: made, at: 2)
        XCTAssertEqual(last.pages.map(\.id), ["a", "b", "t"])
        XCTAssertEqual(last.pages[2].width, 1920)
        XCTAssertEqual(last.pages[2].height, 1080)
        // Past the end, at the end; before the start, first, at the first
        // page's size.
        XCTAssertEqual(DesignStore.insertedTemplatePage(design, page: made, at: 9).pages.last?.id, "t")
        let front = DesignStore.insertedTemplatePage(design, page: made, at: -1)
        XCTAssertEqual(front.pages.map(\.id), ["t", "a", "b"])
        XCTAssertNil(front.pages[0].width)
    }

    func testAddAsNewPageIsOneStepShowsTheNewPageAndKeepsThisOne() {
        let store = storeWithOneShape()
        let before = store.page
        let page = template.makePage(at: 0, width: store.pageWidth, height: store.pageHeight)
        store.selection = ["oval"]
        store.addTemplatePage(page, name: template.name)
        XCTAssertEqual(store.design.pages.count, 2)
        XCTAssertEqual(store.pageIndex, 1)
        XCTAssertEqual(store.design.pages[0], before)
        XCTAssertEqual(store.page.elements.count, page.elements.count)
        XCTAssertTrue(store.selection.isEmpty)
        XCTAssertEqual(store.announcement, "Added a page from \u{201C}\(template.name)\u{201D}")
        store.undo()
        XCTAssertEqual(store.design.pages.count, 1)
        XCTAssertEqual(store.pageIndex, 0)
        XCTAssertEqual(store.page.elements.map(\.id), before.elements.map(\.id))
    }

    func testALockedPageDoesNotStopAddAsNewPage() {
        let store = storeWithOneShape()
        store.setPageLocked(true)
        let page = template.makePage(at: 0, width: store.pageWidth, height: store.pageHeight)
        store.applyTemplatePage(page, name: template.name)
        XCTAssertEqual(store.design.pages.count, 1)
        XCTAssertEqual(store.page.elements.map(\.id), ["oval"], "Use on this page is refused")
        store.addTemplatePage(page, name: template.name)
        XCTAssertEqual(store.design.pages.count, 2)
        XCTAssertTrue(PageLocks.isLocked(store.design.pages[0]))
        XCTAssertFalse(PageLocks.isLocked(store.page))
    }

    func testATapAddsAPageWhereThisPageHasSomethingOnIt() {
        let store = storeWithOneShape()
        XCTAssertTrue(store.templateAddsPage)
        let page = template.makePage(at: 0, width: store.pageWidth, height: store.pageHeight)
        store.useTemplatePage(page, name: template.name)
        XCTAssertEqual(store.design.pages.count, 2, "a filled page is never overwritten")
        // The new page has the template on it; an empty page is replaced.
        store.addPage()
        XCTAssertFalse(store.templateAddsPage)
        let count = store.design.pages.count
        store.useTemplatePage(page, name: template.name)
        XCTAssertEqual(store.design.pages.count, count, "an empty page takes the template in its place")
        XCTAssertEqual(store.page.elements.count, page.elements.count)
        // A locked page, empty or not, gets a new page.
        store.applyToPage { $0.elements = [] }
        store.setPageLocked(true)
        XCTAssertTrue(store.templateAddsPage)
        XCTAssertEqual(ContentLibrary.editorTemplatesNote(exactCount: 3, addsPage: true),
                       "Each one goes on a new page after this one. Hold one to use it on this page instead.")
    }
}
