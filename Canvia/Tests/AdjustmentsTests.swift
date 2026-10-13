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
            [\.brightness, \.contrast, \.saturation, \.warmth, \.sharpness, \.vignette,
             \.tint, \.highlights, \.shadows, \.whites, \.blacks, \.vibrance, \.clarity, \.fade]
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

// MARK: - the shared maths

/// The colour maths both phones share, row for row with the Android twin's
/// PhotoLookTest: a colour in, the filter at its strength and the dials, a
/// colour out. Change a number here and there together.
final class PhotoLookTests: XCTestCase {

    private func dials(_ change: (inout Adjustments) -> Void) -> Adjustments {
        var a = Adjustments()
        change(&a)
        return a
    }

    /// (what, colour in, filter, dials, strength, colour out)
    private var table: [(String, Int, String?, Adjustments, Double?, Int)] {
        [
            ("nothing", 0xc86432, nil, Adjustments(), nil, 0xc86432),
            ("tint +1", 0x808080, nil, dials { $0.tint = 1 }, nil, 0x887188),
            ("tint -0.5", 0xc86432, nil, dials { $0.tint = -0.5 }, nil, 0xc26a31),
            ("fade 1 on black", 0x000000, nil, dials { $0.fade = 1 }, nil, 0x262626),
            ("fade 0.5", 0xc86432, nil, dials { $0.fade = 0.5 }, nil, 0xcc7041),
            ("fade 1 on white", 0xffffff, nil, dials { $0.fade = 1 }, nil, 0xffffff),
            ("highlights +1", 0xbfbfbf, nil, dials { $0.highlights = 1 }, nil, 0xe5e5e5),
            ("highlights -1", 0xbfbfbf, nil, dials { $0.highlights = -1 }, nil, 0x999999),
            ("shadows -1", 0x404040, nil, dials { $0.shadows = -1 }, nil, 0x1a1a1a),
            ("shadows +1", 0x404040, nil, dials { $0.shadows = 1 }, nil, 0x666666),
            ("whites +1", 0xe6e6e6, nil, dials { $0.whites = 1 }, nil, 0xffffff),
            ("whites -1", 0xffffff, nil, dials { $0.whites = -1 }, nil, 0xd9d9d9),
            ("blacks -1", 0x141414, nil, dials { $0.blacks = -1 }, nil, 0x000000),
            ("blacks +0.5", 0x000000, nil, dials { $0.blacks = 0.5 }, nil, 0x131313),
            ("vibrance +1", 0x967864, nil, dials { $0.vibrance = 1 }, nil, 0xaa7450),
            ("vibrance -1", 0x967864, nil, dials { $0.vibrance = -1 }, nil, 0x827c78),
            ("vibrance +1 on pure red", 0xff0000, nil, dials { $0.vibrance = 1 }, nil, 0xff0000),
            ("mono at half", 0xc86432, "mono", Adjustments(), 0.5, 0x9e6c53),
            ("noir at none", 0xc86432, "noir", Adjustments(), 0, 0xc86432),
            ("vivid whole", 0xc86432, "vivid", Adjustments(), nil, 0xff5b01),
            ("warm at a quarter", 0xc86432, "warm", Adjustments(), 0.25, 0xca6935),
            ("brightness 0.5", 0x646464, nil, dials { $0.brightness = 0.5 }, nil, 0x919191),
            ("contrast -0.5, saturation 1", 0xc86432, nil, dials { $0.contrast = -0.5; $0.saturation = 1 }, nil, 0xec601a),
            ("warmth 1", 0x808080, nil, dials { $0.warmth = 1 }, nil, 0x8f8371),
            ("retro at 0.6 with tint, shadows, vibrance and fade", 0x3c78b4, "retro",
             dials { $0.tint = 0.3; $0.shadows = 0.4; $0.vibrance = 0.5; $0.fade = 0.2 }, 0.6, 0x5f7db3),
            ("S-curve then highlights", 0xb4a08c, nil, dials { $0.curve = "scurve"; $0.highlights = 0.5 }, nil, 0xd8bb96),
        ]
    }

