// Image filter presets applied with Core Image, mirroring the web preset
// names. Filtered images are cached per (source, preset).

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation

enum ImageFilterPreset: String, CaseIterable, Identifiable {
    case none, vivid, warm, cool, mono, noir, fade, retro, dramatic, dreamy

    var id: String { rawValue }
    var displayName: String { rawValue == "none" ? "None" : rawValue.capitalized }

    static func from(_ key: String?) -> ImageFilterPreset {
        ImageFilterPreset(rawValue: key ?? "none") ?? .none
    }
}

/// Every edit made to how a photo looks — filter and its strength, dials
/// and curve, duotone, straighten, show-whole and the effects (pixelate,
/// focus, outline or glow) — as one thing to see or take off, as the
/// Android twin's "Reset photo edits". The crop, frame, corners and Ken
/// Burns drift are where the photo sits, not how it looks, and stay.
enum PhotoEdits {
    static func any(_ el: Element) -> Bool {
        ImageFilterPreset.from(el.filter) != .none
            || el.filterStrength != nil
            || !(el.adjustments?.isNeutral ?? true)
            || el.duotone != nil
            || (el.straighten ?? 0) != 0
            || el.cropFit == true
            || el.pixelate != nil
            || el.focusBlur != nil
            || el.edge != nil
    }

    static func reset(_ el: inout Element) {
        el.filter = nil
        el.filterStrength = nil
        el.adjustments = nil
        el.duotone = nil
        el.straighten = nil
        el.cropFit = nil
        el.pixelate = nil
        el.focusBlur = nil
        el.edge = nil
    }
}

/// Free-hand adjustments on top of a preset.
///
/// One struct rather than six fields on Element: a preset is a look someone
/// picks, an adjustment is a dial they turn, and the two compose. Every value
/// is centred on zero so "no adjustment" is the zero value and a document that
/// predates this decodes as untouched.
struct Adjustments: Codable, Equatable, Hashable {
    /// All in -1…1 except vignette and fade, which only go one way.
    var brightness: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    /// Positive is warmer (more orange), negative cooler (more blue).
    var warmth: Double = 0
    /// Positive sharpens, negative blurs.
    var sharpness: Double = 0
    /// 0…1.
    var vignette: Double = 0
    /// A ToneCurve preset id, or nil for a straight line.
    var curve: String?
    /// Positive is more magenta, negative more green.
    var tint: Double = 0
    /// The light tones, lifted or lowered.
    var highlights: Double = 0
    /// The dark tones, lifted or lowered.
    var shadows: Double = 0
    /// Positive clips the lightest tones to white sooner; negative greys them.
    var whites: Double = 0
    /// Negative crushes the darkest tones to black; positive lifts them.
    var blacks: Double = 0
    /// Saturation that boosts the dull colours more than the bright ones.
    var vibrance: Double = 0
    /// Contrast in the detail: an unsharp mask 2% of the picture across.
    var clarity: Double = 0
    /// 0…1: the blacks lifted towards grey, the contrast eased.
    var fade: Double = 0

    static let neutral = Adjustments()
    var isNeutral: Bool { self == Adjustments.neutral }

    /// Short and stable, for cache keys — and it only lengthens for the dials
    /// actually moved, so an untouched image keys the same as before.
    var signature: String {
        guard !isNeutral else { return "" }
        func f(_ label: String, _ value: Double) -> String {
            value == 0 ? "" : "\(label)\(Int((value * 100).rounded()))"
        }
        return "adj" + f("b", brightness) + f("c", contrast) + f("s", saturation)
            + f("w", warmth) + f("k", sharpness) + f("v", vignette)
            + f("n", tint) + f("h", highlights) + f("o", shadows) + f("x", whites)
            + f("z", blacks) + f("y", vibrance) + f("l", clarity) + f("f", fade)
            + (curve.map { "t\($0)" } ?? "")
    }

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, warmth, sharpness, vignette, curve
        case tint, highlights, shadows, whites, blacks, vibrance, clarity, fade
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = (try? c.decode(Double.self, forKey: .brightness)) ?? 0
        contrast = (try? c.decode(Double.self, forKey: .contrast)) ?? 0
        saturation = (try? c.decode(Double.self, forKey: .saturation)) ?? 0
        warmth = (try? c.decode(Double.self, forKey: .warmth)) ?? 0
        curve = try? c.decode(String.self, forKey: .curve)
        sharpness = (try? c.decode(Double.self, forKey: .sharpness)) ?? 0
        vignette = (try? c.decode(Double.self, forKey: .vignette)) ?? 0
        tint = (try? c.decode(Double.self, forKey: .tint)) ?? 0
        highlights = (try? c.decode(Double.self, forKey: .highlights)) ?? 0
        shadows = (try? c.decode(Double.self, forKey: .shadows)) ?? 0
        whites = (try? c.decode(Double.self, forKey: .whites)) ?? 0
        blacks = (try? c.decode(Double.self, forKey: .blacks)) ?? 0
        vibrance = (try? c.decode(Double.self, forKey: .vibrance)) ?? 0
        clarity = (try? c.decode(Double.self, forKey: .clarity)) ?? 0
        fade = (try? c.decode(Double.self, forKey: .fade)) ?? 0
    }

    /// The first seven as they always were; the dials after the curve came
    /// later and are written only once moved, so a photo nobody has turned
    /// them on is saved exactly as before.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(brightness, forKey: .brightness)
        try c.encode(contrast, forKey: .contrast)
        try c.encode(saturation, forKey: .saturation)
        try c.encode(warmth, forKey: .warmth)
        try c.encode(sharpness, forKey: .sharpness)
        try c.encode(vignette, forKey: .vignette)
        try c.encodeIfPresent(curve, forKey: .curve)
        let later: [(Double, CodingKeys)] = [
            (tint, .tint), (highlights, .highlights), (shadows, .shadows), (whites, .whites),
            (blacks, .blacks), (vibrance, .vibrance), (clarity, .clarity), (fade, .fade),
        ]
        for (value, key) in later where value != 0 { try c.encode(value, forKey: key) }
    }
}

extension Element {
    /// One dial set, the adjustments back to nil when every dial is
    /// centred, so an untouched image keeps the filter cache key it had.
    mutating func setAdjustment(_ key: WritableKeyPath<Adjustments, Double>, to value: Double) {
        var adjustments = self.adjustments ?? .neutral
        adjustments[keyPath: key] = value
        self.adjustments = adjustments.isNeutral ? nil : adjustments
    }
}

