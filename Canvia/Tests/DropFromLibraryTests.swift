// Round 32's tiles dragged out of the Add sheet, with the rows the Android
// twin's DropFromLibraryTest holds too: where a carried photo, clip or
// graphic lands — a frame, the page, or nowhere — and the drop's one step.

import XCTest
import CoreGraphics
@testable import Canvia

final class DropFromLibraryTests: XCTestCase {

    private let page = CGSize(width: 1000, height: 800)

    /// An empty frame at (100, 100) 200 × 200, a filled grid's two cells
    /// at (500, 100) and (700, 100), 150 × 150, and a plain photo and a
    /// shape in the way.
    private func elements() -> [Element] {
        var frame = Element.image("asset:x", w: 200, h: 200)
        frame.id = "frame"
        frame.src = nil
        frame.x = 100; frame.y = 100
        var left = Element.image("asset:a", w: 150, h: 150)
        left.id = "cell1"
        left.x = 500; left.y = 100
        left.group = "grid"
        var right = left
        right.id = "cell2"
        right.x = 700
        var photo = Element.image("asset:b", w: 200, h: 200)
        photo.id = "photo"
        photo.x = 100; photo.y = 500
        var shape = Element.shape("rect", w: 100, h: 100)
        shape.id = "shape"
        shape.x = 400; shape.y = 500
        return [frame, left, right, photo, shape]
    }

    func testWhereAnItemLands() {
        typealias Row = (CGPoint, DropFromLibrary.Tile, DropFromLibrary.Landing)
        let rows: [Row] = [
            (CGPoint(x: 200, y: 200), .photo, .frame("frame")),
            (CGPoint(x: 200, y: 200), .clip, .frame("frame")),
            (CGPoint(x: 575, y: 175), .photo, .frame("cell1")),
            (CGPoint(x: 775, y: 175), .clip, .frame("cell2")),
            // A graphic, icon or sticker goes on the page, frame or not.
            (CGPoint(x: 200, y: 200), .sticker, .page),
            (CGPoint(x: 200, y: 200), .icon, .page),
            (CGPoint(x: 200, y: 200), .graphic, .page),
            (CGPoint(x: 200, y: 200), .svgGraphic, .page),
            // A free photo is no frame, nor is a shape.
            (CGPoint(x: 200, y: 600), .photo, .page),
            (CGPoint(x: 450, y: 550), .photo, .page),
            (CGPoint(x: 900, y: 700), .photo, .page),
            // The edges are the page's; past them, nowhere.
            (CGPoint(x: 0, y: 0), .photo, .page),
            (CGPoint(x: 1000, y: 800), .sticker, .page),
            (CGPoint(x: -1, y: 400), .photo, .none),
            (CGPoint(x: 500, y: 801), .icon, .none),
        ]
        for (point, kind, target) in rows {
            XCTAssertEqual(DropFromLibrary.target(point, elements: elements(), kind: kind, page: page), target,
                           "\(kind) at \(point)")
        }
        XCTAssertEqual(DropFromLibrary.holdSeconds, 0.35)
    }

    func testALockedFrameIsNoTarget() {
        var all = elements()
        all[0].locked = true
        XCTAssertEqual(DropFromLibrary.target(CGPoint(x: 200, y: 200), elements: all, kind: .photo, page: page), .page)
    }

    // MARK: the store

    private func store(locked: Bool = false) -> DesignStore {
        var d = Design(title: "drop", width: 1000, height: 800)
        var first = Page(id: "p1", elements: elements())
        first.locked = locked ? true : nil
        d.pages = [first, Page(id: "p2", elements: [])]
        return DesignStore(design: d)
    }

    private func sticker(_ s: DesignStore) -> LibraryDrag.Carried {
        LibraryDrag.Carried(kind: .sticker, src: nil) { point in
            s.add(.sticker("⭐", size: 100))
            s.moveAdded(to: point)
        }
    }

    func testADropIntoAFrameIsOneReplaceStep() {
        let s = store()
        let photo = LibraryDrag.Carried(kind: .photo, src: "asset:new", place: { _ in XCTFail("not on the page") })
        XCTAssertTrue(s.dropLibraryItem(photo, at: CGPoint(x: 200, y: 200), onPage: 0))
        XCTAssertEqual(s.element("frame")?.src, "asset:new")
        XCTAssertEqual(s.selection, ["frame"])
        XCTAssertEqual(s.undoLabel, "Replace")
    }

    func testADropOnThePageIsCentredAtTheFingerAndKeptOnIt() {
        let s = store()
        XCTAssertTrue(s.dropLibraryItem(sticker(s), at: CGPoint(x: 950, y: 400), onPage: 1))
        XCTAssertEqual(s.pageIndex, 1, "onto the page it was let go over")
        let added = s.selectedElements
        XCTAssertEqual(added.count, 1)
        XCTAssertEqual(added.first?.x ?? 0, 900, accuracy: 1e-9, "kept on the page")
        XCTAssertEqual(added.first?.y ?? 0, 350, accuracy: 1e-9)
        XCTAssertEqual(s.undoLabel, "Add")
        s.undo()
        XCTAssertTrue(s.page.elements.isEmpty, "one step")
    }

    func testALockedPageOrNowhereTakesNothing() {
        let locked = store(locked: true)
        XCTAssertFalse(locked.dropLibraryItem(sticker(locked), at: CGPoint(x: 500, y: 400), onPage: 0))
        XCTAssertNil(locked.undoLabel)
        let s = store()
        XCTAssertFalse(s.dropLibraryItem(sticker(s), at: CGPoint(x: -20, y: 400), onPage: 0))
        XCTAssertNil(s.undoLabel, "off the page: no step")
    }
}