    func testTheSharedTable() {
        for (what, input, filter, adjustments, strength, expected) in table {
            let out = PhotoLook.pixel(input, filter: filter, adjustments: adjustments, strength: strength)
            XCTAssertEqual(String(format: "%06x", out), String(format: "%06x", expected), what)
        }
    }

    /// (what, histogram, brightness, whites, blacks)
    private var autoTable: [(String, [Int], Double, Double, Double)] {
        func levels(_ change: (inout [Int]) -> Void) -> [Int] {
            var h = [Int](repeating: 0, count: 256)
            change(&h)
            return h
        }
        return [
            ("one grey", levels { $0[128] = 4096 }, 0, 1, -1),
            ("every level alike", [Int](repeating: 16, count: 256), 0, 0.03, -0.03),
            ("dark", levels { for i in 10...90 { $0[i] = 50 } }, 0, 1, -0.26),
            ("bright", levels { $0[200] = 2000; $0[250] = 2096 }, -0.5, 0.13, -1),
            ("a speck of black", levels { $0[0] = 100; for i in 40...200 { $0[i] = 25 } }, -0.09, 1, 0),
            ("nothing", levels { _ in }, 0, 0, 0),
        ]
    }

    func testAutoAdjustReadsTheHistogram() {
        for (what, histogram, brightness, whites, blacks) in autoTable {
            XCTAssertEqual(PhotoLook.autoAdjust(histogram),
                           PhotoLook.Auto(brightness: brightness, whites: whites, blacks: blacks), what)
        }
    }

    /// Clear pixels are not counted; a half-clear one counts at its colour.
    func testTheHistogramCountsLightnessByRec709() {
        let pixels = [0xff000000, 0xffffffff, 0xff808080, 0x00ffffff, 0xffc86432, 0x80ff0000]
        let counts = PhotoLook.histogram(pixels)
        XCTAssertEqual(counts.reduce(0, +), 5)
        for level in [0, 54, 118, 128, 255] { XCTAssertEqual(counts[level], 1, "level \(level)") }
    }

    /// Auto adjust sets its three dials and keeps the rest.
    func testAutoAdjustKeepsTheOtherDials() {
        var before = Adjustments()
        before.warmth = 0.4
        before.whites = -0.2
        let after = PhotoLook.autoAdjusted(before, histogram: [Int](repeating: 16, count: 256))
        XCTAssertEqual(after.warmth, 0.4)
        XCTAssertEqual(after.whites, 0.03)
        XCTAssertEqual(after.blacks, -0.03)
        XCTAssertEqual(after.brightness, 0)
    }

    func testTheLightDialsAreFivePoints() {
        XCTAssertNil(ToneCurve.light(highlights: 0, shadows: 0, whites: 0, blacks: 0))
        let points = ToneCurve.light(highlights: 1, shadows: -1, whites: 1, blacks: -1)
        XCTAssertEqual(points, [CGPoint(x: 0.15, y: 0), CGPoint(x: 0.25, y: 0.1), CGPoint(x: 0.5, y: 0.5),
                                CGPoint(x: 0.75, y: 0.9), CGPoint(x: 0.85, y: 1)])
        let lifted = ToneCurve.light(highlights: 0, shadows: 0, whites: -1, blacks: 1)
        XCTAssertEqual(lifted?.first, CGPoint(x: 0, y: 0.15))
        XCTAssertEqual(lifted?.last, CGPoint(x: 1, y: 0.85))
        // Crushed: black from the first point down.
        let crush = ToneCurve.table(ToneCurve.light(highlights: 0, shadows: 0, whites: 0, blacks: -1) ?? [])
        XCTAssertEqual(crush[0], 0)
        XCTAssertEqual(crush[38], 0)
        XCTAssertEqual(crush[128], 128)
        XCTAssertEqual(crush[255], 255)
    }

    /// A curve through points on the diagonal is the diagonal.
    func testAStraightCurveChangesNothing() {
        let line = (0...4).map { CGPoint(x: Double($0) / 4, y: Double($0) / 4) }
        XCTAssertEqual(ToneCurve.table(line), Array(0...255))
    }