/// Two colours a photo is mapped onto by luminance.
///
/// The one photo treatment that makes an image belong to a brand rather than
/// merely sit next to it — which is why it is a pair of colours rather than a
/// preset: the whole point is that they are *your* colours.
struct Duotone: Codable, Equatable, Hashable {
    /// Where the photo is darkest, and where it is lightest.
    var dark: String
    var light: String

    static let presets: [(name: String, tone: Duotone)] = [
        ("Ink", Duotone(dark: "#0b1020", light: "#e9edff")),
        ("Ultraviolet", Duotone(dark: "#2a0a5e", light: "#ffd6f2")),
        ("Sunset", Duotone(dark: "#3d1436", light: "#ffc773")),
        ("Forest", Duotone(dark: "#0d2b1d", light: "#c9f2a0")),
        ("Steel", Duotone(dark: "#131a22", light: "#9fd4ff")),
        ("Rose", Duotone(dark: "#3b0d20", light: "#ffd9d0")),
    ]

    private enum CodingKeys: String, CodingKey { case dark, light }

    init(dark: String, light: String) {
        self.dark = dark
        self.light = light
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dark = (try? c.decode(String.self, forKey: .dark)) ?? "#000000"
        light = (try? c.decode(String.self, forKey: .light)) ?? "#ffffff"
    }
}

/// A colour transform as a 4×5 matrix, row-major: each output channel is a
/// weighted sum of R, G, B and A plus an offset, channels and offsets in
/// 0…1. The Android twin's `ColourMatrix`, entry for entry, so the shared
/// test table (see `PhotoLook.pixel`) reads the same on both phones.
struct ColourMatrix: Equatable {
    var m: [Double]

    /// `self` after `first`: the matrix that applies `first`, then this.
    func after(_ first: ColourMatrix) -> ColourMatrix {
        let a = m, b = first.m
        var out = [Double](repeating: 0, count: 20)
        for row in 0..<4 {
            for col in 0..<4 {
                var sum = 0.0
                for k in 0..<4 { sum += a[row * 5 + k] * b[k * 5 + col] }
                out[row * 5 + col] = sum
            }
            var offset = a[row * 5 + 4]
            for k in 0..<4 { offset += a[row * 5 + k] * b[k * 5 + 4] }
            out[row * 5 + 4] = offset
        }
        return ColourMatrix(m: out)
    }

    /// Only `share` of this transform, 0…1: every entry moved that far from
    /// the identity's towards this one's. A colour matrix is linear, so this
    /// is the transformed colour mixed with the colour it came from.
    func partly(_ share: Double) -> ColourMatrix {
        ColourMatrix(m: (0..<20).map { Self.identityEntries[$0] + share * (m[$0] - Self.identityEntries[$0]) })
    }

    var isIdentity: Bool { (0..<20).allSatisfy { abs(m[$0] - Self.identityEntries[$0]) < 1e-12 } }

    /// As the Android twin draws it: single precision, offsets in 0…255.
    var bytes: [Float] { (0..<20).map { Float($0 % 5 == 4 ? m[$0] * 255 : m[$0]) } }

    private static let identityEntries: [Double] = [
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
    ]

    static var identity: ColourMatrix { ColourMatrix(m: identityEntries) }

    /// Rec. 709 luma, the weights Core Image's colour controls use.
    static let lr = 0.2125
    static let lg = 0.7154
    static let lb = 0.0721

    private static func rgb(_ rr: Double, _ rg: Double, _ rb: Double, _ ro: Double,
                            _ gr: Double, _ gg: Double, _ gb: Double, _ go: Double,
                            _ br: Double, _ bg: Double, _ bb: Double, _ bo: Double) -> ColourMatrix {
        ColourMatrix(m: [rr, rg, rb, 0, ro,
                         gr, gg, gb, 0, go,
                         br, bg, bb, 0, bo,
                         0, 0, 0, 1, 0])
    }

    /// Towards grey (0) or away from it (above 1), about each pixel's luma.
    static func saturation(_ s: Double) -> ColourMatrix {
        let t = 1 - s
        return rgb(lr * t + s, lg * t, lb * t, 0,
                   lr * t, lg * t + s, lb * t, 0,
                   lr * t, lg * t, lb * t + s, 0)
    }

    /// Every channel lifted (or lowered) by the same amount.
    static func brightness(_ b: Double) -> ColourMatrix { rgb(1, 0, 0, b, 0, 1, 0, b, 0, 0, 1, b) }

    /// Stretched away from (or squeezed towards) mid grey.
    static func contrast(_ k: Double) -> ColourMatrix {
        let o = 0.5 * (1 - k)
        return rgb(k, 0, 0, o, 0, k, 0, o, 0, 0, k, o)
    }

    /// Core Image's colour controls, in its order: saturation, then
    /// brightness, then contrast.
    static func controls(saturation s: Double = 1, brightness b: Double = 0, contrast k: Double = 1) -> ColourMatrix {
        contrast(k).after(brightness(b)).after(saturation(s))
    }

    /// The classic sepia matrix, mixed in by `intensity` (0…1).
    static func sepia(_ intensity: Double) -> ColourMatrix {
        let i = min(max(intensity, 0), 1)
        let j = 1 - i
        return rgb(j + i * 0.393, i * 0.769, i * 0.189, 0,
                   i * 0.349, j + i * 0.686, i * 0.168, 0,
                   i * 0.272, i * 0.534, j + i * 0.131, 0)
    }

    /// Hues turned by `degrees` about the grey axis, lightness kept.
    static func hue(_ degrees: Double) -> ColourMatrix {
        let r = degrees * 0.017453292519943295
        let c = cos(r), s = sin(r)
        return rgb(0.213 + c * 0.787 - s * 0.213, 0.715 - c * 0.715 - s * 0.715, 0.072 - c * 0.072 + s * 0.928, 0,
                   0.213 - c * 0.213 + s * 0.143, 0.715 + c * 0.285 + s * 0.140, 0.072 - c * 0.072 - s * 0.283, 0,
                   0.213 - c * 0.213 - s * 0.787, 0.715 - c * 0.715 + s * 0.715, 0.072 + c * 0.928 + s * 0.072, 0)
    }

