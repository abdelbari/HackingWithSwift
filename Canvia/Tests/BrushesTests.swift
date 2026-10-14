// The Erase and Restore brush and the blur and pixelate brushes: the mask
// and retouch strokes painted into a grid (MaskRaster), in rows written for
// both phones alike; the `mask` and `retouch` keys as both phones write
// them; and a brush session, one undo step.

import XCTest
import CoreGraphics
@testable import Canvia

final class BrushesTests: XCTestCase {

    private func stroke(_ mode: String, _ w: Double, _ soft: Double, _ pts: [(Double, Double)]) -> MaskStroke {
        MaskStroke(mode: mode, w: w, soft: soft, points: pts.map { CGPoint(x: $0.0, y: $0.1) })
    }

    /// Each row: the strokes, the grid, and the alpha at points of it —
    /// shares across and down, each in the middle of a cell.
    private func assertAlphas(_ strokes: [MaskStroke], width: Int = 100, height: Int = 100, start: Float = 1,
                              _ expected: [((Double, Double), Float)], file: StaticString = #filePath,
                              line: UInt = #line) {
        let grid = MaskRaster.raster(strokes, width: width, height: height, start: start, initial: nil)
        XCTAssertEqual(grid.count, width * height, file: file, line: line)
        for (at, alpha) in expected {
            let got = MaskRaster.sample(grid, width: width, height: height, x: at.0, y: at.1)
            XCTAssertEqual(got, alpha, accuracy: 1e-4, "at \(at)", file: file, line: line)
        }
    }

    // MARK: the shared rows

    /// The Android twin's rows (MaskRasterTest), number for number: a
    /// stroke list, a picture's shape (width over height), and the mask's
    /// alpha at points of it, shares across and down.
    private var maskRows: [(name: String, aspect: Double, strokes: [MaskStroke], samples: [(Double, Double, Double)])] {
        [
            // A hard line across a 2:1 picture: 0.2 of the shorter side wide.
            ("hard line", 2, [stroke("erase", 0.2, 0, [(0.25, 0.5), (0.75, 0.5)])],
             [(0.5, 0.5, 0), (0.5, 0.55, 0), (0.5, 0.65, 1), (0.22, 0.5, 0), (0.1, 0.5, 1)]),
            // Restore paints a dot of the picture back in the middle of it.
            ("erase then restore", 2,
             [stroke("erase", 0.2, 0, [(0.25, 0.5), (0.75, 0.5)]), stroke("restore", 0.1, 0, [(0.5, 0.5)])],
             [(0.5, 0.5, 1), (0.52, 0.5, 1), (0.5, 0.56, 0), (0.3, 0.5, 0)]),
            // Fully soft: the edge fades over the whole half-width.
            ("soft dot", 2, [stroke("erase", 0.2, 1, [(0.5, 0.5)])],
             [(0.5, 0.5, 0), (0.525, 0.5, 0.5), (0.5, 0.575, 0.75), (0.5, 0.7, 1)]),
            // Half soft: solid to half the half-width, then fading.
            ("half-soft dot", 1, [stroke("erase", 0.2, 0.5, [(0.5, 0.5)])],
             [(0.54, 0.5, 0), (0.575, 0.5, 0.5), (0.5, 0.61, 1)]),
            // Two soft strokes over each other take away a share each.
            ("soft twice", 1, [stroke("erase", 0.2, 1, [(0.5, 0.5)]), stroke("erase", 0.2, 1, [(0.5, 0.5)])],
             [(0.55, 0.5, 0.25), (0.5, 0.5, 0)]),
            // A tall picture: down is the longer way.
            ("tall picture", 0.5, [stroke("erase", 0.1, 0, [(0.5, 0.25)])],
             [(0.5, 0.26, 0), (0.5, 0.3, 1), (0.54, 0.25, 0), (0.56, 0.25, 1)]),
            // No strokes is the whole picture.
            ("none", 1.5, [], [(0.5, 0.5, 1)]),
        ]
    }

    func testSharedRowsTheMaskAtSamplePoints() {
        for row in maskRows {
            for (x, y, alpha) in row.samples {
                XCTAssertEqual(MaskRaster.alpha(row.strokes, aspect: row.aspect, x: x, y: y), alpha, accuracy: 1e-9,
                               "\(row.name) at \(x), \(y)")
            }
        }
    }