    func testStrengthIsAShareOfTheFilter() {
        XCTAssertEqual(PhotoLook.strength(nil), 1)
        XCTAssertEqual(PhotoLook.strength(0.4), 0.4)
        XCTAssertEqual(PhotoLook.strength(-2), 0)
        XCTAssertEqual(PhotoLook.strength(.nan), 1)
        let vivid = PhotoLook.preset(.vivid)
        XCTAssertTrue(vivid.partly(0).isIdentity)
        for (whole, all) in zip(vivid.m, vivid.partly(1).m) { XCTAssertEqual(whole, all, accuracy: 1e-12) }
        XCTAssertNil(PhotoLook.preMatrix("vivid", nil, strength: 0))
        XCTAssertNil(PhotoLook.preMatrix(nil, nil, strength: nil))
    }

    // MARK: drawn by Core Image

    private func flat(_ hex: Int, size: Int = 16) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let color = UIColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        return UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        }
    }

    private func centre(_ image: UIImage) throws -> Int {
        let cg = try XCTUnwrap(image.cgImage)
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cg, in: CGRect(x: -cg.width / 2, y: -cg.height / 2, width: cg.width, height: cg.height))
        }
        return (Int(pixel[0]) << 16) | (Int(pixel[1]) << 8) | Int(pixel[2])
    }

    /// The engine draws the new dials as the shared maths says, within a
    /// few levels: they run on the values a picture stores, not on Core
    /// Image's linear light.
    func testTheEngineDrawsWhatTheTableSays() throws {
        let rows: [(String, Int, String?, Adjustments, Double?)] = [
            ("tint", 0x808080, nil, dials { $0.tint = 1 }, nil),
            ("fade", 0x000000, nil, dials { $0.fade = 1 }, nil),
            ("shadows", 0x404040, nil, dials { $0.shadows = -1 }, nil),
            ("blacks", 0x000000, nil, dials { $0.blacks = 0.5 }, nil),
            ("vibrance", 0x967864, nil, dials { $0.vibrance = 1 }, nil),
            ("noir at none", 0xc86432, "noir", Adjustments(), 0),
        ]
        for (what, input, filter, adjustments, strength) in rows {
            let drawn = try centre(ImageFilterEngine.apply(
                ImageFilterPreset.from(filter), adjustments: adjustments, duotone: nil,
                strength: PhotoLook.strength(strength), to: flat(input), cacheKey: UUID().uuidString))
            let shared = PhotoLook.pixel(input, filter: filter, adjustments: adjustments, strength: strength)
            for shift in [16, 8, 0] {
                XCTAssertEqual(Double((drawn >> shift) & 0xff), Double((shared >> shift) & 0xff),
                               accuracy: 6, "\(what), channel \(shift)")
            }
        }
    }

    // MARK: the file

    /// The dials that came later are written only once moved, so a photo
    /// nobody has turned them on is saved exactly as before.
    func testTheLaterDialsAreWrittenOnlyOnceMoved() throws {
        var a = Adjustments()
        a.brightness = 0.2
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        XCTAssertEqual(Set(plain.keys), ["brightness", "contrast", "saturation", "warmth", "sharpness", "vignette"])
        a.tint = -0.3
        a.fade = 0.5
        a.clarity = 0.1
        let moved = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        XCTAssertEqual(moved["tint"] as? Double, -0.3)
        XCTAssertEqual(moved["fade"] as? Double, 0.5)
        XCTAssertEqual(moved["clarity"] as? Double, 0.1)
        XCTAssertNil(moved["highlights"])
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(a)), a)
    }

    func testEveryNewDialReadsFromTheFile() throws {
        let json = #"{"tint":0.1,"highlights":0.2,"shadows":0.3,"whites":0.4,"blacks":-0.5,"vibrance":0.6,"clarity":0.7,"fade":0.8}"#
        let a = try JSONDecoder().decode(Adjustments.self, from: Data(json.utf8))
        XCTAssertEqual([a.tint, a.highlights, a.shadows, a.whites, a.blacks, a.vibrance, a.clarity, a.fade],
                       [0.1, 0.2, 0.3, 0.4, -0.5, 0.6, 0.7, 0.8])
        XCTAssertEqual(a.brightness, 0)
    }

    func testThePhotoKeysAreOmittedAtTheirDefaults() throws {
        let photo = Element.image("asset:x", w: 100, h: 100)
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(photo)) as? [String: Any])
        for key in ["filterStrength", "pixelate", "focusBlur", "edge"] { XCTAssertNil(plain[key], key) }

        var edited = photo
        edited.filterStrength = 0.4
        edited.pixelate = 0.25
        edited.focusBlur = FocusBlur(x: 0.2, y: 0.7, radius: 0.1, amount: 0.9, subject: true)
        edited.edge = PhotoEdge(kind: "glow", color: "#ffe066", width: 45)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
        XCTAssertEqual(object["filterStrength"] as? Double, 0.4)
        XCTAssertEqual(object["pixelate"] as? Double, 0.25)
        let focus = try XCTUnwrap(object["focusBlur"] as? [String: Any])
        XCTAssertEqual(Set(focus.keys), ["x", "y", "radius", "amount", "subject"])
        let edge = try XCTUnwrap(object["edge"] as? [String: Any])
        XCTAssertEqual(edge["kind"] as? String, "glow")
        XCTAssertEqual(edge["color"] as? String, "#ffe066")
        XCTAssertEqual(edge["width"] as? Double, 45)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(edited)), edited)
    }

    /// Written at their defaults by some other build, they read as unset;
    /// a partial object reads with the rest at its defaults.
    func testThePhotoKeysReadForgivingly() throws {
        let json = #"{"id":"el_1","type":"image","src":"asset:x","w":10,"h":10,"filterStrength":1,"pixelate":0,"focusBlur":{"x":0.25},"edge":{"kind":"glow"}}"#
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertNil(el.filterStrength)
        XCTAssertNil(el.pixelate)
        XCTAssertEqual(el.focusBlur, FocusBlur(x: 0.25))
        XCTAssertEqual(el.edge, PhotoEdge(kind: "glow", color: "#ffffff", width: 30))
        let odd = #"{"id":"el_1","type":"image","filterStrength":-3,"pixelate":4}"#
        let held = try JSONDecoder().decode(Element.self, from: Data(odd.utf8))
        XCTAssertEqual(held.filterStrength, 0)
        XCTAssertEqual(held.pixelate, 1)
    }

    /// Reset photo edits takes off the new keys too, and keeps the crop.
    func testResetPhotoEditsTakesOffTheNewKeys() {
        var photo = Element.image("asset:sun")
        photo.cropScale = 2
        let edits: [(String, (inout Element) -> Void)] = [
            ("filterStrength", { $0.filterStrength = 0.5 }),
            ("tint", { $0.setAdjustment(\.tint, to: 0.3) }),
            ("pixelate", { $0.pixelate = 0.2 }),
            ("focusBlur", { $0.focusBlur = FocusBlur() }),
            ("edge", { $0.edge = PhotoEdge() }),
        ]
        for (name, edit) in edits {
            var el = photo
            edit(&el)
            XCTAssertTrue(PhotoEdits.any(el), name)
            XCTAssertTrue(DesignStore.hasLook(el), name)
            PhotoEdits.reset(&el)
            XCTAssertFalse(PhotoEdits.any(el), name)
            XCTAssertEqual(el.cropScale, 2, name)
        }
    }

    /// A dial put back to the middle leaves no adjustments behind.
    func testADialBackAtZeroLeavesNoAdjustments() {
        var el = Element.image("asset:sun")
        el.setAdjustment(\.vibrance, to: 0.4)
        XCTAssertEqual(el.adjustments?.vibrance, 0.4)
        el.setAdjustment(\.vibrance, to: 0)
        XCTAssertNil(el.adjustments)
    }

    func testStyleCopyCarriesTheFilterStrength() {
        var source = Element.image("asset:a", w: 100, h: 100)
        source.filter = "mono"
        source.filterStrength = 0.3
        var target = Element.image("asset:b", w: 50, h: 50)
        DesignStore.apply(DesignStore.style(of: source), to: &target)
        XCTAssertEqual(target.filterStrength, 0.3)
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
