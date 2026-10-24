// Setting a photo dial exactly, row for row with the Android twin's
// DialPrecisionTest: typed numbers, the rest a dial snaps to, VoiceOver's
// steps, and a dial or a group put back with nothing else touched.

import XCTest
@testable import Canvia

final class DialPrecisionTests: XCTestCase {

    func testRangesAreStepsOfTheModelsRange() {
        XCTAssertEqual(DialPrecision.steps(-1...1), -100...100)
        XCTAssertEqual(DialPrecision.steps(0...1), 0...100)
    }

    func testATypedNumberIsHeldToTheDialsRange() {
        let twoWay: ClosedRange<Double> = -100...100
        let oneWay: ClosedRange<Double> = 0...100
        XCTAssertEqual(DialPrecision.typed("+20", in: twoWay), 20)
        XCTAssertEqual(DialPrecision.typed(" -5 ", in: twoWay), -5)
        XCTAssertEqual(DialPrecision.typed("\u{2212}7", in: twoWay), -7)
        XCTAssertEqual(DialPrecision.typed("12.6", in: twoWay), 13)
        XCTAssertEqual(DialPrecision.typed("12,4", in: twoWay), 12)
        XCTAssertEqual(DialPrecision.typed("40%", in: oneWay), 40)
        XCTAssertEqual(DialPrecision.typed("250", in: twoWay), 100)
        XCTAssertEqual(DialPrecision.typed("-30", in: oneWay), 0)
        XCTAssertNil(DialPrecision.typed("", in: twoWay))
        XCTAssertNil(DialPrecision.typed("abc", in: twoWay))
        XCTAssertNil(DialPrecision.typed("+", in: twoWay))
    }

    func testWithinTwoOfItsRestADialRestsAndTheTickIsFeltOnce() {
        let range: ClosedRange<Double> = -100...100
        XCTAssertEqual([-3, -2.4, -2, 1.5, 2, 2.5, 2.6, 57.4].map { DialPrecision.snapped($0, in: range) },
                       [-3, 0, 0, 0, 0, 3, 3, 57])
        XCTAssertEqual(DialPrecision.snapped(130, in: range), 100)
        XCTAssertEqual(DialPrecision.snapped(98.5, rest: 100, in: 0...100), 100, "a strength rests at full")
        XCTAssertEqual(DialPrecision.snapped(97, rest: 100, in: 0...100), 97)
        XCTAssertTrue(DialPrecision.reachedRest(from: 5, to: 0))
        XCTAssertFalse(DialPrecision.reachedRest(from: 0, to: 0), "once per arrival")
        XCTAssertFalse(DialPrecision.reachedRest(from: 0, to: 3))
    }

    func testVoiceOverMovesFiveAtATime() {
        XCTAssertEqual(DialPrecision.stepped(0, up: true, in: -100...100), 5)
        XCTAssertEqual(DialPrecision.stepped(-98, up: false, in: -100...100), -100)
        XCTAssertEqual(DialPrecision.stepped(3, up: false, in: 0...100), 0)
        XCTAssertEqual(DialPrecision.step, 5)
    }

    func testReadoutsAreSignedOnlyForTwoWayDials() {
        XCTAssertEqual(DialPrecision.readout(20, in: -100...100), "+20")
        XCTAssertEqual(DialPrecision.readout(0, in: -100...100), "0")
        XCTAssertEqual(DialPrecision.readout(-5, in: -100...100), "-5")
        XCTAssertEqual(DialPrecision.readout(40, in: 0...100), "40")
    }

    func testOneDialOrOneGroupIsPutBack() {
        var adjustments = Adjustments()
        adjustments.brightness = 0.2
        adjustments.contrast = -0.1
        adjustments.warmth = 0.3
        adjustments.vignette = 0.4
        adjustments.hsl = ["red": HueShift(h: 0.1, s: 0, l: 0)]
        XCTAssertTrue(DialPrecision.isMoved(adjustments, .light))
        XCTAssertTrue(DialPrecision.isMoved(adjustments, .colour))

        let light = DialPrecision.cleared(adjustments, .light)
        XCTAssertEqual(light?.brightness, 0)
        XCTAssertEqual(light?.contrast, 0)
        XCTAssertEqual(light?.warmth, 0.3, "another group's dial kept")
        XCTAssertEqual(light?.vignette, 0.4)
        let colour = DialPrecision.cleared(adjustments, .colour)
        XCTAssertEqual(colour?.warmth, 0)
        XCTAssertEqual(colour?.hsl, [:], "selective colour goes with Colour")
        XCTAssertEqual(colour?.brightness, 0.2)

        var one = Adjustments()
        one.brightness = 0.2
        XCTAssertNil(DialPrecision.reset(one, \.brightness), "nothing left moved is no adjustments")
        XCTAssertNil(DialPrecision.cleared(one, .light))
        XCTAssertEqual(DialPrecision.reset(adjustments, \.brightness)?.contrast, -0.1)
        XCTAssertFalse(DialPrecision.isMoved(nil, .texture))
        XCTAssertEqual(DialPrecision.DialGroup.texture.keys.count, 4)
    }

    @MainActor
    func testAGroupResetIsOneStep() {
        var photo = Element()
        photo.type = .image
        var adjustments = Adjustments()
        adjustments.brightness = 0.5
        adjustments.clarity = 0.2
        photo.adjustments = adjustments
        var design = Design(title: "Dials")
        design.pages = [Page(elements: [photo])]
        let s = DesignStore(design: design)
        s.select(photo.id)
        s.updateSelected { $0.adjustments = DialPrecision.cleared($0.adjustments, .light) }
        XCTAssertEqual(s.element(photo.id)?.adjustments?.brightness, 0)
        XCTAssertEqual(s.element(photo.id)?.adjustments?.clarity, 0.2)
        s.undo()
        XCTAssertEqual(s.element(photo.id)?.adjustments?.brightness, 0.5)
    }
}
