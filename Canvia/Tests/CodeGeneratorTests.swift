// QR codes.
//
// There is exactly one thing worth asserting about a generated code, and it
// is not its pixels: a scanner has to be able to read the payload back out.
// Everything that goes wrong here — a missing quiet zone, a smoothed upscale,
// a stretched frame — produces an image that looks like a perfectly good QR
// code and does not scan, which is a bug you only find after printing.

import XCTest
import UIKit
import Vision
@testable import Canvia

final class CodeGeneratorTests: XCTestCase {

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

    /// The alpha-ignoring colour of one pixel, top-left origin.
    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> (UInt8, UInt8, UInt8) {
        let cg = try XCTUnwrap(image.cgImage)
        var rgba: [UInt8] = [0, 0, 0, 0]
        try rgba.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y),
                                    width: cg.width, height: cg.height))
        }
        return (rgba[0], rgba[1], rgba[2])
    }

    // MARK: the only test that matters

    /// This is also the mirror check, and it earned that in the first run: a
    /// UIKit renderer's context is already flipped, so handing a CGImage
    /// straight to CGContext.draw in it produced codes that looked perfect and
    /// decoded as nothing. A pixel comparison would not have caught it — the
    /// image was a valid-looking QR either way.
    func testAGeneratedCodeScansBackToItsPayload() throws {
        let code = try XCTUnwrap(CodeGenerator.qr("https://example.com/canvia"))
        XCTAssertEqual(try decode(code), "https://example.com/canvia")
    }

    func testALongPayloadStillScans() throws {
        let payload = String(repeating: "canvia-", count: 20)
        let code = try XCTUnwrap(CodeGenerator.qr(payload))
        XCTAssertEqual(try decode(code), payload)
    }

    /// UTF-8, because "text" in a design tool includes menus and place names.
    func testANonASCIIPayloadStillScans() throws {
        let payload = "Café Ω 東京"
        let code = try XCTUnwrap(CodeGenerator.qr(payload))
        XCTAssertEqual(try decode(code), payload)
    }

    /// The small-side case: a code placed at thumbnail size still has to
    /// survive the upscale it gets when the page is exported.
    func testASmallCodeStillScans() throws {
        let code = try XCTUnwrap(CodeGenerator.qr("canvia", side: 128))
        XCTAssertEqual(try decode(code), "canvia")
    }

    // MARK: shape and framing

    func testCodesAreSquareAtTheRequestedSize() throws {
        for side in [128.0, 256, 512] {
            let code = try XCTUnwrap(CodeGenerator.qr("canvia", side: side))
            XCTAssertEqual(code.size, CGSize(width: side, height: side))
        }
    }

    /// The quiet zone. Without it a scanner cannot find the code's edges, and
    /// the generator emits barely one module of margin on its own.
    func testCodesHaveAWhiteQuietZone() throws {
        let code = try XCTUnwrap(CodeGenerator.qr("canvia", side: 512))
        for point in [(2, 2), (509, 2), (2, 509), (509, 509), (256, 3)] {
            let (r, g, b) = try pixel(code, x: point.0, y: point.1)
            XCTAssertEqual(r, 255, "quiet zone at \(point)")
            XCTAssertEqual(g, 255, "quiet zone at \(point)")
            XCTAssertEqual(b, 255, "quiet zone at \(point)")
        }
    }

    // MARK: refusals

    /// Only the empty payload is refused here. Trimming is the insert sheet's
    /// job, since a code made of spaces is legal, scannable and useless — and
    /// deciding that is a question about the button, not the generator.
    func testEmptyPayloadsProduceNothing() {
        XCTAssertNil(CodeGenerator.qr(""))
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
        let src = CodeGenerator.source(for: "qr:nested")
        XCTAssertEqual(CodeGenerator.payload(from: src), "qr:nested")
    }

    /// The canvas resolves an element's src synchronously; a code has to come
    /// back from that path like any other picture.
    func testTheCanvasResolvesACodeSource() throws {
        let src = CodeGenerator.source(for: "https://example.com/resolve")
        let image = try XCTUnwrap(PhotoLibrary.resolve(src))
        XCTAssertEqual(try decode(image), "https://example.com/resolve")
    }
}
