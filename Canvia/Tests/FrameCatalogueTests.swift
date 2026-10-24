// The wider frames and grids catalogue, row for row with the Android twin's
// FrameCatalogueTest: thirty mask frames from the shared PhotoFrames.json
// clipping a photo through "mask:<id>", twelve more decorative frames, and
// twelve more grids — mosaics, bricks and cut cells whose clip is a polygon.

import XCTest
@testable import Canvia

final class FrameCatalogueTests: XCTestCase {

    private func photo(_ src: String?, x: Double = 0, y: Double = 0, w: Double = 100, h: Double = 100) -> Element {
        var el = Element()
        el.type = .image
        el.src = src
        el.x = x; el.y = y; el.w = w; el.h = h
        return el
    }

    // MARK: masks

    func testThirtyMasksInSixCategoriesEachAPathInTheUnitSquare() throws {
        let masks = MaskFrames.all
        XCTAssertEqual(masks.count, 30)
        XCTAssertEqual(MaskFrames.categories, ["brush", "torn", "blob", "arch", "badge", "ticket"])
        XCTAssertEqual(MaskFrames.categories.map { c in masks.filter { $0.category == c }.count }, [6, 5, 6, 4, 6, 3])
        XCTAssertEqual(Set(masks.map(\.id)).count, 30)
        for mask in masks {
            XCTAssertTrue(mask.id.hasPrefix("mask:"), mask.id)
            XCTAssertNotNil(ContentLibrary.frameShape(mask.id), mask.id)
            // Scaled to the library's 0…100 box.
            let numbers = mask.shape.path.split { !($0.isNumber || $0 == "." || $0 == "-") }.compactMap { Double($0) }
            XCTAssertFalse(numbers.isEmpty, mask.id)
            XCTAssertTrue(numbers.allSatisfy { (0...100).contains($0) }, mask.id)
            XCTAssertFalse(SVGPath.path(mask.shape.path).boundingBoxOfPath.isEmpty, mask.id)
        }
        XCTAssertEqual(masks.filter { $0.fillRule == "evenodd" }.map(\.id), ["mask:badge-ring"])
        XCTAssertEqual(MaskFrames.mask("mask:blob-pebble")?.fillRule, "nonzero")
        // The file's raw entries keep the unit square.
        let raw = try XCTUnwrap(PhotoGrids.file.photoMasks?.first?.path)
        XCTAssertTrue(raw.hasPrefix("M0."), raw)
    }

    func testAMaskPathIsScaledAndTheFileIsReadLeniently() throws {
        XCTAssertEqual(MaskFrames.scaled("M0 0L1 0.5C0.25 0.125 0.5 1 0 1Z"), "M0 0L100 50C25 12.5 50 100 0 100Z")
        let json = """
        [{"id":"a","name":"A","category":"blob","path":"M0 0L1 0L1 1Z","fillRule":"evenodd"},
         {"id":"b","name":"B","category":"clouds","path":"M0 0L1 1Z"},
         {"name":"C","category":"blob","path":"M0 0Z"},
         {"id":"d","name":"D","category":"torn","path":"M0 0L1 1L0 1Z","fillRule":"odd"}]
        """
        let read = MaskFrames.parse(try JSONDecoder().decode([MaskFrameDef].self, from: Data(json.utf8)))
        XCTAssertEqual(read.map(\.id), ["mask:a", "mask:d"], "an unknown category or a missing id is left out")
        XCTAssertEqual(read.map(\.fillRule), ["evenodd", "nonzero"])
        XCTAssertEqual(read[0].shape.path, "M0 0L100 0L100 100Z")
        XCTAssertEqual(MaskFrames.filter(read, category: "torn", query: "").map(\.id), ["mask:d"])
        XCTAssertEqual(MaskFrames.filter(MaskFrames.all, category: nil, query: "TICKET").map(\.id),
                       ["mask:ticket-notched", "mask:ticket-corners", "mask:ticket-coupon"], "by category or name")
        XCTAssertEqual(MaskFrames.filter(MaskFrames.all, category: "badge", query: "ring").map(\.id), ["mask:badge-ring"])
    }

    func testAMaskFrameIsAFrameThatTakesADropAndADetach() throws {
        let mask = try XCTUnwrap(MaskFrames.mask("mask:blob-cloud"))
        let frame = MaskFrames.element(mask, page: CGSize(width: 1080, height: 1920))
        XCTAssertEqual([frame.x, frame.y, frame.w, frame.h], [270, 690, 540, 540])
        XCTAssertEqual(frame.maskShapeId, "mask:blob-cloud")
        XCTAssertTrue(PhotoFrames.isEmpty(frame))
        XCTAssertTrue(PhotoFrames.isFrameLike(frame, among: [frame]))
        let free = photo("media:x", x: 2000)
        let dropped = try XCTUnwrap(PhotoFrames.dropped([frame, free], dragged: free.id, onto: frame.id, home: .zero))
        let filled = try XCTUnwrap(dropped.first { $0.id == frame.id })
        XCTAssertEqual(filled.src, "media:x")
        XCTAssertEqual(filled.maskShapeId, "mask:blob-cloud")
        let detached = try XCTUnwrap(PhotoFrames.detached(dropped, id: frame.id))
        XCTAssertEqual(detached.count, 2)
        XCTAssertNil(detached[1].maskShapeId)
        // Written as the frame's own key, as every frame's is.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(frame)) as? [String: Any])
        XCTAssertEqual(json["maskShapeId"] as? String, "mask:blob-cloud")
        XCTAssertEqual(ElementNames.name(of: frame), tr("Empty %@ frame", tr("Cloud blob")))
    }