    func testSharedRowsARetouchLayersCoverAtSamplePoints() {
        // Feathered by a quarter of the width: solid to 0.05, gone at 0.1.
        let paint = RetouchStroke(w: 0.2, points: [CGPoint(x: 0.5, y: 0.5)])
        let rows: [(String, [RetouchStroke], [(Double, Double, Double)])] = [
            ("painted", [paint], [(0.5, 0.5, 1), (0.575, 0.5, 0.5), (0.62, 0.5, 0)]),
            ("taken off in the middle", [paint, RetouchStroke(w: 0.1, points: [CGPoint(x: 0.5, y: 0.5)], erases: true)],
             [(0.5, 0.5, 0), (0.575, 0.5, 0.5)]),
            ("none", [], [(0.5, 0.5, 0)]),
        ]
        for (name, strokes, samples) in rows {
            for (x, y, cover) in samples {
                XCTAssertEqual(MaskRaster.effect(strokes, aspect: 1, x: x, y: y), cover, accuracy: 1e-9,
                               "\(name) at \(x), \(y)")
            }
        }
    }

    func testTheGridIsThePictureUpTo1024OnItsLongerSide() {
        let rows: [((Double, Double), (Int, Int))] = [
            ((4000, 3000), (1024, 768)), ((100, 50), (100, 50)), ((3000, 4000), (768, 1024)),
            ((2048, 1), (1024, 1)), ((1500, 1500), (1024, 1024)), ((0, 10), (1, 1)),
            ((4000, 2000), (1024, 512)), ((300, 200), (300, 200)), ((1, 5000), (1, 1024)),
        ]
        for (picture, grid) in rows {
            let made = MaskRaster.gridSize(width: picture.0, height: picture.1)
            XCTAssertEqual(made.width, grid.0, "\(picture)")
            XCTAssertEqual(made.height, grid.1, "\(picture)")
        }
        // Painted into a grid, a cell is the mask at its centre.
        let strokes = maskRows[0].strokes
        let grid = MaskRaster.raster(strokes, width: 200, height: 100, start: 1, initial: nil)
        for y in [10, 45, 50, 64, 70] {
            for x in [20, 44, 100, 150] {
                let want = MaskRaster.alpha(strokes, aspect: 2, x: (Double(x) + 0.5) / 200, y: (Double(y) + 0.5) / 100)
                XCTAssertEqual(Double(grid[y * 200 + x]), want, accuracy: 1e-6, "\(x), \(y)")
            }
        }
    }

    func testAnEraseStrokeClearsWhatItsRoundBrushCovers() {
        let line = stroke("erase", 0.2, 0, [(0.2, 0.5), (0.8, 0.5)])
        assertAlphas([line], [
            ((0.505, 0.505), 0), ((0.505, 0.595), 0), ((0.505, 0.605), 1),
            ((0.155, 0.505), 0), ((0.095, 0.505), 1), ((0.055, 0.505), 1),
        ])
    }

    func testRestorePutsBackWhatAnEarlierEraseTook() {
        let line = stroke("erase", 0.2, 0, [(0.2, 0.5), (0.8, 0.5)])
        let dot = stroke("restore", 0.1, 0, [(0.5, 0.5)])
        assertAlphas([line, dot], [((0.505, 0.505), 1), ((0.535, 0.505), 1), ((0.555, 0.505), 0), ((0.585, 0.505), 0)])
        // In the other order the erase wins: strokes are painted in turn.
        assertAlphas([dot, line], [((0.505, 0.505), 0)])
        // Restore over a picture nothing erased leaves it whole.
        assertAlphas([stroke("restore", 0.2, 0, [(0.5, 0.5)])], [((0.505, 0.505), 1)])
    }

