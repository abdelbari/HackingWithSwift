// The twelve later filters (PhotoLook.recipe), the photo fx — glitch,
// slice, halftone and grain, in the `fx` key and a pixel at a time
// (PhotoLook.fx) — and Hold to compare. The tables are the Android twin's
// PhotoLookTest and PixelLookTest rows, value for value.

import UIKit
import XCTest
@testable import Canvia

final class PhotoLooksTests: XCTestCase {

    // MARK: filters

    func testTheTwelveNewFiltersFollowTheNineInOrder() {
        XCTAssertEqual(ImageFilterPreset.allCases.map(\.rawValue), [
            "none", "vivid", "warm", "cool", "mono", "noir", "fade", "retro", "dramatic", "dreamy",
            "summer", "street", "nordic", "bliss", "whimsical", "selfie", "festive", "coastal", "drama", "edge",
            "solar", "classic",
        ])
        XCTAssertEqual(ImageFilterPreset.from("whimsical").displayName, "Whimsical")
        XCTAssertEqual(ImageFilterPreset.from("edge").displayName, "Edge")
        for preset in ImageFilterPreset.allCases.prefix(10) { XCTAssertNil(PhotoLook.recipe(preset), preset.rawValue) }
        for preset in ImageFilterPreset.allCases.dropFirst(10) { XCTAssertNotNil(PhotoLook.recipe(preset), preset.rawValue) }
    }

    /// Each later filter's red and blue rows, entry for entry with the
    /// Android twin's matrices.
    func testTheNewFiltersMatrices() throws {
        let rows: [(ImageFilterPreset, red: [Double], blue: [Double])] = [
            (.summer, [1.401908, -0.229858, -0.020895, 0, 0.0065], [-0.072293, -0.229858, 1.234905, 0, 0.0065]),
            (.street, [0.954687, 0.268275, 0.027038, 0, -0.15], [0.079687, 0.268275, 0.902038, 0, -0.15]),
            (.nordic, [0.684917, 0.162262, 0.017661, 0, 0.105165], [0.045306, 0.162262, 0.752534, 0, 0.105165]),
            (.bliss, [1.125952, -0.101944, -0.010685, 0, 0.082], [-0.032098, -0.101944, 1.125515, 0, 0.082]),
            (.whimsical, [1.043067, -0.291356, 0.210789, 0, 0.076], [-0.224533, 0.052041, 1.134992, 0, 0.076]),
            (.selfie, [1.036777, -0.033982, -0.003356, 0, 0.0725], [-0.010598, -0.033982, 0.974194, 0, 0.0725]),
            (.festive, [1.682134, -0.362815, -0.036566, 0, -0.075], [-0.118766, -0.362815, 1.597584, 0, -0.075]),
            (.coastal, [1.001754, -0.071329, -0.007753, 0, 0.051825], [-0.019733, -0.071329, 1.175022, 0, 0.051825]),
            (.drama, [1.146437, 0.139503, 0.01406, 0, -0.202], [0.041438, 0.139503, 1.11906, 0, -0.202]),
            (.edge, [1.675625, -0.25039, -0.025235, 0, -0.2], [-0.074375, -0.25039, 1.724765, 0, -0.2]),
            (.solar, [1.065224, 0.097632, 0.041135, 0, -0.028], [0.035294, 0.020082, 1.011995, 0, -0.028]),
            (.classic, [0.253383, 0.853035, 0.085971, 0, -0.062765], [0.238435, 0.802711, 0.080899, 0, -0.058177]),
        ]
        XCTAssertEqual(rows.count, 12)
        for (preset, red, blue) in rows {
            let m = PhotoLook.preset(preset).m
            XCTAssertEqual(m, try XCTUnwrap(PhotoLook.recipe(preset)).matrix.m, preset.rawValue)
            for (i, want) in red.enumerated() { XCTAssertEqual(m[i], want, accuracy: 1e-6, "\(preset.rawValue) red \(i)") }
            for (i, want) in blue.enumerated() {
                XCTAssertEqual(m[10 + i], want, accuracy: 1e-6, "\(preset.rawValue) blue \(i)")
            }
        }
    }

