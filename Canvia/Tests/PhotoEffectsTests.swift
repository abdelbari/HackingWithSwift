// Photo effects: pixelate, focus, and an outline or glow round what the
// photo shows. The numbers match the Android twin's PhotoEffectsTest; the
// drawing is checked by what it does to a picture — blocks are flat, the
// focus point stays sharp, an edge reaches past the frame.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class PhotoEffectsTests: XCTestCase {

    // MARK: the numbers

    func testPixelatesBlockIsTwoPlusFortyEightTimesItsValue() {
        XCTAssertEqual(PhotoEffects.blockSize(nil), 0)
        XCTAssertEqual(PhotoEffects.blockSize(0), 0)
        XCTAssertEqual(PhotoEffects.blockSize(0.25), 2 + 48 * 0.25, accuracy: 1e-12)
        XCTAssertEqual(PhotoEffects.blockSize(1), 50)
        XCTAssertEqual(PhotoEffects.blockSize(7), 50)
    }

    /// A block in page units is as many of the picture's pixels as cover it.
    func testABlockIsCountedInThePicturesPixels() {
        // A 2000-pixel-wide picture filling a 500-wide frame: four pixels to
        // a page unit, so a 14-unit block is 56 pixels.
        var el = Element.image("media:a", w: 500, h: 500)
        el.pixelate = 0.25
        let picture = CGSize(width: 2000, height: 2000)
        XCTAssertEqual(PhotoEffects.blockPixels(el, picture: picture), 56)
        // Zoomed in twice, the same block covers half as many pixels.
        var zoomed = el
        zoomed.cropScale = 2
        XCTAssertEqual(PhotoEffects.blockPixels(zoomed, picture: picture), 28)
        var none = el
        none.pixelate = nil
        XCTAssertEqual(PhotoEffects.blockPixels(none, picture: picture), 0)
        // Never less than a pixel.
        var tiny = el
        tiny.pixelate = 0.0001
        XCTAssertEqual(PhotoEffects.blockPixels(tiny, picture: CGSize(width: 10, height: 10)), 1)
    }

    /// Each block is its pixels' mean from the top left, the cut-short last
    /// column too; a clear pixel adds clearness, not black.
    func testEachBlockIsItsPixelsMean() {
        func grey(_ v: UInt8) -> [UInt8] { [v, v, v, 255] }
        var bytes = grey(0) + grey(100) + grey(200)
            + grey(50) + grey(150) + [0, 0, 0, 0]
        PhotoEffects.pixelate(&bytes, width: 3, height: 2, block: 2)
        XCTAssertEqual(bytes[0], 75)
        XCTAssertEqual(bytes[4 * 4], 75)
        // The last column: 200 at half, premultiplied.
        XCTAssertEqual(bytes[2 * 4], 100)
        XCTAssertEqual(bytes[5 * 4 + 3], 128)
        // All clear stays clear.
        var clear = [UInt8](repeating: 0, count: 16)
        PhotoEffects.pixelate(&clear, width: 2, height: 2, block: 2)
        XCTAssertTrue(clear.allSatisfy { $0 == 0 })
    }

    func testFocusIsSharpInsideItsCircleAndFullyBlurredATenthBeyond() {
        XCTAssertEqual(PhotoEffects.focusWeight(distance: 10, radius: 30, feather: 10), 0)
        XCTAssertEqual(PhotoEffects.focusWeight(distance: 35, radius: 30, feather: 10), 0.5, accuracy: 1e-12)
        XCTAssertEqual(PhotoEffects.focusWeight(distance: 90, radius: 30, feather: 10), 1)
        XCTAssertEqual(PhotoEffects.focusWeight(distance: 31, radius: 30, feather: 0), 1)
        XCTAssertEqual(PhotoEffects.focusSpread, 0.03)
        XCTAssertEqual(PhotoEffects.focusFeather, 0.1)
    }

    /// An edge is a fifth of its width thick, and a glow reaches half as far
    /// again.
    func testAnEdgesThicknessAndReach() {
        XCTAssertEqual(PhotoEffects.thickness(nil), 0)
        XCTAssertEqual(PhotoEffects.thickness(PhotoEdge(kind: "outline", color: "#ffffff", width: 30)), 6, accuracy: 1e-12)
        XCTAssertEqual(PhotoEffects.thickness(PhotoEdge(width: 400)), 20)
        XCTAssertEqual(PhotoEffects.reach(PhotoEdge(kind: "outline", color: "#ffffff", width: 30)), 6, accuracy: 1e-12)
        XCTAssertEqual(PhotoEffects.reach(PhotoEdge(kind: "glow", color: "#ffffff", width: 30)), 9, accuracy: 1e-12)
        // An unknown kind is drawn as an outline.
        XCTAssertEqual(PhotoEffects.reach(PhotoEdge(kind: "sparkle", color: "#ffffff", width: 30)), 6, accuracy: 1e-12)
    }

    func testThePlanKeysEachEffectApart() {
        var el = Element.image("media:a", w: 100, h: 100)
        let picture = CGSize(width: 400, height: 400)
        XCTAssertTrue(PhotoEffects.plan(el, picture: picture).isNone)
        XCTAssertEqual(PhotoEffects.plan(el, picture: picture).signature, "")
        el.pixelate = 0.5
        let blocked = PhotoEffects.plan(el, picture: picture)
        XCTAssertEqual(blocked.block, 104)
        el.focusBlur = FocusBlur()
        let both = PhotoEffects.plan(el, picture: picture)
        XCTAssertNotEqual(blocked.signature, both.signature)
        el.focusBlur?.subject = true
        XCTAssertNotEqual(both.signature, PhotoEffects.plan(el, picture: picture).signature)
        // No amount is no focus.
        el.focusBlur = FocusBlur(amount: 0)
        XCTAssertNil(PhotoEffects.plan(el, picture: picture).focus)
    }

    /// An outline or glow reaches past the frame, so an exported picture of
    /// the photo keeps room for it.
    func testTheSVGPictureKeepsRoomForTheEdge() {
        var photo = Element.image("media:a", w: 200, h: 150)
        photo.edge = PhotoEdge(kind: "glow", color: "#ffffff", width: 30)
        XCTAssertEqual(SVGExporter.overflow(photo), 9, accuracy: 1e-9)
    }

    // MARK: the drawing

    /// Left half black, right half white, with a sharp edge down the middle.
    private func halves(size: Int = 64) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor.white.setFill()
            ctx.fill(CGRect(x: size / 2, y: 0, width: size / 2, height: size))
        }
    }

    /// Red, 0…255, and alpha at (x, y) from the top left.
    private func pixel(_ image: UIImage, x: Int, y: Int) throws -> (red: Double, alpha: Double) {
        let cg = try XCTUnwrap(image.cgImage)
        var bytes: [UInt8] = [0, 0, 0, 0]
        try bytes.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        }
        return (Double(bytes[0]), Double(bytes[3]))
    }

    /// The sharp edge down the middle stays sharp at the focus point and
    /// runs together far from it.
    func testFocusKeepsItsPointSharpAndBlursBeyond() throws {
        let source = halves(size: 200)
        let focus = FocusBlur(x: 0.5, y: 0.1, radius: 0.1, amount: 1)
        let out = ImageFilterEngine.apply(.none, adjustments: .neutral, duotone: nil,
                                          effects: PhotoEffects.Plan(block: 0, focus: focus),
                                          to: source, cacheKey: UUID().uuidString)
        // Either side of the edge, near the focus point: black and white.
        let near = try pixel(out, x: 102, y: 18).red - pixel(out, x: 97, y: 18).red
        XCTAssertGreaterThan(near, 225)
        // Either side of it, far below: run together.
        let far = try pixel(out, x: 102, y: 190).red - pixel(out, x: 97, y: 190).red
        XCTAssertLessThan(far, near - 20)
    }

    /// Each block is one colour: the black and white either side of the
    /// middle fall in one block and come out the same.
    func testPixelateMakesFlatBlocks() throws {
        let out = ImageFilterEngine.apply(.none, adjustments: .neutral, duotone: nil,
                                          effects: PhotoEffects.Plan(block: 16, focus: nil),
                                          to: halves(), cacheKey: UUID().uuidString)
        let a = try pixel(out, x: 17, y: 20).red
        let b = try pixel(out, x: 30, y: 20).red
        XCTAssertEqual(a, b, accuracy: 2, "a block is not one colour")
        // The blocks meet at the middle, so each side keeps its own colour.
        XCTAssertLessThan(a, 128)
        XCTAssertGreaterThan(try pixel(out, x: 40, y: 20).red, 128)
    }

    func testNoEffectsLeaveThePictureAlone() {
        let source = halves()
        XCTAssertIdentical(ImageFilterEngine.apply(.none, adjustments: .neutral, duotone: nil,
                                                   effects: .none, to: source, cacheKey: "plain"),
                           source)
    }

    /// The edge is a picture larger than the frame by its reach, coloured
    /// past the frame and clear well beyond it.
    func testAnOutlineReachesPastTheFrame() throws {
        var photo = Element.image("media:a", w: 64, h: 64)
        photo.edge = PhotoEdge(kind: "outline", color: "#ff0000", width: 50)
        let edge = try XCTUnwrap(PhotoEffects.edge(photo, picture: halves(), key: UUID().uuidString))
        XCTAssertGreaterThanOrEqual(edge.pad, 10)
        let drawn = try XCTUnwrap(edge.image.cgImage)
        let scale = Double(drawn.width) / (64 + 2 * edge.pad)
        // Five page units out from the frame's left edge, half way down.
        let x = Int(((edge.pad - 5) * scale).rounded())
        let y = drawn.height / 2
        let near = try pixel(edge.image, x: x, y: y)
        XCTAssertGreaterThan(near.alpha, 200, "the outline is not there")
        XCTAssertGreaterThan(near.red, 200, "the outline is not in its colour")
        XCTAssertLessThan(try pixel(edge.image, x: 0, y: 0).alpha, 10, "the outline fills its whole picture")
        // None at all, no picture.
        photo.edge = nil
        XCTAssertNil(PhotoEffects.edge(photo, picture: halves(), key: "none"))
    }
}
