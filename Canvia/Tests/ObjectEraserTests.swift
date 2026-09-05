// The object eraser: mapping a page stroke into the picture, the mask, the
// onion-peel fill and the whole erase on a synthetic photo.

import XCTest
import UIKit
@testable import Canvia

final class ObjectEraserTests: XCTestCase {

    func testPagePointsMapIntoThePictureThroughFillCropAndRotation() {
        var el = Element.image("asset:x", w: 400, h: 200)
        el.x = 100; el.y = 50
        let size = CGSize(width: 800, height: 400)   // same aspect as the frame
        // Frame centre is the picture's centre; a corner is a corner.
        XCTAssertEqual(ObjectEraser.imagePoint(CGPoint(x: 300, y: 150), element: el, imageSize: size), CGPoint(x: 400, y: 200))
        XCTAssertEqual(ObjectEraser.imagePoint(CGPoint(x: 100, y: 50), element: el, imageSize: size), CGPoint(x: 0, y: 0))
        // Zoomed 2× about the centre: the frame's corner is a quarter in.
        el.cropScale = 2
        let z = ObjectEraser.imagePoint(CGPoint(x: 100, y: 50), element: el, imageSize: size)
        XCTAssertEqual(z.x, 200, accuracy: 0.001); XCTAssertEqual(z.y, 100, accuracy: 0.001)
        el.cropScale = nil
        // A tall picture filling a wide frame: the frame shows its middle band.
        let tall = CGSize(width: 400, height: 800)
        let top = ObjectEraser.imagePoint(CGPoint(x: 300, y: 50), element: el, imageSize: tall)
        XCTAssertEqual(top.x, 200, accuracy: 0.001)
        XCTAssertEqual(top.y, 300, accuracy: 0.001, "the frame's top edge is 300px into an 800px picture")
        // Rotated 90° clockwise: a page point 100 above the centre was, before
        // the turn, 100 to the left of it — a quarter of the way in.
        el.rotation = 90
        let r = ObjectEraser.imagePoint(CGPoint(x: 300, y: 50), element: el, imageSize: size)
        XCTAssertEqual(r.x, 200, accuracy: 0.01); XCTAssertEqual(r.y, 200, accuracy: 0.01)
    }

    func testMaskPaintsTheStrokeWhiteWhereItGoes() throws {
        let mask = try XCTUnwrap(ObjectEraser.mask(size: CGSize(width: 100, height: 60), strokes: [[CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10)]], width: 8))
        var px = [UInt8](repeating: 0, count: 100 * 60)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 100, height: 60, bitsPerComponent: 8, bytesPerRow: 100,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        ctx.draw(mask, in: CGRect(x: 0, y: 0, width: 100, height: 60))
        // The drawn context has row 0 at the bottom: y=10 from the top is row 49.
        XCTAssertGreaterThan(px[49 * 100 + 50], 200, "on the stroke")
        XCTAssertEqual(px[10 * 100 + 50], 0, "far from the stroke, at the top-of-image's mirror")
        XCTAssertEqual(px[49 * 100 + 2], 0, "before the stroke's start")
    }

    func testPeelFillClosesAHoleFromItsNeighbours() {
        let w = 8, h = 8
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for p in 0..<(w * h) { pixels[p * 4] = 10; pixels[p * 4 + 1] = 200; pixels[p * 4 + 2] = 30; pixels[p * 4 + 3] = 255 }
        var masked = [Bool](repeating: false, count: w * h)
        for y in 2...5 { for x in 2...5 { masked[y * w + x] = true; pixels[(y * w + x) * 4] = 255; pixels[(y * w + x) * 4 + 1] = 0 } }
        ObjectEraser.peelFill(pixels: &pixels, masked: masked, width: w, height: h)
        let centre = (4 * w + 4) * 4
        XCTAssertEqual(pixels[centre], 10); XCTAssertEqual(pixels[centre + 1], 200)
    }

    func testErasingARedSquareLeavesGreen() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let img = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format).image { ctx in
            UIColor(red: 0.1, green: 0.8, blue: 0.2, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            UIColor.red.setFill(); ctx.fill(CGRect(x: 80, y: 80, width: 40, height: 40))
        }
        let out = try XCTUnwrap(ObjectEraser.erase(img, strokes: [[CGPoint(x: 75, y: 100), CGPoint(x: 125, y: 100)]], width: 56))
        XCTAssertEqual(out.size, img.size)
        let cg = try XCTUnwrap(out.cgImage)
        var px = [UInt8](repeating: 0, count: 200 * 200 * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: 200, height: 200, bitsPerComponent: 8, bytesPerRow: 800,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 200, height: 200))
        let c = (100 * 200 + 100) * 4
        XCTAssertLessThan(px[c], 110, "red is gone at the centre: \(px[c]) \(px[c + 1]) \(px[c + 2])")
        XCTAssertGreaterThan(px[c + 1], 120, "green filled in")
        // Untouched far away.
        let corner = (10 * 200 + 10) * 4
        XCTAssertGreaterThan(px[corner + 1], 180)
        // No strokes: nothing to do.
        XCTAssertNil(ObjectEraser.erase(img, strokes: [], width: 20))
    }
}
