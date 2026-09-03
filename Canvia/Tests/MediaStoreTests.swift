// The user-media store: what gets written, what comes back, and what the
// launch-time sweep is allowed to delete.
//
// The sweep is the dangerous one. It deletes files by extension, and until
// cutouts arrived every file in the folder was a .jpg — so a PNG cutout, once
// written, would have been invisible to the sweep and immortal, or (had the
// filter been inverted) deleted while a design was still pointing at it.

import XCTest
import UIKit
@testable import Canvia

final class MediaStoreTests: XCTestCase {

    private var stored: [String] = []

    override func tearDown() {
        for id in stored {
            for ext in MediaStore.extensions {
                try? FileManager.default.removeItem(
                    at: MediaStore.directory.appendingPathComponent("\(id).\(ext)"))
            }
        }
        stored = []
        super.tearDown()
    }

    // MARK: fixtures

    /// An opaque picture, as JPEG bytes, the way a picker hands one over.
    private func photoData(width: Int = 400, height: Int = 300) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
        return image.jpegData(compressionQuality: 0.9)!
    }

    /// Half opaque, half fully transparent — a cutout in miniature.
    private func cutoutImage(width: Int = 120, height: Int = 80) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        }
    }

    private func track(_ src: String) -> String {
        let id = String(src.dropFirst("media:".count))
        stored.append(id)
        return id
    }

    private func fileExists(_ id: String, ext: String) -> Bool {
        FileManager.default.fileExists(
            atPath: MediaStore.directory.appendingPathComponent("\(id).\(ext)").path)
    }

    /// The alpha of one pixel, read straight out of the file rather than from
    /// the in-memory cache — the point is what survived the round trip.
    private func alpha(atX x: Int, y: Int, of id: String, ext: String) throws -> UInt8 {
        let url = MediaStore.directory.appendingPathComponent("\(id).\(ext)")
        let data = try Data(contentsOf: url)
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        // The buffer has to stay put for the draw as well as the init, so the
        // context is built and used inside the same access — `&pixel` alone
        // is only guaranteed for the duration of the call it appears in.
        try pixel.withUnsafeMutableBytes { raw in
            let context = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.interpolationQuality = .none
            // CG counts rows from the bottom; the caller counts from the top.
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                           width: image.width, height: image.height))
        }
        return pixel[3]
    }

    // MARK: round trips

    func testStoresAPickedPhotoAsJPEG() throws {
        let prepared = try XCTUnwrap(ImageDownsampler.prepare(photoData(), maxEdge: 200))
        let src = try XCTUnwrap(MediaStore.store(prepared))
        XCTAssertTrue(src.hasPrefix("media:"))
        let id = track(src)
        XCTAssertTrue(fileExists(id, ext: "jpg"))
        let loaded = try XCTUnwrap(MediaStore.load(id))
        XCTAssertEqual(loaded.size, CGSize(width: 200, height: 150))
    }

    /// A cutout's whole value is the transparency. JPEG cannot carry it, so
    /// storing one through the photo path would silently fill the background
    /// back in — black, usually.
    func testTransparentMediaKeepsItsAlpha() throws {
        let src = try XCTUnwrap(MediaStore.storeTransparent(cutoutImage()))
        let id = track(src)
        XCTAssertTrue(fileExists(id, ext: "png"))
        XCTAssertFalse(fileExists(id, ext: "jpg"))
        XCTAssertEqual(try alpha(atX: 10, y: 40, of: id, ext: "png"), 255)
        XCTAssertEqual(try alpha(atX: 110, y: 40, of: id, ext: "png"), 0)
    }

    func testLoadFindsEitherFormat() throws {
        let jpeg = try XCTUnwrap(MediaStore.store(
            try XCTUnwrap(ImageDownsampler.prepare(photoData(), maxEdge: 100))))
        let png = try XCTUnwrap(MediaStore.storeTransparent(cutoutImage()))
        XCTAssertNotNil(MediaStore.load(track(jpeg)))
        XCTAssertNotNil(MediaStore.load(track(png)))
    }

    func testLoadReturnsNilForAnUnknownID() {
        XCTAssertNil(MediaStore.load("img_does_not_exist"))
    }

    func testResolveRoutesMediaSourcesToTheStore() throws {
        let src = try XCTUnwrap(MediaStore.storeTransparent(cutoutImage()))
        _ = track(src)
        XCTAssertNotNil(PhotoLibrary.resolve(src))
        XCTAssertNil(PhotoLibrary.resolve("media:img_does_not_exist"))
        XCTAssertNil(PhotoLibrary.resolve(nil))
    }

    // MARK: the sweep

    /// Both formats have to be swept, and only when nothing points at them.
    func testPruningKeepsReferencedMediaAndDeletesTheRest() throws {
        let keptJPEG = try XCTUnwrap(MediaStore.store(
            try XCTUnwrap(ImageDownsampler.prepare(photoData(), maxEdge: 100))))
        let keptPNG = try XCTUnwrap(MediaStore.storeTransparent(cutoutImage()))
        let orphanPNG = try XCTUnwrap(MediaStore.storeTransparent(cutoutImage()))
        let keptJPEGID = track(keptJPEG)
        let keptPNGID = track(keptPNG)
        let orphanID = track(orphanPNG)

        var design = Design(title: "prune fixture")
        design.pages[0].background = .image(keptJPEG)
        design.pages[0].elements = [Element.image(keptPNG, w: 120, h: 80)]
        DesignLibrary.save(design)
        defer { DesignLibrary.delete(id: design.id) }

        DesignLibrary.pruneUnusedMedia()

        XCTAssertTrue(fileExists(keptJPEGID, ext: "jpg"), "referenced JPEG was deleted")
        XCTAssertTrue(fileExists(keptPNGID, ext: "png"), "referenced cutout was deleted")
        XCTAssertFalse(fileExists(orphanID, ext: "png"), "orphaned cutout was kept forever")
    }
}
