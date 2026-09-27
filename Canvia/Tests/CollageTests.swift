// Photos into frames and grid cells: what counts as a frame, which one a
// finger is over, what a drop does to both photos, and the order picked
// photos fill a grid in — the rules the Android twin shares.

import XCTest
@testable import Canvia

final class CollageTests: XCTestCase {

    // MARK: fixtures

    private func photo(_ src: String?, x: Double = 0, y: Double = 0, w: Double = 100, h: Double = 100) -> Element {
        var el = Element.image(src ?? "", w: w, h: h)
        el.src = src
        el.x = x
        el.y = y
        return el
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "collage", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    // MARK: what a frame is

    func testAPlainFreePhotoIsNotAFrame() {
        let free = photo("asset:mesh-sunset")
        XCTAssertFalse(PhotoFrames.isFrameLike(free, among: [free]))
    }

    func testEmptyFramesShapedPhotosAndGridCellsAreFrames() {
        let empty = photo(nil)
        var shaped = photo("asset:mesh-sunset")
        shaped.maskShapeId = "circle"
        var a = photo("asset:mesh-ocean"), b = photo("asset:mesh-candy")
        a.group = "grp_1"; b.group = "grp_1"
        let page = [empty, shaped, a, b]
        XCTAssertTrue(PhotoFrames.isFrameLike(empty, among: page))
        XCTAssertTrue(PhotoFrames.isFrameLike(shaped, among: page))
        XCTAssertTrue(PhotoFrames.isFrameLike(a, among: page), "a photo grouped with another is a grid's cell")
        XCTAssertTrue(PhotoFrames.isFrameLike(b, among: page))
    }

    /// Grouped with a caption is not a grid: it takes another image.
    func testAPhotoGroupedOnlyWithTextIsNotACell() {
        var a = photo("asset:mesh-ocean")
        var caption = Element.text("Hello")
        a.group = "grp_1"; caption.group = "grp_1"
        XCTAssertFalse(PhotoFrames.isFrameLike(a, among: [a, caption]))
    }

    func testALockedFrameOrAShapeIsNotAFrame() {
        var locked = photo(nil)
        locked.locked = true
        let shape = Element.shape("rect")
        XCTAssertFalse(PhotoFrames.isFrameLike(locked, among: [locked]))
        XCTAssertFalse(PhotoFrames.isFrameLike(shape, among: [shape]))
    }

    /// A code is used whole, and an empty frame has nothing to give.
    func testOnlyAPhotoOrAClipCanBeDroppedIntoAFrame() {
        XCTAssertTrue(PhotoFrames.canDrop(photo("asset:mesh-sunset")))
        XCTAssertTrue(PhotoFrames.canDrop(photo("video:vid_1")))
        XCTAssertFalse(PhotoFrames.canDrop(photo(CodeGenerator.source(for: "https://example.com"))))
        XCTAssertFalse(PhotoFrames.canDrop(photo(nil)))
        var locked = photo("asset:mesh-sunset")
        locked.locked = true
        XCTAssertFalse(PhotoFrames.canDrop(locked))
    }

    // MARK: which frame

    func testTheTopmostFrameUnderTheFingerNeverTheDraggedOne() {
        let lower = photo(nil, x: 0, y: 0, w: 200, h: 200)
        let upper = photo(nil, x: 50, y: 50, w: 100, h: 100)
        let dragged = photo("asset:mesh-sunset", x: 60, y: 60)
        let page = [lower, upper, dragged]
        let at = CGPoint(x: 100, y: 100)
        XCTAssertEqual(PhotoFrames.target(at: at, in: page, excluding: dragged.id)?.id, upper.id)
        XCTAssertEqual(PhotoFrames.target(at: CGPoint(x: 20, y: 20), in: page, excluding: dragged.id)?.id, lower.id)
        XCTAssertNil(PhotoFrames.target(at: CGPoint(x: 600, y: 600), in: page, excluding: dragged.id))
        // A free photo under the finger is passed over for the frame below.
        let free = photo("asset:mesh-ocean", x: 90, y: 90, w: 30, h: 30)
        XCTAssertEqual(PhotoFrames.target(at: at, in: [upper, free], excluding: nil)?.id, upper.id)
    }

    // MARK: dropping

    func testReplacedResetsTheCropAndLevelButKeepsTheFrame() {
        var el = photo("asset:mesh-sunset", x: 10, y: 20, w: 300, h: 200)
        el.cropScale = 2.5; el.cropX = 0.1; el.cropY = 0.9
        el.straighten = 12
        el.radius = 24
        el.maskShapeId = "heart"
        el.filter = "noir"
        let out = Crop.replaced(el, src: "asset:mesh-ocean")
        XCTAssertEqual(out.src, "asset:mesh-ocean")
        XCTAssertEqual(out.cropScale, 1)
        XCTAssertEqual(out.cropX, 0.5)
        XCTAssertEqual(out.cropY, 0.5)
        XCTAssertNil(out.straighten)
        XCTAssertEqual(out.frame, el.frame)
        XCTAssertEqual(out.radius, 24)
        XCTAssertEqual(out.maskShapeId, "heart")
        XCTAssertEqual(out.filter, "noir")
        XCTAssertNil(Crop.replaced(el, src: nil).src)
    }

    /// A free photo let go over a frame goes into it and is used up; the
    /// move and the drop are one Undo, felt, and the frame ends selected.
    func testAFreePhotoDroppedIntoAFrameFillsItAsOneStep() {
        let frame = photo(nil, x: 0, y: 0, w: 400, h: 400)
        var free = photo("asset:mesh-sunset", x: 600, y: 600)
        free.cropScale = 3
        let s = store([frame, free])
        s.selection = [free.id]
        s.beginGesture()
        s.design.pages[0].elements[1].x = 150   // the drag, on its way
        XCTAssertTrue(s.dropIntoFrame(free.id, onto: frame.id, home: CGPoint(x: 600, y: 600)))
        XCTAssertEqual(s.page.elements.count, 1)
        XCTAssertEqual(s.page.elements[0].src, "asset:mesh-sunset")
        XCTAssertEqual(s.page.elements[0].cropScale, 1, "the frame's crop is reset, not the photo's taken")
        XCTAssertEqual(s.selection, [frame.id])
        XCTAssertEqual(s.haptic.kind, .confirm)
        s.undo()
        XCTAssertEqual(s.page.elements.count, 2)
        XCTAssertNil(s.page.elements[0].src)
        XCTAssertEqual(s.page.elements[1].x, 600, "one Undo takes back the move and the drop")
        XCTAssertFalse(s.canUndo)
    }

    /// Two cells trade pictures, and the dragged one goes back where it was.
    func testTwoCellsSwapAndTheDraggedOneGoesHome() {
        let cells = PhotoGrids.elements(for: PhotoGrids.layouts[0], width: 1000, height: 1000, margin: 40, gutter: 20)
        var a = cells[0], b = cells[1]
        a.src = "asset:mesh-sunset"; a.cropX = 0.2
        b.src = "asset:mesh-ocean"
        let s = store([a, b])
        s.selection = [a.id]
        s.beginGesture()
        s.design.pages[0].elements[0].x = b.x + 30
        XCTAssertTrue(s.dropIntoFrame(a.id, onto: b.id, home: CGPoint(x: a.x, y: a.y)))
        let movedA = s.element(a.id), movedB = s.element(b.id)
        XCTAssertEqual(movedA?.src, "asset:mesh-ocean")
        XCTAssertEqual(movedB?.src, "asset:mesh-sunset")
        XCTAssertEqual(movedA?.frame, a.frame, "the dragged cell goes home")
        XCTAssertEqual(movedA?.cropX, 0.5)
        XCTAssertEqual(movedA?.group, a.group)
    }

    /// A cell dropped on an empty frame gives its picture and is left empty.
    func testACellDroppedOnAnEmptyFrameIsLeftEmpty() {
        var shaped = photo("asset:mesh-sunset", x: 500, y: 500)
        shaped.maskShapeId = "circle"
        let empty = photo(nil)
        let s = store([empty, shaped])
        XCTAssertTrue(s.dropIntoFrame(shaped.id, onto: empty.id, home: CGPoint(x: 500, y: 500)))
        XCTAssertEqual(s.element(empty.id)?.src, "asset:mesh-sunset")
        XCTAssertNotNil(s.element(shaped.id), "a frame is never used up")
        XCTAssertNil(s.element(shaped.id)?.src)
    }

    /// Over a free photo, or dragging a code, it is an ordinary move.
    func testNoDropOntoAFreePhotoOrWithACode() {
        let free = photo("asset:mesh-ocean")
        let dragged = photo("asset:mesh-sunset", x: 20, y: 20)
        let code = photo(CodeGenerator.source(for: "hello"), x: 40, y: 40)
        let empty = photo(nil, x: 300, y: 300)
        let s = store([free, dragged, code, empty])
        XCTAssertNil(s.frameDropTarget(at: CGPoint(x: 50, y: 50), dragging: dragged.id))
        XCTAssertFalse(s.dropIntoFrame(dragged.id, onto: free.id, home: .zero))
        XCTAssertNil(s.frameDropTarget(at: CGPoint(x: 350, y: 350), dragging: code.id))
        XCTAssertEqual(s.frameDropTarget(at: CGPoint(x: 350, y: 350), dragging: dragged.id), empty.id)
        XCTAssertFalse(s.canUndo)
    }

    // MARK: picking

    /// Picked photos fill a selected grid's empty cells top to bottom, then
    /// left to right; cells already filled are passed over.
    func testPickedPhotosFillAGridsEmptyCellsInReadingOrder() throws {
        let layout = try XCTUnwrap(PhotoGrids.layouts.first { $0.id == "onePlusTwo" })
        var cells = PhotoGrids.elements(for: layout, width: 1000, height: 1000, margin: 40, gutter: 20)
        // Laid out big-left, then top-right, bottom-right; shuffled on the
        // page, as layers get.
        cells.swapAt(0, 2)
        let s = store(cells)
        s.select(cells[0].id)   // takes the whole grid
        XCTAssertEqual(s.selection.count, 3)
        let order = s.framesToFill.compactMap { id in s.element(id) }
        XCTAssertEqual(order.map(\.center.y), order.map(\.center.y).sorted())
        // The top-right cell's centre is highest; the big left one next.
        XCTAssertEqual(order.first?.x, order.last?.x)
        XCTAssertLessThan(order[1].x, order[0].x)

        XCTAssertTrue(s.replacePicture(order[0].id, with: "asset:mesh-sunset"))
        XCTAssertEqual(s.framesToFill, [order[1].id, order[2].id])
    }

    func testOneSelectedEmptyFrameIsFilledAndAFullOneIsNot() {
        let empty = photo(nil)
        let full = photo("asset:mesh-sunset", x: 200)
        let s = store([empty, full])
        s.selection = [empty.id]
        XCTAssertEqual(s.framesToFill, [empty.id])
        s.selection = [full.id]
        XCTAssertTrue(s.framesToFill.isEmpty)
    }

    /// A clip may fill a frame, as a photo may.
    func testAClipFillsAFrame() {
        let empty = photo(nil)
        let s = store([empty])
        XCTAssertTrue(s.replacePicture(empty.id, with: "video:vid_1"))
        XCTAssertEqual(s.element(empty.id)?.src, "video:vid_1")
    }

    func testALockedPhotoIsNotReplaced() {
        var locked = photo("asset:mesh-sunset")
        locked.locked = true
        let s = store([locked])
        XCTAssertFalse(s.replacePicture(locked.id, with: "asset:mesh-ocean"))
        XCTAssertEqual(s.element(locked.id)?.src, "asset:mesh-sunset")
        XCTAssertEqual(s.haptic.kind, .reject)
        XCTAssertFalse(s.canUndo)
    }
}
