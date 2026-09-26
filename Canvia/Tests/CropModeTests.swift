// Crop mode: the picture moved, zoomed and trimmed where it sits, by the
// same rules as the Android twin's CropTest, so the two phones write the
// same crop numbers — and the mode itself, one step that Cancel undoes.

import XCTest
import UIKit
@testable import Canvia

final class CropModeTests: XCTestCase {

    // A 400 x 300 picture in a 200 x 200 frame at (100, 100): covering takes
    // scale 2/3 (height-bound), so the picture is drawn 266.67 x 200 and
    // overflows by 66.67 sideways and not at all vertically.
    private let image = CGSize(width: 400, height: 300)

    private func photo(rotation: Double = 0, flipH: Bool = false) -> Element {
        var el = Element.image("media:x", w: 200, h: 200)
        el.x = 100; el.y = 100
        el.rotation = rotation
        el.flipH = flipH
        return el
    }

    private func assertPoint(_ expected: CGPoint, _ actual: CGPoint, accuracy: Double = 1e-6,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(expected.x, actual.x, accuracy: accuracy, "x", file: file, line: line)
        XCTAssertEqual(expected.y, actual.y, accuracy: accuracy, "y", file: file, line: line)
    }

    /// Where a point of the picture — as a fraction of it — lands on the page.
    private func onPage(_ el: Element, _ u: Double, _ v: Double) -> CGPoint {
        let seen = Crop.picture(el, image: image)
        return Crop.toPage(el, CGPoint(x: seen.minX + seen.width * u, y: seen.minY + seen.height * v))
    }

