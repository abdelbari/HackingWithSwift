// Pages across the pasteboard, and the multi-page operations behind the
// organizer.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class PageClipboardTests: XCTestCase {

    private func page(_ n: Int, group: String? = nil) -> Page {
        var els = (0..<n).map { _ in Element.shape("rect", w: 100, h: 50) }
        for i in els.indices { els[i].group = group }
        return Page(background: .color("#abcdef"), elements: els)
    }

    private func store(pages: [Page], width: Double = 1000, height: Double = 500) -> DesignStore {
        var d = Design(title: "pages", width: width, height: height)
        d.pages = pages
        return DesignStore(design: d)
    }

    func testAPageSurvivesThePasteboardWithNewIds() throws {
        let board = UIPasteboard.withUniqueName()
        let source = page(2, group: "g1")
        PageClipboard.copy(source, width: 1000, height: 500, to: board)
        XCTAssertTrue(PageClipboard.hasPage(in: board))
        let payload = try XCTUnwrap(PageClipboard.paste(from: board))
        XCTAssertEqual(payload.page.elements.count, 2)
        XCTAssertEqual(payload.page.background, .color("#abcdef"))

        let landed = PageClipboard.fitted(payload, width: 1000, height: 500)
        XCTAssertNotEqual(landed.id, source.id)
        XCTAssertEqual(Set(landed.elements.map(\.id)).intersection(source.elements.map(\.id)).count, 0)
        XCTAssertEqual(landed.elements[0].x, source.elements[0].x, "same size: nothing moves")
        let groups = Set(landed.elements.compactMap(\.group))
        XCTAssertEqual(groups.count, 1)
        XCTAssertNotEqual(groups.first, "g1", "the group is re-keyed but kept")
    }

    func testAPasteIntoASmallerDesignScalesToFit() throws {
        var text = Element.text("Hi", fontSize: 40, w: 400)
        text.x = 100; text.y = 100
        let payload = PageClipboard.Payload(page: Page(elements: [text]), width: 1000, height: 1000)
        let landed = PageClipboard.fitted(payload, width: 500, height: 250)
        // Fit scale is 0.25 (height-bound); the 250-wide result centres in 500.
        XCTAssertEqual(landed.elements[0].w, 100, accuracy: 0.001)
        XCTAssertEqual(landed.elements[0].fontSize ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(landed.elements[0].x, 125 + 25, accuracy: 0.001)
        XCTAssertEqual(landed.elements[0].y, 25, accuracy: 0.001)
    }

    func testAnEmptyPasteboardHasNoPage() {
        let board = UIPasteboard.withUniqueName()
        XCTAssertFalse(PageClipboard.hasPage(in: board))
        XCTAssertNil(PageClipboard.paste(from: board))
    }

    // MARK: multi-page operations

    func testReorderKeepsTheCurrentPageCurrent() {
        let s = store(pages: [page(1), page(2), page(3)])
        s.setPage(2)
        let currentId = s.page.id
        s.movePages(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(s.pageIndex, 0)
        XCTAssertEqual(s.page.id, currentId)
        XCTAssertEqual(s.design.pages.map { $0.elements.count }, [3, 1, 2])
        s.undo()
        XCTAssertEqual(s.design.pages.map { $0.elements.count }, [1, 2, 3])
    }

    func testDeletingSeveralPagesIsOneUndoStepAndNeverTheLast() {
        let s = store(pages: [page(1), page(2), page(3)])
        let ids = Set(s.design.pages.prefix(2).map(\.id))
        s.deletePages(ids)
        XCTAssertEqual(s.design.pages.count, 1)
        XCTAssertEqual(s.page.elements.count, 3)
        XCTAssertEqual(s.announcement, "Deleted 2 pages")
        s.undo()
        XCTAssertEqual(s.design.pages.count, 3)

        s.deletePages(Set(s.design.pages.map(\.id)))
        XCTAssertEqual(s.design.pages.count, 3, "every page cannot go")
    }

    func testDuplicatingPagesPutsEachCopyAfterItsSource() {
        let s = store(pages: [page(1), page(2), page(3)])
        let ids: Set<String> = [s.design.pages[0].id, s.design.pages[2].id]
        s.duplicatePages(ids)
        XCTAssertEqual(s.design.pages.map { $0.elements.count }, [1, 1, 2, 3, 3])
        XCTAssertEqual(Set(s.design.pages.map(\.id)).count, 5, "copies have their own ids")
    }

    func testPastePageLandsAfterTheCurrentOne() {
        let s = store(pages: [page(1), page(2)])
        s.copyPage()
        guard s.hasPageOnClipboard else { return }   // the general pasteboard is unavailable in some hosts
        s.pastePage()
        XCTAssertEqual(s.design.pages.count, 3)
        XCTAssertEqual(s.pageIndex, 1)
        XCTAssertEqual(s.page.elements.count, 1)
        XCTAssertNotEqual(s.page.id, s.design.pages[0].id)
    }
}
