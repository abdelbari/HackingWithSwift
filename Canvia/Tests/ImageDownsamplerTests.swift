// Photo-import decoding: size clamping, and the EXIF orientation trap.
//
// The orientation cases are the reason this file exists. Scaling during
// decode is easy to get right and easy to check; applying the camera's
// rotation while doing it is neither, and getting it wrong shows up only as
// "every portrait photo I import is on its side" — on device, with a real
// camera roll, which is exactly where nobody is running a debugger.

import XCTest
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import Canvia

final class ImageDownsamplerTests: XCTestCase {

    // MARK: fixtures

    /// A JPEG of exactly `width` x `height` stored pixels, carrying `exif` as
    /// its orientation tag. Written through CGImageDestination rather than
    /// UIImage.jpegData so the tag is guaranteed present: the tests below are
    /// about what happens when one *is* there.
    private func jpeg(width: Int, height: Int, exif: Int = 1) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Left half red, right half blue, so an unwanted transpose is visible
        // in the pixels and not only in the reported size.
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        ctx.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        let cg = ctx.makeImage()!

        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, [
            kCGImagePropertyOrientation: exif,
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    /// A PNG of `width` x `height` whose left half is opaque red and whose
    /// right half is fully transparent when `clear` is set.
    private func png(width: Int, height: Int, clear: Bool) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: clear ? width / 2 : width, height: height))
        let cg = ctx.makeImage()!
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, cg, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }

    // MARK: alpha

    /// A logo with a see-through background has to stay see-through, and
    /// only that: an opaque PNG is stored as the smaller JPEG.
    func testTransparencySurvivesImportAndOpacityDoesNotPayForIt() throws {
        let clear = try XCTUnwrap(ImageDownsampler.prepare(png(width: 64, height: 32, clear: true)))
        XCTAssertEqual(clear.ext, "png")
        XCTAssertTrue(clear.keepsAlpha)
        let stored = try XCTUnwrap(UIImage(data: clear.encoded)?.cgImage)
        XCTAssertTrue(ImageDownsampler.hasTransparentPixels(stored), "the stored copy lost its alpha")

        let solid = try XCTUnwrap(ImageDownsampler.prepare(png(width: 64, height: 32, clear: false)))
        XCTAssertEqual(solid.ext, "jpg")
        XCTAssertFalse(solid.keepsAlpha)
    }

    func testAnImageWithoutAnAlphaChannelIsNeverTransparent() throws {
        let cg = try XCTUnwrap(UIImage(data: jpeg(width: 16, height: 16))?.cgImage)
        XCTAssertFalse(ImageDownsampler.hasTransparentPixels(cg))
    }

    // MARK: size

    func testPixelSizeReadsTheHeader() {
        let size = ImageDownsampler.pixelSize(jpeg(width: 320, height: 200))
        XCTAssertEqual(size?.width, 320)
        XCTAssertEqual(size?.height, 200)
    }

    /// Orientations 5-8 are the quarter turns: the stored grid is transposed
    /// against what a viewer shows, so the size we hand to the layout has to
    /// be the transposed one. Miss this and a camera portrait is inserted
    /// into a landscape frame and squashed to fit.
    func testPixelSizeTransposesQuarterTurnedOrientations() {
        for exif in 5...8 {
            let size = ImageDownsampler.pixelSize(jpeg(width: 400, height: 200, exif: exif))
            XCTAssertEqual(size?.width, 200, "exif \(exif)")
            XCTAssertEqual(size?.height, 400, "exif \(exif)")
        }
    }

    func testPixelSizeKeepsUprightOrientations() {
        for exif in 1...4 {
            let size = ImageDownsampler.pixelSize(jpeg(width: 400, height: 200, exif: exif))
            XCTAssertEqual(size?.width, 400, "exif \(exif)")
            XCTAssertEqual(size?.height, 200, "exif \(exif)")
        }
    }

    func testPixelSizeRejectsNonImageData() {
        XCTAssertNil(ImageDownsampler.pixelSize(Data("not an image".utf8)))
        XCTAssertNil(ImageDownsampler.pixelSize(Data()))
    }

    // MARK: downsampling

    func testDownsampleClampsTheLongestEdge() {
        let image = ImageDownsampler.downsample(jpeg(width: 2000, height: 1000), maxEdge: 400)
        XCTAssertEqual(image?.size.width, 400)
        XCTAssertEqual(image?.size.height, 200)
    }

    func testDownsampleClampsHeightWhenPortrait() {
        let image = ImageDownsampler.downsample(jpeg(width: 1000, height: 2000), maxEdge: 400)
        XCTAssertEqual(image?.size.width, 200)
        XCTAssertEqual(image?.size.height, 400)
    }

    /// A picture already smaller than the limit comes back untouched. The
    /// alternative — upscaling to the limit — would inflate every sticker-
    /// sized import into a megabyte of blur.
    func testDownsampleNeverUpscales() {
        let image = ImageDownsampler.downsample(jpeg(width: 100, height: 50), maxEdge: 4000)
        XCTAssertEqual(image?.size.width, 100)
        XCTAssertEqual(image?.size.height, 50)
    }

    func testDownsampleRejectsNonImageData() {
        XCTAssertNil(ImageDownsampler.downsample(Data("not an image".utf8), maxEdge: 400))
    }

    func testDownsampleRejectsNonPositiveMaxEdge() {
        XCTAssertNil(ImageDownsampler.downsample(jpeg(width: 100, height: 50), maxEdge: 0))
    }

    /// The decoded image must come out the way a viewer would show it, not the
    /// way the sensor stored it — and with .up orientation, because the tag is
    /// gone by then and nothing downstream could correct for it.
    func testDownsampleAppliesTheOrientationTag() {
        for exif in 5...8 {
            let image = ImageDownsampler.downsample(jpeg(width: 400, height: 200, exif: exif),
                                                    maxEdge: 4000)
            XCTAssertEqual(image?.size.width, 200, "exif \(exif)")
            XCTAssertEqual(image?.size.height, 400, "exif \(exif)")
            XCTAssertEqual(image?.imageOrientation, .up, "exif \(exif)")
        }
    }

    /// The invariant the two functions have to share: whatever size we report
    /// for layout is the size we actually decode. If these ever disagree the
    /// picture is drawn stretched, at every orientation.
    func testReportedSizeAgreesWithDecodedSize() {
        for exif in 1...8 {
            let data = jpeg(width: 400, height: 200, exif: exif)
            let reported = ImageDownsampler.pixelSize(data)
            let decoded = ImageDownsampler.downsample(data, maxEdge: 4000)?.size
            XCTAssertNotNil(reported, "exif \(exif)")
            XCTAssertNotNil(decoded, "exif \(exif)")
            XCTAssertEqual(reported?.width, decoded?.width, "exif \(exif)")
            XCTAssertEqual(reported?.height, decoded?.height, "exif \(exif)")
        }
    }

    // MARK: prepare

    func testPrepareReturnsStoredBytesAtTheClampedSize() throws {
        let prepared = try XCTUnwrap(ImageDownsampler.prepare(jpeg(width: 2000, height: 1000),
                                                              maxEdge: 400))
        XCTAssertEqual(prepared.natural, CGSize(width: 2000, height: 1000))
        XCTAssertEqual(prepared.image.size, CGSize(width: 400, height: 200))
        // The bytes handed to the store must decode back at the stored size,
        // not the original's: that is the whole point of the re-encode.
        let round = try XCTUnwrap(ImageDownsampler.pixelSize(prepared.encoded))
        XCTAssertEqual(round, CGSize(width: 400, height: 200))
        XCTAssertLessThan(prepared.encoded.count, 2_000_000)
    }

    /// `natural` is the *original's* displayed size, because that is what the
    /// inserted element takes its aspect ratio from.
    func testPrepareReportsTheOriginalDisplayedSize() throws {
        let prepared = try XCTUnwrap(ImageDownsampler.prepare(jpeg(width: 2000, height: 1000, exif: 6),
                                                              maxEdge: 400))
        XCTAssertEqual(prepared.natural, CGSize(width: 1000, height: 2000))
        XCTAssertEqual(prepared.image.size, CGSize(width: 200, height: 400))
    }

    func testPrepareRejectsNonImageData() {
        XCTAssertNil(ImageDownsampler.prepare(Data("not an image".utf8)))
    }
}