    func testAFreshPhotosPictureJustCoversTheFrameCentred() {
        let seen = Crop.picture(photo(), image: image)
        XCTAssertEqual(seen.minX, -33.333333, accuracy: 1e-5)
        XCTAssertEqual(seen.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(seen.width, 266.666667, accuracy: 1e-5)
        XCTAssertEqual(seen.height, 200, accuracy: 1e-9)
    }

    /// The picture as crop mode computes it is the picture as the canvas
    /// draws it: ImageElementView's offset and zoom about the focus, worked
    /// out by hand for a zoomed, off-centre crop.
    func testTheDrawnPictureIsWhatImageElementViewDraws() {
        var el = photo()
        el.cropScale = 2; el.cropX = 0.25; el.cropY = 0.75
        let drawn = Crop.drawnPicture(el, image: image)
        // Cover 2/3 then zoom 2: 533.33 x 400, overflowing 333.33 and 200.
        let dispW = 400.0 * (2.0 / 3.0), dispH = 300.0 * (2.0 / 3.0)
        let left0 = -(dispW - 200) * 0.25, top0 = -(dispH - 200) * 0.75
        let anchor = CGPoint(x: 0.25 * 200, y: 0.75 * 200)
        XCTAssertEqual(drawn.minX, anchor.x + (left0 - anchor.x) * 2, accuracy: 1e-9)
        XCTAssertEqual(drawn.minY, anchor.y + (top0 - anchor.y) * 2, accuracy: 1e-9)
        XCTAssertEqual(drawn.width, dispW * 2, accuracy: 1e-9)
    }

    func testMovingFollowsTheFingerUntilAnEdgeReachesTheFrame() {
        let start = Crop.picture(photo(), image: image)
        let moved = Crop.moved(photo(), image: image, by: CGPoint(x: 10, y: 0))
        XCTAssertEqual(Crop.picture(moved, image: image).minX, start.minX + 10, accuracy: 1e-9)
        let pinned = Crop.moved(photo(), image: image, by: CGPoint(x: 500, y: 0))
        XCTAssertEqual(Crop.picture(pinned, image: image).minX, 0, accuracy: 1e-9)
        XCTAssertEqual(pinned.cropX ?? -1, 0, accuracy: 1e-9)
        let down = Crop.moved(photo(), image: image, by: CGPoint(x: 0, y: 50))
        XCTAssertEqual(Crop.picture(down, image: image).minY, 0, accuracy: 1e-9)
    }

    func testATurnedOrFlippedPhotosPictureMovesTheWayTheFingerDoes() {
        let turned = photo(rotation: 90)
        let before = onPage(turned, 0.5, 0.5)
        let moved = Crop.moved(turned, image: image, by: CGPoint(x: 0, y: 10))
        assertPoint(CGPoint(x: before.x, y: before.y + 10), onPage(moved, 0.5, 0.5))

        let flipped = photo(flipH: true)
        let seen = Crop.picture(flipped, image: image)
        let slid = Crop.moved(flipped, image: image, by: CGPoint(x: 10, y: 0))
        XCTAssertEqual(Crop.picture(slid, image: image).minX, seen.minX + 10, accuracy: 1e-9)
    }

    func testZoomingKeepsThePointUnderTheFingersStill() {
        let el = photo()
        let around = CGPoint(x: 150, y: 180)
        let z = Crop.zoomed(el, image: image, by: 2, around: around)
        XCTAssertEqual(z.cropScale ?? 0, 2, accuracy: 1e-9)
        let seen = Crop.picture(el, image: image)
        let f = Crop.toFrame(el, around)
        assertPoint(around, onPage(z, (f.x - seen.minX) / seen.width, (f.y - seen.minY) / seen.height))
    }

    func testZoomStaysBetweenCoveringAndTheCeiling() {
        XCTAssertEqual(Crop.zoomed(photo(), image: image, by: 0.1, around: CGPoint(x: 200, y: 200)).cropScale ?? 0,
                       1, accuracy: 1e-9)
        XCTAssertEqual(Crop.zoomed(photo(), image: image, by: 1000, around: CGPoint(x: 200, y: 200)).cropScale ?? 0,
                       Crop.maxZoom, accuracy: 1e-9)
        let slider = Crop.zoomed(photo(), image: image, to: 2.5)
        XCTAssertEqual(slider.cropScale ?? 0, 2.5, accuracy: 1e-9)
        XCTAssertEqual(slider.cropX ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertEqual(slider.cropY ?? 0, 0.5, accuracy: 1e-9)
    }

    func testZoomingOutNearAnEdgeSlidesThePictureBackRatherThanOpeningAGap() {
        let el = Crop.zoomed(photo(), image: image, by: 3, around: CGPoint(x: 100, y: 100))
        let out = Crop.zoomed(el, image: image, by: 0.5, around: CGPoint(x: 300, y: 300))
        let seen = Crop.picture(out, image: image)
        XCTAssertTrue(seen.minX <= 1e-9 && seen.minY <= 1e-9)
        XCTAssertTrue(seen.maxX >= 200 - 1e-9 && seen.maxY >= 200 - 1e-9)
    }

    func testTrimmingMovesOneEdgeAndLeavesThePictureWhereItWas() {
        let el = photo()
        let corner = onPage(el, 0, 0)
        let middle = onPage(el, 0.5, 0.5)
        let trimmed = Crop.trimmed(el, image: image, handle: .e, to: CGPoint(x: 240, y: 200))
        XCTAssertEqual(trimmed.w, 140, accuracy: 1e-9)
        XCTAssertEqual(trimmed.h, 200, accuracy: 1e-9)
        XCTAssertEqual(trimmed.x, 100, accuracy: 1e-9)
        assertPoint(corner, onPage(trimmed, 0, 0))
        assertPoint(middle, onPage(trimmed, 0.5, 0.5))
    }

    func testAnEdgePullsBackOutOnlyAsFarAsThePictureGoes() {
        let pulled = Crop.trimmed(photo(), image: image, handle: .w, to: CGPoint(x: -500, y: 200))
        XCTAssertEqual(pulled.x, 100 - 33.333333, accuracy: 1e-5)
        XCTAssertEqual(pulled.w, 233.333333, accuracy: 1e-5)
        XCTAssertEqual(Crop.picture(pulled, image: image).minX, 0, accuracy: 1e-9)
        let up = Crop.trimmed(photo(), image: image, handle: .n, to: CGPoint(x: 200, y: -500))
        XCTAssertEqual(up.y, 100, accuracy: 1e-9)
        XCTAssertEqual(up.h, 200, accuracy: 1e-9)
        let crushed = Crop.trimmed(photo(), image: image, handle: .e, to: CGPoint(x: -900, y: 200), minSize: 16)
        XCTAssertEqual(crushed.w, 16, accuracy: 1e-9)
        XCTAssertEqual(crushed.x, 100, accuracy: 1e-9)
    }

    func testACornerTrimsBothEdgesOnATurnedFlippedPhoto() {
        let el = Crop.zoomed(photo(rotation: 30, flipH: true), image: image, by: 1.5, around: photo().center)
        let corner = onPage(el, 0, 0)
        let far = onPage(el, 1, 1)
        let grab = Crop.toPage(el, CGPoint(x: 30, y: 30))
        let trimmed = Crop.trimmed(el, image: image, handle: .nw, to: grab)
        XCTAssertEqual(trimmed.w, 170, accuracy: 1e-6)
        XCTAssertEqual(trimmed.h, 170, accuracy: 1e-6)
        XCTAssertEqual(trimmed.rotation, 30, accuracy: 1e-9)
        assertPoint(corner, onPage(trimmed, 0, 0))
        assertPoint(far, onPage(trimmed, 1, 1))
        assertPoint(Crop.toPage(el, CGPoint(x: 200, y: 200)), Crop.toPage(trimmed, CGPoint(x: 170, y: 170)))
    }

    func testAMoveThatChangesNothingVisibleLeavesTheNumbersAlone() {
        let el = Element.image("media:x", w: 1152, h: 2492.41)
        XCTAssertEqual(Crop.moved(el, image: CGSize(width: 1284, height: 2778), by: CGPoint(x: 0, y: 40)), el)
        XCTAssertEqual(Crop.zoomed(el, image: CGSize(width: 1284, height: 2778), by: 0.5, around: CGPoint(x: 100, y: 100)), el)
    }

    func testResetCentresAndCoversKeepingTheFrame() {
        let el = Crop.zoomed(photo(), image: image, by: 3, around: CGPoint(x: 120, y: 120))
        XCTAssertTrue(Crop.isAdjusted(el))
        let reset = Crop.reset(el)
        XCTAssertFalse(Crop.isAdjusted(reset))
        XCTAssertEqual(reset.w, el.w)
        var fitted = photo()
        fitted.cropFit = true
        let whole = Crop.drawnPicture(fitted, image: image)
        XCTAssertEqual(whole, CGRect(x: 0, y: 25, width: 200, height: 150))
    }

    func testFrameAndPageCoordinatesRoundTripOnATurnedElement() {
        let el = photo(rotation: 37)
        let p = CGPoint(x: 123, y: 234)
        assertPoint(p, Crop.toPage(el, Crop.toFrame(el, p)))
        assertPoint(Geometry.handlePoint(el, .nw), Crop.toPage(el, .zero))
    }

    // MARK: the mode

    private func store(with photo: Element) -> DesignStore {
        var design = Design(title: "crop", width: 600, height: 600)
        design.pages[0].elements = [photo]
        return DesignStore(design: design)
    }

    private var libraryPhoto: Element {
        var el = Element.image("asset:" + (PhotoLibrary.photos.first?.id ?? "none"), w: 300, h: 300)
        el.x = 50; el.y = 50
        el.cropFit = true
        return el
    }

    /// Crop mode is one open step: Cancel puts the photo back exactly and
    /// records nothing, Done keeps it as one Undo, and choosing anything else
    /// ends it with the crop kept.
    func testCropModeIsOneStepThatCancelPutsBack() {
        let original = libraryPhoto
        let s = store(with: original)
        s.select(original.id)
        XCTAssertTrue(s.startCrop(original.id))
        XCTAssertNil(s.cropElement?.cropFit, "cropping chooses what fills the frame")
        s.moveCropPicture(by: CGPoint(x: 40, y: 0))
        s.cancelCrop()
        XCTAssertNil(s.cropping)
        XCTAssertEqual(s.element(original.id), original, "Cancel put the photo back differently")
        XCTAssertFalse(s.canUndo, "Cancel recorded a step")

        XCTAssertTrue(s.startCrop(original.id))
        s.setCropZoom(3)
        s.finishCrop()
        XCTAssertEqual(s.element(original.id)?.cropScale ?? 0, 3, accuracy: 1e-9)
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertEqual(s.element(original.id), original, "the crop was more than one step")

        XCTAssertTrue(s.startCrop(original.id))
        s.setCropZoom(2)
        s.select(nil)
        XCTAssertNil(s.cropping, "selecting something else left crop mode open")
        XCTAssertEqual(s.element(original.id)?.cropScale ?? 0, 2, accuracy: 1e-9, "the crop so far was dropped")

        // Undo in the middle of a crop takes back the crop, not what came before.
        XCTAssertTrue(s.startCrop(original.id))
        s.setCropZoom(4)
        s.undo()
        XCTAssertNil(s.cropping)
        XCTAssertEqual(s.element(original.id)?.cropScale ?? 0, 2, accuracy: 1e-9)
    }

    /// What cannot be cropped says why and opens nothing.
    func testCropModeRefusesWhatItCannotCrop() {
        var locked = libraryPhoto
        locked.locked = true
        let code = Element.image(CodeGenerator.source(for: "https://canvia.app"), w: 200, h: 200)
        var empty = Element.image("media:x", w: 200, h: 200)
        empty.src = nil
        let missing = Element.image("media:img_does_not_exist", w: 200, h: 200)
        for el in [locked, code, empty, missing] {
            let s = store(with: el)
            s.select(el.id)
            XCTAssertFalse(s.startCrop(el.id), "\(el.src ?? "empty") opened crop mode")
            XCTAssertNil(s.cropping)
            XCTAssertNotNil(s.announcement, "\(el.src ?? "empty") was refused without a word")
        }
        let text = store(with: Element.text("Hello"))
        XCTAssertFalse(text.startCrop(text.page.elements[0].id))
    }
}