    /// Each channel scaled on its own.
    static func gains(_ r: Double, _ g: Double, _ b: Double) -> ColourMatrix { rgb(r, 0, 0, 0, 0, g, 0, 0, 0, 0, b, 0) }

    /// Black lifted to `lift`, white kept: a straight line from (0, lift)
    /// to (1, 1) on every channel, flatter the higher it starts.
    static func lift(_ lift: Double) -> ColourMatrix {
        let k = 1 - lift
        return rgb(k, 0, 0, lift, 0, k, 0, lift, 0, 0, k, lift)
    }
}

/// A photo's colour, worked out a pixel at a time: the maths both phones
/// share for the filter at its strength, the dials, Auto adjust and the
/// light dials' curve, with one test table of colours in and out
/// (AdjustmentsTests, the Android twin's PhotoLookTest). The engine below
/// draws the same with Core Image.
enum PhotoLook {

    /// How much of its filter a photo shows, 0…1, from its `filterStrength`:
    /// all of it when there is none, or it is not a number.
    static func strength(_ filterStrength: Double?) -> Double {
        guard let s = filterStrength, s.isFinite else { return 1 }
        return min(max(s, 0), 1)
    }

    /// Where fade at full lifts black to.
    static let fadeLift = 0.15

    /// Clarity's unsharp mask spreads over 2% of the picture's shorter side.
    static let clarityRadius = 0.02

    /// The filter presets, number for number with the engine's Core Image
    /// chains (Dreamy's soft focus is not colour, and not in it).
    static func preset(_ preset: ImageFilterPreset) -> ColourMatrix {
        switch preset {
        case .none: return .identity
        case .vivid: return .controls(saturation: 1.6, brightness: 0.02, contrast: 1.12)
        case .warm: return ColourMatrix.controls(saturation: 1.25, brightness: 0.02).after(.sepia(0.35))
        case .cool: return ColourMatrix.controls(saturation: 1.15, brightness: 0.01).after(.hue(-18))
        case .mono: return .controls(saturation: 0, contrast: 1.08)
        case .noir: return .controls(saturation: 0, brightness: -0.04, contrast: 1.4)
        case .fade: return .controls(saturation: 0.65, brightness: 0.08, contrast: 0.88)
        case .retro: return ColourMatrix.controls(saturation: 1.15, contrast: 0.95).after(.sepia(0.5))
        case .dramatic: return .controls(saturation: 1.1, brightness: -0.03, contrast: 1.35)
        case .dreamy: return .controls(saturation: 1.15, brightness: 0.04)
        }
    }

    /// Tint's gains: red and blue by 1 + 0.06 × tint, green by
    /// 1 − 0.12 × tint — a turn along the green to magenta axis.
    static func tint(_ tint: Double) -> ColourMatrix {
        let t = min(max(tint, -1), 1)
        return .gains(1 + 0.06 * t, 1 - 0.12 * t, 1 + 0.06 * t)
    }

    /// Fade's line: black lifted to 0.15 × fade, white kept, which also
    /// eases the contrast.
    static func fade(_ fade: Double) -> ColourMatrix {
        .lift(fadeLift * min(max(fade, 0), 1))
    }

