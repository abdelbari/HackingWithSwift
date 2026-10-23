// Selective colour: the eight hue bands, how much of a hue each claims,
// one colour through a band's shift, the `hsl` key as the file carries it,
// and the chips' order. The same rows as the Android twin's HueBandsTest.

import XCTest
import UIKit
@testable import Canvia

final class SelectiveColourTests: XCTestCase {

    // MARK: the bands

    func testTheEightBandsSitAtTheirCentres() {
        XCTAssertEqual(HueBands.keys, ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"])
        XCTAssertEqual(HueBands.bands.map(\.centre), [0, 30, 60, 120, 180, 240, 270, 300])
        XCTAssertEqual(HueBands.turn, 30)
    }

    /// A band claims all of its centre, half of the hue midway to the next
    /// centre and none of that centre; the two bands either side of a hue
    /// share it to one, round the top of the circle too.
    func testABandClaimsItsHuesByACosineToTheNextCentre() {
        XCTAssertEqual(HueBands.weight(0, band: 0), 1, accuracy: 1e-9)
        XCTAssertEqual(HueBands.weight(15, band: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HueBands.weight(30, band: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(HueBands.weight(15, band: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HueBands.weight(60, band: 0), 0)
        // Red reaches back 60° to magenta, so 330° is halfway.
        XCTAssertEqual(HueBands.weight(330, band: 0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(HueBands.weight(345, band: 0), 0.5 + 0.5 * cos(.pi / 4), accuracy: 1e-9)
        XCTAssertEqual(HueBands.weight(345, band: 0) + HueBands.weight(345, band: 7), 1, accuracy: 1e-9)
        XCTAssertEqual(HueBands.weight(90, band: 2) + HueBands.weight(90, band: 3), 1, accuracy: 1e-9)
        XCTAssertEqual(HueBands.band(ofHue: 10), 0)
        XCTAssertEqual(HueBands.band(ofHue: 200), 4)
        XCTAssertEqual(HueBands.band(ofHue: 350), 0)
    }

    // MARK: one colour through a shift

    /// The shared table: 0xRRGGBB in, the shift, 0xRRGGBB out, each
    /// channel rounded half up.
    func testTheSharedTableOfColoursThroughAShift() {
        let rows: [(Int, [String: HueShift], Int)] = [
            // Red turned a full shift is orange: hue 0 → 30°.
            (0xff0000, ["red": HueShift(h: 1)], 0xff8000),
            // Or towards magenta the other way.
            (0xff0000, ["red": HueShift(h: -1)], 0xff0080),
            // Red with its saturation taken away is mid grey.
            (0xff0000, ["red": HueShift(s: -1)], 0x808080),
            // Red lifted a full shift is a quarter lighter, and lowered.
            (0xff0000, ["red": HueShift(l: 1)], 0xff8080),
            (0xff0000, ["red": HueShift(l: -1)], 0x800000),
            // Another band leaves red alone.
            (0xff0000, ["blue": HueShift(h: 1)], 0xff0000),
            // Blue towards aqua.
            (0x0000ff, ["blue": HueShift(h: -1)], 0x0080ff),
            // Green is already as saturated as it gets.
            (0x00ff00, ["green": HueShift(s: 1)], 0x00ff00),
            // White stays white.
            (0xffffff, ["red": HueShift(l: -1)], 0xffffff),
            // A grey stays put whatever is shifted.
            (0x808080, ["red": HueShift(h: 1, s: 1, l: 1)], 0x808080),
            // Orange sits on the next centre, which red does not claim.
            (0xff8000, ["red": HueShift(h: 1)], 0xff8000),
            // Green darkened a full shift.
            (0x00ff00, ["green": HueShift(l: -1)], 0x008000),
            // Blue half desaturated.
            (0x0000ff, ["blue": HueShift(s: -0.5)], 0x4040bf),
            // No shift at all is the colour itself.
            (0x123456, [:], 0x123456),
            // A band this build does not know is no shift.
            (0xff0000, ["teal": HueShift(h: 1)], 0xff0000),
        ]
        for (rgb, hsl, want) in rows {
            XCTAssertEqual(String(HueBands.pixel(rgb, hsl: hsl), radix: 16), String(want, radix: 16),
                           "\(String(rgb, radix: 16)) through \(hsl)")
        }
    }

    /// A half-saturated red moves half as far, and opposite shifts on the
    /// two bands either side of a hue cancel between them.
    func testTheShiftScalesWithSaturationAndNeighboursCancel() {
        // (191, 64, 64): saturation 0.498, so a full hue turn is 14.9°.
        let moved = HueBands.pixel(0xbf4040, hsl: ["red": HueShift(h: 1)])
        let hue = HueBands.toHSL(Double((moved >> 16) & 0xff) / 255, Double((moved >> 8) & 0xff) / 255,
                                 Double(moved & 0xff) / 255).h
        XCTAssertEqual(hue, 14.9, accuracy: 0.5)
        let between = HueBands.toRGB(15, 1, 0.5)
        let packed = (PhotoLook.byte(between.r * 255) << 16) | (PhotoLook.byte(between.g * 255) << 8) | PhotoLook.byte(between.b * 255)
        let cancelled = HueBands.pixel(packed, hsl: ["red": HueShift(h: 1), "orange": HueShift(h: -1)])
        for shift in [16, 8, 0] {
            XCTAssertLessThanOrEqual(abs(((packed >> shift) & 0xff) - ((cancelled >> shift) & 0xff)), 1)
        }
    }

    /// The bands come after every global colour dial and before the curves
    /// in the pixel's order: a red dial turned to orange, then lifted by
    /// the light curve, is the orange lifted — not red lifted then turned.
    func testTheBandsComeAfterTheDialsAndBeforeTheCurves() {
        var a = Adjustments()
        a.hsl = ["red": HueShift(h: 1)]
        XCTAssertEqual(String(PhotoLook.pixel(0xff0000, filter: nil, adjustments: a, strength: nil), radix: 16), "ff8000")
        // Saturation off first leaves a grey, which no band moves.
        a.saturation = -1
        var grey = Adjustments()
        grey.saturation = -1
        XCTAssertEqual(PhotoLook.pixel(0xff0000, filter: nil, adjustments: a, strength: nil),
                       PhotoLook.pixel(0xff0000, filter: nil, adjustments: grey, strength: nil))
    }

    /// Rendered through the engine, a red patch with red's hue shifted a
    /// full turn comes out orange: more green than it had, red kept.
    @MainActor
    func testTheEngineShiftsABandThroughItsCube() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let red = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format).image { ctx in
            UIColor(red: 1, green: 0, blue: 0, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        var a = Adjustments()
        a.hsl = ["red": HueShift(h: 1)]
        let out = ImageFilterEngine.apply(.none, adjustments: a, to: red, cacheKey: "hsl-red-\(UUID().uuidString)")
        let cg = try XCTUnwrap(out.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                              bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: -4, y: -4, width: cg.width, height: cg.height))
        }
        XCTAssertGreaterThan(pixel[0], 240, "red kept")
        XCTAssertGreaterThan(pixel[1], 90, "green came in: the red turned towards orange")
        XCTAssertLessThan(pixel[1], 170)
        XCTAssertLessThan(pixel[2], 20)
    }

    // MARK: the file

    func testOnlyShiftedBandsAreWrittenAndNoneIsNoKey() throws {
        var a = Adjustments()
        a.hsl = ["red": HueShift(h: 0.5), "blue": HueShift(), "teal": HueShift(s: 1)]
        let data = try JSONEncoder().encode(a)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let hsl = try XCTUnwrap(json["hsl"] as? [String: Any])
        XCTAssertEqual(Set(hsl.keys), ["red", "teal"], "a band with no shift is not written; one not known is kept")
        let red = try XCTUnwrap(hsl["red"] as? [String: Any])
        XCTAssertEqual(red["h"] as? Double, 0.5)
        XCTAssertEqual(red["s"] as? Double, 0)
        XCTAssertEqual(red["l"] as? Double, 0)
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Adjustments()))
                                   as? [String: Any])["hsl"])
        let back = try JSONDecoder().decode(Adjustments.self, from: data)
        XCTAssertEqual(back.hsl, ["red": HueShift(h: 0.5), "teal": HueShift(s: 1)])
        XCTAssertFalse(back.isNeutral)
        var rested = Adjustments()
        rested.hsl = ["red": HueShift()]
        XCTAssertTrue(rested.isNeutral, "a band at rest counts as not moved")
    }

    func testAnOddHslReadsLeniently() throws {
        let json = #"{"brightness":0,"contrast":0,"saturation":0,"warmth":0,"sharpness":0,"vignette":0,"#
            + #""hsl":{"green":{"h":"x","s":2,"l":-0.5},"teal":{"h":1},"blue":{"h":0,"s":0,"l":0}}}"#
        let a = try JSONDecoder().decode(Adjustments.self, from: Data(json.utf8))
        XCTAssertEqual(a.hsl, ["green": HueShift(h: 0, s: 1, l: -0.5), "teal": HueShift(h: 1)],
                       "a bad value is 0, a wild one held to ±1, a band at rest dropped")
        XCTAssertNotEqual(a.signature, Adjustments().signature)
        XCTAssertNotEqual(a.signature, { var b = Adjustments(); b.hsl = ["green": HueShift(h: 0.3)]; return b }().signature)
    }

    func testSettingABandBackToNeutralDropsItAndTheAdjustments() {
        var el = Element.image("asset:mesh-sunset")
        el.setHueShift("red", to: HueShift(h: 0.4))
        XCTAssertEqual(el.adjustments?.hsl, ["red": HueShift(h: 0.4)])
        el.setHueShift("red", to: HueShift())
        XCTAssertNil(el.adjustments, "every dial centred is no adjustments at all")
        el.setHueShift("blue", to: HueShift(s: 1))
        XCTAssertTrue(PhotoEdits.any(el))
        XCTAssertNil(PhotoEdits.original(el).adjustments, "Hold to compare shows the photo without it")
        PhotoEdits.reset(&el)
        XCTAssertNil(el.adjustments, "Reset photo edits takes it off")
    }

    // MARK: the chips

    func testTheChipsLeadWithTheBandsInThePhoto() {
        XCTAssertEqual(HueBands.band(of: 0xff0000), "red")
        XCTAssertEqual(HueBands.band(of: 0x2040c0), "blue")
        XCTAssertEqual(HueBands.band(of: 0xe11d48), "red")
        XCTAssertEqual(HueBands.band(of: 0x2563eb), "blue")
        XCTAssertEqual(HueBands.band(of: 0xffd60a), "yellow")
        XCTAssertNil(HueBands.band(of: 0x808080), "a grey is in no band")
        XCTAssertNil(HueBands.band(of: 0x8a8880), "nor a near grey")
        XCTAssertEqual(HueBands.present(in: ["#2040c0", "#ff0000", "#777777", "#2040c0", "nope"]), ["blue", "red"])
        XCTAssertEqual(HueBands.chipOrder(present: ["blue", "red"]),
                       ["blue", "red", "orange", "yellow", "green", "aqua", "purple", "magenta"])
        XCTAssertEqual(HueBands.chipOrder(present: []), HueBands.keys)
    }
}
