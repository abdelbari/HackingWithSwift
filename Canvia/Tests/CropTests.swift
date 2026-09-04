// Straightening inside a frame, the subject finder, and PDF pages as
// pictures.

import XCTest
import UIKit
@testable import Canvia

final class CropTests: XCTestCase {

    // MARK: straighten

    func testALevelPictureNeedsNoExtraCover() {
        XCTAssertEqual(Geometry.coverScale(width: 300, height: 200, degrees: 0), 1)
        XCTAssertEqual(Geometry.coverScale(width: 300, height: 200, degrees: 360), 1, accuracy: 1e-9)
    }

    func testAQuarterTurnOfALandscapeFrameNeedsItsAspectRatio() {
        // Turned 90°, the frame's box is 200 wide and 300 tall; the picture
        // must reach 300 tall, so it grows by 300/200.
        XCTAssertEqual(Geometry.coverScale(width: 300, height: 200, degrees: 90), 1.5, accuracy: 1e-9)
        XCTAssertEqual(Geometry.coverScale(width: 300, height: 200, degrees: -90), 1.5, accuracy: 1e-9)
    }

    func testASmallTiltGrowsALittleAndMonotonically() {
        var previous = 1.0
        for degrees in stride(from: 1.0, through: 45, by: 4) {
            let s = Geometry.coverScale(width: 400, height: 300, degrees: degrees)
            XCTAssertGreaterThan(s, previous, "\(degrees)° did not need more cover than the angle before")
            previous = s
        }
        // A square turned 45° needs exactly √2.
        XCTAssertEqual(Geometry.coverScale(width: 100, height: 100, degrees: 45), 2.0.squareRoot(), accuracy: 1e-9)
    }

    // MARK: subject

    /// A bright disc on a dark field, off-centre. The one thing to get wrong
    /// is Vision's bottom-left origin, so the check is which quarter the
    /// focus lands in.
    func testTheFocusLandsOnTheSubjectsQuarter() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300), format: format).image { ctx in
            UIColor(white: 0.1, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            UIColor.orange.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 40, y: 30, width: 90, height: 90))   // top-left
        }
        guard let point = SmartCrop.focalPoint(in: image) else {
            throw XCTSkip("saliency found no subject in this environment")
        }
        XCTAssertLessThan(point.x, 0.5, "\(point)")
        XCTAssertLessThan(point.y, 0.5, "the focus is on the wrong half vertically: \(point) — origin flipped?")
    }

    // MARK: pdf

    /// Two pages of different shapes, the first with a red mark in its top-left
    /// corner: page count, aspect ratio and orientation in one document.
    func testPDFPagesComeOutUprightAtTheirOwnShape() throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 100))
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 50))          // top-left in UIKit space
            ctx.beginPage(withBounds: CGRect(x: 0, y: 0, width: 100, height: 200), pageInfo: [:])
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 200))
        }
        let pages = PDFImporter.pages(of: data, maxEdge: 400)
        XCTAssertEqual(pages.count, 2)
        let first = try XCTUnwrap(pages.first), second = try XCTUnwrap(pages.last)
        XCTAssertEqual(first.size.width / first.size.height, 2, accuracy: 0.01)
        XCTAssertEqual(second.size.width / second.size.height, 0.5, accuracy: 0.01)
        XCTAssertEqual(first.size.width, 400, accuracy: 1, "the long edge is the requested size")

        let topLeft = try rgb(first, x: 10, y: 10)
        let bottomRight = try rgb(first, x: Int(first.size.width) - 10, y: Int(first.size.height) - 10)
        XCTAssertGreaterThan(topLeft.r, 200, "the red mark is not at the top-left: the page is flipped")
        XCTAssertLessThan(topLeft.g, 60)
        XCTAssertGreaterThan(bottomRight.g, 200, "the rest of the page is not white")
    }

    func testAFileThatIsNotAPDFImportsNothing() {
        XCTAssertTrue(PDFImporter.pages(of: Data("not a pdf".utf8)).isEmpty)
    }

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
}
