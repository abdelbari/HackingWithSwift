// Clear a colour: a tap kept in the photo's mask as {"mode": "key", x, y,
// tol, all}, in order with the brush strokes; what it clears of the
// picture's pixels (MaskRaster.keyCoverage, a flood or everywhere, Lab ΔE
// within the tolerance, a one-pixel feathered edge); and Remove white
// background's four corner taps. Fixtures/colour-key.json is byte for byte
// the Android twin's, read by its MaskRasterTest row for row.

import UIKit
import XCTest
@testable import Canvia

final class ColourKeyTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("colour-key") }

    private func picture(_ f: [String: Any], _ name: String) throws -> [UInt8] {
        try XCTUnwrap(f[name] as? [Int]).map { UInt8($0) }
    }

    private func tap(_ row: [Any]) throws -> MaskStroke {
        MaskStroke(keyAt: try XCTUnwrap(row[0] as? Double), try XCTUnwrap(row[1] as? Double),
                   tol: try XCTUnwrap(row[2] as? Double), all: try XCTUnwrap(row[3] as? Bool))
    }

    private func floats(_ value: Any?) throws -> [Float] {
        try XCTUnwrap(value as? [Double]).map { Float($0) }
    }

    /// Shared: what each tap leaves, pixel for pixel — 1 kept, 0 cleared,
    /// 0.5 the edge — on the picture and on it with a clear corner.
    func testEveryTapClearsTheSharedPixels() throws {
        let f = try fixture()
        let w = try XCTUnwrap(f["width"] as? Int), h = try XCTUnwrap(f["height"] as? Int)
        let pixels = try picture(f, "pixels")
        let rows = try XCTUnwrap(f["rows"] as? [[Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 5)
        for (n, row) in rows.enumerated() {
            XCTAssertEqual(MaskRaster.keyCoverage(pixels, width: w, height: h, entry: try tap(row)),
                           try floats(row[4]), "row \(n)")
        }
        // A clear pixel never matches, and tapping one clears nothing.
        let clear = try picture(f, "clearPicture")
        for (n, row) in try XCTUnwrap(f["clearRows"] as? [[Any]]).enumerated() {
            XCTAssertEqual(MaskRaster.keyCoverage(clear, width: w, height: h, entry: try tap(row)),
                           try floats(row[4]), "clear row \(n)")
        }
    }

    /// Shared: Remove white background's four taps share one edge, and
    /// each takes the mask down only to the least of it and what it
    /// leaves, so the edge stays half clear rather than compounding.
    func testOverlappingTapsNeverCompound() throws {
        let f = try fixture()
        let w = try XCTUnwrap(f["width"] as? Int), h = try XCTUnwrap(f["height"] as? Int)
        let pixels = try picture(f, "pixels")
        let keyed: MaskRaster.Keyed = { MaskRaster.keyCoverage(pixels, width: w, height: h, entry: $0) }
        let grid = MaskRaster.raster(MaskRaster.whiteBackgroundTaps, width: w, height: h, start: 1, initial: nil,
                                     keyed: keyed)
        XCTAssertEqual(grid, try floats(f["whiteBackground"]))
    }

    /// Shared: the Lab both phones measure by, to six places.
    func testTheSharedLab() throws {
        for row in try XCTUnwrap(try fixture()["lab"] as? [[Double]]) {
            let lab = MaskRaster.lab(Int(row[0]), Int(row[1]), Int(row[2]))
            XCTAssertEqual(lab.l, row[3], accuracy: 0.000001)
            XCTAssertEqual(lab.a, row[4], accuracy: 0.000001)
            XCTAssertEqual(lab.b, row[5], accuracy: 0.000001)
        }
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
        let w = try XCTUnwrap(f["width"] as? Int), h = try XCTUnwrap(f["height"] as? Int)
        let pixels = try picture(f, "pixels")
        let tap = MaskStroke(keyAt: 0, 0, tol: 0.12)
        let restore = MaskStroke(mode: MaskStroke.restore, w: 0.2, soft: 0, points: [CGPoint(x: 0.0625, y: 0.0833)])
        let keyed: MaskRaster.Keyed = { MaskRaster.keyCoverage(pixels, width: w, height: h, entry: $0) }
        let grid = MaskRaster.raster([tap, restore], width: w, height: h, start: 1, initial: nil, keyed: keyed)
        XCTAssertEqual(Array(grid.prefix(8)), [1, 0, 0, 0, 0, 0, 0, 0])
        // With no pixels to read the tap is passed over.
        XCTAssertEqual(MaskRaster.raster([tap], width: w, height: h, start: 1, initial: nil),
                       [Float](repeating: 1, count: w * h))
        // And it draws no stroke of its own.
        XCTAssertEqual(MaskRaster.alpha([tap], aspect: 1, x: 0.1, y: 0.1), 1)
    }

    /// The grid reads the picture's own pixels, never a blend of them.
    func testTheGridSamplesTheNearestPixel() throws {
        let f = try fixture()
        let pixels = try picture(f, "pixels")
        let image = try XCTUnwrap(Self.image(pixels, width: 8, height: 6))
        let half = try XCTUnwrap(ImageMasking.gridPixels(image, width: 4, height: 3))
        // Grid (1, 0) is picture (3, 1), on the red ring.
        XCTAssertEqual(Array(half[4..<8]), [208, 48, 48, 255])
        XCTAssertEqual(try XCTUnwrap(ImageMasking.gridPixels(image, width: 8, height: 6)), pixels)
    }

    private static func image(_ bytes: [UInt8], width: Int, height: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
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
