// Image adjustments.
//
// Every dial has a direction, and getting one backwards produces a picture
// that is obviously wrong to a person and invisible to a test that only
// checks "did something change". So each of these asserts the direction:
// brighter is brighter, warmer has more red than blue, a vignette is darker
// at the corner than in the middle.

import XCTest
import UIKit
@testable import Canvia

final class AdjustmentsTests: XCTestCase {

    /// A dark neutral ground with a light warm patch in the middle. Neutral so
    /// a shift in one channel is unambiguous, and clearly lighter in the
    /// middle than at the edge so contrast has a gap to widen — a fixture
    /// whose patch and ground happened to share a luminance would make the
    /// contrast assertion meaningless.
    private func fixture(size: Int = 64) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size),
                                       format: format).image { ctx in
            UIColor(white: 0.3, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
            UIColor(red: 0.8, green: 0.55, blue: 0.35, alpha: 1).setFill()
            ctx.fill(CGRect(x: size / 4, y: size / 4, width: size / 2, height: size / 2))
        }
    }

    private func rgb(_ image: UIImage, x: Int, y: Int) throws -> (r: Double, g: Double, b: Double) {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y),
                                    width: cg.width, height: cg.height))
        }
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    private func luma(_ image: UIImage, x: Int, y: Int) throws -> Double {
        let c = try rgb(image, x: x, y: y)
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    }

    private func applied(_ mutate: (inout Adjustments) -> Void, key: String = UUID().uuidString) throws -> UIImage {
        var adjustments = Adjustments()
        mutate(&adjustments)
        return ImageFilterEngine.apply(.none, adjustments: adjustments,
                                       to: fixture(), cacheKey: key)
    }

    // MARK: neutrality

    func testNeutralAdjustmentsAreTheIdentity() {
        XCTAssertTrue(Adjustments().isNeutral)
        XCTAssertEqual(Adjustments().signature, "")
        let source = fixture()
        let out = ImageFilterEngine.apply(.none, adjustments: .neutral,
                                          to: source, cacheKey: "identity")
        XCTAssertIdentical(out, source, "a neutral adjustment re-encoded the image")
    }

    /// The cache key has to move when the dials do, or turning one shows the
    /// previous result.
    func testTheSignatureChangesWithEveryDial() {
        var seen = Set<String>([Adjustments().signature])
        let dials: [WritableKeyPath<Adjustments, Double>] =
            [\.brightness, \.contrast, \.saturation, \.warmth, \.sharpness, \.vignette]
        for dial in dials {
            var a = Adjustments()
            a[keyPath: dial] = 0.5
            XCTAssertFalse(a.isNeutral)
            XCTAssertTrue(seen.insert(a.signature).inserted,
                          "two different adjustments share a cache key")
        }
    }

    // MARK: direction

    func testBrightnessBrightensAndDarkens() throws {
        let base = try luma(fixture(), x: 4, y: 4)
        let up = try luma(try applied { $0.brightness = 0.8 }, x: 4, y: 4)
        let down = try luma(try applied { $0.brightness = -0.8 }, x: 4, y: 4)
        XCTAssertGreaterThan(up, base + 10)
        XCTAssertLessThan(down, base - 10)
    }

    /// Contrast pushes values away from mid-grey, so the light patch gets
    /// lighter and the dark ground gets darker.
    func testContrastSeparatesLightFromDark() throws {
        let plain = fixture()
        let punchy = try applied { $0.contrast = 0.9 }
        let plainSpread = try luma(plain, x: 32, y: 32) - luma(plain, x: 2, y: 2)
        let punchySpread = try luma(punchy, x: 32, y: 32) - luma(punchy, x: 2, y: 2)
        XCTAssertGreaterThan(punchySpread, plainSpread + 3)
    }

    /// Saturation at its floor is greyscale: the three channels converge.
    func testFullDesaturationRemovesColour() throws {
        let grey = try applied { $0.saturation = -1 }
        let c = try rgb(grey, x: 32, y: 32)
        XCTAssertEqual(c.r, c.g, accuracy: 3)
        XCTAssertEqual(c.g, c.b, accuracy: 3)
    }

    func testSaturationDeepensColour() throws {
        let plain = try rgb(fixture(), x: 32, y: 32)
        let rich = try rgb(try applied { $0.saturation = 0.9 }, x: 32, y: 32)
        XCTAssertGreaterThan(rich.r - rich.b, plain.r - plain.b)
    }

    /// Warm is more red than blue, cool the other way. Reversing this is the
    /// single most likely mistake here and looks entirely plausible.
    func testWarmthMovesTowardsOrangeAndCoolTowardsBlue() throws {
        let plain = try rgb(fixture(), x: 4, y: 4)
        let warm = try rgb(try applied { $0.warmth = 0.9 }, x: 4, y: 4)
        let cool = try rgb(try applied { $0.warmth = -0.9 }, x: 4, y: 4)
        XCTAssertGreaterThan(warm.r - warm.b, plain.r - plain.b + 3, "warm is not warmer")
        XCTAssertLessThan(cool.r - cool.b, plain.r - plain.b - 3, "cool is not cooler")
    }

    /// A vignette darkens the corners and leaves the middle alone.
    func testVignetteDarkensTheCornersOnly() throws {
        let plain = fixture()
        let vignetted = try applied { $0.vignette = 1 }
        let corner = try luma(vignetted, x: 1, y: 1)
        let middle = try luma(vignetted, x: 32, y: 32)
        XCTAssertLessThan(corner, try luma(plain, x: 1, y: 1) - 5, "the corner did not darken")
        XCTAssertEqual(middle, try luma(plain, x: 32, y: 32), accuracy: 12,
                       "the vignette reached the middle")
    }

    /// Blur spreads the coloured patch past its own edge; sharpening does not.
    func testNegativeSharpnessBlurs() throws {
        let plain = try rgb(fixture(), x: 12, y: 32)
        let blurred = try rgb(try applied { $0.sharpness = -1 }, x: 12, y: 32)
        XCTAssertGreaterThan(abs(blurred.r - plain.r), 2, "nothing bled into the surround")
    }

    // MARK: composition and the model

    /// A preset is the look, the dials are the correction on top. Applied the
    /// other way round, picking a preset would silently undo the dials.
    func testAdjustmentsComposeOnTopOfAPreset() throws {
        let source = fixture()
        let presetOnly = ImageFilterEngine.apply(.mono, adjustments: .neutral,
                                                 to: source, cacheKey: "compose-a")
        var brighter = Adjustments()
        brighter.brightness = 0.8
        let both = ImageFilterEngine.apply(.mono, adjustments: brighter,
                                           to: source, cacheKey: "compose-b")
        // Still greyscale…
        let c = try rgb(both, x: 32, y: 32)
        XCTAssertEqual(c.r, c.g, accuracy: 3)
        // …and brighter than the preset alone.
        XCTAssertGreaterThan(try luma(both, x: 32, y: 32), try luma(presetOnly, x: 32, y: 32) + 10)
    }

    func testAdjustmentsSurviveAJSONRoundTrip() throws {
        var el = Element.image("asset:x", w: 100, h: 100)
        var a = Adjustments()
        a.brightness = 0.25
        a.vignette = 0.5
        el.adjustments = a
        let restored = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(restored.adjustments, a)
        XCTAssertEqual(restored, el)
    }

    /// A document written before adjustments existed has no such key, and must
    /// decode as untouched rather than as zeroed-out nonsense.
    func testAnOlderDocumentDecodesAsUntouched() throws {
        let json = #"{"id":"el_1","type":"image","src":"asset:x","w":100,"h":100}"#
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertNil(el.adjustments)
    }

    func testStyleCopyCarriesAdjustments() {
        var source = Element.image("asset:a", w: 100, h: 100)
        var a = Adjustments()
        a.warmth = -0.4
        source.adjustments = a
        var target = Element.image("asset:b", w: 50, h: 50)
        DesignStore.apply(DesignStore.style(of: source), to: &target)
        XCTAssertEqual(target.adjustments, a)
        XCTAssertEqual(target.src, "asset:b", "the picture itself was overwritten")
    }
}

