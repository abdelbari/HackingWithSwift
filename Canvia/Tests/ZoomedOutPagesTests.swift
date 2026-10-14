// Zoomed out over a long design (PageColumn.drawMode): the page worked is
// always live, and the others near the view are drawn as pictures when
// small on screen or among many in view, each picture made at a width
// bucket of its size on screen — the Android twin's Viewport tables.

import XCTest
import CoreGraphics
@testable import Canvia

final class ZoomedOutPagesTests: XCTestCase {

    func testDrawModeTable() {
        // Rows: page, worked page, page's width on screen, view's width,
        // pages in view → how the page is drawn.
        let rows: [(Int, Int, Double, Double, Int, PageColumn.DrawMode)] = [
            // The page worked is always live, however small and however many.
            (3, 3, 50, 1000, 30, .live),
            (0, 0, 349, 1000, 7, .live),
            // Wide enough and few enough in view: live.
            (1, 0, 900, 1000, 2, .live),
            (1, 0, 350, 1000, 6, .live),
            // Narrower than 0.35 of the view: a picture.
            (1, 0, 349, 1000, 2, .picture),
            (2, 0, 100, 1000, 1, .picture),
            // More than six in view: a picture, however wide.
            (1, 0, 900, 1000, 7, .picture),
            (5, 2, 400, 1000, 12, .picture),
        ]
        for row in rows {
            XCTAssertEqual(PageColumn.drawMode(pageIndex: row.0, workedIndex: row.1, pageScreenWidth: row.2,
                                               viewportWidth: row.3, inViewCount: row.4),
                           row.5, "\(row)")
        }
    }

    func testPictureWidthTable() {
        // Rows: the page's width on screen in pixels → the picture's width.
        let rows: [(Double, Int)] = [
            (1, 256),
            (200, 256),
            (256, 256),
            (257, 512),
            (512, 512),
            (513, 1024),
            (1024, 1024),
            (3000, 1024),
        ]
        for row in rows {
            XCTAssertEqual(PageColumn.pictureWidth(screenPixels: row.0), row.1, "\(row.0) px")
        }
    }

    /// Thirty pages zoomed out to a column a phone wide: all of them are in
    /// view, so every page but the one worked is a picture.
    func testAZoomedOutColumnDrawsPicturesButThePageWorked() {
        let slots = PageColumn.pageOrigins(Array(repeating: CGSize(width: 100, height: 100), count: 30),
                                           gap: 0, gutter: 0, viewportWidth: 100)
        let visible = CGRect(x: 0, y: 0, width: 3000, height: 3000)
        let inView = PageColumn.pages(slots, within: 0, of: visible)
        XCTAssertEqual(inView.count, 30)
        let live = PageColumn.livePages(slots, visible: visible).filter { i in
            PageColumn.drawMode(pageIndex: i, workedIndex: 4, pageScreenWidth: Double(slots[i].rect.width),
                                viewportWidth: Double(visible.width), inViewCount: inView.count) == .live
        }
        XCTAssertEqual(live, [4])
    }
}
