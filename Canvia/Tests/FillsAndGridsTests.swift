// Pattern fills, photo grids, and the system pasteboard for elements.

import XCTest
import UIKit
@testable import Canvia

final class FillsAndGridsTests: XCTestCase {

    private func rgb(_ image: UIImage, x: Int, y: Int) throws -> (r: Double, g: Double, b: Double) {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        }
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    // MARK: patterns

    func testStripesAlternateAtTheTileWidth() throws {
        let paint = Paint.pattern("stripes", color: "#ff0000", secondary: "#0000ff", scale: 20)
        let image = Patterns.image(paint, size: CGSize(width: 80, height: 20))
        // Bars are the first half of every 20px tile: red at x 5, blue at x 15.
        XCTAssertGreaterThan(try rgb(image, x: 5, y: 10).r, 200)
        XCTAssertGreaterThan(try rgb(image, x: 15, y: 10).b, 200)
        XCTAssertGreaterThan(try rgb(image, x: 45, y: 10).r, 200)
        XCTAssertGreaterThan(try rgb(image, x: 75, y: 10).b, 200)
    }

    func testChecksAlternateInBothDirections() throws {
        let paint = Paint.pattern("checks", color: "#000000", secondary: "#ffffff", scale: 10)
        let image = Patterns.image(paint, size: CGSize(width: 40, height: 40))
        XCTAssertLessThan(try rgb(image, x: 5, y: 5).r, 60)        // (0,0) filled
        XCTAssertGreaterThan(try rgb(image, x: 15, y: 5).r, 200)   // (1,0) open
        XCTAssertGreaterThan(try rgb(image, x: 5, y: 15).r, 200)   // (0,1) open
        XCTAssertLessThan(try rgb(image, x: 15, y: 15).r, 60)      // (1,1) filled
    }

    func testEveryPatternDrawsBothColours() throws {
        for name in Patterns.names {
            let paint = Paint.pattern(name, color: "#000000", secondary: "#ffffff", scale: 12)
            let image = Patterns.image(paint, size: CGSize(width: 60, height: 60))
            // Every pixel, not a stride: a hairline grid and small dots fall
            // between any coarse sample, and the point is whether marks exist.
            var dark = 0, light = 0
            for y in 0..<60 { for x in 0..<60 {
                let c = try rgb(image, x: x, y: y)
                if c.r < 100 { dark += 1 } else if c.r > 180 { light += 1 }
            } }
            XCTAssertGreaterThan(dark, 20, "\(name) drew no marks")
            XCTAssertGreaterThan(light, 20, "\(name) covered its background")
        }
    }

    func testPaintKindsRoundTripAndOldDocumentsStillDecode() throws {
        let pattern = Paint.pattern("dots", color: "#112233", secondary: "#eeeeee", scale: 16)
        let back = try JSONDecoder().decode(Paint.self, from: JSONEncoder().encode(pattern))
        XCTAssertEqual(back, pattern)
        let old = try JSONDecoder().decode(Paint.self, from: Data(##"{"kind":"solid","color":"#ff0000"}"##.utf8))
        XCTAssertEqual(old, .solid("#ff0000"))
        XCTAssertEqual(Paint.image("asset:x").kind, "image")
    }

    func testDocumentColoursIncludeAPatternsColours() {
        var d = Design(title: "p", width: 100, height: 100)
        var el = Element.shape("rect")
        el.fill = .pattern("grid", color: "#123456", secondary: "#abcdef")
        d.pages[0].elements = [el]
        let colors = Set(ColorTools.documentColors(d))
        XCTAssertTrue(colors.contains("#123456") && colors.contains("#abcdef"), "\(colors)")
    }

    // MARK: photo grids

    func testCellsFillTheInnerAreaOneGutterApartWithoutOverlap() {
        for layout in PhotoGrids.layouts {
            let els = PhotoGrids.elements(for: layout, width: 1000, height: 800, margin: 40, gutter: 20)
            XCTAssertEqual(els.count, layout.cells.count)
            XCTAssertEqual(Set(els.compactMap(\.group)).count, 1, "\(layout.id) is not one group")
            let union = Geometry.union(els.map(Geometry.aabb))
            XCTAssertEqual(union.minX, 40, accuracy: 1, layout.id)
            XCTAssertEqual(union.minY, 40, accuracy: 1, layout.id)
            XCTAssertEqual(union.maxX, 960, accuracy: 1, layout.id)
            XCTAssertEqual(union.maxY, 760, accuracy: 1, layout.id)
            for (i, a) in els.enumerated() {
                for b in els.dropFirst(i + 1) {
                    XCTAssertFalse(a.frame.insetBy(dx: 1, dy: 1).intersects(b.frame), "\(layout.id): cells overlap")
                }
                XCTAssertTrue(a.type == .image && a.src == nil, "an empty frame, to be filled with Replace")
            }
        }
        let two = PhotoGrids.elements(for: PhotoGrids.layouts[0], width: 1000, height: 800, margin: 40, gutter: 20)
        XCTAssertEqual(two[1].x - two[0].frame.maxX, 20, accuracy: 1, "neighbours are one gutter apart")
    }

    // MARK: pasteboard

    func testElementsSurviveThePasteboardAndOfferTheirText() throws {
        let board = UIPasteboard.withUniqueName()
        let text = Element.text("Hello there")
        ElementClipboard.write([text, Element.shape("rect")], to: board)
        XCTAssertTrue(ElementClipboard.hasContent(in: board))
        let back = try XCTUnwrap(ElementClipboard.read(from: board))
        XCTAssertEqual(back.map(\.type), [.text, .shape])
        XCTAssertEqual(back[0].text, "Hello there")
        XCTAssertEqual(board.string, "Hello there", "other apps get the words")
    }

    func testTextFromAnotherAppPastesAsATextElement() throws {
        let board = UIPasteboard.withUniqueName()
        board.string = "  Quarterly results  "
        XCTAssertNil(ElementClipboard.read(from: board))
        let el = try XCTUnwrap(ElementClipboard.foreign(from: board, designWidth: 1200))
        XCTAssertEqual(el.type, .text)
        XCTAssertEqual(el.text, "Quarterly results")
        XCTAssertEqual(el.w, 720)
    }

    func testAPictureFromAnotherAppPastesAsAPhoto() throws {
        let board = UIPasteboard.withUniqueName()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        board.image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: format).image { ctx in
            UIColor.orange.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
        let el = try XCTUnwrap(ElementClipboard.foreign(from: board, designWidth: 1000))
        XCTAssertEqual(el.type, .image)
        XCTAssertEqual(el.w, 500)
        XCTAssertEqual(el.h, 250, "the picture keeps its 2:1 shape")
        XCTAssertTrue(el.src?.hasPrefix("media:") == true)
        if let id = el.src?.dropFirst(6) {
            try? FileManager.default.removeItem(at: MediaStore.directory.appendingPathComponent("\(id).jpg"))
        }
    }

    func testAnEmptyPasteboardOffersNothing() {
        let board = UIPasteboard.withUniqueName()
        XCTAssertFalse(ElementClipboard.hasContent(in: board))
        XCTAssertNil(ElementClipboard.foreign(from: board, designWidth: 1000))
    }
}