// MARK: - duotone

final class DuotoneTests: XCTestCase {

    /// A gradient from black to white, so every point of the luminance ramp is
    /// present and can be checked against where it should land.
    private func rampImage(size: Int = 64) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size),
                                       format: format).image { ctx in
            for x in 0..<size {
                UIColor(white: CGFloat(x) / CGFloat(size - 1), alpha: 1).setFill()
                ctx.fill(CGRect(x: x, y: 0, width: 1, height: size))
            }
        }
    }

    private func rgb(_ image: UIImage, x: Int, y: Int) throws -> (r: Double, g: Double, b: Double) {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y),
                                    width: cg.width, height: cg.height))
        }
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }

    private func toned(_ tone: Duotone, key: String = UUID().uuidString) -> UIImage {
        ImageFilterEngine.apply(.none, adjustments: .neutral, duotone: tone,
                                to: rampImage(), cacheKey: key)
    }

    /// The defining property: darkest becomes the dark colour, lightest
    /// becomes the light one. Swapping those is the obvious mistake and the
    /// result still looks like a duotone.
    func testTheDarkEndBecomesTheDarkColour() throws {
        let tone = Duotone(dark: "#0000ff", light: "#ffff00")
        let out = toned(tone)
        let darkEnd = try rgb(out, x: 1, y: 32)
        let lightEnd = try rgb(out, x: 62, y: 32)
        XCTAssertGreaterThan(darkEnd.b, darkEnd.r + 60, "the dark end is not blue")
        XCTAssertGreaterThan(lightEnd.r, lightEnd.b + 60, "the light end is not yellow")
    }

    /// Between the ends it is a ramp, not a threshold — a two-tone poster
    /// effect would pass the ends test and be a different feature.
    func testTheMiddleIsBetweenTheTwoColours() throws {
        let out = toned(Duotone(dark: "#000000", light: "#ffffff"))
        let left = try rgb(out, x: 4, y: 32).r
        let middle = try rgb(out, x: 32, y: 32).r
        let right = try rgb(out, x: 60, y: 32).r
        XCTAssertGreaterThan(middle, left + 20)
        XCTAssertLessThan(middle, right - 20)
    }

    /// Colour in the source must not decide where a pixel lands on the ramp —
    /// only how light it is. Without the desaturation first, a red and a green
    /// of the same luminance map to different points.
    func testSourceColourDoesNotChangeWhereAPixelLands() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // Two patches with matching luminance and opposite hues.
        let source = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20),
                                             format: format).image { ctx in
            UIColor(red: 0.6, green: 0.35, blue: 0.35, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            UIColor(red: 0.35, green: 0.35, blue: 0.6, alpha: 1).setFill()
            ctx.fill(CGRect(x: 20, y: 0, width: 20, height: 20))
        }
        let out = ImageFilterEngine.apply(.none, adjustments: .neutral,
                                          duotone: Duotone(dark: "#000000", light: "#ffffff"),
                                          to: source, cacheKey: UUID().uuidString)
        let a = try rgb(out, x: 5, y: 10)
        let b = try rgb(out, x: 35, y: 10)
        XCTAssertEqual(a.r, b.r, accuracy: 22, "hue is still deciding the mapping")
    }

    func testNoDuotoneLeavesTheImageAlone() {
        let source = rampImage()
        XCTAssertIdentical(
            ImageFilterEngine.apply(.none, adjustments: .neutral, duotone: nil,
                                    to: source, cacheKey: "none"),
            source)
    }

    /// Two duotones must not share a cache key, or picking a second one shows
    /// the first.
    func testEachDuotoneHasItsOwnCacheEntry() throws {
        let source = rampImage()
        let a = ImageFilterEngine.apply(.none, adjustments: .neutral,
                                        duotone: Duotone(dark: "#ff0000", light: "#ffffff"),
                                        to: source, cacheKey: "shared")
        let b = ImageFilterEngine.apply(.none, adjustments: .neutral,
                                        duotone: Duotone(dark: "#0000ff", light: "#ffffff"),
                                        to: source, cacheKey: "shared")
        let redEnd = try rgb(a, x: 1, y: 32)
        let blueEnd = try rgb(b, x: 1, y: 32)
        XCTAssertGreaterThan(redEnd.r, redEnd.b + 60)
        XCTAssertGreaterThan(blueEnd.b, blueEnd.r + 60)
    }

    func testDuotoneSurvivesAJSONRoundTrip() throws {
        var el = Element.image("asset:x", w: 100, h: 100)
        el.duotone = Duotone(dark: "#123456", light: "#fedcba")
        let restored = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(restored.duotone, el.duotone)
        XCTAssertEqual(restored, el)
    }

    func testADocumentWithoutADuotoneDecodesWithNone() throws {
        let json = #"{"id":"el_1","type":"image","src":"asset:x","w":10,"h":10}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(json.utf8)).duotone)
    }
}
