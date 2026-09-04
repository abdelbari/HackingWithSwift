// QR codes.
//
// The generator shipped broken twice, and both times it looked perfect: once
// mirrored, once invisible. Neither is detectable by eye or by a pixel
// assertion — a mirrored QR is a beautiful picture of a QR code that decodes
// as nothing. So this file checks two independent things.
//
// Structure, which needs no decoder: the QR standard fixes where the finder
// patterns go and how the timing patterns alternate, and those are exactly the
// properties a flip or an inversion destroys.
//
// Decoding, which is the real proof — gated behind a known-good reference code
// generated outside this app. If the reference decodes and ours does not, ours
// is wrong; if neither decodes, the environment has no barcode detector and
// the decode tests skip rather than lie.

import XCTest
import UIKit
import Vision
@testable import Canvia

final class CodeGeneratorTests: XCTestCase {

    // MARK: fixtures

    /// A QR of "CANVIA-REFERENCE" produced by an independent encoder, so a
    /// failure to decode it is a fact about the detector, not about us.
    private static let referencePNG =
        "iVBORw0KGgoAAAANSUhEUgAAAPoAAAD6AQAAAACgl2eQAAAA3ElEQVR42u2YQQ7DIAwEreYBPClf50l5AJILxhC1h1aYHMeHSCF7" +
        "Gq3tJaK/KwsCBAgQIFAVr0PlvObDBC/5Uwi8OkmjppWfv17+AZLLJCs6c2J1aTuD5D5Jf6W7d0n6aSp48pE5KWmuJECtkZy72+ek" +
        "FqG7IyS/iu7emZPNjo1fHqESkkFPGkQLQMdHdAfU6sYp447TxyYpKOrJa+wZG5GZ3b3tyXtO4smQJxs/G5EdJ3MynifTyOM5jXiJ" +
        "J6Oe7C1+3pdHSAbzZOdnZy1ZQvKBOw6/xBEgQIBgCt6gDkP3tnYMBQAAAABJRU5ErkJggg=="

    private func referenceCode() throws -> UIImage {
        let data = try XCTUnwrap(Data(base64Encoded: Self.referencePNG))
        return try XCTUnwrap(UIImage(data: data))
    }

    private func decode(_ image: UIImage) throws -> String? {
        let cg = try XCTUnwrap(image.cgImage)
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        do {
            try VNImageRequestHandler(cgImage: cg).perform([request])
        } catch {
            throw XCTSkip("Vision barcode detection is unavailable here: \(error)")
        }
        return request.results?.first?.payloadStringValue
    }

    /// Skip, rather than fail, when the detector itself cannot read a code
    /// this app did not make.
    private func requireWorkingDetector() throws {
        guard try decode(try referenceCode()) == "CANVIA-REFERENCE" else {
            throw XCTSkip("no working QR detector in this environment")
        }
    }

    private func darkFraction(_ image: UIImage) throws -> Double {
        let cg = try XCTUnwrap(image.cgImage)
        let w = cg.width, h = cg.height
        var bytes = [UInt8](repeating: 0, count: w * h)
        try bytes.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: w, height: h,
                                              bitsPerComponent: 8, bytesPerRow: w,
                                              space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Double(bytes.filter { $0 < 128 }.count) / Double(w * h)
    }