    // MARK: grids

    func testCutGridsCarryAClipACellAndNoDividers() throws {
        let cut = PhotoGrids.layouts.filter(\.isCut).map(\.id)
        XCTAssertEqual(cut, ["threeCircles", "diagonalTwo", "diagonalTwoBack", "slantedTwo", "slantedThree", "diagonalFour"])
        let two = try XCTUnwrap(PhotoGrids.layout("diagonalTwo"))
        XCTAssertEqual(two.cells, [CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 0, y: 0, width: 1, height: 1)])
        XCTAssertEqual(two.clips[0], [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1)])
        XCTAssertEqual(PhotoGrids.dividers(two, splits: nil), [])
        XCTAssertEqual(PhotoGrids.dividers(try XCTUnwrap(PhotoGrids.layout("slantedTwo")), splits: nil), [])
        XCTAssertFalse(try XCTUnwrap(PhotoGrids.layout("brick")).isCut)

        // The cut is read from the cell's grid key and never written, as on
        // the Android twin; a frame of the cell's own wins over it.
        let cells = PhotoGrids.elements(for: two, width: 1000, height: 1000, margin: 40, gutter: 20)
        XCTAssertEqual(cells.map(\.maskShapeId), [nil, nil])
        XCTAssertEqual(PhotoGrids.clipShape(of: cells[0])?.path, "M0 0L100 0L0 100Z")
        XCTAssertEqual(ContentLibrary.frameShape(of: cells[1])?.path, "M100 0L100 100L0 100Z")
        XCTAssertEqual(ContentLibrary.frameShape(of: cells[1])?.id, "grid:diagonalTwo:1")
        var framed = cells[0]
        framed.maskShapeId = "circle"
        XCTAssertNil(PhotoGrids.clip(of: framed))
        XCTAssertEqual(ContentLibrary.frameShape(of: framed)?.id, "circle")
        let nine = PhotoGrids.elements(for: try XCTUnwrap(PhotoGrids.layout("nine")), width: 1000, height: 1000, margin: 40, gutter: 20)
        XCTAssertNil(PhotoGrids.clip(of: nine[0]), "a cell that is not cut has no clip")
        XCTAssertEqual(ElementNames.name(of: cells[0]), tr("Empty photo frame"))

        // The cell under the finger is the one whose cut is there: the top
        // left half picks the first, the bottom right the second.
        let topLeft = CGPoint(x: 200, y: 200), bottomRight = CGPoint(x: 800, y: 800)
        XCTAssertEqual(cells.last { Geometry.hits($0, point: topLeft) }?.id, cells[0].id)
        XCTAssertEqual(cells.last { Geometry.hits($0, point: bottomRight) }?.id, cells[1].id)
        XCTAssertEqual(PhotoFrames.target(at: topLeft, in: cells, excluding: nil)?.id, cells[0].id)
    }

    func testARelayoutHandsTheCutToTheNewCells() throws {
        let four = try XCTUnwrap(PhotoGrids.layout("four"))
        var cells = PhotoGrids.elements(for: four, width: 1000, height: 1000, margin: 40, gutter: 20)
        cells[0].src = "media:a"
        cells[1].src = "media:b"
        let cut = try XCTUnwrap(PhotoGrids.layout("diagonalTwo"))
        let moved = PhotoGrids.relayout(cells, to: cut)
        XCTAssertTrue(moved.prefix(2).allSatisfy { $0.maskShapeId == nil && PhotoGrids.clip(of: $0) != nil })
        XCTAssertEqual(moved.prefix(2).compactMap(\.src).sorted(), ["media:a", "media:b"])
        let back = PhotoGrids.relayout(Array(moved.prefix(2)), to: four)
        XCTAssertTrue(back.allSatisfy { PhotoGrids.clip(of: $0) == nil }, "out of a cut layout, no cut left")
    }

    func testTheNewMosaicsTileTheirArea() throws {
        for id in ["mosaicFiveBig", "mosaicSix", "mosaicSeven", "mosaicNine", "brick", "brickWall"] {
            let layout = try XCTUnwrap(PhotoGrids.layout(id), id)
            let area = layout.cells.reduce(0.0) { $0 + Double($1.width * $1.height) }
            XCTAssertEqual(area, 1, accuracy: 1e-9, id)
            XCTAssertTrue(layout.clips.isEmpty, id)
        }
        XCTAssertEqual(try XCTUnwrap(PhotoGrids.layout("mosaicNine")).cells.count, 9)
    }
}
