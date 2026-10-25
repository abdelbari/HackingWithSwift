// Expand photo: the plan, the three shared borders (Fixtures/photo-expand.json,
// byte for byte the Android twin's: exact for mirror and stretch, within 2 a
// channel for blur), the fill, and the element's `expandedFrom` — written,
// undone, dropped by Replace, its retouched faces moved with the picture.

import XCTest
import CoreGraphics
@testable import Canvia

final class PhotoExpandTests: XCTestCase {

    /// The fixture's picture: opaque, each pixel (x*8 mod 256, y*12 mod 256,
    /// (x*5 + y*7) mod 256).
    private func picture(_ w: Int, _ h: Int) -> [Int] {
        (0..<(w * h)).map { i in
            let x = i % w, y = i / w
            return (0xff << 24) | ((x * 8 % 256) << 16) | ((y * 12 % 256) << 8) | ((x * 5 + y * 7) % 256)
        }
    }

    func testTheSharedRowsGrowAPictureTheSameOnBothPhones() throws {
        let cases = try XCTUnwrap(try SharedFixture.object("photo-expand")["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for row in cases {
            let w = try XCTUnwrap(row["w"] as? Int), h = try XCTUnwrap(row["h"] as? Int)
            let ratio = try XCTUnwrap(row["ratio"] as? String)
            let mode = try XCTUnwrap(row["mode"] as? String)
            let aspect = try XCTUnwrap(PhotoExpand.ratios.first { $0.key == ratio }?.aspect)
            let plan = try XCTUnwrap(PhotoExpand.plan(w, h, aspect: aspect))
            XCTAssertEqual([plan.width, plan.height, plan.x, plan.y],
                           [row["width"], row["height"], row["x"], row["y"]].map { $0 as? Int ?? -1 }, "\(w) x \(h) to \(ratio)")
            let out = PhotoExpand.expand(picture(w, h), w, h, plan: plan, mode: mode)
            let want = try XCTUnwrap(row["out"] as? String).split(separator: " ").map { Int($0, radix: 16) ?? -1 }
            XCTAssertEqual(want.count, out.count)
            let tolerance = mode == PhotoExpand.blur ? 2 : 0
            for i in want.indices where i < out.count {
                for shift in [16, 8, 0] {
                    let d = abs(((out[i] >> shift) & 0xff) - ((want[i] >> shift) & 0xff))
                    XCTAssertLessThanOrEqual(d, tolerance, "\(mode) \(ratio) pixel \(i)")
                }
                XCTAssertEqual((out[i] >> 24) & 0xff, 0xff)
            }
        }
    }

    func testAPlanGrowsOneSideKeepsThePictureWholeAndStaysWithinTheLongestSide() throws {
        // Already that shape: nothing to grow.
        XCTAssertNil(PhotoExpand.plan(400, 400, aspect: 1))
        let tall = try XCTUnwrap(PhotoExpand.plan(400, 300, aspect: 9.0 / 16))
        XCTAssertEqual(tall, PhotoExpand.Plan(width: 400, height: 711, x: 0, y: 205, w: 400, h: 300))
        XCTAssertEqual(tall.rect, CGRect(x: 0, y: 0.2883, width: 1, height: 0.4219))
        // Past the longest side, every side scaled alike.
        let big = try XCTUnwrap(PhotoExpand.plan(4000, 3000, aspect: 9.0 / 16, maxEdge: 2048))
        XCTAssertEqual([big.width, big.height, big.w, big.h], [1152, 2048, 1152, 864])
        XCTAssertEqual(PhotoExpand.plan(800, 900, aspect: 16.0 / 9),
                       PhotoExpand.Plan(width: 1600, height: 900, x: 400, y: 0, w: 800, h: 900))
    }

    func testMirrorReflectsWithTheEdgePixelRepeatedAndTheFillClosesTheBorder() throws {
        XCTAssertEqual((-3...5).map { PhotoExpand.reflect($0, 3) }, [2, 1, 0, 0, 1, 2, 2, 1, 0])
        XCTAssertEqual(PhotoExpand.reflect(7, 1), 0)
        XCTAssertEqual(PhotoExpand.dimmed(0xffffffff), 0xffe6e6e6)
        // Fill: the border takes the picture's colour; the middle is as it was.
        let px = [Int](repeating: 0xff3366cc, count: 20 * 20)
        let plan = try XCTUnwrap(PhotoExpand.plan(20, 20, aspect: 2))
        let filled = PhotoExpand.filled(px, 20, 20, plan: plan)
        XCTAssertEqual(filled.count, 40 * 20)
        XCTAssertEqual(filled[0], 0xff3366cc)
        XCTAssertEqual(filled[20 * 40 - 1], 0xff3366cc)
        XCTAssertEqual(filled[10 * 40 + 20], 0xff3366cc)
    }

    func testAnExpandedPhotoSaysWhatItCameFromAndGoesBackToIt() throws {
        var photo = Element.image("media:a", w: 400, h: 300)
        photo.x = 100
        photo.y = 50
        photo.cropScale = 1.4
        let plan = try XCTUnwrap(PhotoExpand.plan(800, 600, aspect: 1))
        let expanded = PhotoExpand.expanded(photo, src: "media:b", original: "media:a", plan: plan, mode: PhotoExpand.mirror)
        XCTAssertEqual(expanded.src, "media:b")
        // Grown to a square about its centre; the picture covering it.
        XCTAssertEqual(expanded.frame, CGRect(x: 100, y: 0, width: 400, height: 400))
        XCTAssertEqual(expanded.cropScale, 1)
        let origin = try XCTUnwrap(expanded.expandedFrom)
        XCTAssertEqual(origin, PhotoExpand.Origin(src: "media:a", rect: CGRect(x: 0, y: 0.125, width: 1, height: 0.75),
                                                  mode: PhotoExpand.mirror))
        // The key as both phones write it, and read back.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(origin), as: UTF8.self),
                       #"{"mode":"mirror","rect":{"h":0.75,"w":1,"x":0,"y":0.125},"src":"media:a"}"#)
        let again = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(expanded))
        XCTAssertEqual(again.expandedFrom, origin)
        // Read leniently: an unknown fill is Blur, no rect is none.
        let odd = try JSONDecoder().decode(PhotoExpand.Origin.self,
                                           from: Data(#"{"src":"media:a","rect":{"x":0,"y":0,"w":1,"h":1},"mode":"swirl"}"#.utf8))
        XCTAssertEqual(odd.mode, PhotoExpand.blur)
        XCTAssertThrowsError(try JSONDecoder().decode(PhotoExpand.Origin.self, from: Data(#"{"src":"media:a"}"#.utf8)))
        XCTAssertEqual(PhotoExpand.aspect(of: origin, 800, 600), 1, accuracy: 1e-9)
        // Undo expand: the original, its frame the part it covered.
        let back = try XCTUnwrap(PhotoExpand.undone(expanded))
        XCTAssertEqual(back.src, "media:a")
        XCTAssertEqual(back.frame, CGRect(x: 100, y: 50, width: 400, height: 300))
        XCTAssertNil(back.expandedFrom)
        XCTAssertNil(PhotoExpand.undone(photo))
        // Replace drops it.
        XCTAssertNil(Crop.replaced(expanded, src: "media:c").expandedFrom)
    }

    /// The Android twin's PhotoExpandTest has the same row.
    func testAltTextDrawnFromThePictureFollowsItSoAReplaceStillDropsIt() throws {
        var photo = Element.image("media:a")
        photo.altText = "A dog"
        photo.altTextSource = "media:a"
        let plan = try XCTUnwrap(PhotoExpand.plan(100, 100, aspect: 2))
        let expanded = PhotoExpand.expanded(photo, src: "media:b", original: "media:a", plan: plan, mode: PhotoExpand.blur)
        XCTAssertEqual(expanded.altTextSource, "media:b")
        XCTAssertNil(Crop.replaced(expanded, src: "media:c").altText)
        let back = try XCTUnwrap(PhotoExpand.undone(expanded))
        XCTAssertEqual(back.altTextSource, "media:a")
        XCTAssertNil(Crop.replaced(back, src: "media:c").altText)
        // Typed alt text names no picture, and stays.
        photo.altTextSource = nil
        let typed = PhotoExpand.expanded(photo, src: "media:b", original: "media:a", plan: plan, mode: PhotoExpand.blur)
        XCTAssertNil(typed.altTextSource)
        XCTAssertEqual(Crop.replaced(typed, src: "media:c").altText, "A dog")
    }

    func testRetouchedFacesMoveWithThePictureTheyAreOn() throws {
        var photo = Element.image("media:a")
        photo.retouchFace = FaceRetouch(amount: 0.5, faces: [FaceRetouch.Face(x: 0, y: 0, w: 0.5, h: 0.5)])
        let plan = try XCTUnwrap(PhotoExpand.plan(100, 100, aspect: 2))
        let expanded = PhotoExpand.expanded(photo, src: "media:b", original: "media:a", plan: plan, mode: PhotoExpand.blur)
        XCTAssertEqual(expanded.retouchFace?.faces, [FaceRetouch.Face(x: 0.25, y: 0, w: 0.25, h: 0.5)])
        XCTAssertEqual(PhotoExpand.undone(expanded)?.retouchFace?.faces, [FaceRetouch.Face(x: 0, y: 0, w: 0.5, h: 0.5)])
        XCTAssertNotNil(expanded.expandedFrom)
    }

    func testExpandingAgainAndChangeFillGrowFromTheOriginalNotTheExpandedPicture() throws {
        // A 400 x 300 photo in a 200 x 150 frame with a face; the Android
        // twin's PhotoExpandTest has the same row.
        var photo = Element.image("media:a", w: 200, h: 150)
        photo.retouchFace = FaceRetouch(amount: 0.5, faces: [FaceRetouch.Face(x: 0.2, y: 0.4, w: 0.3, h: 0.3)])
        let squarePlan = try XCTUnwrap(PhotoExpand.plan(400, 300, aspect: 1))
        let square = PhotoExpand.expanded(photo, src: "media:b", original: "media:a", plan: squarePlan, mode: PhotoExpand.blur)
        XCTAssertEqual(square.frame, CGRect(x: 0, y: -25, width: 200, height: 200))
        XCTAssertEqual(square.retouchFace?.faces, [FaceRetouch.Face(x: 0.2, y: 0.425, w: 0.3, h: 0.225)])
        // Then 16:9: the same as one expand to 16:9 from the original, the
        // original still 200 x 150 on the page.
        let wide = try XCTUnwrap(PhotoExpand.plan(400, 300, aspect: 16.0 / 9))
        let once = PhotoExpand.expanded(photo, src: "media:c", original: "media:a", plan: wide, mode: PhotoExpand.blur)
        let twice = PhotoExpand.expanded(square, src: "media:c", original: "media:a", plan: wide, mode: PhotoExpand.blur)
        XCTAssertEqual(twice.frame, once.frame)
        XCTAssertEqual(twice.retouchFace, once.retouchFace)
        XCTAssertEqual(twice.expandedFrom, once.expandedFrom)
        XCTAssertEqual(twice.h, 150, accuracy: 1e-9)
        let rect = try XCTUnwrap(twice.expandedFrom?.rect)
        XCTAssertEqual(twice.w * Double(rect.width), 200, accuracy: 0.1)
        // Change fill (same shape, another fill) keeps the frame and the face where they were.
        let refilled = PhotoExpand.expanded(twice, src: "media:d", original: "media:a", plan: wide, mode: PhotoExpand.mirror)
        XCTAssertEqual(refilled.frame, twice.frame)
        XCTAssertEqual(refilled.retouchFace, twice.retouchFace)
        XCTAssertEqual(refilled.expandedFrom?.mode, PhotoExpand.mirror)
    }

    func testOnlyAStillPhotoIsExpanded() {
        XCTAssertTrue(DesignStore.isStillPhoto(Element.image("media:a")))
        XCTAssertFalse(DesignStore.isStillPhoto(Element.image("video:abc")))
        XCTAssertFalse(DesignStore.isStillPhoto(Element.image("qr:hello")))
        XCTAssertFalse(DesignStore.isStillPhoto(Element.shape("rect")))
        XCTAssertEqual(PhotoExpand.ratios.map(\.key), ["page", "1:1", "4:5", "9:16", "16:9"])
        XCTAssertEqual(PhotoExpand.modes.map(\.key), ["blur", "mirror", "stretch", "fill"])
    }
}