    func testSoftnessFeathersTheEdgeInward() {
        // Soft 1 feathers the whole half-width: a straight ramp from the line.
        let soft = stroke("erase", 0.2, 1, [(0.2, 0.5), (0.8, 0.5)])
        assertAlphas([soft], [((0.505, 0.505), 0.05), ((0.505, 0.555), 0.55), ((0.505, 0.575), 0.75),
                              ((0.505, 0.605), 1)])
        // Soft 0.5: solid to half of it, then the ramp.
        let half = stroke("erase", 0.2, 0.5, [(0.2, 0.5), (0.8, 0.5)])
        assertAlphas([half], [((0.505, 0.505), 0), ((0.505, 0.555), 0.1), ((0.505, 0.575), 0.5),
                              ((0.505, 0.605), 1)])
        XCTAssertEqual(MaskRaster.coverage(distance: 5, radius: 10, feather: 0), 1)
        XCTAssertEqual(MaskRaster.coverage(distance: 9.9, radius: 10, feather: 0), 1)
        XCTAssertEqual(MaskRaster.coverage(distance: 10, radius: 10, feather: 0), 0, "the edge itself is outside")
        XCTAssertEqual(MaskRaster.coverage(distance: 8, radius: 10, feather: 1), 1)
        XCTAssertEqual(MaskRaster.coverage(distance: 9.5, radius: 10, feather: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(MaskRaster.coverage(distance: 2, radius: 10, feather: 10), 0.8, accuracy: 1e-9)
        XCTAssertEqual(MaskRaster.coverage(distance: 2, radius: 10, feather: 40), 0.8, accuracy: 1e-9,
                       "a feather is held within the radius")
    }

    func testADotAWideBrushAndAStrokeOffThePicture() {
        assertAlphas([stroke("erase", 0.1, 0, [(0.3, 0.3)])],
                     [((0.305, 0.305), 0), ((0.345, 0.305), 0), ((0.355, 0.305), 1)])
        // A width past 0.2 is read as 0.2.
        assertAlphas([stroke("erase", 0.5, 0, [(0.5, 0.5)])],
                     [((0.505, 0.585), 0), ((0.505, 0.595), 0), ((0.505, 0.605), 1)])
        let off = MaskRaster.raster([stroke("erase", 0.1, 0, [(1.5, 1.5)])], width: 100, height: 100, start: 1, initial: nil)
        XCTAssertEqual(off.min(), 1, "a stroke off the picture clears nothing")
    }

    func testTheWidthIsAShareOfTheShorterSide() {
        // 200 x 100: the brush is 10 cells across, round, whichever way.
        assertAlphas([stroke("erase", 0.1, 0, [(0.5, 0.5)])], width: 200, height: 100, [
            ((0.5025, 0.505), 0), ((0.5225, 0.505), 0), ((0.5275, 0.505), 1),
            ((0.5025, 0.545), 0), ((0.5025, 0.555), 1),
        ])
    }

    func testARetouchLayerCoversWhatItsStrokesPaintFeatheredByAQuarterOfTheirWidth() {
        let dot = RetouchLayer(kind: "blur", amount: 0.5,
                               strokes: [RetouchStroke(w: 0.2, points: [CGPoint(x: 0.5, y: 0.5)])])
        let grid = MaskRaster.coverage(of: dot, width: 100, height: 100)
        let rows: [((Double, Double), Float)] = [
            ((0.505, 0.505), 1), ((0.505, 0.555), 0.895464), ((0.505, 0.575), 0.49667),
            ((0.505, 0.585), 0.297061), ((0.505, 0.605), 0),
        ]
        for (at, cover) in rows {
            XCTAssertEqual(MaskRaster.sample(grid, width: 100, height: 100, x: at.0, y: at.1), cover,
                           accuracy: 1e-4, "at \(at)")
        }
        // Erase from effect takes it back off, with the same feather.
        let taken = RetouchLayer(kind: "pixelate", amount: 0.5, strokes: [
            RetouchStroke(w: 0.2, points: [CGPoint(x: 0.3, y: 0.5), CGPoint(x: 0.7, y: 0.5)]),
            RetouchStroke(w: 0.1, points: [CGPoint(x: 0.5, y: 0.5)], erases: true),
        ])
        let left = MaskRaster.coverage(of: taken, width: 100, height: 100)
        let after: [((Double, Double), Float)] = [
            ((0.505, 0.505), 0), ((0.405, 0.505), 1), ((0.535, 0.505), 0.414214), ((0.555, 0.505), 1),
        ]
        for (at, cover) in after {
            XCTAssertEqual(MaskRaster.sample(left, width: 100, height: 100, x: at.0, y: at.1), cover,
                           accuracy: 1e-4, "at \(at)")
        }
    }

    func testABlurIsItsAmountTimesFourPerCentOfTheShorterSide() {
        XCTAssertEqual(MaskRaster.blurRadius(amount: 0.5, shortSide: 1000), 20, accuracy: 1e-9)
        XCTAssertEqual(MaskRaster.blurRadius(amount: 1, shortSide: 300), 12, accuracy: 1e-9)
        XCTAssertEqual(MaskRaster.blurRadius(amount: 0, shortSide: 500), 0)
        XCTAssertEqual(MaskRaster.blurRadius(amount: 2, shortSide: 100), 4, accuracy: 1e-9)
        // A pixelate brush's blocks are pixelate's own: 2 + 48 × its amount.
        XCTAssertEqual(PhotoEffects.blockSize(0.5), 26)
    }

    // MARK: the file

    func testAMaskIsWrittenWithItsStrokesAndBaseAndReadBack() throws {
        var el = Element.image("media:cut", w: 300, h: 200)
        el.mask = ImageMask(strokes: [stroke("erase", 0.05, 0.3, [(0.1, 0.2), (0.3, 0.4)]),
                                      stroke("restore", 0.1, 0, [(0.5, 0.5)])],
                            base: "media:original")
        let data = try JSONEncoder().encode(el)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let mask = try XCTUnwrap(written["mask"] as? [String: Any])
        XCTAssertEqual(Set(mask.keys), ["strokes", "base"])
        XCTAssertEqual(mask["base"] as? String, "media:original")
        let first = try XCTUnwrap((mask["strokes"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(first.keys), ["mode", "w", "soft", "pts"])
        XCTAssertEqual(first["mode"] as? String, "erase")
        XCTAssertEqual(first["pts"] as? [[Double]], [[0.1, 0.2], [0.3, 0.4]])
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data), el)

        // No strokes and no base is no key at all.
        el.mask = ImageMask.kept(ImageMask())
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        XCTAssertNil(plain["mask"])

        func read(_ json: String) throws -> ImageMask? {
            try JSONDecoder().decode(Element.self,
                                     from: Data(#"{"id":"e","type":"image","mask":\#(json)}"#.utf8)).mask
        }
        // A stroke of another mode, or with no point that reads, is left out.
        let tolerant = try read(#"{"strokes": [{"mode": "smudge", "w": 0.1, "soft": 0, "pts": [[0.5, 0.5]]},"# +
                                #" {"mode": "restore", "w": 0.1, "soft": 0, "pts": [[0.5], ["x", 1]]},"# +
                                #" {"mode": "erase", "w": 0.1, "soft": 0, "pts": [[0.5, 0.5, 9]]}]}"#)
        XCTAssertEqual(tolerant?.strokes, [stroke("erase", 0.1, 0, [(0.5, 0.5)])])
        XCTAssertNil(try read(#"{"strokes": []}"#), "an empty mask is none")
        XCTAssertEqual(try read(#"{"strokes": [], "base": "media:a"}"#), ImageMask(base: "media:a"))
    }

    func testRetouchIsWrittenOnlyWithAPaintedLayerAndReadBack() throws {
        var el = Element.image("media:p", w: 300, h: 200)
        el.retouch = RetouchLayer.kept([RetouchLayer(kind: "blur", amount: 0.4)])
        XCTAssertNil(el.retouch, "a layer with no stroke is not kept")
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        XCTAssertNil(plain["retouch"])

        el.retouch = [RetouchLayer(kind: "pixelate", amount: 0.7, strokes: [
            RetouchStroke(w: 0.08, points: [CGPoint(x: 0.25, y: 0.5)]),
            RetouchStroke(w: 0.04, points: [CGPoint(x: 0.75, y: 0.5)], erases: true),
        ])]
        let data = try JSONEncoder().encode(el)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let layer = try XCTUnwrap((written["retouch"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(layer.keys), ["kind", "amount", "strokes"])
        XCTAssertEqual(layer["kind"] as? String, "pixelate")
        let strokes = try XCTUnwrap(layer["strokes"] as? [[String: Any]])
        XCTAssertEqual(Set(strokes[0].keys), ["w", "pts"])
        XCTAssertEqual(Set(strokes[1].keys), ["w", "pts", "mode"])
        XCTAssertEqual(strokes[1]["mode"] as? String, "erase")
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data), el)

        // A kind this build does not know, or a layer with no stroke, is
        // left out when read; none left is no retouch.
        let read = try JSONDecoder().decode(Element.self, from: Data(
            (#"{"id":"e","type":"image","retouch":[{"kind":"swirl","amount":1,"strokes":[{"w":0.1,"pts":[[0.5,0.5]]}]},"# +
             #"{"kind":"blur","amount":0.3,"strokes":[]}]}"#).utf8))
        XCTAssertNil(read.retouch)
    }

    // MARK: the session

    private var libraryPhoto: Element {
        var el = Element.image("asset:" + (PhotoLibrary.photos.first?.id ?? "none"), w: 300, h: 300)
        el.x = 50; el.y = 50
        return el
    }

    @MainActor
    private func store(with photo: Element) -> DesignStore {
        var design = Design(title: "brush", width: 600, height: 600)
        design.pages[0].elements = [photo]
        return DesignStore(design: design)
    }

    @MainActor
    func testABrushSessionIsOneStepThatCancelPutsBack() throws {
        let original = libraryPhoto
        let s = store(with: original)
        s.select(original.id)
        XCTAssertTrue(s.beginBrush(original.id, kind: .mask))
        s.brushStroke([CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200)])
        s.brushing?.reverse = true
        s.brushStroke([CGPoint(x: 150, y: 150)])
        XCTAssertEqual(s.element(original.id)?.mask?.strokes.map(\.mode), ["erase", "restore"])
        s.undoBrushStroke()
        XCTAssertEqual(s.element(original.id)?.mask?.strokes.count, 1)
        s.cancelBrush()
        XCTAssertNil(s.brushing)
        XCTAssertEqual(s.element(original.id), original, "Cancel put the photo back differently")
        XCTAssertFalse(s.canUndo, "Cancel recorded a step")

        XCTAssertTrue(s.beginBrush(original.id, kind: .blur))
        s.setBrushStrength(0.8)
        s.brushStroke([CGPoint(x: 100, y: 100), CGPoint(x: 120, y: 140)])
        s.brushStroke([CGPoint(x: 300, y: 300)])
        s.finishBrush()
        let layer = try XCTUnwrap(s.element(original.id)?.retouch?.first)
        XCTAssertEqual(layer.kind, "blur")
        XCTAssertEqual(layer.amount, 0.8, accuracy: 1e-9)
        XCTAssertEqual(layer.strokes.count, 2)
        XCTAssertEqual(layer.strokes[0].w, BrushSession.defaultSize, accuracy: 1e-9)
        s.undo()
        XCTAssertEqual(s.element(original.id), original, "the brush was more than one step")

        // Every stroke taken back leaves no layer behind.
        XCTAssertTrue(s.beginBrush(original.id, kind: .pixelate))
        s.brushStroke([CGPoint(x: 100, y: 100)])
        s.undoBrushStroke()
        s.finishBrush()
        XCTAssertEqual(s.element(original.id), original)
        XCTAssertFalse(s.canUndo)
    }

    @MainActor
    func testStrokesLandInThePictureAsSharesOfIt() throws {
        // A 300 x 300 frame filled by the picture: the frame's middle is the
        // picture's, wherever the picture's own size.
        let original = libraryPhoto
        let s = store(with: original)
        s.select(original.id)
        XCTAssertTrue(s.beginBrush(original.id, kind: .mask))
        s.brushStroke([CGPoint(x: 200, y: 200)])
        s.finishBrush()
        let point = try XCTUnwrap(s.element(original.id)?.mask?.strokes.first?.points.first)
        XCTAssertEqual(Double(point.x), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Double(point.y), 0.5, accuracy: 1e-6)
    }

    @MainActor
    func testABrushIsRefusedWhereItCannotPaint() {
        var locked = libraryPhoto
        locked.locked = true
        let code = Element.image(CodeGenerator.source(for: "https://canvia.app"), w: 200, h: 200)
        let missing = Element.image("media:img_does_not_exist", w: 200, h: 200)
        for el in [locked, code, missing] {
            let s = store(with: el)
            XCTAssertFalse(s.beginBrush(el.id, kind: .mask), "\(el.src ?? "") took a brush")
            XCTAssertNil(s.brushing)
        }
        // Nor on a locked page.
        let photo = libraryPhoto
        let s = store(with: photo)
        s.setPageLocked(true)
        XCTAssertFalse(s.beginBrush(photo.id, kind: .blur))
    }

    @MainActor
    func testShowOriginalShowsThePictureBeforeTheCutOrWithoutTheRetouch() {
        var el = libraryPhoto
        el.src = "media:cut"
        el.mask = ImageMask(strokes: [stroke("restore", 0.1, 0, [(0.5, 0.5)])], base: "media:before")
        el.retouch = [RetouchLayer(kind: "blur", strokes: [RetouchStroke(points: [CGPoint(x: 0.5, y: 0.5)])])]
        let uncut = ImageMasking.original(el, retouching: false)
        XCTAssertEqual(uncut.src, "media:before")
        XCTAssertNil(uncut.mask)
        XCTAssertNotNil(uncut.retouch)
        let plain = ImageMasking.original(el, retouching: true)
        XCTAssertEqual(plain.src, "media:cut")
        XCTAssertNotNil(plain.mask)
        XCTAssertNil(plain.retouch)
        // Reset photo edits takes the retouch off, and leaves the mask.
        var reset = el
        PhotoEdits.reset(&reset)
        XCTAssertNil(reset.retouch)
        XCTAssertEqual(reset.mask, el.mask)
    }
}
