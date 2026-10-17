// Crop mode's second row — the frame's shape, the straighten dial, a
// quarter turn and a flip — by the same rules as the Android twin's crop
// bar, so the two phones write the same numbers; and the row as part of
// the one open crop step, which Cancel puts back and Done keeps as one Undo.

import XCTest
import UIKit
@testable import Canvia

final class CropToolsTests: XCTestCase {

    // A 400 x 300 picture in a 200 x 200 frame at (100, 100): covering takes
    // scale 2/3, so the picture is drawn 266.67 x 200, overflowing 66.67
    // sideways.
    private let image = CGSize(width: 400, height: 300)

    private func photo(w: Double = 200, h: Double = 200) -> Element {
        var el = Element.image("media:x", w: w, h: h)
        el.x = 100; el.y = 100
        return el
    }

    /// Shared rows: the largest box of the ratio inside a 200 x 200 frame,
    /// centred on it — the frame only ever shrinks, with no rounding.
    func testTrimmedToRatioKeepsTheLargestCentredBox() {
        // ratio, width, height
        let rows: [(Double, Double, Double)] = [
            (4.0 / 5, 160, 200),
            (16.0 / 9, 200, 112.5),
            (9.0 / 16, 112.5, 200),
            (3.0 / 2, 200, 133.333333),
            (4.0 / 3, 200, 150),
            (1, 200, 200),
        ]
        for (ratio, w, h) in rows {
            let out = Crop.trimmedToRatio(photo(), ratio: ratio, image: image)
            XCTAssertEqual(out.w, w, accuracy: 1e-5, "\(ratio) width")
            XCTAssertEqual(out.h, h, accuracy: 1e-5, "\(ratio) height")
            XCTAssertEqual(out.x + out.w / 2, 200, accuracy: 1e-9, "\(ratio) centre x")
            XCTAssertEqual(out.y + out.h / 2, 200, accuracy: 1e-9, "\(ratio) centre y")
        }
        // Original is the picture's own shape: 4:3 here.
        XCTAssertEqual(CropAspect.original.ratio(image: image) ?? 0, 4.0 / 3, accuracy: 1e-9)
        XCTAssertNil(CropAspect.free.ratio(image: image))
        // A frame already that shape, and a ratio that is no ratio, are left as they are.
        let square = photo()
        XCTAssertEqual(Crop.trimmedToRatio(square, ratio: 1, image: image), square)
        XCTAssertEqual(Crop.trimmedToRatio(square, ratio: 0, image: image), square)
        XCTAssertEqual(Crop.trimmedToRatio(square, ratio: -2, image: image), square)
    }

    /// The picture does not move on the page as the frame is trimmed to a
    /// shape: its corner lands where it was, and the zoom is unchanged.
    func testTrimmingToARatioLeavesThePictureWhereItWas() {
        var el = photo()
        el.cropScale = 1.5; el.cropX = 0.2; el.cropY = 0.8
        let before = Crop.picture(el, image: image)
        let beforeCorner = Crop.toPage(el, before.origin)
        let out = Crop.trimmedToRatio(el, ratio: 4.0 / 5, image: image)
        let after = Crop.picture(out, image: image)
        let afterCorner = Crop.toPage(out, after.origin)
        XCTAssertEqual(Double(afterCorner.x), Double(beforeCorner.x), accuracy: 1e-6)
        XCTAssertEqual(Double(afterCorner.y), Double(beforeCorner.y), accuracy: 1e-6)
        XCTAssertEqual(Double(after.width), Double(before.width), accuracy: 1e-6)
        XCTAssertEqual(out.cropScale ?? 0, 1.5, accuracy: 1e-6, "the zoom changed with the shape")
        // Turned, the same: the frame's centre is the turn's.
        var turned = el
        turned.rotation = 30
        let spun = Crop.trimmedToRatio(turned, ratio: 16.0 / 9, image: image)
        XCTAssertEqual(spun.rotation, 30)
        XCTAssertEqual(spun.x + spun.w / 2, 200, accuracy: 1e-9)
        XCTAssertEqual(spun.y + spun.h / 2, 200, accuracy: 1e-9)
        let spunCorner = Crop.toPage(spun, Crop.picture(spun, image: image).origin)
        let wasCorner = Crop.toPage(turned, Crop.picture(turned, image: image).origin)
        XCTAssertEqual(Double(spunCorner.x), Double(wasCorner.x), accuracy: 1e-6)
        XCTAssertEqual(Double(spunCorner.y), Double(wasCorner.y), accuracy: 1e-6)
    }

    /// The chip lit is the first whose shape the frame has, Original before
    /// 4:3 for a 4:3 picture, and Free when none does.
    func testTheLitChipIsTheFrameShape() {
        XCTAssertEqual(CropAspect.matching(photo(), image: image), .square)
        XCTAssertEqual(CropAspect.matching(photo(w: 400, h: 300), image: image), .original)
        XCTAssertEqual(CropAspect.matching(photo(w: 400, h: 300), image: CGSize(width: 10, height: 10)), .fourThree)
        XCTAssertEqual(CropAspect.matching(photo(w: 200, h: 113), image: image), .sixteenNine)
        XCTAssertEqual(CropAspect.matching(photo(w: 123, h: 200), image: image), .free)
        XCTAssertEqual(CropAspect.allCases.map(\.name), ["Free", "Original", "1:1", "4:5", "3:2", "4:3", "16:9", "9:16"])
    }