    /// The colour before the tone curve: the filter's, at its strength
    /// (its matrix moved that share of the way from the identity, the
    /// filtered picture mixed with the plain one), then warmth, tint, the
    /// brightness, contrast and saturation dials, and fade. nil when it
    /// would change nothing.
    static func preMatrix(_ filter: String?, _ adjustments: Adjustments?, strength: Double? = nil) -> ColourMatrix? {
        let share = self.strength(strength)
        let whole = preset(ImageFilterPreset.from(filter))
        var m = share < 1 ? whole.partly(share) : whole
        let a = adjustments ?? .neutral
        if a.warmth != 0 {
            m = ColourMatrix.gains(1 + 0.12 * a.warmth, 1 + 0.02 * a.warmth, 1 - 0.12 * a.warmth).after(m)
        }
        if min(max(a.tint, -1), 1) != 0 { m = tint(a.tint).after(m) }
        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            m = ColourMatrix.controls(saturation: max(0, 1 + a.saturation),
                                      brightness: a.brightness * 0.35,
                                      contrast: 1 + a.contrast * 0.6).after(m)
        }
        if min(max(a.fade, 0), 1) > 0 { m = fade(a.fade).after(m) }
        return m.isIdentity ? nil : m
    }

    /// Vibrance on one colour, 0…255 channels: saturation about its Rec. 709
    /// luma by 1 + `amount` × (1 − its own saturation), where that is its
    /// largest channel less its smallest, over 255 — so a dull colour moves
    /// the whole amount and a pure one not at all.
    static func vibrant(_ r: Int, _ g: Int, _ b: Int, amount: Double) -> (r: Int, g: Int, b: Int) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let luma = ColourMatrix.lr * rf + ColourMatrix.lg * gf + ColourMatrix.lb * bf
        let sat = max(rf, gf, bf) - min(rf, gf, bf)
        let k = 1 + amount * (1 - sat)
        func channel(_ v: Double) -> Int { byte((luma + (v - luma) * k) * 255) }
        return (channel(rf), channel(gf), channel(bf))
    }

    /// One opaque colour, 0xRRGGBB, through a photo's filter at `strength`
    /// and its dials — everything that is the colour of a pixel alone, in
    /// the order the picture gets it: the colour matrix (in single
    /// precision, as the Android twin's paint holds it), vibrance, the
    /// preset curve, the light curve. What a pixel's neighbours decide
    /// (clarity, sharpness, blurs, pixelate) and the duotone are not in it.
    /// The shared test table both phones check their maths against.
    static func pixel(_ rgb: Int, filter: String?, adjustments: Adjustments?, strength: Double? = nil) -> Int {
        var r = (rgb >> 16) & 0xff, g = (rgb >> 8) & 0xff, b = rgb & 0xff
        let a = adjustments ?? .neutral
        if let m = preMatrix(filter, a, strength: strength)?.bytes {
            let fr = Float(r), fg = Float(g), fb = Float(b), fa = Float(255)
            let nr: Float = m[0] * fr + m[1] * fg + m[2] * fb + m[3] * fa + m[4]
            let ng: Float = m[5] * fr + m[6] * fg + m[7] * fb + m[8] * fa + m[9]
            let nb: Float = m[10] * fr + m[11] * fg + m[12] * fb + m[13] * fa + m[14]
            r = byte(Double(nr)); g = byte(Double(ng)); b = byte(Double(nb))
        }
        let vibrance = min(max(a.vibrance, -1), 1)
        if vibrance != 0 {
            let v = vibrant(r, g, b, amount: vibrance)
            r = v.r; g = v.g; b = v.b
        }
        if let table = ToneCurve.table(preset: a.curve) { r = table[r]; g = table[g]; b = table[b] }
        if let points = ToneCurve.light(highlights: a.highlights, shadows: a.shadows,
                                        whites: a.whites, blacks: a.blacks) {
            let table = ToneCurve.table(points)
            r = table[r]; g = table[g]; b = table[b]
        }
        return (r << 16) | (g << 8) | b
    }

    /// Rounded half up and held to a byte, as the Android twin rounds.
    static func byte(_ v: Double) -> Int {
        guard v.isFinite else { return 0 }
        return min(max(Int((v + 0.5).rounded(.down)), 0), 255)
    }

    // MARK: clarity

    /// A colour's lightness, 0xRRGGBB, as clarity reads it: 0.299 red,
    /// 0.587 green and 0.114 blue, in single precision as the Android
    /// twin's PixelLook holds it.
    static func lightness(_ rgb: Int) -> Float {
        let r = Float((rgb >> 16) & 0xff), g = Float((rgb >> 8) & 0xff), b = Float(rgb & 0xff)
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// One pixel of clarity, 0xRRGGBB: its detail — its lightness `light`
    /// less the lightness `around` it — `k` times added to each channel,
    /// rounded half up. The shared table's clarity rows check it.
    static func lifted(_ rgb: Int, light: Float, around: Float, k: Float) -> Int {
        let d = k * (light - around)
        func channel(_ v: Int) -> Int { byte(Double(Float(v) + d)) }
        return (channel((rgb >> 16) & 0xff) << 16) | (channel((rgb >> 8) & 0xff) << 8) | channel(rgb & 0xff)
    }

    /// Clarity on `bytes` — RGBA, premultiplied, `width` × `height`, top
    /// row first — by `amount`, −1…1: each pixel `lifted` by its lightness
    /// less a Gaussian of the lightness about it, spread `clarityRadius` of
    /// the shorter side, as the Android twin's PixelLook does it. Below zero
    /// the detail is taken away, which softens.
    static func clarify(_ bytes: inout [UInt8], width: Int, height: Int, amount: Double) {
        let n = width * height
        let k = Float(min(max(amount, -1), 1))
        guard k != 0, width > 0, height > 0, bytes.count >= n * 4 else { return }
        var colours = [Int](repeating: 0, count: n)
        var light = [Float](repeating: 0, count: n)
        for i in 0..<n {
            colours[i] = unpremultiplied(bytes, at: i)
            light[i] = lightness(colours[i])
        }
        var around = light
        gauss(&around, width: width, height: height, sigma: clarityRadius * Double(min(width, height)))
        for i in 0..<n {
            let a = Int(bytes[i * 4 + 3])
            guard a > 0 else { continue }
            let c = lifted(colours[i], light: light[i], around: around[i], k: k)
            bytes[i * 4] = UInt8((((c >> 16) & 0xff) * a + 127) / 255)
            bytes[i * 4 + 1] = UInt8((((c >> 8) & 0xff) * a + 127) / 255)
            bytes[i * 4 + 2] = UInt8(((c & 0xff) * a + 127) / 255)
        }
    }

    /// Pixel `i` of premultiplied RGBA `bytes` as 0xRRGGBB at the colour it
    /// is, as the Android twin's pixels hold it; 0 where it is clear.
    static func unpremultiplied(_ bytes: [UInt8], at i: Int) -> Int {
        let a = Int(bytes[i * 4 + 3])
        guard a > 0 else { return 0 }
        func channel(_ v: UInt8) -> Int { min(255, (Int(v) * 255 + a / 2) / a) }
        return (channel(bytes[i * 4]) << 16) | (channel(bytes[i * 4 + 1]) << 8) | channel(bytes[i * 4 + 2])
    }

    /// A Gaussian of spread `sigma` over a plane `width` × `height`, its
    /// edges held: three box blurs, each across then down, or below a spread
    /// of 2 a small exact kernel — step for step the Android twin's
    /// `PixelLook.gauss`, so clarity reads the same lightness about a pixel
    /// there.
    static func gauss(_ v: inout [Float], width w: Int, height h: Int, sigma: Double) {
        guard sigma > 0, w > 0, h > 0, v.count >= w * h else { return }
        var tmp = [Float](repeating: 0, count: v.count)
        if sigma < 2 {
            let radius = max(1, Int((sigma * 3 + 0.5).rounded(.down)))
            var kernel = (0...(2 * radius)).map { i -> Float in
                let d = Double(i - radius)
                return Float(exp(-(d * d) / (2 * sigma * sigma)))
            }
            let total = kernel.reduce(0, +)
            for i in kernel.indices { kernel[i] /= total }
            for y in 0..<h {
                let row = y * w
                for x in 0..<w {
                    var sum: Float = 0
                    for j in -radius...radius { sum += kernel[j + radius] * v[row + min(w - 1, max(0, x + j))] }
                    tmp[row + x] = sum
                }
            }
            for y in 0..<h {
                for x in 0..<w {
                    var sum: Float = 0
                    for j in -radius...radius { sum += kernel[j + radius] * tmp[min(h - 1, max(0, y + j)) * w + x] }
                    v[y * w + x] = sum
                }
            }
            return
        }
        // Three box widths that together blur like the Gaussian.
        let ideal = (12 * sigma * sigma / 3 + 1).squareRoot()
        var lower = Int(ideal)
        if lower % 2 == 0 { lower -= 1 }
        let upper = lower + 2
        let m = Int(((12 * sigma * sigma - Double(3 * lower * lower) - Double(12 * lower) - 9)
                     / Double(-4 * lower - 4) + 0.5).rounded(.down))
        for pass in 0..<3 {
            let r = ((pass < m ? lower : upper) - 1) / 2
            guard r > 0 else { continue }
            let span = Float(2 * r) + 1
            for y in 0..<h {
                let row = y * w
                var sum: Float = 0
                for j in -r...r { sum += v[row + min(w - 1, max(0, j))] }
                for x in 0..<w {
                    tmp[row + x] = sum / span
                    sum += v[row + min(w - 1, x + r + 1)] - v[row + max(0, x - r)]
                }
            }
            for x in 0..<w {
                var sum: Float = 0
                for j in -r...r { sum += tmp[min(h - 1, max(0, j)) * w + x] }
                for y in 0..<h {
                    v[y * w + x] = sum / span
                    sum += tmp[min(h - 1, y + r + 1) * w + x] - tmp[max(0, y - r) * w + x]
                }
            }
        }
    }

    // MARK: auto adjust

    /// Auto adjust's reading of a picture: how many of its pixels sit at
    /// each of 256 levels of lightness — Rec. 709 luma of the 0…255
    /// channels, rounded half up. `pixels` are 0xAARRGGBB, not
    /// premultiplied; clear ones are not counted. Both phones read it from
    /// the picture boiled down to 64 × 64 by `reduced` (see `histogram(of:)`).
    static func histogram(_ pixels: [Int]) -> [Int] {
        var counts = [Int](repeating: 0, count: 256)
        for c in pixels where (c >> 24) & 0xff != 0 {
            let luma = ColourMatrix.lr * Double((c >> 16) & 0xff) + ColourMatrix.lg * Double((c >> 8) & 0xff)
                + ColourMatrix.lb * Double(c & 0xff)
            counts[min(max(Int((luma + 0.5).rounded(.down)), 0), 255)] += 1
        }
        return counts
    }

    /// The side of the picture auto adjust reads.
    static let autoSide = 64

    /// `pixels` — 0xAARRGGBB, not premultiplied, `width` × `height`, top
    /// row first — boiled down to `side` × `side` for auto adjust to read:
    /// each cell the mean of the picture's pixels in it, its colour weighted
    /// by alpha so a clear pixel adds no black, every channel rounded half
    /// up; a cell with nothing but clear pixels is clear. Cell column i
    /// holds the columns from i × width / side up to (i + 1) × width / side,
    /// in whole numbers and at least one, counted from the top left; rows
    /// alike. Both phones boil the picture down so, rather than leaving it
    /// to their scalers, which keep a speck of highlight or lose it as they
    /// please.
    static func reduced(_ pixels: [Int], width: Int, height: Int, side: Int = PhotoLook.autoSide) -> [Int] {
        var out = [Int](repeating: 0, count: side * side)
        guard width > 0, height > 0, side > 0, pixels.count >= width * height else { return out }
        func mean(_ sum: Int, _ of: Int) -> Int { min(max((2 * sum + of) / (2 * of), 0), 255) }
        for row in 0..<side {
            let top = row * height / side
            let bottom = max((row + 1) * height / side, top + 1)
            for col in 0..<side {
                let left = col * width / side
                let right = max((col + 1) * width / side, left + 1)
                var alpha = 0, r = 0, g = 0, b = 0
                for y in top..<bottom {
                    for x in left..<right {
                        let c = pixels[y * width + x]
                        let a = (c >> 24) & 0xff
                        alpha += a
                        r += ((c >> 16) & 0xff) * a
                        g += ((c >> 8) & 0xff) * a
                        b += (c & 0xff) * a
                    }
                }
                guard alpha > 0 else { continue }
                let n = (bottom - top) * (right - left)
                out[row * side + col] = (mean(alpha, n) << 24) | (mean(r, alpha) << 16) | (mean(g, alpha) << 8) | mean(b, alpha)
            }
        }
        return out
    }

    /// `image` upright at its own pixels, boiled down by `reduced` and read
    /// as a `histogram`; nil when it cannot be drawn.
    static func histogram(of image: UIImage) -> [Int]? {
        let width = Int((image.size.width * image.scale).rounded())
        let height = Int((image.size.height * image.scale).rounded())
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Drawn by UIKit, top down, so a photo that carries a turn is
            // read the way it shows — cell for cell as the Android twin
            // reads it.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            UIGraphicsPopContext()
            return true
        }
        guard drawn else { return nil }
        // Undone from premultiplied, so a half-clear pixel reads at the
        // colour it is, as the Android twin's pixels are.
        let pixels = (0..<(width * height)).map { i in (Int(bytes[i * 4 + 3]) << 24) | unpremultiplied(bytes, at: i) }
        return histogram(reduced(pixels, width: width, height: height))
    }

    /// The three dials auto adjust sets.
    struct Auto: Equatable {
        var brightness: Double
        var whites: Double
        var blacks: Double
    }

    /// Auto adjust, from a `histogram`: the darkest level is where the
    /// running count first reaches 0.5% of the pixels, the lightest where it
    /// reaches 99.5%, the middle where it reaches 50%.
    ///
    /// - blacks = −(darkest / 255) / 0.15, to −1 at most: the curve's start
    ///   moved to the darkest level, crushing what is under it to black;
    /// - whites = (1 − lightest / 255) / 0.15, to 1 at most: the curve
    ///   reaching white at the lightest level;
    /// - brightness = 0.5 − the middle's place between the two (0.5 when
    ///   they are the same level), within −1…1.
    ///
    /// Each is rounded to the hundredth, half away from zero — a slider's
    /// step. An empty histogram changes nothing.
    static func autoAdjust(_ histogram: [Int]) -> Auto {
        let total = histogram.reduce(0, +)
        guard total > 0 else { return Auto(brightness: 0, whites: 0, blacks: 0) }
        func level(_ share: Double) -> Int {
            var running = 0
            for (i, n) in histogram.enumerated() {
                running += n
                if Double(running) >= share * Double(total) { return i }
            }
            return histogram.count - 1
        }
        let lo = Double(level(0.005)) / 255
        let hi = Double(level(0.995)) / 255
        let mid = Double(level(0.5)) / 255
        let blacks = -min(lo / ToneCurve.lightReach, 1)
        let whites = min((1 - hi) / ToneCurve.lightReach, 1)
        let placed = hi > lo ? (mid - lo) / (hi - lo) : 0.5
        let brightness = min(max(0.5 - placed, -1), 1)
        return Auto(brightness: hundredth(brightness), whites: hundredth(whites), blacks: hundredth(blacks))
    }

    /// `a` with auto adjust's three dials set from `histogram`, the rest kept.
    static func autoAdjusted(_ a: Adjustments?, histogram: [Int]) -> Adjustments {
        let auto = autoAdjust(histogram)
        var out = a ?? .neutral
        out.brightness = auto.brightness
        out.whites = auto.whites
        out.blacks = auto.blacks
        return out
    }

    /// To the hundredth, half away from zero, and never minus zero.
    private static func hundredth(_ v: Double) -> Double {
        let r = (abs(v) * 100 + 0.5).rounded(.down) / 100
        return r == 0 ? 0 : (v < 0 ? -r : r)
    }
}