    private func gray(_ image: UIImage, x: Int, y: Int) throws -> UInt8 {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel: [UInt8] = [0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: 1, height: 1,
                                              bitsPerComponent: 8, bytesPerRow: 1,
                                              space: CGColorSpaceCreateDeviceGray(),
                                              bitmapInfo: CGImageAlphaInfo.none.rawValue))
            ctx.interpolationQuality = .none
            // CG counts rows from the bottom; the caller counts from the top.
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y),
                                    width: cg.width, height: cg.height))
        }
        return pixel[0]
    }

    // MARK: structure — no decoder needed

    /// A QR symbol is square and 21, 25, 29 … modules on a side. Anything else
    /// means the generator's margin was trimmed wrong.
    func testModulesAreSquareAndAValidVersion() throws {
        for payload in ["canvia", "https://example.com/canvia", String(repeating: "x", count: 300)] {
            let grid = try XCTUnwrap(CodeGenerator.modules(for: payload), payload)
            XCTAssertGreaterThanOrEqual(grid.count, 21, payload)
            XCTAssertLessThanOrEqual(grid.count, 177, payload)
            XCTAssertEqual((grid.count - 21) % 4, 0, "\(grid.count) is not a QR version size")
            for row in grid { XCTAssertEqual(row.count, grid.count, payload) }
        }
    }

    /// The invariant a flip destroys. Finder patterns sit at three corners and
    /// never the fourth, so their placement says which way up the grid is.
    func testFinderPatternsSitAtThreeCornersAndNotTheFourth() throws {
        let grid = try XCTUnwrap(CodeGenerator.modules(for: "https://example.com/canvia"))
        let n = grid.count
        func isFinder(x0: Int, y0: Int) -> Bool {
            for dy in 0..<7 {
                for dx in 0..<7 {
                    let ring = dx == 0 || dx == 6 || dy == 0 || dy == 6
                    let core = (2...4).contains(dx) && (2...4).contains(dy)
                    if grid[y0 + dy][x0 + dx] != (ring || core) { return false }
                }
            }
            return true
        }
        XCTAssertTrue(isFinder(x0: 0, y0: 0), "no finder at top-left")
        XCTAssertTrue(isFinder(x0: n - 7, y0: 0), "no finder at top-right")
        XCTAssertTrue(isFinder(x0: 0, y0: n - 7), "no finder at bottom-left")
        XCTAssertFalse(isFinder(x0: n - 7, y0: n - 7), "a finder at bottom-right means the grid is flipped")
    }

    /// The timing patterns: row 6 and column 6 alternate dark/light between
    /// the finders. Inverting the whole grid breaks this, and so does reading
    /// it off by one.
    func testTimingPatternsAlternate() throws {
        let grid = try XCTUnwrap(CodeGenerator.modules(for: "https://example.com/canvia"))
        let n = grid.count
        for i in 8..<(n - 8) {
            XCTAssertEqual(grid[6][i], i % 2 == 0, "horizontal timing broken at \(i)")
            XCTAssertEqual(grid[i][6], i % 2 == 0, "vertical timing broken at \(i)")
        }
    }

    func testLongerPayloadsNeedMoreModules() throws {
        let small = try XCTUnwrap(CodeGenerator.modules(for: "hi"))
        let large = try XCTUnwrap(CodeGenerator.modules(for: String(repeating: "canvia-", count: 40)))
        XCTAssertGreaterThan(large.count, small.count)
    }

    // MARK: rendering

    func testCodesAreSquareAtTheRequestedSize() throws {
        for side in [128.0, 256, 512] {
            let code = try XCTUnwrap(CodeGenerator.qr("canvia", side: side))
            XCTAssertEqual(code.size, CGSize(width: side, height: side))
        }
    }

    /// The quiet zone. Without it a scanner cannot find the code's edges.
    func testCodesHaveAWhiteQuietZone() throws {
        let code = try XCTUnwrap(CodeGenerator.qr("canvia", side: 512))
        for point in [(2, 2), (509, 2), (2, 509), (509, 509), (256, 3), (3, 256)] {
            XCTAssertEqual(try gray(code, x: point.0, y: point.1), 255, "quiet zone at \(point)")
        }
    }

    /// Both tones are present and in the proportion a real code has. A blank
    /// white square — which is what an inverted draw produced — has a dark
    /// fraction of zero and would have passed every other check here.
    func testCodesAreRoughlyHalfDarkInsideTheirMargin() throws {
        let fraction = try darkFraction(try XCTUnwrap(CodeGenerator.qr("https://example.com/canvia")))
        XCTAssertGreaterThan(fraction, 0.15, "the code is blank or nearly so")
        XCTAssertLessThan(fraction, 0.55, "the code is inverted or flooded")
    }

    // MARK: decoding — the real proof

    func testTheReferenceCodeDecodes() throws {
        try requireWorkingDetector()
    }

    func testAGeneratedCodeScansBackToItsPayload() throws {
        try requireWorkingDetector()
        let code = try XCTUnwrap(CodeGenerator.qr("https://example.com/canvia"))
        XCTAssertEqual(try decode(code), "https://example.com/canvia")
    }

    func testALongPayloadStillScans() throws {
        try requireWorkingDetector()
        let payload = String(repeating: "canvia-", count: 20)
        XCTAssertEqual(try decode(try XCTUnwrap(CodeGenerator.qr(payload))), payload)
    }

    /// UTF-8, because "text" in a design tool includes menus and place names.
    func testANonASCIIPayloadStillScans() throws {
        try requireWorkingDetector()
        let payload = "Café Ω 東京"
        XCTAssertEqual(try decode(try XCTUnwrap(CodeGenerator.qr(payload))), payload)
    }

    func testASmallCodeStillScans() throws {
        try requireWorkingDetector()
        XCTAssertEqual(try decode(try XCTUnwrap(CodeGenerator.qr("canvia", side: 128))), "canvia")
    }

    /// The canvas resolves an element's src synchronously; a code has to come
    /// back from that path like any other picture.
    func testTheCanvasResolvesACodeSource() throws {
        try requireWorkingDetector()
        let src = CodeGenerator.source(for: "https://example.com/resolve")
        let image = try XCTUnwrap(PhotoLibrary.resolve(src))
        XCTAssertEqual(try decode(image), "https://example.com/resolve")
    }

    // MARK: refusals

    /// Only the empty payload is refused here. Trimming is the insert sheet's
    /// job, since a code made of spaces is legal, scannable and useless — and
    /// deciding that is a question about the button, not the generator.
    func testEmptyPayloadsProduceNothing() {
        XCTAssertNil(CodeGenerator.qr(""))
        XCTAssertNil(CodeGenerator.modules(for: ""))
    }

    func testNonPositiveSidesProduceNothing() {
        XCTAssertNil(CodeGenerator.qr("canvia", side: 0))
        XCTAssertNil(CodeGenerator.qr("canvia", side: -10))
    }

    // MARK: sources

    func testSourcesRoundTripThroughTheirPayload() {
        let src = CodeGenerator.source(for: "https://example.com")
        XCTAssertEqual(CodeGenerator.payload(from: src), "https://example.com")
        XCTAssertNil(CodeGenerator.payload(from: "asset:blob1"))
        XCTAssertNil(CodeGenerator.payload(from: "media:img_1"))
    }

    /// A payload containing the prefix again must survive, since the split is
    /// on the first occurrence only.
    func testAPayloadThatLooksLikeASourceSurvives() {
        XCTAssertEqual(CodeGenerator.payload(from: CodeGenerator.source(for: "qr:nested")), "qr:nested")
    }
}
