// Round 33's fuller crop ratios: the shared list, each pair kept
// landscape-normalised, both orientations recognised, the orientation chip
// turning the lit ratio and Custom…'s whole numbers — the Android twin's
// Crop.aspects rows — and the same in a graphic's crop.

import XCTest
import UIKit
@testable import Canvia

final class CropRatiosTests: XCTestCase {

    private let image = CGSize(width: 400, height: 300)

    private func photo(w: Double, h: Double) -> Element {
        var el = Element.image("media:x", w: w, h: h)
        el.x = 100; el.y = 100
        return el
    }

    /// Shared rows: the chips in order, each as first offered and as kept.
    func testTheSharedList() {
        let ratios = CropAspect.allCases.filter { $0.sides != nil }
        XCTAssertEqual(ratios.map(\.name), ["1:1", "4:5", "2:3", "3:4", "9:16", "21:9"])
        XCTAssertEqual(ratios.compactMap(\.landscape).map { "\($0.w):\($0.h)" },
                       ["1:1", "5:4", "3:2", "4:3", "16:9", "21:9"])
        XCTAssertEqual(CropAspect.allCases.prefix(2), [.free, .original])
        XCTAssertEqual(CropAspect.allCases.filter(\.turns).count, 5, "all but Free, Original and 1:1")
        XCTAssertEqual(CropAspect.fourFive.name(turned: true), "5:4")
        XCTAssertEqual(CropAspect.twentyOneNine.name(turned: true), "9:21")
        XCTAssertEqual(CropAspect.square.name(turned: true), "1:1")
        XCTAssertEqual(CropAspect.twoThree.ratio(image: image, turned: true) ?? 0, 1.5, accuracy: 1e-12)
        XCTAssertEqual(CropAspect.original.ratio(image: image, turned: true) ?? 0, 4.0 / 3, accuracy: 1e-12,
                       "Original does not turn")
    }

    /// Shared rows: a frame's ratio either way round lights its chip, its
    /// own way first; Original before a ratio the picture has.
    func testBothOrientationsAreRecognised() {
        let rows: [(w: Double, h: Double, aspect: CropAspect, turned: Bool)] = [
            (200, 250, .fourFive, false),
            (250, 200, .fourFive, true),
            (300, 200, .twoThree, true),
            (210, 90, .twentyOneNine, false),
            (90, 210, .twentyOneNine, true),
            (160, 90, .nineSixteen, true),
            (400, 300, .original, false),
            (100, 100, .square, false),
            (123, 200, .free, false),
        ]
        for row in rows {
            let match = CropAspect.matched(photo(w: row.w, h: row.h), image: image)
            XCTAssertEqual(match, CropAspect.Match(aspect: row.aspect, turned: row.turned), "\(row.w) × \(row.h)")
        }
        // A 3:4 picture's own shape is Original; turned, the 3:4 chip.
        let tall = CGSize(width: 300, height: 400)
        XCTAssertEqual(CropAspect.matched(photo(w: 300, h: 400), image: tall).aspect, .original)
        XCTAssertEqual(CropAspect.matched(photo(w: 400, h: 300), image: tall),
                       CropAspect.Match(aspect: .threeFour, turned: true))
    }

    /// Shared rows: Custom… takes whole numbers from 1 to 100 a side.
    func testCustomTakesWholeNumbersFrom1To100() {
        XCTAssertEqual(CropAspect.customRatio("7", "5") ?? 0, 1.4, accuracy: 1e-12)
        XCTAssertEqual(CropAspect.customRatio(" 1 ", "100") ?? 0, 0.01, accuracy: 1e-12)
        XCTAssertNil(CropAspect.customRatio("0", "5"))
        XCTAssertNil(CropAspect.customRatio("101", "5"))
        XCTAssertNil(CropAspect.customRatio("2.5", "1"))
        XCTAssertNil(CropAspect.customRatio("", "1"))
        XCTAssertEqual(CropAspect.customMost, 100)
    }

    private var libraryPhoto: Element {
        var el = Element.image("asset:" + (PhotoLibrary.photos.first?.id ?? "none"), w: 300, h: 200)
        el.x = 50; el.y = 50
        return el
    }

    /// The orientation chip turns the lit ratio, within the one crop step;
    /// it waits on Free, Original and 1:1; Custom… trims to its ratio.
    func testTheOrientationChipTurnsTheLitRatio() {
        let original = libraryPhoto
        var design = Design(title: "crop", width: 600, height: 600)
        design.pages[0].elements = [original]
        let s = DesignStore(design: design)
        s.select(original.id)
        XCTAssertTrue(s.startCrop(original.id))
        s.setCropAspect(.nineSixteen)
        XCTAssertEqual(s.cropMatch, CropAspect.Match(aspect: .nineSixteen, turned: false))
        s.turnCropAspect()
        XCTAssertEqual(s.cropMatch, CropAspect.Match(aspect: .nineSixteen, turned: true))
        let turned = s.cropElement
        XCTAssertEqual((turned?.w ?? 0) / (turned?.h ?? 1), 16.0 / 9, accuracy: 1e-6)
        s.setCropAspect(.square)
        s.turnCropAspect()
        XCTAssertEqual(s.cropMatch.aspect, .square, "1:1 has no other way round")
        s.setCropRatio(CropAspect.customRatio("2", "1") ?? 1)
        XCTAssertEqual((s.cropElement?.w ?? 0) / (s.cropElement?.h ?? 1), 2, accuracy: 1e-6,
                       "2:1, trimmed inside the square")
        s.finishCrop()
        XCTAssertTrue(s.canUndo)
        s.undo()
        XCTAssertEqual(s.element(original.id), original, "the crop was more than one step")
    }
}
