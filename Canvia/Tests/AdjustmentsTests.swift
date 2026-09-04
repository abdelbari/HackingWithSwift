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
