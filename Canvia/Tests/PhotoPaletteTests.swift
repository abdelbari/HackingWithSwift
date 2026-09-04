// A palette read out of a picture's pixels.

import XCTest
import UIKit
@testable import Canvia

final class PhotoPaletteTests: XCTestCase {

    /// A picture in blocks: red across the top two thirds, blue below, and a
    /// small green square — three colours, in that order of area.
    private func blocks(transparentCorner: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !transparentCorner
        return UIGraphicsImageRenderer(size: CGSize(width: 90, height: 90), format: format).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 90, height: 60))
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 60, width: 90, height: 30))
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 70, y: 70, width: 12, height: 12))
            if transparentCorner {
                ctx.cgContext.clear(CGRect(x: 0, y: 0, width: 45, height: 45))
            }
        }
    }

    private func channels(_ hex: String) -> (r: Int, g: Int, b: Int) {
        let v = Int(hex.dropFirst(), radix: 16) ?? 0
        return (v >> 16 & 0xff, v >> 8 & 0xff, v & 0xff)
    }

    func testTheBiggestColoursComeFirst() {
        let palette = PhotoPalette.extract(from: blocks(), count: 3)
        XCTAssertEqual(palette.count, 3, "\(palette)")
        let first = channels(palette[0]), second = channels(palette[1]), third = channels(palette[2])
        XCTAssertGreaterThan(first.r, 200, "\(palette)"); XCTAssertLessThan(first.b, 60, "\(palette)")
        XCTAssertGreaterThan(second.b, 200, "\(palette)"); XCTAssertLessThan(second.r, 60, "\(palette)")
        XCTAssertGreaterThan(third.g, 200, "\(palette)"); XCTAssertLessThan(third.r, 60, "\(palette)")
    }

    func testCountIsHonoured() {
        XCTAssertEqual(PhotoPalette.extract(from: blocks(), count: 2).count, 2)
        XCTAssertTrue(PhotoPalette.extract(from: blocks(), count: 0).isEmpty)
    }

    /// A gradient must not fill the palette with its own neighbours.
    func testNearbyShadesCollapseIntoOne() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let ramp = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 8), format: format).image { ctx in
            for x in 0..<64 {
                UIColor(red: 0.5 + CGFloat(x) / 512, green: 0.2, blue: 0.2, alpha: 1).setFill()
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: 8))
            }
        }
        // 32 distinct reds a hair apart; with the default distance they are
        // one colour.
        XCTAssertEqual(PhotoPalette.extract(from: ramp, count: 6).count, 1)
    }

    func testTransparentPixelsAreNotColours() {
        let palette = PhotoPalette.extract(from: blocks(transparentCorner: true), count: 6)
        XCTAssertFalse(palette.isEmpty)
        for hex in palette {
            let c = channels(hex)
            XCTAssertFalse(c.r < 40 && c.g < 40 && c.b < 40, "cleared pixels came out as black: \(hex)")
        }
    }
}
