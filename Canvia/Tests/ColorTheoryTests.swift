// Colour derivation, and the recents list.
//
// All arithmetic, so all assertable: a complement is 180° round the wheel, a
// ramp runs light to dark, and a grey has no hue to rotate — which is the
// case that would otherwise hand back five identical chips.

import XCTest
import UIKit
@testable import Canvia

final class ColorTheoryTests: XCTestCase {

    private func hue(_ hex: String) -> Double { ColorTheory.hsl(hex).h }

    private func distance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    // MARK: conversion

    func testRoundTripThroughHSL() {
        for hex in ["#ff0000", "#00ff00", "#0000ff", "#5a31f4", "#ffe066", "#123456", "#ffffff", "#000000"] {
            let c = ColorTheory.hsl(hex)
            XCTAssertEqual(ColorTheory.hex(h: c.h, s: c.s, l: c.l), hex, "round trip lost \(hex)")
        }
    }

    func testGreysHaveNoSaturation() {
        for hex in ["#000000", "#808080", "#ffffff"] {
            XCTAssertEqual(ColorTheory.hsl(hex).s, 0, accuracy: 0.001, hex)
        }
    }

    func testHueWrapsRatherThanClamping() {
        XCTAssertEqual(ColorTheory.hex(h: 380, s: 1, l: 0.5), ColorTheory.hex(h: 20, s: 1, l: 0.5))
        XCTAssertEqual(ColorTheory.hex(h: -20, s: 1, l: 0.5), ColorTheory.hex(h: 340, s: 1, l: 0.5))
    }

    // MARK: harmony

    func testTheSeedIsAlwaysTheFirstColour() {
        for kind in ColorHarmony.allCases where kind != .monochrome {
            let out = ColorTheory.harmony(kind, from: "#5a31f4")
            XCTAssertEqual(out.first, "#5a31f4", kind.rawValue)
        }
    }

    func testComplementIsOppositeOnTheWheel() {
        let out = ColorTheory.harmony(.complementary, from: "#ff0000")
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(distance(hue(out[0]), hue(out[1])), 180, accuracy: 1)
    }

    func testTriadicIsThreeEvenlySpacedHues() {
        let out = ColorTheory.harmony(.triadic, from: "#00a3ff")
        XCTAssertEqual(out.count, 3)
        XCTAssertEqual(distance(hue(out[0]), hue(out[1])), 120, accuracy: 1)
        XCTAssertEqual(distance(hue(out[1]), hue(out[2])), 120, accuracy: 1)
    }

    /// Analogous colours are neighbours, not opposites. Getting the sign or
    /// the magnitude wrong here produces a palette that still looks like a
    /// palette and is not the one asked for.
    func testAnalogousColoursStayNearTheSeed() {
        let out = ColorTheory.harmony(.analogous, from: "#00a3ff")
        for companion in out.dropFirst() {
            XCTAssertLessThanOrEqual(distance(hue(out[0]), hue(companion)), 61)
        }
    }

    func testEveryHarmonyKeepsSaturationAndLightness() {
        let seed = "#c0392b"
        let base = ColorTheory.hsl(seed)
        for kind in ColorHarmony.allCases where kind != .monochrome {
            for companion in ColorTheory.harmony(kind, from: seed) {
                let c = ColorTheory.hsl(companion)
                XCTAssertEqual(c.s, base.s, accuracy: 0.02, "\(kind.rawValue) moved saturation")
                XCTAssertEqual(c.l, base.l, accuracy: 0.02, "\(kind.rawValue) moved lightness")
            }
        }
    }

    /// A grey has no hue, so every rotation lands on the same colour. It gets
    /// the lightness ramp instead of five identical chips.
    func testGreySeedsGetARampRatherThanFiveIdenticalChips() {
        let out = ColorTheory.harmony(.triadic, from: "#808080")
        XCTAssertEqual(Set(out).count, out.count, "a grey seed produced duplicate companions")
    }

    // MARK: ramps

    func testRampRunsLightToDark() {
        let out = ColorTheory.ramp(from: "#5a31f4", steps: 5)
        XCTAssertEqual(out.count, 5)
        let lightness = out.map { ColorTheory.hsl($0).l }
        XCTAssertEqual(lightness, lightness.sorted(by: >), "the ramp is not ordered light to dark")
        XCTAssertGreaterThan(lightness.first!, lightness.last!)
    }

    /// Never pure white or pure black: those are the ends a naive 0...1 sweep
    /// hands back, and neither is a usable tint or shade.
    func testRampAvoidsTheExtremes() {
        for hex in ColorTheory.ramp(from: "#00a3ff", steps: 7) {
            let l = ColorTheory.hsl(hex).l
            XCTAssertGreaterThan(l, 0.05)
            XCTAssertLessThan(l, 0.97)
        }
    }

    func testDegenerateRampSizes() {
        XCTAssertTrue(ColorTheory.ramp(from: "#000000", steps: 0).isEmpty)
        XCTAssertEqual(ColorTheory.ramp(from: "#123456", steps: 1), ["#123456"])
    }

    func testReadableInkFlipsWithTheBackground() {
        XCTAssertEqual(ColorTheory.readableInk(on: "#ffffff"), "#16181d")
        XCTAssertEqual(ColorTheory.readableInk(on: "#101820"), "#ffffff")
    }

    // MARK: recents

    override func setUp() {
        super.setUp()
        RecentColors.clear()
    }

    override func tearDown() {
        RecentColors.clear()
        super.tearDown()
    }

    func testMostRecentComesFirst() {
        RecentColors.record("#ff0000")
        RecentColors.record("#00ff00")
        XCTAssertEqual(RecentColors.all.first, "#00ff00")
    }

    /// The same colour written three ways is one colour, not three entries.
    func testTheSameColourIsNotRecordedTwice() {
        RecentColors.record("#FFFFFF")
        RecentColors.record("ffffff")
        RecentColors.record("#fff")
        XCTAssertEqual(RecentColors.all, ["#ffffff"])
    }

    /// Re-using an older colour moves it back to the front rather than
    /// leaving it buried.
    func testReusingAColourPromotesIt() {
        RecentColors.record("#ff0000")
        RecentColors.record("#00ff00")
        RecentColors.record("#ff0000")
        XCTAssertEqual(RecentColors.all, ["#ff0000", "#00ff00"])
    }

    func testTheListIsCapped() {
        for i in 0..<(RecentColors.limit + 10) {
            RecentColors.record(String(format: "#%06x", i * 1000))
        }
        XCTAssertEqual(RecentColors.all.count, RecentColors.limit)
    }

    func testNonsenseIsRejectedRatherThanStored() {
        RecentColors.record("not a colour")
        RecentColors.record("")
        RecentColors.record("#12")
        XCTAssertTrue(RecentColors.all.isEmpty)
    }
}