    /// Rotate 90: a quarter turn clockwise about the centre, the sides
    /// swapped, the angle kept within a turn, the crop numbers as they were.
    func testRotate90SwapsTheSidesAboutTheCentre() {
        var el = photo(w: 200, h: 100)
        el.cropScale = 2; el.cropX = 0.3
        let out = Crop.rotated90(el)
        XCTAssertEqual(out.w, 100); XCTAssertEqual(out.h, 200)
        XCTAssertEqual(out.x, 150); XCTAssertEqual(out.y, 50)
        XCTAssertEqual(out.rotation, 90)
        XCTAssertEqual(out.cropScale ?? 0, 2); XCTAssertEqual(out.cropX ?? 0, 0.3)
        el.rotation = 350
        XCTAssertEqual(Crop.rotated90(el).rotation, 80, accuracy: 1e-9)
        el.rotation = -30
        XCTAssertEqual(Crop.rotated90(el).rotation, 60, accuracy: 1e-9)
    }

    /// Shared rows: the dial writes half degrees, a half up, within ±45,
    /// and nothing at level.
    func testTheStraightenDialStepsByHalfDegrees() {
        // dialled, written (0 for nil)
        let rows: [(Double, Double)] = [
            (12.26, 12.5), (12.24, 12), (0.25, 0.5), (0.24, 0), (-0.2, 0), (-0.26, -0.5),
            (50, 45), (-50, -45), (0, 0), (-12.74, -12.5), (-12.76, -13),
        ]
        for (dialled, written) in rows {
            XCTAssertEqual(Crop.steppedStraighten(dialled) ?? 0, written, accuracy: 1e-9, "\(dialled)")
        }
        XCTAssertNil(Crop.steppedStraighten(0.2))
        XCTAssertNil(Crop.steppedStraighten(.nan))
        XCTAssertEqual(Crop.straightenReadout(12.5), "12.5 deg")
        XCTAssertEqual(Crop.straightenReadout(-3), "-3.0 deg")
        XCTAssertEqual(Crop.straightenReadout(nil), "0.0 deg")
        XCTAssertEqual(Crop.straightenReach, 45)
        XCTAssertEqual(Crop.straightenStep, 0.5)
    }

    // MARK: the mode

    private func store(with photo: Element) -> DesignStore {
        var design = Design(title: "crop", width: 600, height: 600)
        design.pages[0].elements = [photo]
        return DesignStore(design: design)
    }

    private var libraryPhoto: Element {
        var el = Element.image("asset:" + (PhotoLibrary.photos.first?.id ?? "none"), w: 300, h: 200)
        el.x = 50; el.y = 50
        return el
    }

    /// The shape, the dial, the turn and the flip are all inside the one
    /// crop step: Cancel puts every one of them back and records nothing,
    /// Done keeps them as a single Undo.
    func testTheSecondRowIsPartOfTheOneCropStep() {
        let original = libraryPhoto
        let s = store(with: original)
        s.select(original.id)
        XCTAssertTrue(s.startCrop(original.id))
        s.setCropAspect(.square)
        XCTAssertEqual(s.cropElement?.w ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(s.cropElement?.h ?? 0, 200, accuracy: 1e-9)
        s.setCropStraighten(7.3)
        XCTAssertEqual(s.cropElement?.straighten ?? 0, 7.5, accuracy: 1e-9)
        s.rotateCrop90()
        XCTAssertEqual(s.cropElement?.rotation ?? 0, 90)
        s.flipCrop()
        XCTAssertEqual(s.cropElement?.flipH, true)
        s.flipCrop()
        XCTAssertEqual(s.cropElement?.flipH, false)
        s.cancelCrop()
        XCTAssertEqual(s.element(original.id), original, "Cancel put the photo back differently")
        XCTAssertFalse(s.canUndo, "Cancel recorded a step")

        XCTAssertTrue(s.startCrop(original.id))
        s.setCropAspect(.fourFive)
        s.setCropStraighten(-2)
        s.flipCrop()
        s.finishCrop()
        let kept = s.element(original.id)
        XCTAssertEqual(kept?.w ?? 0, 160, accuracy: 1e-9)
        XCTAssertEqual(kept?.h ?? 0, 200, accuracy: 1e-9)
        XCTAssertEqual(kept?.straighten ?? 0, -2, accuracy: 1e-9)
        XCTAssertEqual(kept?.flipH, true)
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertEqual(s.element(original.id), original, "the crop was more than one step")
        // Free changes nothing, and the dial back at level leaves no key.
        XCTAssertTrue(s.startCrop(original.id))
        s.setCropAspect(.free)
        s.setCropStraighten(3)
        s.setCropStraighten(0.1)
        XCTAssertEqual(s.cropElement, original)
        s.finishCrop()
        XCTAssertFalse(s.canUndo, "a crop that changed nothing was recorded")
    }

    /// A photo locked in position keeps its frame: the shapes and the turn
    /// wait, while the dial and the flip, which leave the frame be, work.
    func testAPhotoLockedInPositionKeepsItsFrame() {
        var held = libraryPhoto
        held.lockPosition = true
        let s = store(with: held)
        s.select(held.id)
        XCTAssertTrue(s.startCrop(held.id))
        s.setCropAspect(.square)
        s.rotateCrop90()
        XCTAssertEqual(s.cropElement?.w ?? 0, 300)
        XCTAssertEqual(s.cropElement?.rotation ?? 0, 0)
        s.flipCrop()
        s.setCropStraighten(4)
        XCTAssertEqual(s.cropElement?.flipH, true)
        XCTAssertEqual(s.cropElement?.straighten ?? 0, 4, accuracy: 1e-9)
    }
}
