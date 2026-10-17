// Thumbnails kept for a page as it stands (ThumbnailCache), and made only
// for the pages of the column near the view.

import XCTest
import CoreGraphics
import UIKit
@testable import Canvia

final class ThumbnailCacheTests: XCTestCase {

    private func pages(_ ids: String) -> [Page] {
        ids.map { Page(id: String($0)) }
    }

    /// A kept thumbnail is for the page as it stands: any change to it, to
    /// the look made for it, or to its width, is another key.
    @MainActor
    func testAThumbnailIsKeptForThePageAsItStands() {
        var d = Design(title: "t", width: 400, height: 300)
        d.pages = pages("ab")
        let page = d.pages[0]
        let key = ThumbnailCache.key(page: page, design: d, baked: 0, subjects: 0, pixelWidth: 140)
        XCTAssertEqual(key, ThumbnailCache.key(page: page, design: d, baked: 0, subjects: 0, pixelWidth: 140))
        XCTAssertTrue(key.hasPrefix("a|"))
        var moved = page
        moved.elements = [Element.shape("rect")]
        XCTAssertNotEqual(key, ThumbnailCache.key(page: moved, design: d, baked: 0, subjects: 0, pixelWidth: 140))
        XCTAssertNotEqual(key, ThumbnailCache.key(page: page, design: d, baked: 1, subjects: 0, pixelWidth: 140))
        XCTAssertNotEqual(key, ThumbnailCache.key(page: page, design: d, baked: 0, subjects: 1, pixelWidth: 140))
        XCTAssertNotEqual(key, ThumbnailCache.key(page: page, design: d, baked: 0, subjects: 0, pixelWidth: 280))
    }

    /// A page's last thumbnail is found by its id alone, at whatever width
    /// it was made, so a view built on every frame of a pan never hashes
    /// the page for its first frame — and a page with none yet has none.
    @MainActor
    func testAPagesLastThumbnailIsFoundByItsIdAlone() async {
        var d = Design(title: "t", width: 400, height: 300)
        d.pages = pages("xy")
        let page = d.pages[0]
        XCTAssertNil(ThumbnailCache.shared.lastThumbnail(pageId: "x"))
        let key = ThumbnailCache.key(page: page, design: d, baked: 0, subjects: 0, pixelWidth: 140)
        let made = UIGraphicsImageRenderer(size: CGSize(width: 14, height: 10)).image { _ in }
        let got = await ThumbnailCache.shared.image(key, priority: 0) { made }
        XCTAssertTrue(got === made)
        XCTAssertTrue(ThumbnailCache.shared.lastThumbnail(pageId: "x") === made)
        XCTAssertNil(ThumbnailCache.shared.lastThumbnail(pageId: "y"))
        // Another width made since is the last, whatever the first's width.
        let wider = ThumbnailCache.key(page: page, design: d, baked: 0, subjects: 0, pixelWidth: 280)
        let big = UIGraphicsImageRenderer(size: CGSize(width: 28, height: 20)).image { _ in }
        _ = await ThumbnailCache.shared.image(wider, priority: 0) { big }
        XCTAssertTrue(ThumbnailCache.shared.lastThumbnail(pageId: "x") === big)
    }

    /// The column makes thumbnails within two viewport heights of the view,
    /// and draws live within one.
    func testTheColumnMakesThumbnailsOnlyNearTheView() {
        let slots = PageColumn.pageOrigins(Array(repeating: CGSize(width: 100, height: 100), count: 20),
                                           gap: 0, gutter: 0, viewportWidth: 100)
        let visible = CGRect(x: 0, y: 1000, width: 100, height: 100)
        let thumbs = PageColumn.thumbnailPages(slots, visible: visible)
        let live = PageColumn.livePages(slots, visible: visible)
        XCTAssertFalse(thumbs.isEmpty)
        XCTAssertTrue(Set(live).isSubset(of: Set(thumbs)))
        XCTAssertLessThan(thumbs.count, 20, "pages far off get none")
        XCTAssertFalse(thumbs.contains(0))
        XCTAssertTrue(PageColumn.pages(slots, within: 0, of: visible).allSatisfy(thumbs.contains))
    }
}
