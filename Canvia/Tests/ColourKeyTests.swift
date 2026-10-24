// Clear a colour: a tap kept in the photo's mask as {"mode": "key", x, y,
// tol, all}, in order with the brush strokes; what it clears of the
// picture's pixels (MaskRaster.keyCoverage, a flood or everywhere, Lab ΔE
// within the tolerance, a one-pixel feathered edge); and Remove white
// background's four corner taps. The coverage rows (Fixtures/colour-key
// .json) are shared with the Android twin's MaskRasterTest.

import XCTest
@testable import Canvia

final class ColourKeyTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("colour-key") }

    private func coverage(_ row: [Any], pixels: [UInt8], w: Int, h: Int) throws -> (got: [Float], want: [Float]) {
        let entry = MaskStroke(keyAt: try XCTUnwrap(row[0] as? Double), try XCTUnwrap(row[1] as? Double),
                               tol: try XCTUnwrap(row[2] as? Double), all: try XCTUnwrap(row[3] as? Bool))
        let want = try XCTUnwrap(row[4] as? [Double]).map { Float($0) }
        return (MaskRaster.keyCoverage(pixels, width: w, height: h, entry: entry), want)
    }

    /// Shared: each tap's coverage, pixel for pixel.
    func testEveryTapClearsTheSharedPixels() throws {
        let f = try fixture()
        let w = try XCTUnwrap(f["width"] as? Int), h = try XCTUnwrap(f["height"] as? Int)
        let pixels = try XCTUnwrap(f["pixels"] as? [Int]).map { UInt8($0) }
        let rows = try XCTUnwrap(f["rows"] as? [[Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 5)
        for (n, row) in rows.enumerated() {
            let result = try coverage(row, pixels: pixels, w: w, h: h)
            XCTAssertEqual(result.got, result.want, "row \(n)")
        }
        // A clear pixel tapped clears nothing.
        let clear = try XCTUnwrap(f["clearCorner"] as? [Int]).map { UInt8($0) }
        let result = try coverage(try XCTUnwrap(f["clearCornerRow"] as? [Any]), pixels: clear, w: w, h: h)
        XCTAssertEqual(result.got, result.want)
    }

    /// Shared: a tap written and read back, and read leniently.
    func testATapIsWrittenAndReadAsBothPhonesDo() throws {
        let written = try XCTUnwrap((try fixture()["entry"] as? [String: Any])?["written"] as? String)
        let tap = MaskStroke(keyAt: 0.25, 0.75, tol: 0.12, all: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(tap), as: UTF8.self), written)
        XCTAssertEqual(try JSONDecoder().decode(MaskStroke.self, from: Data(written.utf8)), tap)
        let mask = try JSONDecoder().decode(ImageMask.self, from: Data(##"""
        {"strokes": [{"mode": "erase", "w": 0.1, "soft": 0, "pts": [[0.5, 0.5]]},
                     {"mode": "key", "y": 0.5},
                     {"mode": "key", "x": 2, "y": -1, "tol": "x", "all": "yes"},
                     {"mode": "restore", "w": 0.1, "soft": 0, "pts": [[0.2, 0.2]]}]}
        """##.utf8))
        XCTAssertEqual(mask.strokes.map(\.mode), ["erase", "key", "restore"], "a tap with no point is left out")
        XCTAssertEqual(mask.strokes[1], MaskStroke(keyAt: 1, 0, tol: MaskStroke.defaultTolerance, all: false))
        XCTAssertTrue(mask.strokes[1].keys)
        XCTAssertEqual(MaskStroke.defaultTolerance, 0.25)
    }

    /// The tap is laid down in order with the strokes: a Restore after it
    /// paints the colour back.
    func testARestoreAfterATapPaintsTheColourBack() throws {
        let f = try fixture()
        let pixels = try XCTUnwrap(f["pixels"] as? [Int]).map { UInt8($0) }
        let tap = MaskStroke(keyAt: 0.1, 0.1, tol: 0.25)
        let restore = MaskStroke(mode: MaskStroke.restore, w: 0.2, soft: 0, points: [CGPoint(x: 0.1, y: 0.1)])
        let keyed: MaskRaster.Keyed = { MaskRaster.keyCoverage(pixels, width: 5, height: 3, entry: $0) }
        let grid = MaskRaster.raster([tap, restore], width: 5, height: 3, start: 1, initial: nil, keyed: keyed)
        XCTAssertEqual(grid, [1, 0, 0.5, 1, 1, 0, 0.5, 1, 1, 1, 0, 0, 0.5, 1, 1])
        // With no pixels to read the tap is passed over.
        XCTAssertEqual(MaskRaster.raster([tap], width: 5, height: 3, start: 1, initial: nil), [Float](repeating: 1, count: 15))
        // And it draws no stroke of its own.
        XCTAssertEqual(MaskRaster.alpha([tap], aspect: 1, x: 0.1, y: 0.1), 1)
    }

    func testTheToleranceIsADistanceInLab() {
        XCTAssertEqual(MaskRaster.keyLimit(0.25), 625)
        XCTAssertEqual(MaskRaster.keyLimit(2), 10_000)
        let white = MaskRaster.lab(255, 255, 255)
        XCTAssertEqual(white.l, 100, accuracy: 0.01)
        XCTAssertEqual(white.a, 0, accuracy: 0.01)
        XCTAssertEqual(white.b, 0, accuracy: 0.01)
        XCTAssertEqual(MaskRaster.lab(0, 0, 0).l, 0, accuracy: 0.0001)
    }

    @MainActor
    func testRemoveWhiteBackgroundTapsTheFourCorners() {
        let taps = MaskRaster.whiteBackgroundTaps
        XCTAssertEqual(taps.map(\.x), [0, 1, 0, 1])
        XCTAssertEqual(taps.map(\.y), [0, 0, 1, 1])
        XCTAssertTrue(taps.allSatisfy { $0.tol == 0.12 && !$0.all && $0.keys })
        XCTAssertEqual(DesignStore.keyCorners.count, 4)
        XCTAssertEqual(DesignStore.keyCentre.first?.x, 0.5)
    }
}
