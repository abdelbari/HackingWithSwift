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

    /// A code grouped with a logo is not a frame, so a picture let go over
    /// it cannot replace it, and the logo is not a cell for being with it.
    func testACodeGroupedWithALogoIsNotAFrame() {
        var code = photo(CodeGenerator.source(for: "https://example.com"))
        var logo = photo("asset:mesh-sunset", x: 120)
        code.group = "grp_1"; logo.group = "grp_1"
        let dragged = photo("asset:mesh-ocean", x: 400)
        let page = [code, logo, dragged]
        XCTAssertFalse(PhotoFrames.isFrameLike(code, among: page))
        XCTAssertFalse(PhotoFrames.isFrameLike(logo, among: page))
        XCTAssertNil(PhotoFrames.target(at: CGPoint(x: 50, y: 50), in: page, excluding: dragged.id))
        XCTAssertNil(PhotoFrames.dropped(page, dragged: dragged.id, onto: code.id, home: .zero))
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

    /// Pictures dropped from another app together on one cell: the first
    /// fills it, and the rest go on the page beside it rather than over it.
    func testACellADropHasFilledTakesNoMoreOfIt() {
        var a = photo("asset:mesh-ocean", w: 400, h: 400), b = photo("asset:mesh-candy", x: 500)
        a.group = "grp_1"; b.group = "grp_1"
        let page = [a, b]
        let at = CGPoint(x: 50, y: 50)
        XCTAssertEqual(CanvasDrop.pictureTarget(at: at, in: page, filled: [])?.id, a.id)
        XCTAssertNil(CanvasDrop.pictureTarget(at: at, in: page, filled: [a.id]))
        XCTAssertNil(CanvasDrop.pictureTarget(at: CGPoint(x: 450, y: 450), in: page, filled: []))
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

    // MARK: grid layouts — the same rows as the Android twin's PhotoFramesTest

    private func layout(_ id: String) throws -> PhotoGrids.Layout {
        try XCTUnwrap(PhotoGrids.layout(id), "no layout \(id)")
    }

    /// The x, y, w and h of each, to the thousandth.
    private func boxes(_ rects: [CGRect]) -> [[Double]] {
        rects.map { r in [r.minX, r.minY, r.width, r.height].map { (Double($0) * 1000).rounded() / 1000 } }
    }

    private func elementBoxes(_ elements: [Element]) -> [[Double]] {
        boxes(elements.map(\.frame))
    }

    func testTheGridsAreTheSharedFilesInItsOrder() throws {
        XCTAssertEqual(PhotoGrids.layouts.map(\.id), [
            "two", "three", "four", "onePlusTwo", "bigTop", "nine", "twoStack", "threeStack", "twoByThree", "threeByTwo",
            "oneLeftTwoRight", "oneRightTwoLeft", "twoOverOne", "bigLeftThree", "mosaicFive", "sixMixed", "fourAcross",
            "fourStack", "eightMixed",
        ])
        XCTAssertEqual(PhotoGrids.layouts.map(\.cells.count), [2, 3, 4, 3, 4, 9, 2, 3, 6, 6, 3, 3, 3, 4, 5, 6, 4, 4, 8])
        for layout in PhotoGrids.layouts {
            let area = layout.cells.reduce(0.0) { $0 + Double($1.width * $1.height) }
            XCTAssertEqual(area, 1, accuracy: 1e-9, "\(layout.id) leaves a gap or overlaps")
        }
        // The lattice gives the literal: 3/5 is 0.6 exactly.
        XCTAssertEqual(try layout("onePlusTwo").cells[0], CGRect(x: 0, y: 0, width: 0.6, height: 1))
        XCTAssertEqual(try layout("onePlusTwo").cells[2], CGRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5))
        XCTAssertEqual(try layout("eightMixed").cells[7], CGRect(x: 2 / 4.0, y: 2 / 3.0, width: 2 / 4.0, height: 1 / 3.0))
    }

    /// layout, box, gutter → each cell's x, y, w and h: half a gutter in
    /// from every inner edge, the outer edges on the box, nothing rounded.
    func testCellsAreLaidInTheirBoxHalfAGutterInFromEveryInnerEdge() throws {
        let rows: [(String, CGRect, Double, [[Double]])] = [
            ("twoOverOne", CGRect(x: 0, y: 0, width: 1000, height: 800), 20,
             [[0, 0, 490, 390], [510, 0, 490, 390], [0, 410, 1000, 390]]),
            ("threeStack", CGRect(x: 100, y: 50, width: 600, height: 900), 30,
             [[100, 50, 600, 285], [100, 365, 600, 270], [100, 665, 600, 285]]),
            ("oneLeftTwoRight", CGRect(x: 0, y: 0, width: 800, height: 800), 0,
             [[0, 0, 400, 800], [400, 0, 400, 400], [400, 400, 400, 400]]),
            ("mosaicFive", CGRect(x: 0, y: 0, width: 1200, height: 600), 40,
             [[0, 0, 580, 280], [620, 0, 580, 280], [0, 320, 380, 280], [420, 320, 360, 280], [820, 320, 380, 280]]),
        ]
        for (id, box, gutter, expected) in rows {
            XCTAssertEqual(boxes(PhotoGrids.frames(try layout(id), in: box, gutter: gutter)), expected, id)
        }
    }

    func testAGridsCellsCarryTheirGrid() throws {
        let cells = PhotoGrids.elements(for: try layout("twoOverOne"), width: 1080, height: 1080, margin: 43, gutter: 22)
        let group = try XCTUnwrap(cells[0].group)
        XCTAssertEqual(cells[0].grid, GridCell(id: group, layout: "twoOverOne", cell: 0, gutter: 22, margin: 43))
        XCTAssertEqual(cells.map { $0.grid?.cell }, [0, 1, 2])
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cells[1])) as? [String: Any]
        let grid = try XCTUnwrap(written?["grid"] as? [String: Any])
        XCTAssertEqual(grid["layout"] as? String, "twoOverOne")
        XCTAssertEqual(grid["cell"] as? Int, 1)
        XCTAssertEqual(grid["gutter"] as? Double, 22)
        XCTAssertEqual(grid["margin"] as? Double, 43)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(cells[1])), cells[1])
    }

    /// As the Android twin writes it — a whole number written with a point —
    /// and without its margin; one without a gutter is no grid.
    func testAGridKeyReadsAsTheAndroidTwinWritesIt() throws {
        let json = #"{"id":"a","type":"image","grid":{"id":"grp_a","layout":"two","cell":1.0,"gutter":20.0,"margin":40.0}}"#
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertEqual(el.grid, GridCell(id: "grp_a", layout: "two", cell: 1, gutter: 20, margin: 40))
        let noMargin = #"{"type":"image","grid":{"id":"g","layout":"two","cell":0,"gutter":8}}"#
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: Data(noMargin.utf8)).grid?.margin, 0)
        let noGutter = #"{"type":"image","grid":{"id":"g","layout":"two","cell":0}}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(noGutter.utf8)).grid)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Element())) as? [String: Any]
        XCTAssertNil(plain?["grid"], "no key on anything else")
    }

    func testSpacingIsOfferedForExactlyOneWholeGrid() throws {
        let three = try layout("three")
        let cells = PhotoGrids.elements(for: three, width: 1080, height: 1080, margin: 43, gutter: 22)
        let found = try XCTUnwrap(PhotoGrids.grid(of: cells.reversed()))
        XCTAssertEqual(found.layout.id, "three")
        XCTAssertEqual(found.cells.map(\.id), cells.map(\.id), "in cell order")
        XCTAssertNil(PhotoGrids.grid(of: Array(cells.dropFirst())), "a cell short")
        XCTAssertNil(PhotoGrids.grid(of: cells + [Element.shape("rect")]), "with something else")
        XCTAssertNil(PhotoGrids.grid(of: cells.map { var el = $0; el.group = nil; return el }), "ungrouped")
        let other = PhotoGrids.elements(for: three, width: 1080, height: 1080, margin: 43, gutter: 22)
        XCTAssertNil(PhotoGrids.grid(of: Array(cells.prefix(2)) + [other[2]]), "two grids' cells")
        // A grid made before `grid` was written has no key, and no Spacing.
        XCTAssertNil(PhotoGrids.grid(of: cells.map { var el = $0; el.grid = nil; return el }))
        XCTAssertNil(PhotoGrids.grid(of: cells.map { var el = $0; el.grid?.layout = "teapot"; return el }),
                     "a layout this build lacks")
    }

    func testSpacingAndCornersLayTheGridOutAgainInItsOwnBoxPicturesKept() throws {
        let twoOverOne = try layout("twoOverOne")
        let made = PhotoGrids.elements(for: twoOverOne, width: 1080, height: 1080, margin: 40, gutter: 20)
        // Moved and filled since.
        var cells = made.map { var el = $0; el.x += 100; return el }
        cells[1] = Crop.replaced(cells[1], src: "media:p")
        cells[1].cropScale = 1.5
        cells[1].cropX = 0.2
        cells[1].filter = "mono"
        let (grid, ordered) = try XCTUnwrap(PhotoGrids.grid(of: cells))
        let out = PhotoGrids.relaid(grid, cells: ordered, gutter: 0, corners: 50)
        // The box: 140…1140 across, 40…1040 down.
        XCTAssertEqual(elementBoxes(out), [[140, 40, 500, 500], [640, 40, 500, 500], [140, 540, 1000, 500]])
        // Half of each cell's own shorter side.
        XCTAssertEqual(out.map(\.radius), [250, 250, 250])
        XCTAssertEqual(out[1].src, "media:p")
        XCTAssertEqual(out[1].cropScale, 1.5)
        XCTAssertEqual(out[1].filter, "mono")
        XCTAssertEqual(PhotoGrids.spacing(of: out), 0)
        XCTAssertEqual(PhotoGrids.corners(of: out), 50, accuracy: 1e-9)
        XCTAssertEqual(out[0].grid?.margin, 40)
        // And back: the same box, so the same cells as at first, moved.
        let back = PhotoGrids.relaid(grid, cells: out, gutter: 20, corners: 0)
        XCTAssertEqual(elementBoxes(back), elementBoxes(cells))
        XCTAssertEqual(PhotoGrids.corners(of: back), 0)
        // Out of range is held to the tracks.
        let far = PhotoGrids.relaid(grid, cells: out, gutter: 99, corners: 99)
        XCTAssertEqual(PhotoGrids.spacing(of: far), PhotoGrids.maxSpacing)
        XCTAssertEqual(PhotoGrids.corners(of: far), PhotoGrids.maxCorners, accuracy: 1e-9)
    }

    /// A slider's drag and release is one Undo; a cell that keeps its place
    /// keeps the grid as it is.
    func testSpacingIsOneStepAndUndoes() throws {
        let cells = PhotoGrids.elements(for: try layout("two"), width: 1000, height: 1000, margin: 40, gutter: 20)
        let s = store(cells)
        s.select(cells[0].id)
        XCTAssertEqual(s.selection.count, 2, "a cell selects its grid")
        XCTAssertTrue(s.selectedGridCanRelay)
        s.setGridSpacingTransient(4)
        s.setGridSpacingTransient(10)
        s.commit()
        XCTAssertEqual(s.element(cells[0].id)?.grid?.gutter, 10)
        XCTAssertEqual(s.element(cells[1].id)?.x ?? 0, 505, accuracy: 1e-9)
        s.setGridCornersTransient(50)
        s.commit()
        XCTAssertEqual(s.element(cells[0].id)?.radius ?? 0, 227.5, accuracy: 1e-9)
        s.undo()
        XCTAssertEqual(s.element(cells[0].id)?.radius, 0)
        s.undo()
        XCTAssertEqual(s.element(cells[0].id)?.grid?.gutter, 20)
        XCTAssertEqual(s.element(cells[1].id)?.x, cells[1].x)
        XCTAssertFalse(s.canUndo)

        var held = cells
        held[1].lockPosition = true
        let pinned = store(held)
        pinned.selection = Set(held.map(\.id))
        XCTAssertNotNil(pinned.selectedGrid)
        XCTAssertFalse(pinned.selectedGridCanRelay)
        pinned.setGridSpacingTransient(0)
        XCTAssertFalse(pinned.hasPendingChanges)
    }

    // MARK: decorative frames — the same rows as the Android twin's

    func testTheDecorativeFramesAreTheSharedFilesEightEachWithOneWindow() {
        XCTAssertEqual(DecorativeFrames.presets.map(\.id),
                       ["polaroid", "filmStrip", "phone", "laptop", "browserWindow", "tornPaper", "circleStamp", "arch"])
        XCTAssertEqual(DecorativeFrames.presets.map(\.name),
                       ["Polaroid", "Film strip", "Phone", "Laptop", "Browser window", "Torn paper", "Circle stamp", "Arch"])
        for preset in DecorativeFrames.presets {
            let els = DecorativeFrames.elements(preset, page: CGSize(width: 1080, height: 1080))
            XCTAssertEqual(els.count, preset.parts.count, preset.id)
            XCTAssertEqual(els.filter { PhotoFrames.isEmpty($0) }.count, 1, preset.id)
            XCTAssertTrue(els.allSatisfy { $0.group != nil && $0.group == els[0].group }, preset.id)
            XCTAssertTrue(els.filter { $0.type == .shape }.allSatisfy { $0.pathData?.isEmpty == false }, preset.id)
        }
    }

    func testADecorativeFrameGoesOnAtMostSixTenthsOfThePageCentred() throws {
        let polaroid = try XCTUnwrap(DecorativeFrames.preset("polaroid"))
        XCTAssertEqual(polaroid.width, 600)
        XCTAssertEqual(polaroid.height, 720)
        // 1080 square: 648 / 720 = 0.9 is the smaller factor.
        let els = DecorativeFrames.elements(polaroid, page: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(els.count, 3)
        let card = els[0], window = els[1], caption = els[2]
        XCTAssertEqual(elementBoxes([card]), [[270, 216, 540, 648]])
        XCTAssertEqual(elementBoxes([window]), [[302.4, 248.4, 475.2, 475.2]])
        XCTAssertEqual(caption.text, "Good times")
        XCTAssertEqual(caption.fontSize ?? 0, 39.6, accuracy: 1e-9)
        XCTAssertEqual(caption.fontFamily, "script")
        XCTAssertEqual(card.strokeWidth ?? 0, 1.8, accuracy: 1e-9)
        XCTAssertEqual(card.stroke, "#e2e2e2")
        // A circle stamp's window is a circle frame.
        let stamp = DecorativeFrames.elements(try XCTUnwrap(DecorativeFrames.preset("circleStamp")),
                                              page: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(stamp.filter { $0.type == .image }.map(\.maskShapeId), ["circle"])
        // 1080 tall: 648 / 700 across a wide page.
        XCTAssertEqual(stamp[0].h, 648, accuracy: 1e-9)
        XCTAssertEqual(stamp[0].x, (1920 - 648) / 2, accuracy: 1e-9)
    }

    func testADecorativeFramesWindowTakesAPickedOrDroppedPhoto() throws {
        let els = DecorativeFrames.elements(try XCTUnwrap(DecorativeFrames.preset("phone")),
                                            page: CGSize(width: 1080, height: 1920))
        let window = try XCTUnwrap(els.first { $0.type == .image })
        XCTAssertEqual(PhotoFrames.fillOrder(els).map(\.id), [window.id])
        XCTAssertTrue(PhotoFrames.isFrameLike(window, among: els))
        let dropped = photo("media:x", x: 0, y: 0)
        let out = try XCTUnwrap(PhotoFrames.dropped(els + [dropped], dragged: dropped.id, onto: window.id, home: .zero))
        XCTAssertEqual(out.first { $0.id == window.id }?.src, "media:x")
    }

    /// Under the arch's mat, which is drawn over its window, a photo let go
    /// still finds the window.
    func testAPhotoFindsTheArchsWindowUnderItsMat() throws {
        let els = DecorativeFrames.elements(try XCTUnwrap(DecorativeFrames.preset("arch")),
                                            page: CGSize(width: 1000, height: 1000))
        let window = try XCTUnwrap(els.first { $0.type == .image })
        let free = photo("asset:mesh-sunset")
        let s = store(els + [free])
        XCTAssertEqual(s.frameDropTarget(at: window.center, dragging: free.id), window.id)
    }

    /// One odd value loses that element at most; a frame without a size is
    /// passed over.
    func testFrameJSONIsReadLeniently() throws {
        let json = """
        [{"id":"a","name":"A","width":100,"height":50,"elements":[
           {"type":"shape","x":0,"y":0,"w":100,"h":50,"pathData":"M0 0L100 0L100 100Z","fill":7},
           {"type":"image","x":"ten","y":5,"w":20,"h":20},
           {"type":"sprite","w":5,"h":5},
           {"type":"shape","w":5,"h":5},
           {"type":"text","w":50,"h":10}]},
         {"id":"b","name":"B","height":50,"elements":[]}]
        """
        let presets = try JSONDecoder().decode([FrameDef].self, from: Data(json.utf8))
        XCTAssertEqual(presets.map(\.isUsable), [true, false])
        let made = DecorativeFrames.elements(presets[0], page: CGSize(width: 1000, height: 500))
        XCTAssertEqual(made.map(\.type), [.shape, .image],
                       "an unknown kind, a shape with no path and a text with no words are left out")
        XCTAssertEqual(made[0].fill, Paint.solid("#000000"))
        XCTAssertEqual(made[1].x, 200, accuracy: 1e-9, "an unreadable x is 0, within the centred frame")
    }
}