    func testTheNewFiltersCurvesAndVignettes() {
        let curves: [ImageFilterPreset: String] = [.street: "crush", .bliss: "bright", .selfie: "lift",
                                                    .drama: "scurve", .edge: "crush"]
        let vignettes: [ImageFilterPreset: Double] = [.street: 0.3, .festive: 0.25, .drama: 0.45, .edge: 0.2,
                                                      .solar: 0.2]
        for preset in ImageFilterPreset.allCases.dropFirst(10) {
            XCTAssertEqual(PhotoLook.recipe(preset)?.curve, curves[preset], preset.rawValue)
            XCTAssertEqual(PhotoLook.recipe(preset)?.vignette, vignettes[preset] ?? 0, preset.rawValue)
            if let curve = curves[preset] { XCTAssertNotNil(ToneCurve.preset(curve), curve) }
        }
    }

    /// A colour through each later filter, whole and at half: the shared
    /// table's rows for them. A filter with a curve is drawn whole and mixed
    /// with the colour by its strength.
    func testTheNewFiltersTable() {
        let rows: [(String, whole: Int, half: Int)] = [
            ("summer", 0xff661a, 0x397fba),
            ("street", 0xb84a1a, 0x2e6dac),
            ("nordic", 0xb5795a, 0x4b7fb6),
            ("bliss", 0xf18a4e, 0x4d8dca),
            ("whimsical", 0xd17824, 0x487dc6),
            ("selfie", 0xdf8155, 0x4f85ba),
            ("festive", 0xff5201, 0x2e78c7),
            ("coastal", 0xce6f3d, 0x3e7fc5),
            ("drama", 0xd24210, 0x2a6bb6),
            ("edge", 0xff3d00, 0x2174cc),
            ("solar", 0xda7135, 0x447db4),
            ("classic", 0x7c7a75, 0x597591),
        ]
        for (filter, whole, half) in rows {
            let full = PhotoLook.pixel(0xc86432, filter: filter, adjustments: nil, strength: nil)
            XCTAssertEqual(String(format: "%06x", full), String(format: "%06x", whole), "\(filter) whole")
            let mixed = PhotoLook.pixel(0x3c78b4, filter: filter, adjustments: nil, strength: 0.5)
            XCTAssertEqual(String(format: "%06x", mixed), String(format: "%06x", half), "\(filter) at half")
        }
        // Black, grey and white through a few.
        XCTAssertEqual(PhotoLook.pixel(0x808080, filter: "summer", adjustments: nil, strength: nil), 0x958b79)
        XCTAssertEqual(PhotoLook.pixel(0x000000, filter: "nordic", adjustments: nil, strength: nil), 0x1b1b1b)
        XCTAssertEqual(PhotoLook.pixel(0x000000, filter: "selfie", adjustments: nil, strength: nil), 0x282828)
        XCTAssertEqual(PhotoLook.pixel(0x808080, filter: "drama", adjustments: nil, strength: nil), 0x6e6e6e)
        XCTAssertEqual(PhotoLook.pixel(0xc86432, filter: "drama", adjustments: nil, strength: 0), 0xc86432)
    }

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

    /// Core Image draws the later filters as the shared maths says, within
    /// a few levels, at the middle of the picture, clear of the vignette.
    func testTheEngineDrawsTheNewFiltersAsTheTableSays() throws {
        for filter in ["summer", "nordic", "whimsical", "classic"] {
            let drawn = try centre(ImageFilterEngine.apply(ImageFilterPreset.from(filter), adjustments: .neutral,
                                                           duotone: nil, to: flat(0xc86432),
                                                           cacheKey: UUID().uuidString))
            let shared = PhotoLook.pixel(0xc86432, filter: filter, adjustments: nil, strength: nil)
            for shift in [16, 8, 0] {
                XCTAssertEqual(Double((drawn >> shift) & 0xff), Double((shared >> shift) & 0xff),
                               accuracy: 6, "\(filter), channel \(shift)")
            }
        }
    }

    // MARK: the seeded random numbers

    /// The generator both phones draw an fx's bands, strips and grain from.
    func testTheSeededRandomNumbers() {
        var random = SeededRandom(seed: 7)
        XCTAssertEqual(random.next(), 0.238780839834, accuracy: 1e-11)
        XCTAssertEqual(random.next(), 0.913493264699, accuracy: 1e-11)
        XCTAssertEqual(random.next(), 0.612491666339, accuracy: 1e-11)
        var whole = SeededRandom(seed: 7)
        XCTAssertEqual([10, 10, 10, 6, 2].map { whole.below($0) }, [2, 9, 6, 5, 0])
        XCTAssertEqual(whole.below(0), 0)
    }

