// Round 34's Portrait | Landscape and swap in Resize: a preset turned to
// stand the way chosen, a square left as it is, and the custom fields
// swapped — the rows the Android twin's tests hold too.

import XCTest
@testable import Canvia

final class ResizeOrientationTests: XCTestCase {

    func testA4ChosenLandscapeIs297By210() throws {
        let a4 = try XCTUnwrap(SizePreset.all.first { $0.id == "a4" })
        let turned = CustomSizes.turned(width: a4.w, height: a4.h, landscape: true)
        XCTAssertEqual(turned.width, a4.h)
        XCTAssertEqual(turned.height, a4.w)
        XCTAssertEqual(Units.dimensions(width: turned.width, height: turned.height, unit: a4.unit, dpi: a4.dpi),
                       "297 × 210 mm")
        // Portrait leaves a page that already stands so as it is.
        let upright = CustomSizes.turned(width: a4.w, height: a4.h, landscape: false)
        XCTAssertEqual(upright.width, a4.w)
        XCTAssertEqual(upright.height, a4.h)
    }

    func testAWidePresetChosenPortraitStandsUp() {
        let turned = CustomSizes.turned(width: 1920, height: 1080, landscape: false)
        XCTAssertEqual(turned.width, 1080)
        XCTAssertEqual(turned.height, 1920)
    }

    func testASquareIsTheSameEitherWay() {
        for landscape in [false, true] {
            let turned = CustomSizes.turned(width: 1080, height: 1080, landscape: landscape)
            XCTAssertEqual(turned.width, 1080)
            XCTAssertEqual(turned.height, 1080)
        }
    }

    func testTheFieldsSwapOnlyWhenTheyStandTheOtherWay() {
        let wide = CustomSizes.turnedFields(width: "1600", height: "900", landscape: false)
        XCTAssertEqual(wide.width, "900")
        XCTAssertEqual(wide.height, "1600")
        let kept = CustomSizes.turnedFields(width: "1600", height: "900", landscape: true)
        XCTAssertEqual(kept.width, "1600")
        XCTAssertEqual(kept.height, "900")
        // Square, or not yet a number: left as typed.
        XCTAssertEqual(CustomSizes.turnedFields(width: "500", height: "500", landscape: true).width, "500")
        XCTAssertEqual(CustomSizes.turnedFields(width: "", height: "900", landscape: true).height, "900")
    }

    /// The row reads the way the chosen size stands, and is off for a
    /// square — the Android twin's SizePresets.isLandscape rows.
    func testTheRowReadsTheWayTheChosenSizeStands() throws {
        let a4 = try XCTUnwrap(SizePreset.all.first { $0.id == "a4" })
        XCTAssertEqual(CustomSizes.isLandscape(width: a4.w, height: a4.h), false)
        XCTAssertEqual(CustomSizes.isLandscape(width: 1920, height: 1080), true)
        XCTAssertNil(CustomSizes.isLandscape(width: 1080, height: 1080))
    }

    @MainActor
    func testATurnedPresetIsOneUndoStep() {
        let store = DesignStore(design: Design(title: "a4", width: 2480, height: 3508))
        let turned = CustomSizes.turned(width: 2480, height: 3508, landscape: true)
        store.magicResize(width: turned.width, height: turned.height)
        XCTAssertEqual(store.design.width, 3508)
        XCTAssertEqual(store.design.height, 2480)
        store.undo()
        XCTAssertEqual(store.design.width, 2480)
        XCTAssertEqual(store.design.height, 3508)
    }
}
