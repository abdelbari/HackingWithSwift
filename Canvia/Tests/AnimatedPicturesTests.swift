// Animated GIFs and WebPs as elements: the frame at a moment, the source
// grammar, what a design file carries, and a real GIF stored, timed and
// decoded — the same rows as the Android twin's AnimatedImagesTest.

import XCTest
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import Canvia

final class AnimatedPicturesTests: XCTestCase {

    // MARK: the frame at a moment — the same rows as the Android twin's

    func testTheFrameAtAMomentLoopsOverTheDelaysNoneShorterThan20ms() {
        // As the file has them: the third asks for none, and is shown for 20.
        let delays = [100, 50, 0, 200]
        XCTAssertEqual(AnimStore.duration(delays), 370)
        let rows: [(Double, Int)] = [
            (0.0, 0), (0.099, 0), (0.1, 1), (0.149, 1), (0.15, 2), (0.169, 2), (0.17, 3), (0.369, 3),
            (0.37, 0), (0.52, 2), (1.0, 3), (1.25, 1), (10.0, 0), (-1.0, 0),
        ]
        for (t, frame) in rows {
            XCTAssertEqual(AnimStore.frame(at: t, delays: delays), frame, "t = \(t)")
        }
        // To the nearest millisecond: 0.0995 is 100 ms, frame 1.
        XCTAssertEqual(AnimStore.frame(at: 0.0995, delays: delays), 1)
        // One frame, or none, is always frame 0.
        XCTAssertEqual(AnimStore.frame(at: 3.0, delays: [80]), 0)
        XCTAssertEqual(AnimStore.frame(at: 3.0, delays: []), 0)
        // All asking for nothing: 20 ms each.
        XCTAssertEqual(AnimStore.frame(at: 0.045, delays: [0, 10, 0]), 2)
        XCTAssertEqual(AnimStore.start(of: 2, delays: delays), 0.15, accuracy: 1e-12)
    }

    func testAStampIsThePagesMomentToAHundredthAsAClips() {
        XCTAssertEqual(AnimStore.src("anim-1", at: nil), "anim:anim-1")
        XCTAssertEqual(AnimStore.src("anim-1", at: 1.25), "anim:anim-1@1.25")
        XCTAssertEqual(AnimStore.split("anim:anim-1@1.25")?.id, "anim-1")
        XCTAssertEqual(AnimStore.split("anim:anim-1@1.25")?.time, 1.25)
        XCTAssertEqual(AnimStore.split("anim:anim-1")?.id, "anim-1")
        XCTAssertNil(AnimStore.split("anim:anim-1")?.time)
        XCTAssertNil(AnimStore.split("video:v"))
        XCTAssertEqual(AnimStore.playing("anim:anim-1", at: 0.3), "anim:anim-1@0.30")
        // Stamped already, it keeps its moment; anything else is as it was.
        XCTAssertEqual(AnimStore.playing("anim:anim-1@0.30", at: 2), "anim:anim-1@0.30")
        XCTAssertEqual(AnimStore.playing("media:x", at: 1), "media:x")
        XCTAssertNil(AnimStore.playing(nil, at: 1))
    }

    func testAPageWithAnAnimatedPicturePlaysInAVideo() {
        var design = Design(title: "anim", width: 100, height: 100)
        design.pages[0].elements = [Element.image("anim:a")]
        XCTAssertTrue(MovieExporter.isAnimated(design.pages[0], in: design))
        XCTAssertEqual(AnimStore.ids(in: design), ["a"])
        XCTAssertFalse(DesignStore.canBecomeBackground(design.pages[0].elements[0]))
    }

    func testADesignFileCarriesTenMegabytesEachAndFiftyInAllInIdOrder() {
        let mb = 1024 * 1024
        let files: [String: (bytes: Int, ext: String)] = [
            "a": (9 * mb, "gif"),
            "b": (11 * mb, "gif"),
            "c": (2 * mb, "png"),
            "d": (10 * mb, "WEBP"),
            "e": (10 * mb, "gif"),
            "f": (10 * mb, "gif"),
            "g": (10 * mb, "gif"),
            "h": (2 * mb, "gif"),
        ]
        // b is too big and c no animation; a, d, e, f and g make 49, and h
        // would pass 50, so it stays a still.
        XCTAssertEqual(AnimStore.packedIDs(files), ["a", "d", "e", "f", "g"])
        XCTAssertEqual(AnimStore.stillID("h"), "still-h")
    }