    // MARK: fx, a pixel at a time

    /// An opaque test picture: red 40 a column, green 60 a row, blue 20 a
    /// step of either, as 0xRRGGBBAA.
    private func ramp(_ w: Int, _ h: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        for y in 0..<h {
            for x in 0..<w {
                bytes += [UInt8((x * 40) & 0xff), UInt8((y * 60) & 0xff), UInt8(((x + y) * 20) & 0xff), 255]
            }
        }
        return bytes
    }

    private func words(_ bytes: [UInt8]) -> [UInt32] {
        stride(from: 0, to: bytes.count, by: 4).map { i in
            (UInt32(bytes[i]) << 24) | (UInt32(bytes[i + 1]) << 16) | (UInt32(bytes[i + 2]) << 8) | UInt32(bytes[i + 3])
        }
    }

    private func drawn(_ bytes: [UInt8], _ w: Int, _ h: Int, _ fx: PhotoFx) -> [UInt32] {
        var out = bytes
        PhotoLook.fx(&out, width: w, height: h, fx: fx)
        return words(out)
    }

    func testGlitchSlidesBandsOfRowsFromItsSeed() {
        // Too narrow for the colours to part: four bands of one row, slid
        // by one pixel or none.
        XCTAssertEqual(drawn(ramp(6, 4), 6, 4, PhotoFx(kind: "glitch", amount: 1, seed: 3)), [
            0x000000ff, 0x280014ff, 0x500028ff, 0x78003cff, 0xa00050ff, 0xc80064ff,
            0xc83c78ff, 0x003c14ff, 0x283c28ff, 0x503c3cff, 0x783c50ff, 0xa03c64ff,
            0xc8788cff, 0x007828ff, 0x28783cff, 0x507850ff, 0x787864ff, 0xa07878ff,
            0x00b43cff, 0x28b450ff, 0x50b464ff, 0x78b478ff, 0xa0b48cff, 0xc8b4a0ff,
        ])
        // Wide enough for red and blue to part by a pixel, and bands slid
        // by two.
        XCTAssertEqual(drawn(ramp(20, 2), 20, 2, PhotoFx(kind: "glitch", amount: 1, seed: 5)), [
            0xf80054ff, 0xf80068ff, 0x280000ff, 0x500000ff, 0x780014ff, 0xa00028ff, 0xc8003cff, 0xf00050ff,
            0x180064ff, 0x400078ff, 0x68008cff, 0x9000a0ff, 0xb800b4ff, 0xe000c8ff, 0x0800dcff, 0x3000f0ff,
            0x580004ff, 0x800018ff, 0xa8002cff, 0xd00040ff,
            0xf83c68ff, 0xf83c7cff, 0x283c14ff, 0x503c14ff, 0x783c28ff, 0xa03c3cff, 0xc83c50ff, 0xf03c64ff,
            0x183c78ff, 0x403c8cff, 0x683ca0ff, 0x903cb4ff, 0xb83cc8ff, 0xe03cdcff, 0x083cf0ff, 0x303c04ff,
            0x583c18ff, 0x803c2cff, 0xa83c40ff, 0xd03c54ff,
        ])
    }

    func testSliceSlidesAlternateStrips() {
        // Seven standing strips, the even ones up a row and the odd down.
        XCTAssertEqual(drawn(ramp(4, 13), 4, 13, PhotoFx(kind: "slice", amount: 1, seed: 2)), [
            0x00d0f0ff, 0x28d004ff, 0x50d018ff, 0x783c50ff, 0x000000ff, 0x280014ff, 0x500028ff, 0x787864ff,
            0x003c14ff, 0x283c28ff, 0x503c3cff, 0x78b478ff, 0x007828ff, 0x28783cff, 0x507850ff, 0x78f08cff,
            0x00b43cff, 0x28b450ff, 0x50b464ff, 0x782ca0ff, 0x00f050ff, 0x28f064ff, 0x50f078ff, 0x7868b4ff,
            0x002c64ff, 0x282c78ff, 0x502c8cff, 0x78a4c8ff, 0x006878ff, 0x28688cff, 0x5068a0ff, 0x78e0dcff,
            0x00a48cff, 0x28a4a0ff, 0x50a4b4ff, 0x781cf0ff, 0x00e0a0ff, 0x28e0b4ff, 0x50e0c8ff, 0x785804ff,
            0x001cb4ff, 0x281cc8ff, 0x501cdcff, 0x789418ff, 0x0058c8ff, 0x2858dcff, 0x5058f0ff, 0x78d02cff,
            0x0094dcff, 0x2894f0ff, 0x509404ff, 0x78003cff,
        ])
    }

