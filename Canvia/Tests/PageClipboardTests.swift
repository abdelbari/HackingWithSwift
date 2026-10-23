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

    /// The row the Android twin's "a pasted page's table keeps its cell
    /// spacing in proportion" checks: a table's cell spacing scales with
    /// the page it lands on.
    func testAPastedTableKeepsItsCellSpacingInProportion() {
        var cell = Element.shape("rect", w: 400, h: 200)
        cell.x = 0; cell.y = 0
        cell.table = TableCell(id: "tbl_1", row: 0, col: 0, pad: 30)
        let payload = PageClipboard.Payload(page: Page(elements: [cell]), width: 1080, height: 1080)
        let landed = PageClipboard.fitted(payload, width: 540, height: 540).elements
        XCTAssertEqual(landed[0].w, 200, accuracy: 0.001)
        XCTAssertEqual(landed[0].table?.pad ?? 0, 15, accuracy: 0.001)
        XCTAssertEqual(PageClipboard.fitted(payload, width: 1080, height: 1080).elements[0].table?.pad, 30)
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

    // MARK: several pages (round 31)

    /// Three pages of three sizes, each with one 100 × 100 box at 0, 0, and
    /// a title, notes and a lock or a hide of its own.
    private var three: PageClipboard.Pages {
        let sizes: [(Double, Double)] = [(1000, 1000), (2000, 1000), (500, 1000)]
        let entries = sizes.enumerated().map { n, size -> PageClipboard.CopiedPage in
            var box = Element.shape("rect", w: 100, h: 100)
            box.id = "box\(n)"
            var page = Page(id: "p\(n)", elements: [box])
            page.title = "Page \(n)"
            page.notes = "Notes \(n)"
            return PageClipboard.CopiedPage(page: page, width: size.0, height: size.1)
        }
        return PageClipboard.Pages(pages: entries)
    }

    func testSeveralPagesTravelInOrderUnderTheNewTypeAndTheFirstUnderTheOld() throws {
        let board = UIPasteboard.withUniqueName()
        PageClipboard.copy(three, to: board)
        XCTAssertTrue(PageClipboard.hasPage(in: board))
        XCTAssertEqual(PageClipboard.copiedCount(in: board), 3)
        XCTAssertEqual(try XCTUnwrap(PageClipboard.pastePages(from: board)), three)
        let old = try XCTUnwrap(PageClipboard.paste(from: board), "an older build reads the first page")
        XCTAssertEqual(old.page, three.pages[0].page)
        XCTAssertEqual(old.width, 1000)
    }

    func testThePayloadIsTheAndroidTwinsJSON() throws {
        let data = try JSONEncoder().encode(PageClipboard.Pages(pages: [three.pages[0]]))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["pages", "fonts"])
        let first = try XCTUnwrap((object["pages"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["page", "width", "height"])
        let lenient = try JSONDecoder().decode(PageClipboard.Pages.self, from: Data(#"{"pages":[]}"#.utf8))
        XCTAssertEqual(lenient.fonts, [], "no fonts key is no fonts")
    }

    func testThreeMixedSizePagesLandInOrderEachFittedToTheDesign() {
        let landed = PageClipboard.landed(three, width: 1000, height: 500)
        XCTAssertEqual(landed.map(\.title), ["Page 0", "Page 1", "Page 2"], "in order, titles travelling")
        XCTAssertEqual(landed.map(\.notes), ["Notes 0", "Notes 1", "Notes 2"])
        // 1000² fits by 0.5, centred across; 2000 × 1000 by 0.5, flush;
        // 500 × 1000 by 0.5, centred across.
        XCTAssertEqual(landed.map { $0.elements[0].w }, [50, 50, 50])
        XCTAssertEqual(landed.map { $0.elements[0].x }, [250, 0, 375])
        XCTAssertEqual(landed.map { $0.elements[0].y }, [0, 0, 0])
        XCTAssertTrue(landed.allSatisfy { $0.id.hasPrefix("page") }, "fresh ids")
        XCTAssertFalse(landed.contains { $0.elements[0].id.hasPrefix("box") })
    }

    func testPastingSeveralIsOneStepAfterTheCurrentPageAndShowsTheFirst() {
        let s = store(pages: [page(1), page(2)])
        PageClipboard.copy(three)
        guard PageClipboard.hasPage() else { return }   // the general pasteboard is unavailable in some hosts
        s.pastePage()
        XCTAssertEqual(s.design.pages.count, 5)
        XCTAssertEqual(s.design.pages[1...3].map(\.title), ["Page 0", "Page 1", "Page 2"])
        XCTAssertEqual(s.pageIndex, 1, "the first pasted page is shown")
        s.undo()
        XCTAssertEqual(s.design.pages.count, 2, "one undo step")
    }

    func testASinglePagePayloadStillPastesFromTheOldType() throws {
        let board = UIPasteboard.withUniqueName()
        PageClipboard.copy(page(2), width: 1000, height: 500, to: board)
        let read = try XCTUnwrap(PageClipboard.pastePages(from: board))
        XCTAssertEqual(read.pages.count, 1)
        XCTAssertEqual(read.pages[0].page.elements.count, 2)
        XCTAssertEqual(read.pages[0].width, 1000)
        XCTAssertEqual(PageClipboard.landed(read, width: 1000, height: 500).count, 1)
    }

    func testCopyingTickedPagesKeepsTheDesignsOrder() {
        let s = store(pages: [page(1), page(2), page(3)])
        let ids = Set([s.design.pages[2].id, s.design.pages[0].id])
        s.copyPages(ids)
        guard let copied = PageClipboard.pastePages() else { return }   // as above
        XCTAssertEqual(copied.pages.map { $0.page.id }, [s.design.pages[0].id, s.design.pages[2].id])
        XCTAssertEqual(copied.pages.map(\.width), [1000, 1000])
    }
}