    // MARK: a real GIF

    /// An animated GIF, 4 × 3, a frame of each colour shown for its delay
    /// in seconds.
    private func gif(_ colours: [UIColor], delays: [Double]) throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString,
                                                                         colours.count, nil))
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        for (colour, delay) in zip(colours, delays) {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 3), format: format).image { context in
                colour.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 4, height: 3))
            }
            CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay],
            ] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testAnAnimatedGIFIsStoredTimedAndDecoded() throws {
        let bytes = try gif([.red, .green, .blue], delays: [0.05, 0.12, 0.2])
        XCTAssertEqual(AnimStore.type(of: bytes), "gif")
        let brought = try XCTUnwrap(AnimStore.bringIn(bytes))
        let id = try XCTUnwrap(AnimStore.split(brought.src)?.id)
        defer { AnimStore.delete(id) }
        XCTAssertEqual(brought.src, "anim:\(id)")
        XCTAssertEqual(brought.natural, CGSize(width: 4, height: 3))
        XCTAssertEqual(AnimStore.delays(of: id), [50, 120, 200])
        XCTAssertNotNil(AnimStore.image(id, frame: 2))
        XCTAssertNil(AnimStore.image(id, frame: 3))
        XCTAssertEqual(AnimStore.frameIndex("anim:\(id)"), 0, "at rest, the first frame")
        XCTAssertEqual(AnimStore.frameIndex("anim:\(id)@0.06"), 1)
        XCTAssertEqual(AnimStore.frameIndex("anim:\(id)@0.40"), 0, "round again after 370 ms")
        XCTAssertNotNil(PhotoLibrary.resolve("anim:\(id)@0.20"))
        // Looks are kept by the frame shown: every moment in a frame is one key.
        XCTAssertEqual(AnimStore.shownKey("anim:\(id)@0.07"), AnimStore.shownKey("anim:\(id)@0.16"))
        XCTAssertEqual(AnimStore.shownKey("anim:\(id)@0.07"), "anim:\(id)@0.05")
        XCTAssertEqual(AnimStore.shownKey("anim:\(id)@0.01"), "anim:\(id)")
    }

    func testAStillGIFOrAPhotoIsNoAnimation() throws {
        XCTAssertNil(AnimStore.bringIn(try gif([.red], delays: [0.1])), "one frame is a photo")
        let png = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }.pngData())
        XCTAssertNil(AnimStore.type(of: png))
        XCTAssertNil(AnimStore.bringIn(png))
        var webp = Data("RIFF".utf8)
        webp.append(contentsOf: [0, 0, 0, 0])
        webp.append(Data("WEBP".utf8))
        XCTAssertEqual(AnimStore.type(of: webp), "webp")
        XCTAssertNil(AnimStore.bringIn(webp), "no frames in it")
    }

    // MARK: design files

    /// An animated picture travels under "animations" and comes back as one
    /// of its own under a fresh id, its moments kept.
    func testAnAnimatedPictureTravelsInADesignFile() throws {
        let bytes = try gif([.red, .green], delays: [0.1, 0.1])
        let id = try XCTUnwrap(AnimStore.store(bytes))
        defer { AnimStore.delete(id) }
        var design = Design(title: "anim", width: 320, height: 240)
        design.pages[0].elements = [Element.image(AnimStore.src(id, at: nil), w: 40, h: 30),
                                    Element.image(AnimStore.src(id, at: 1.25), w: 40, h: 30)]
        let data = try DesignPackage.export(design)
        let package = try JSONDecoder().decode(DesignPackage.Package.self, from: data)
        XCTAssertEqual(package.animations?[id]?.data, bytes)
        XCTAssertEqual(package.animations?[id]?.ext, "gif")
        XCTAssertTrue(package.media.isEmpty, "no still beside it")

        let imported = try DesignPackage.import(data)
        let sources = imported.pages[0].elements.compactMap(\.src)
        let fresh = try XCTUnwrap(AnimStore.split(sources[0])?.id)
        defer { AnimStore.delete(fresh) }
        XCTAssertNotEqual(fresh, id)
        XCTAssertEqual(sources, [AnimStore.src(fresh, at: nil), AnimStore.src(fresh, at: 1.25)])
        XCTAssertEqual(AnimStore.delays(of: fresh), [100, 100])

        let plain = try JSONSerialization.jsonObject(with: DesignPackage.export(Design(title: "Still"))) as? [String: Any]
        XCTAssertNil(plain?["animations"], "no key when there are none")
    }

    /// Past the limits, it travels as its first frame, "media:still-<id>",
    /// wherever it appears.
    func testOnePastTheLimitsTravelsAsItsFirstFrame() throws {
        let id = try XCTUnwrap(AnimStore.store(try gif([.red, .green], delays: [0.1, 0.1])))
        defer { AnimStore.delete(id) }
        var design = Design(title: "anim", width: 320, height: 240)
        var shape = Element.shape("rect", w: 100, h: 100)
        shape.fill = .image(AnimStore.src(id, at: nil))
        design.pages[0].elements = [Element.image(AnimStore.src(id, at: 0.5), w: 40, h: 30), shape]
        var media: [String: DesignPackage.Media] = [:]
        var animations: [String: DesignPackage.Media] = [:]
        let packed = DesignPackage.packingAnimations(design, media: &media, animations: &animations, whole: { _ in [] })
        XCTAssertTrue(animations.isEmpty)
        XCTAssertEqual(media["still-\(id)"]?.ext, "png")
        XCTAssertEqual(packed.pages[0].elements[0].src, "media:still-\(id)")
        XCTAssertEqual(packed.pages[0].elements[1].fill?.src, "media:still-\(id)")
    }

    /// A backup keeps an animated picture under its own id.
    func testABackupCarriesItWholeUnderItsOwnId() throws {
        let bytes = try gif([.red, .green], delays: [0.1, 0.1])
        let id = try XCTUnwrap(AnimStore.store(bytes))
        defer { AnimStore.delete(id) }
        var design = Design(title: "anim", width: 320, height: 240)
        design.pages[0].elements = [Element.image(AnimStore.src(id, at: nil), w: 40, h: 30)]
        let gathered = DesignPackage.gatheredForBackup(design, media: [:])
        XCTAssertEqual(gathered.package.animations?[id]?.data, bytes)
        var file = Data()
        try DesignPackage.stream(gathered.package, clips: gathered.clips) { file.append($0) }
        let read = try JSONDecoder().decode(DesignPackage.Package.self, from: file)
        XCTAssertEqual(read.animations?[id]?.data, bytes)

        AnimStore.delete(id)
        let restored = DesignPackage.storeKeepingIds(read)
        XCTAssertEqual(restored.pages[0].elements[0].src, AnimStore.src(id, at: nil))
        XCTAssertNotNil(AnimStore.url(for: id), "put back under its own id")
    }

    /// The launch sweep lets go of animated pictures nothing shows, and
    /// keeps one cut and waiting on the pasteboard.
    func testTheSweepKeepsOnlyAnimatedPicturesSomethingShows() throws {
        let bytes = try gif([.red, .green], delays: [0.1, 0.1])
        let kept = try XCTUnwrap(AnimStore.store(bytes))
        let orphan = try XCTUnwrap(AnimStore.store(bytes))
        defer { AnimStore.delete(kept); AnimStore.delete(orphan) }
        let board = UIPasteboard.withUniqueName()
        defer { UIPasteboard.remove(withName: board.name) }
        ElementClipboard.write([Element.image(AnimStore.src(kept, at: nil), w: 40, h: 30)], to: board)
        DesignLibrary.pruneUnusedAnimations(pasteboard: board)
        XCTAssertNotNil(AnimStore.url(for: kept), "one waiting on the pasteboard was deleted")
        XCTAssertNil(AnimStore.url(for: orphan), "one nothing shows was kept")
    }
}