    func testHalftoneKeepsTheDotsAndWhitensThePaper() {
        func grey(_ hex: Int, amount: Double) -> (paper: Int, words: [UInt32]) {
            let one: [UInt8] = [UInt8(hex >> 16 & 0xff), UInt8(hex >> 8 & 0xff), UInt8(hex & 0xff), 255]
            let out = drawn([UInt8](Array(repeating: one, count: 50 * 50).joined()), 50, 50,
                            PhotoFx(kind: "halftone", amount: amount))
            return (out.filter { $0 == 0xffffffff }.count, out)
        }
        let mid = grey(0x808080, amount: 1)
        XCTAssertEqual(mid.paper, 524)
        XCTAssertEqual(mid.words[0], 0xffffffff)
        XCTAssertEqual(mid.words[1], 0x808080ff)
        XCTAssertEqual(mid.words[10 * 50 + 10], 0xffffffff)
        XCTAssertEqual(mid.words[10 * 50 + 11], 0x808080ff)
        XCTAssertEqual(grey(0x404040, amount: 0.5).paper, 103)
        XCTAssertEqual(grey(0xc0c0c0, amount: 1).paper, 1540)
        // Black fills every cell; white is all paper.
        XCTAssertEqual(grey(0x000000, amount: 1).paper, 0)
        XCTAssertEqual(grey(0xffffff, amount: 1).paper, 2500)
    }

    func testGrainLiftsAndLowersEachPixelFromItsSeed() {
        let bytes: [UInt8] = [100, 100, 100, 255, 0, 0, 0, 255, 250, 250, 250, 255,
                              50, 50, 50, 128, 0, 0, 0, 0, 200, 10, 90, 255]
        XCTAssertEqual(drawn(bytes, 3, 2, PhotoFx(kind: "grain", amount: 1, seed: 9)),
                       [0x4b4b4bff, 0x000000ff, 0xffffffff, 0x1a1a1a80, 0x00000000, 0xba004cff])
        XCTAssertEqual(drawn(bytes, 3, 2, PhotoFx(kind: "grain", amount: 0.5, seed: 9)),
                       [0x575757ff, 0x000000ff, 0xffffffff, 0x26262680, 0x00000000, 0xc10353ff])
    }

    func testAnFxOfNothingChangesNothing() {
        let bytes = ramp(6, 4)
        XCTAssertEqual(drawn(bytes, 6, 4, PhotoFx(kind: "grain", amount: 0, seed: 9)), words(bytes))
        XCTAssertEqual(drawn(bytes, 6, 4, PhotoFx(kind: "melt", amount: 1)), words(bytes))
        XCTAssertFalse(PhotoFx(kind: "glitch", amount: 0).draws)
        XCTAssertTrue(PhotoFx(kind: "glitch", amount: 3).draws)
        XCTAssertEqual(PhotoFx(kind: "glitch", amount: 3).share, 1)
    }

    // MARK: the fx key

    private func element(_ fx: String?) throws -> Element {
        let extra = fx.map { ", \"fx\": \($0)" } ?? ""
        let json = "{\"id\": \"p1\", \"type\": \"image\", \"src\": \"asset:sun\"\(extra)}"
        return try JSONDecoder().decode(Element.self, from: Data(json.utf8))
    }

