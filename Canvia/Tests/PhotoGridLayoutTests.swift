// Change layout, divider drags and Detach image: the shared tests, the
// Android twin's PhotoGridLayoutTest row for row, and the steps the store
// makes of them.

import XCTest
import CoreGraphics
@testable import Canvia

final class PhotoGridLayoutTests: XCTestCase {

    private func layout(_ id: String) throws -> PhotoGrids.Layout {
        try XCTUnwrap(PhotoGrids.layout(id), id)
    }

    /// A grid of `id` on a 1000 × 800 page, its cells filled with `pictures`.
    private func grid(_ id: String, _ pictures: String?...) throws -> [Element] {
        let cells = PhotoGrids.elements(for: try layout(id), width: 1000, height: 800, margin: 40, gutter: 20)
        return cells.enumerated().map { i, el in
            i < pictures.count ? pictures[i].map { Crop.replaced(el, src: $0) } ?? el : el
        }
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "grid", width: 1000, height: 800)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    private func json(_ el: Element) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
    }

    // MARK: the lattice

    func testALayoutKeepsItsLatticeAndItsOwnSplitsAreEven() throws {
        let l = try layout("onePlusTwo")
        XCTAssertEqual(l.columns, 5)
        XCTAssertEqual(l.rows, 2)
        XCTAssertEqual(l.lattice, [[0, 0, 3, 2], [3, 0, 2, 1], [3, 1, 2, 1]])
        XCTAssertEqual(PhotoGrids.ownSplits(l), GridSplits(x: [0.2, 0.4, 0.6, 0.8], y: [0.5]))
        XCTAssertEqual(PhotoGrids.unitCells(l, splits: nil), l.cells)
        XCTAssertEqual(PhotoGrids.layouts.count, 19)
    }

    func testADividerIsALatticeLineNoCellRunsAcross() throws {
        // 1 + 2: the line at 0.6 runs the full height; the row line is
        // crossed by the big cell, and the other column lines by every cell.
        XCTAssertEqual(PhotoGrids.dividers(try layout("onePlusTwo"), splits: nil),
                       [PhotoGrids.GridDivider(vertical: true, index: 2, at: 0.6)])
        // 2 by 2: one each way, both at the middle.
        XCTAssertEqual(PhotoGrids.dividers(try layout("four"), splits: nil),
                       [PhotoGrids.GridDivider(vertical: true, index: 0, at: 0.5),
                        PhotoGrids.GridDivider(vertical: false, index: 0, at: 0.5)])
        // 3 across: two vertical lines, no horizontal.
        XCTAssertEqual(PhotoGrids.dividers(try layout("three"), splits: nil).map(\.vertical), [true, true])
        // 1 over 3: the row line at 0.6 only.
        XCTAssertEqual(PhotoGrids.dividers(try layout("bigTop"), splits: nil),
                       [PhotoGrids.GridDivider(vertical: false, index: 2, at: 0.6)])
    }

    func testADraggedDividerIsHeldEightPercentOffItsNeighboursAndSnapsToTheMiddle() throws {
        let three = try layout("three")
        let first = PhotoGrids.dividers(three, splits: nil)[0]
        XCTAssertEqual(PhotoGrids.dragged(three, splits: nil, divider: first, to: 0.25),
                       GridSplits(x: [0.25, 2.0 / 3], y: []))
        // No nearer its neighbour than 8%: the next line stands at 2/3.
        XCTAssertEqual(try XCTUnwrap(PhotoGrids.dragged(three, splits: nil, divider: first, to: 0.9)).x[0],
                       2.0 / 3 - 0.08, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(PhotoGrids.dragged(three, splits: nil, divider: first, to: -1)).x[0], 0.08, accuracy: 1e-12)
        // Within 2% of the middle it is the middle.
        XCTAssertEqual(try XCTUnwrap(PhotoGrids.dragged(three, splits: nil, divider: first, to: 0.515)).x[0], 0.5)
        // Back at its own place, there are no custom splits.
        XCTAssertNil(PhotoGrids.dragged(three, splits: nil, divider: first, to: 1.0 / 3))
        // The cells follow the moved line.
        let moved = PhotoGrids.unitCells(three, splits: GridSplits(x: [0.25, 2.0 / 3], y: []))
        XCTAssertEqual(moved[0], CGRect(x: 0, y: 0, width: 0.25, height: 1))
        XCTAssertEqual(moved[1].minX, 0.25, accuracy: 1e-12)
        XCTAssertEqual(moved[1].width, 2.0 / 3 - 0.25, accuracy: 1e-12)
    }

    func testCustomSplitsLayTheGridOutAreWrittenOnlyWhenCustomAndReadBack() throws {
        let cells = try grid("four", "media:a", nil, "media:b")
        let four = try layout("four")
        let splits = GridSplits(x: [0.3], y: [0.5])
        let laid = PhotoGrids.relaid(four, cells: cells, gutter: 20, corners: 0, splits: splits)
        // The left column is 30% of the grid's width less half the gutter.
        let width = PhotoGrids.bounds(of: cells).width
        XCTAssertEqual(laid[0].w, width * 0.3 - 10, accuracy: 1e-9)
        XCTAssertEqual(laid[1].w, width * 0.7 - 10, accuracy: 1e-9)
        XCTAssertEqual(PhotoGrids.splits(of: laid), splits)
        let written = try XCTUnwrap(try json(laid[0])["grid"] as? [String: Any])
        let kept = try XCTUnwrap(written["splits"] as? [String: Any])
        XCTAssertEqual(kept["x"] as? [Double], [0.3])
        XCTAssertEqual(kept["y"] as? [Double], [0.5])
        // The pictures and their crops stay as they were.
        XCTAssertEqual(laid[0].src, "media:a")
        XCTAssertEqual(laid[0].cropScale, cells[0].cropScale)
        // Laid out again, the custom splits are kept; back at the layout's
        // own, the key goes.
        XCTAssertEqual(PhotoGrids.splits(of: PhotoGrids.relaid(four, cells: laid, gutter: 10, corners: 20)), splits)
        let even = PhotoGrids.relaid(four, cells: laid, gutter: 20, corners: 0, splits: PhotoGrids.ownSplits(four))
        XCTAssertNil(PhotoGrids.splits(of: even))
        XCTAssertNil(try XCTUnwrap(try json(even[0])["grid"] as? [String: Any])["splits"])
        // Through the file and back, and a grid from either phone reads the same.
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(laid[0]))
        XCTAssertEqual(back.grid?.splits, splits)
        // Splits that are not the lattice's size, or out of order, are the
        // layout's own.
        let wrong = ##"{"id":"c","type":"image","grid":{"id":"g","layout":"four","cell":0,"gutter":20,"margin":40,"splits":{"x":[0.3,0.2],"y":[0.5]}}}"##
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(wrong.utf8)).grid?.splits)
        let odd = ##"{"id":"c","type":"image","grid":{"id":"g","layout":"four","cell":0,"gutter":20,"margin":40,"splits":{"x":[0.3],"y":[]}}}"##
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(odd.utf8)).grid?.splits)
        let own = ##"{"id":"c","type":"image","grid":{"id":"g","layout":"four","cell":0,"gutter":20,"margin":40,"splits":{"x":[0.5],"y":[0.5]}}}"##
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(own.utf8)).grid?.splits, "the layout's own is no key")
    }

    // MARK: change layout

    func testChangeLayoutKeepsTheBoxGutterAndCornersHandsThePicturesOnInFillOrderAndKeepsTheCellIds() throws {
        let cells = try grid("two", "media:a", "media:b").map { el -> Element in
            var out = el
            out.radius = 20
            return out
        }
        let out = PhotoGrids.relayout(cells, to: try layout("bigTop"))
        XCTAssertEqual(out.count, 4)
        let grid = try XCTUnwrap(PhotoGrids.grid(of: out))
        XCTAssertEqual(grid.layout.id, "bigTop")
        XCTAssertEqual(PhotoGrids.bounds(of: out), PhotoGrids.bounds(of: cells))
        XCTAssertEqual(PhotoGrids.spacing(of: out), 20)
        XCTAssertEqual(PhotoGrids.corners(of: out), PhotoGrids.corners(of: cells), accuracy: 1e-9)
        XCTAssertTrue(out.allSatisfy { $0.group == cells[0].group })
        // The first cells are the old elements, so the selection survives.
        XCTAssertEqual(out[0].id, cells[0].id)
        XCTAssertEqual(out[1].id, cells[1].id)
        // The big cell comes first in fill order and takes picture a; the
        // first of the small ones b; the rest are empty.
        XCTAssertEqual(out[0].src, "media:a")
        XCTAssertEqual(out[1].src, "media:b")
        XCTAssertTrue(PhotoFrames.isEmpty(out[2]) && PhotoFrames.isEmpty(out[3]))
        XCTAssertEqual(out.map { $0.grid?.cell }, [0, 1, 2, 3])
        XCTAssertEqual(out[3].grid?.margin, 40)
        XCTAssertNil(out[3].grid?.splits)
    }

    func testPicturesASmallerLayoutHasNoCellForBecomeFreePhotosBesideTheGrid() throws {
        let cells = try grid("three", "media:a", "media:b", "media:c")
        let out = PhotoGrids.relayout(cells, to: try layout("twoStack"))
        XCTAssertEqual(out.count, 3)
        let grid = try XCTUnwrap(PhotoGrids.grid(of: Array(out.prefix(2))))
        XCTAssertEqual(grid.layout.id, "twoStack")
        XCTAssertEqual(out.prefix(2).map(\.src), ["media:a", "media:b"])
        // Unwrapped rather than subscripted: a relayout that lost the
        // picture once took the whole test run down with it here.
        let free = try XCTUnwrap(out.count > 2 ? out[2] : nil, "the third picture comes out free")
        XCTAssertEqual(free.src, "media:c")
        XCTAssertNil(free.group)
        XCTAssertNil(free.grid)
        XCTAssertEqual(free.x, PhotoGrids.bounds(of: cells).maxX + 20, accuracy: 1e-9)
        XCTAssertEqual(free.y, PhotoGrids.bounds(of: cells).minY, accuracy: 1e-9)
        XCTAssertEqual(free.w, cells[2].w, accuracy: 1e-9)
        for id in ["bigTop", "nine", "fourAcross"] {
            XCTAssertTrue(PhotoGrids.layoutsFor(4).contains { $0.id == id }, id)
        }
        XCTAssertFalse(PhotoGrids.layoutsFor(4).contains { $0.cells.count < 4 })
    }

    /// The Android twin's "a grid inside a group keeps its own level and
    /// the group's turn through a change of layout".
    func testAGridInsideAGroupKeepsItsOwnLevelAndTheGroupsTurnThroughAChangeOfLayout() throws {
        func nested(_ cells: [Element]) -> [Element] {
            cells.map { el in
                var out = Groups.withChain(el, ["outer"] + Groups.chain(el))
                out.groupTurn = 30
                return out
            }
        }
        let three = nested(try grid("three", "media:a", "media:b", "media:c"))
        let gid = try XCTUnwrap(three[0].grid?.id)
        let out = PhotoGrids.relayout(three, to: try layout("twoStack"))
        XCTAssertEqual(out.count, 3)
        XCTAssertTrue(out.prefix(2).allSatisfy { Groups.chain($0) == ["outer", gid] && $0.groupTurn == 30 })
        XCTAssertTrue(out.prefix(2).allSatisfy { $0.grid?.id == gid })
        // The picture left over leaves the grid but not the group round it.
        let free = try XCTUnwrap(out.count > 2 ? out[2] : nil)
        XCTAssertEqual(Groups.chain(free), ["outer"])
        XCTAssertEqual(free.groupTurn, 30)
        // New, empty cells are in both groups too.
        let two = nested(try grid("two", "media:a"))
        let twoId = try XCTUnwrap(two[0].grid?.id)
        let more = PhotoGrids.relayout(two, to: try layout("three"))
        XCTAssertTrue(more.allSatisfy { Groups.chain($0) == ["outer", twoId] && $0.groupTurn == 30 })
    }

    // MARK: detach

    func testDetachImageMakesThePictureAFreePhotoAtTheFramesBoxAndLeavesTheFrameEmpty() throws {
        let cells = try grid("two", "media:a", nil)
        var cropped = cells[0]
        cropped.cropScale = 1.5; cropped.cropX = 0.2; cropped.cropY = 0.7
        cropped.radius = 12; cropped.stroke = "#ffffff"; cropped.strokeWidth = 4
        let page = [Element.text("Title"), cropped, cells[1]]
        let out = try XCTUnwrap(PhotoFrames.detached(page, id: cropped.id))
        XCTAssertEqual(out.count, 4)
        let frame = out[1]
        let free = out[2]
        XCTAssertEqual(frame.id, cropped.id)
        XCTAssertTrue(PhotoFrames.isEmpty(frame))
        XCTAssertEqual(frame.group, cropped.group)
        XCTAssertEqual(free.src, "media:a")
        XCTAssertEqual(free.frame, cropped.frame)
        XCTAssertEqual(free.cropScale, 1.5)
        XCTAssertEqual(free.cropX, 0.2)
        XCTAssertEqual(free.radius, 12)
        XCTAssertEqual(free.stroke, "#ffffff")
        XCTAssertNil(free.group)
        XCTAssertNil(free.grid)
        XCTAssertNotEqual(free.id, cropped.id)
        // Nothing to detach from an empty frame, a plain photo or a locked one.
        XCTAssertNil(PhotoFrames.detached(page, id: cells[1].id))
        XCTAssertNil(PhotoFrames.detached([Element.image("media:z")], id: "x"))
        let plain = Element.image("media:z")
        XCTAssertNil(PhotoFrames.detached([plain], id: plain.id))
        var locked = cropped
        locked.locked = true
        XCTAssertNil(PhotoFrames.detached([page[0], locked, cells[1]], id: cropped.id))
        // A shaped frame's photo comes out of the shape.
        var shaped = Element.image("media:s")
        shaped.maskShapeId = "circle"
        let outOfShape = try XCTUnwrap(PhotoFrames.detached([shaped], id: shaped.id))
        XCTAssertNil(outOfShape[1].maskShapeId)
        XCTAssertEqual(outOfShape[0].maskShapeId, "circle")
        XCTAssertTrue(PhotoFrames.isEmpty(outOfShape[0]))
    }

    // MARK: the store

    func testChangingTheLayoutIsOneStepAndKeepsTheGridSelected() throws {
        let cells = try grid("two", "media:a", "media:b")
        let s = store([Element.text("Title")] + cells)
        s.selection = Set(cells.map(\.id))
        XCTAssertNotNil(s.selectedGrid)
        s.changeGridLayout(to: try layout("bigTop"))
        XCTAssertEqual(s.page.elements.count, 5)
        XCTAssertEqual(s.page.elements[0].text, "Title", "the cells stay where they stood in the stack")
        XCTAssertEqual(s.selectedGrid?.layout.id, "bigTop")
        XCTAssertEqual(s.selection.count, 4)
        s.undo()
        XCTAssertEqual(s.page.elements.count, 3)
        XCTAssertEqual(s.page.elements.compactMap { $0.grid?.layout }, ["two", "two"])
        // Its own layout again is nothing.
        s.selection = Set(cells.map(\.id))
        s.changeGridLayout(to: try layout("two"))
        XCTAssertFalse(s.canUndo || s.hasPendingChanges)
    }

    func testADividerDraggedOnTheCanvasLaysTheGridOutLiveAndClosesOnRelease() throws {
        let cells = try grid("three", "media:a", nil, nil)
        let s = store(cells)
        s.selection = Set(cells.map(\.id))
        XCTAssertEqual(s.gridDividers.count, 2)
        let box = try XCTUnwrap(s.selectedGridBox)
        // Within float noise: the divider is placed through the lattice's
        // fraction, which rounds a hair apart from box.width / 3.
        XCTAssertEqual(s.gridDividers[0].at.x, box.minX + box.width / 3, accuracy: 1e-9)
        XCTAssertEqual(s.gridDividers[0].at.y, box.midY, accuracy: 1e-9)
        XCTAssertEqual(s.dragGridDivider(0, to: 0.25), 0.25)
        XCTAssertTrue(s.hasPendingChanges)
        XCTAssertEqual(PhotoGrids.splits(of: s.selectedElements), GridSplits(x: [0.25, 2.0 / 3], y: []))
        XCTAssertEqual(PhotoGrids.bounds(of: s.selectedElements), box, "the box never creeps")
        s.commit()
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertNil(PhotoGrids.splits(of: s.selectedElements))
    }

    func testDetachImageIsOneStepAndSelectsThePhoto() throws {
        let cells = try grid("two", "media:a", nil)
        let s = store(cells)
        s.selection = [cells[0].id]
        XCTAssertTrue(s.canDetachImage)
        s.detachImage()
        XCTAssertEqual(s.page.elements.count, 3)
        let free = s.page.elements[1]
        XCTAssertEqual(free.src, "media:a")
        XCTAssertEqual(s.selection, [free.id])
        XCTAssertTrue(PhotoFrames.isEmpty(s.page.elements[0]))
        s.undo()
        XCTAssertEqual(s.page.elements.count, 2)
        s.selection = [cells[1].id]
        XCTAssertFalse(s.canDetachImage, "an empty frame has nothing to detach")
    }

    /// A locked page keeps its grid: Layout, a divider and Detach are
    /// refused and said, with Unlock.
    func testALockedPageRefusesEveryGridStep() throws {
        let cells = try grid("two", "media:a", "media:b")
        let s = store(cells)
        s.setPageLocked(true)
        s.selection = Set(cells.map(\.id))
        let before = s.page.elements
        s.changeGridLayout(to: try layout("bigTop"))
        XCTAssertEqual(s.page.elements, before)
        XCTAssertEqual(s.announcementUnlocks, s.page.id)
        XCTAssertNil(s.dragGridDivider(0, to: 0.3), "a locked page's grid cannot be laid out again")
        s.selection = [cells[0].id]
        s.detachImage()
        XCTAssertEqual(s.page.elements, before)
    }
}