enum ImageFilterEngine {
    private static let context = CIContext()
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 48
        return c
    }()

    static func apply(_ preset: ImageFilterPreset, to image: UIImage, cacheKey: String) -> UIImage {
        apply(preset, adjustments: .neutral, to: image, cacheKey: cacheKey)
    }

    static func apply(_ preset: ImageFilterPreset, adjustments: Adjustments,
                      to image: UIImage, cacheKey: String) -> UIImage {
        apply(preset, adjustments: adjustments, duotone: nil, to: image, cacheKey: cacheKey)
    }

    /// The whole look of the photo `el` on `image`, its picture: the filter
    /// at its strength, the dials, the effects drawn into the picture
    /// (pixelate and focus) and the duotone. The edge is drawn behind the
    /// frame, not here (see `PhotoEffects.edge`). `waits` for the subject a
    /// focus keeps sharp to be found, as a file must; on screen it does not
    /// (see `apply(_:adjustments:duotone:strength:effects:waits:to:cacheKey:)`).
    static func apply(look el: Element, to image: UIImage, cacheKey: String, waits: Bool = true) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        return apply(ImageFilterPreset.from(el.filter), adjustments: el.adjustments ?? .neutral,
                     duotone: el.duotone, strength: PhotoLook.strength(el.filterStrength),
                     effects: PhotoEffects.plan(el, picture: pixels), waits: waits, to: image, cacheKey: cacheKey)
    }

    /// The look on `image`, in the Android twin's order: the filter at its
    /// strength, the dials, clarity and sharpness, focus, pixelate, the
    /// vignette, the duotone. A focus that keeps its subject sharp finds the
    /// subject first; unless the call `waits`, that is done off the main
    /// thread, the circle drawn meanwhile and not kept, and `subjectsFound`
    /// moves on when it is ready, so the photo is drawn again with it.
    static func apply(_ preset: ImageFilterPreset, adjustments: Adjustments,
                      duotone: Duotone?, strength: Double = 1, effects: PhotoEffects.Plan = .none,
                      waits: Bool = true, to image: UIImage, cacheKey: String) -> UIImage {
        if preset == .none && adjustments.isNeutral && duotone == nil && effects.isNone { return image }
        let share = min(max(strength, 0), 1)
        let partly = preset != .none && share < 1
        let tone = duotone.map { "|duo\($0.dark)\($0.light)" } ?? ""
        let mix = partly ? "@\(Int((share * 100).rounded()))" : ""
        let key = "\(cacheKey)|\(preset.rawValue)\(mix)\(adjustments.signature)\(tone)\(effects.signature)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let input = CIImage(image: image) else { return image }
        let extent = input.extent
        // Preset first, adjustments second: the preset is the look, the dials
        // are the correction on top of it. The other order would have a dial
        // silently undone by whichever preset was picked afterwards.
        var output = filtered(input, preset: preset)
        // Less than all of the filter: the filtered picture dissolved into
        // the plain one, on the encoded values, as the Android twin moves
        // its matrix towards the identity.
        if partly { output = dissolved(input, into: output, share) }
        output = adjusted(output, adjustments, extent: extent)
        // Focus on the corrected picture, before the blocks, as the Android
        // twin bakes them.
        var stopgap = false
        if let focus = effects.focus {
            var subject: CIImage?
            if focus.subject {
                switch subjectMask(of: image, key: cacheKey, extent: extent, waits: waits) {
                case .found(let mask): subject = mask
                case .finding: stopgap = true
                }
            }
            output = PhotoEffects.focused(output, focus: focus, subject: subject, extent: extent)
        }
        // Pixelate on the drawn pixels, block by block from the top left as
        // the Android twin counts them.
        if effects.block > 1 {
            output = throughPixels(output, extent: extent) { bytes, width, height in
                PhotoEffects.pixelate(&bytes, width: width, height: height, block: effects.block)
            }
        }
        // The vignette over the blur and the blocks, a smooth fade as the
        // Android twin lays it over the drawn picture.
        output = vignetted(output, adjustments, extent: extent)
        // Duotone last, because it replaces colour outright — running it
        // before a saturation dial would leave that dial with nothing to do.
        if let duotone { output = mapped(output, to: duotone) }
        guard let cg = context.createCGImage(output, from: extent) else { return image }
        let result = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        if !stopgap { cache.setObject(result, forKey: key as NSString) }
        return result
    }

    /// `image` drawn into a bitmap by the engine's context.
    static func cgImage(_ image: CIImage, from rect: CGRect) -> CGImage? {
        context.createCGImage(image, from: rect)
    }

    /// `image` drawn, `work` done to its pixels (see
    /// `PhotoEffects.withPixels`) and taken up again where it was: the steps
    /// the shared maths does a pixel at a time, on the values as a picture
    /// stores them.
    private static func throughPixels(_ image: CIImage, extent: CGRect,
                                      _ work: (inout [UInt8], Int, Int) -> Void) -> CIImage {
        guard let cg = context.createCGImage(image, from: extent),
              let done = PhotoEffects.withPixels(cg, work) else { return image }
        return CIImage(cgImage: done).transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    // MARK: the subject focus keeps sharp

    /// The subject of each picture focus keeps sharp, by picture: finding it
    /// takes the better part of a second, and a focus dial moved under the
    /// thumb must not find it again. A picture with no subject keeps an
    /// empty image here, so it is not looked for again either. Kept at most
    /// `subjectSide` across, so a page of them stays kept.
    private static let subjects: NSCache<NSString, CIImage> = {
        let c = NSCache<NSString, CIImage>()
        c.countLimit = 32
        return c
    }()

    /// The longest side a found subject is kept at.
    private static let subjectSide: CGFloat = 1024

    /// What focus keeps sharp of a picture: its subject as a mask, nil when
    /// it has none (focus keeps its circle then) — or `finding`, while it is
    /// looked for off the main thread.
    private enum Subject {
        case found(CIImage?)
        case finding
    }

    /// Moves on each time a subject is found off the main thread, so the
    /// photos showing focus on screen — which read it — draw again with it.
    @Observable
    final class Subjects {
        fileprivate(set) var version = 0
    }

    static let subjectsFound = Subjects()

    /// The pictures whose subject is being looked for, by the key it is
    /// kept under; guarded by `findingLock`, never held while one is found.
    private static var finding = Set<String>()
    private static let findingLock = NSLock()
    private static let finder = DispatchQueue(label: "canvia.photo-subjects", qos: .userInitiated)

    /// The subject of `image` as a mask the size of `extent`: kept, found
    /// there and then when the call `waits`, or else looked for on a worker
    /// — once, however often it is asked for meanwhile — and `finding`.
    private static func subjectMask(of image: UIImage, key: String, extent: CGRect, waits: Bool) -> Subject {
        let id = "\(key)|\(Int(extent.width))x\(Int(extent.height))"
        if let known = subjects.object(forKey: id as NSString) { return .found(fitted(known, to: extent)) }
        guard !waits else {
            let found = findSubject(of: image)
            subjects.setObject(found, forKey: id as NSString)
            return .found(fitted(found, to: extent))
        }
        findingLock.lock()
        let start = finding.insert(id).inserted
        findingLock.unlock()
        if start {
            finder.async {
                let found = ImageFilterEngine.findSubject(of: image)
                ImageFilterEngine.subjects.setObject(found, forKey: id as NSString)
                ImageFilterEngine.findingLock.lock()
                ImageFilterEngine.finding.remove(id)
                ImageFilterEngine.findingLock.unlock()
                DispatchQueue.main.async { ImageFilterEngine.subjectsFound.version &+= 1 }
            }
        }
        return .finding
    }

    /// A kept subject stretched over `extent`; nil for a picture with none.
    private static func fitted(_ mask: CIImage, to extent: CGRect) -> CIImage? {
        guard !mask.extent.isEmpty, mask.extent.width > 0, mask.extent.height > 0 else { return nil }
        return mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                      y: extent.height / mask.extent.height))
    }

    /// `image`'s subject as Cut out finds it — its cut-out, clear round it —
    /// at most `subjectSide` across; an empty image when it has none.
    private static func findSubject(of image: UIImage) -> CIImage {
        guard let cut = (try? SubjectMask.cutout(image))?.cgImage else { return CIImage.empty() }
        let found = CIImage(cgImage: cut)
        let shrink = min(1, subjectSide / max(found.extent.width, found.extent.height, 1))
        guard shrink < 1 else { return found }
        let small = found.transformed(by: CGAffineTransform(scaleX: shrink, y: shrink))
        guard let kept = context.createCGImage(small, from: small.extent.integral) else { return found }
        return CIImage(cgImage: kept)
    }

    /// `image` turned into `target` by `share`, on sRGB's encoded values —
    /// the numbers the shared maths works on.
    private static func dissolved(_ image: CIImage, into target: CIImage, _ share: Double) -> CIImage {
        let f = CIFilter.dissolveTransition()
        f.inputImage = encoded(image)
        f.targetImage = encoded(target)
        f.time = Float(share)
        return f.outputImage.map(decoded) ?? target
    }

    /// Core Image works on linear light; the shared maths, like the Android
    /// twin's paint, on the values as a picture stores them. These go there
    /// and back round each of the new dials, so they draw what the shared
    /// test table says.
    private static func encoded(_ image: CIImage) -> CIImage { image.applyingFilter("CILinearToSRGBToneCurve") }
    private static func decoded(_ image: CIImage) -> CIImage { image.applyingFilter("CISRGBToneCurveToLinear") }

    /// One shared colour matrix on the encoded values.
    private static func matrixed(_ image: CIImage, _ matrix: ColourMatrix) -> CIImage {
        let m = matrix.m
        let f = CIFilter.colorMatrix()
        f.inputImage = encoded(image)
        f.rVector = CIVector(x: m[0], y: m[1], z: m[2], w: m[3])
        f.gVector = CIVector(x: m[5], y: m[6], z: m[7], w: m[8])
        f.bVector = CIVector(x: m[10], y: m[11], z: m[12], w: m[13])
        f.aVector = CIVector(x: m[15], y: m[16], z: m[17], w: m[18])
        f.biasVector = CIVector(x: m[4], y: m[9], z: m[14], w: m[19])
        return f.outputImage.map(decoded) ?? image
    }

    /// Vibrance, then the preset curve, then the light dials' curve, as one
    /// colour cube made from the shared maths (`PhotoLook.vibrant`,
    /// `ToneCurve.at`), on the encoded values.
    private static func cubed(_ image: CIImage, vibrance: Double, curve: String?, light: [CGPoint]?) -> CIImage {
        let preset = ToneCurve.preset(curve)
        // The two curves one after the other, read finely enough that a
        // straight line between readings is the curve.
        let steps = 1024
        let tone: [Double] = (0...steps).map { i in
            var v = Double(i) / Double(steps)
            if let preset { v = ToneCurve.at(preset.points, v) }
            if let light { v = ToneCurve.at(light, v) }
            return v
        }
        func toned(_ v: Double) -> Double {
            let x = min(max(v, 0), 1) * Double(steps)
            let i = min(Int(x), steps - 1)
            return tone[i] + (tone[i + 1] - tone[i]) * (x - Double(i))
        }
        let size = 48
        var data = [Float](repeating: 1, count: size * size * size * 4)
        for b in 0..<size {
            for g in 0..<size {
                for r in 0..<size {
                    var rf = Double(r) / Double(size - 1)
                    var gf = Double(g) / Double(size - 1)
                    var bf = Double(b) / Double(size - 1)
                    if vibrance != 0 {
                        let luma = ColourMatrix.lr * rf + ColourMatrix.lg * gf + ColourMatrix.lb * bf
                        let k = 1 + vibrance * (1 - (max(rf, gf, bf) - min(rf, gf, bf)))
                        rf = luma + (rf - luma) * k
                        gf = luma + (gf - luma) * k
                        bf = luma + (bf - luma) * k
                    }
                    let i = ((b * size + g) * size + r) * 4
                    data[i] = Float(toned(rf))
                    data[i + 1] = Float(toned(gf))
                    data[i + 2] = Float(toned(bf))
                }
            }
        }
        let f = CIFilter.colorCube()
        f.inputImage = encoded(image)
        f.cubeDimension = Float(size)
        f.cubeData = data.withUnsafeBufferPointer { Data(buffer: $0) }
        return f.outputImage.map(decoded) ?? image
    }

    /// Luminance mapped onto two colours: darkest becomes `dark`, lightest
    /// becomes `light`, and everything between is a straight ramp.
    ///
    /// Desaturated first. CIFalseColor reads luminance, so a picture with
    /// strong colour in it would otherwise map its reds and its greens to
    /// different points of the ramp for reasons that have nothing to do with
    /// how light they are.
    private static func mapped(_ input: CIImage, to duotone: Duotone) -> CIImage {
        let mono = CIFilter.colorControls()
        mono.inputImage = input
        mono.saturation = 0
        guard let grey = mono.outputImage else { return input }
        let map = CIFilter.falseColor()
        map.inputImage = grey
        map.color0 = CIColor(color: UIColor(hex: duotone.dark))
        map.color1 = CIColor(color: UIColor(hex: duotone.light))
        return map.outputImage ?? input
    }

    /// The dials, in the order a photographer would reach for them; the
    /// vignette waits for the effects (`vignetted`).
    private static func adjusted(_ input: CIImage, _ a: Adjustments,
                                 extent: CGRect) -> CIImage {
        guard !a.isNeutral else { return input }
        var image = input

        if a.warmth != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            // The filter re-balances a picture lit at `neutral` as if it had
            // been lit at `targetNeutral`, so a *higher* target temperature
            // makes the picture bluer — the light it is correcting for was
            // warm. Warmer therefore means a lower target. This is the
            // direction the test pins, because the other way round looks
            // entirely plausible.
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - a.warmth * 2500, y: 0)
            image = f.outputImage ?? image
        }

        if min(max(a.tint, -1), 1) != 0 { image = matrixed(image, PhotoLook.tint(a.tint)) }

        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            // Core Image's ranges: brightness is an offset around 0, contrast
            // and saturation are multipliers around 1.
            f.brightness = Float(a.brightness * 0.35)
            f.contrast = Float(1 + a.contrast * 0.6)
            f.saturation = Float(max(0, 1 + a.saturation))
            image = f.outputImage ?? image
        }

        if min(max(a.fade, 0), 1) > 0 { image = matrixed(image, PhotoLook.fade(a.fade)) }

        // The curve after the dials, on the already balanced picture; with
        // vibrance or the light dials, all three in one cube of the shared
        // maths, in the Android twin's order.
        let vibrance = min(max(a.vibrance, -1), 1)
        let light = ToneCurve.light(highlights: a.highlights, shadows: a.shadows,
                                    whites: a.whites, blacks: a.blacks)
        if vibrance != 0 || light != nil {
            image = cubed(image, vibrance: vibrance, curve: a.curve, light: light)
        } else {
            image = ToneCurve.apply(a.curve, to: image)
        }

        // Clarity: the detail in lightness, about 2% of the picture's shorter
        // side, added back (or taken away) by the dial — the shared maths on
        // the picture's own pixels (`PhotoLook.clarify`), so it draws what
        // the Android twin draws, softening too.
        let clarity = min(max(a.clarity, -1), 1)
        if clarity != 0 {
            image = throughPixels(image, extent: extent) { bytes, width, height in
                PhotoLook.clarify(&bytes, width: width, height: height, amount: clarity)
            }
        }

        if a.sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(a.sharpness * 1.5)
            image = (f.outputImage ?? image).cropped(to: extent)
        } else if a.sharpness < 0 {
            let f = CIFilter.gaussianBlur()
            f.inputImage = image.clampedToExtent()
            f.radius = Float(-a.sharpness * 12)
            image = (f.outputImage ?? image).cropped(to: extent)
        }
        return image
    }

    /// The vignette dial, after the effects (see `apply`) and before the
    /// duotone, so a duotoned photo's corners fall into its dark colour.
    private static func vignetted(_ input: CIImage, _ a: Adjustments, extent: CGRect) -> CIImage {
        guard a.vignette > 0 else { return input }
        let f = CIFilter.vignette()
        f.inputImage = input
        f.intensity = Float(a.vignette * 2)
        f.radius = Float(1.4)
        return (f.outputImage ?? input).cropped(to: extent)
    }

    private static func filtered(_ input: CIImage, preset: ImageFilterPreset) -> CIImage {
        func controls(_ image: CIImage, saturation: Double = 1, brightness: Double = 0, contrast: Double = 1) -> CIImage {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.saturation = Float(saturation)
            f.brightness = Float(brightness)
            f.contrast = Float(contrast)
            return f.outputImage ?? image
        }
        func sepia(_ image: CIImage, _ intensity: Double) -> CIImage {
            let f = CIFilter.sepiaTone()
            f.inputImage = image
            f.intensity = Float(intensity)
            return f.outputImage ?? image
        }
        func hue(_ image: CIImage, degrees: Double) -> CIImage {
            let f = CIFilter.hueAdjust()
            f.inputImage = image
            f.angle = Float(degrees * .pi / 180)
            return f.outputImage ?? image
        }
        func blur(_ image: CIImage, _ radius: Double) -> CIImage {
            let f = CIFilter.gaussianBlur()
            f.inputImage = image
            f.radius = Float(radius)
            return (f.outputImage ?? image).cropped(to: image.extent)
        }

        switch preset {
        case .none: return input
        case .vivid: return controls(input, saturation: 1.6, brightness: 0.02, contrast: 1.12)
        case .warm: return controls(sepia(input, 0.35), saturation: 1.25, brightness: 0.02)
        case .cool: return controls(hue(input, degrees: -18), saturation: 1.15, brightness: 0.01)
        case .mono: return controls(input, saturation: 0, contrast: 1.08)
        case .noir: return controls(input, saturation: 0, brightness: -0.04, contrast: 1.4)
        case .fade: return controls(input, saturation: 0.65, brightness: 0.08, contrast: 0.88)
        case .retro: return controls(sepia(input, 0.5), saturation: 1.15, contrast: 0.95)
        case .dramatic: return controls(input, saturation: 1.1, brightness: -0.03, contrast: 1.35)
        case .dreamy: return controls(blur(input, 1.6), saturation: 1.15, brightness: 0.04)
        }
    }
}