    func testTheFxKeyIsWrittenWholeAndReadForgivingly() throws {
        var el = Element.image("asset:sun")
        el.fx = PhotoFx(kind: "halftone", amount: 0.4, seed: 12)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        let written = try XCTUnwrap(object["fx"] as? [String: Any])
        XCTAssertEqual(written["kind"] as? String, "halftone")
        XCTAssertEqual(written["amount"] as? Double, 0.4)
        XCTAssertEqual(written["seed"] as? Int, 12)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el)).fx, el.fx)

        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Element.image("asset:sun"))) as? [String: Any]
        XCTAssertNil(plain?["fx"], "no fx is no key")
        XCTAssertEqual(try element(#"{"kind": "grain"}"#).fx, PhotoFx(kind: "grain", amount: 0.5, seed: 0))
        XCTAssertEqual(try element(#"{"kind": "slice", "amount": "lots", "seed": 4}"#).fx,
                       PhotoFx(kind: "slice", amount: 0.5, seed: 4))
        XCTAssertNil(try element(#"{"kind": "melt", "amount": 1}"#).fx, "an unknown kind is no fx")
        XCTAssertNil(try element(#"{"amount": 1}"#).fx)
        XCTAssertNil(try element(#""glitch""#).fx)
    }

    func testTheFxIsPartOfTheLookAndItsCacheKey() {
        var el = Element.image("asset:sun", w: 100, h: 100)
        el.fx = PhotoFx(kind: "glitch", amount: 0.5, seed: 3)
        let plan = PhotoEffects.plan(el, picture: CGSize(width: 100, height: 100))
        XCTAssertEqual(plan.fx, el.fx)
        XCTAssertTrue(plan.signature.contains("|fxglitch0.5,3"), plan.signature)
        XCTAssertTrue(ImageFilterEngine.makesLater(el))
        el.fx?.amount = 0
        XCTAssertNil(PhotoEffects.plan(el, picture: CGSize(width: 100, height: 100)).fx)
        // A code never draws one, so it still scans.
        var code = Element.image(CodeGenerator.source(for: "https://example.com"))
        code.fx = PhotoFx(kind: "grain", amount: 1, seed: 1)
        XCTAssertFalse(ImageFilterEngine.makesLater(code))
    }

    func testResetPhotoEditsTakesOffTheFx() {
        var el = Element.image("asset:sun")
        el.fx = PhotoFx(kind: "slice")
        XCTAssertTrue(PhotoEdits.any(el))
        PhotoEdits.reset(&el)
        XCTAssertNil(el.fx)
        XCTAssertFalse(PhotoEdits.any(el))
    }

    // MARK: Hold to compare

    func testHoldToCompareShowsThePhotoWithoutItsLooks() {
        var photo = Element.image("asset:sun")
        photo.filter = "drama"
        photo.filterStrength = 0.5
        photo.setAdjustment(\.brightness, to: 0.3)
        photo.duotone = Duotone.presets[0].tone
        photo.pixelate = 0.2
        photo.focusBlur = FocusBlur()
        photo.edge = PhotoEdge()
        photo.fx = PhotoFx(kind: "grain")
        photo.straighten = 5
        photo.cropScale = 2
        let shown = PhotoEdits.original(photo)
        XCTAssertFalse(PhotoEdits.any(PhotoEdits.original(Element.image("asset:sun"))))
        for (name, gone) in [("filter", shown.filter == nil), ("strength", shown.filterStrength == nil),
                             ("dials", shown.adjustments == nil), ("duotone", shown.duotone == nil),
                             ("pixelate", shown.pixelate == nil), ("focus", shown.focusBlur == nil),
                             ("edge", shown.edge == nil), ("fx", shown.fx == nil)] {
            XCTAssertTrue(gone, name)
        }
        XCTAssertEqual(shown.straighten, 5, "where it sits stays")
        XCTAssertEqual(shown.cropScale, 2)
        XCTAssertEqual(PhotoEdits.comparingNote, "Showing original")

        let text = Element.text("Hello")
        let page = Page(elements: [photo, text])
        let compared = PhotoEdits.comparing(page, photo.id)
        XCTAssertEqual(compared.elements[0], shown)
        XCTAssertEqual(compared.elements[1], text)
        XCTAssertEqual(PhotoEdits.comparing(page, text.id), page, "only a photo is compared")
    }

    @MainActor
    func testComparingWritesNothing() {
        var design = Design(title: "compare", width: 1000, height: 1000)
        var photo = Element.image("asset:sun")
        photo.filter = "summer"
        design.pages[0].elements = [photo]
        let s = DesignStore(design: design)
        s.select(photo.id)
        let before = s.design
        s.comparing = true
        XCTAssertEqual(s.element(photo.id)?.filter, "summer")
        s.comparing = false
        XCTAssertEqual(s.design, before)
        XCTAssertFalse(s.canUndo, "no step")
    }
}
