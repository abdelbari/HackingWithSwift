// A page's colours as a print shop's press lays down ink — the print-ready
// PDF's "Colour profile: CMYK", as Canva offers it for professional
// printing. One formula on both phones, with one test table (the Android
// twin's core/content/Cmyk.kt):
//
// - pure black (#000000), as text is, is black ink alone: 0/0/0/100;
// - otherwise K = 1 − max(R, G, B), held to at most maxK (95%) — grey
//   replaced by black ink in full, short of the darkest shadows — and
//   C = (1 − R − K) / (1 − K), M and Y the same from G and B;
// - and no more than inkLimit (300%) of ink in all: past it, C, M and Y are
//   scaled down together, K kept.
//
// What is clear on the page is the paper, white, so it takes no ink.

import Foundation

enum Cmyk {

    /// The most black ink any colour but pure black takes.
    static let maxK = 0.95

    /// The most ink, all four together, as a share: 300%.
    static let inkLimit = 3.0

    /// Above this ΔE a colour is one that prints noticeably duller
    /// (outOfGamut).
    static let gamutDeltaE = 35.0

    /// Said under the colour profile when the design has any.
    static let dullerWarning = tr("Bright colours will print duller")

    /// C, M, Y and K, each 0 to 1.
    struct PressInk: Equatable {
        var c: Double
        var m: Double
        var y: Double
        var k: Double

        /// All four as bytes, 0 to 255, as a DeviceCMYK image holds them.
        var bytes: [UInt8] { [c, m, y, k].map(Self.byte) }

        private static func byte(_ v: Double) -> UInt8 {
            UInt8(min(max((v * 255).rounded(), 0), 255))
        }
    }

    /// Red, green and blue, each 0 to 255, as ink.
    static func fromRGB(_ r: Int, _ g: Int, _ b: Int) -> PressInk {
        if r == 0 && g == 0 && b == 0 { return PressInk(c: 0, m: 0, y: 0, k: 1) }
        let red = Double(r) / 255, green = Double(g) / 255, blue = Double(b) / 255
        let k = min(1 - max(red, green, blue), maxK)
        func share(_ v: Double) -> Double { min(max((1 - v - k) / (1 - k), 0), 1) }
        var c = share(red), m = share(green), y = share(blue)
        let colour = c + m + y
        if colour + k > inkLimit && colour > 0 {
            let scale = (inkLimit - k) / colour
            c *= scale
            m *= scale
            y *= scale
        }
        return PressInk(c: c, m: m, y: y, k: k)
    }

    /// A colour written "#rgb", "#rrggbb" or "#rrggbbaa" (its alpha left
    /// aside) as red, green and blue 0 to 255; nil when it does not read —
    /// the Android twin's Palettes.parseHex.
    static func rgb(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 3: digits = digits.map { "\($0)\($0)" }.joined()
        case 6: break
        case 8: digits = String(digits.prefix(6))
        default: return nil
        }
        guard let value = Int(digits, radix: 16) else { return nil }
        return (value >> 16 & 0xff, value >> 8 & 0xff, value & 0xff)
    }

    /// A colour written "#rrggbb" as ink, or nil when it does not read.
    static func fromHex(_ hex: String) -> PressInk? {
        rgb(hex).map { fromRGB($0.r, $0.g, $0.b) }
    }

    /// `count` pixels of `argb` (0xAARRGGBB, from `from`) as DeviceCMYK bytes
    /// into `out` at `at`, four a pixel — each laid on white paper first, by
    /// its alpha. A run of one colour is worked out once.
    static func convert(_ argb: [UInt32], from: Int, count: Int, into out: inout [UInt8], at: Int) {
        var last: UInt32 = 0
        var lastInk: [UInt8] = [0, 0, 0, 0]
        var known = false
        var o = at
        for i in from..<(from + count) {
            let px = argb[i]
            if !known || px != last {
                let a = Int(px >> 24 & 0xff)
                // Over white: what is clear is paper.
                func over(_ v: Int) -> Int { (v * a + 255 * (255 - a) + 127) / 255 }
                lastInk = fromRGB(over(Int(px >> 16 & 0xff)), over(Int(px >> 8 & 0xff)), over(Int(px & 0xff))).bytes
                last = px
                known = true
            }
            out[o] = lastInk[0]
            out[o + 1] = lastInk[1]
            out[o + 2] = lastInk[2]
            out[o + 3] = lastInk[3]
            o += 4
        }
    }

    // MARK: what prints duller

    /// The process inks as a screen shows them, red, green and blue 0 to 1:
    /// cyan #00AEEF, magenta #EC008C and yellow #FFF200.
    private static let cyan: [Double] = [0, 0xAE / 255.0, 0xEF / 255.0]
    private static let magenta: [Double] = [0xEC / 255.0, 0, 0x8C / 255.0]
    private static let yellow: [Double] = [1, 0xF2 / 255.0, 0]

    /// `ink` as it comes off the press, roughly, red, green and blue 0 to
    /// 1: each ink filters the paper by its share of its own colour, the
    /// three multiplied, and black darkens the whole by its share.
    static func printed(_ ink: PressInk) -> [Double] {
        (0..<3).map { (ch: Int) -> Double in
            let c: Double = 1 - ink.c * (1 - cyan[ch])
            let m: Double = 1 - ink.m * (1 - magenta[ch])
            let y: Double = 1 - ink.y * (1 - yellow[ch])
            return (1 - ink.k) * c * m * y
        }
    }

    /// How far `hex` moves on the way to paper: the CIE76 ΔE between it and
    /// printed of its ink, in CIELAB under D65. Nil when it does not read.
    static func deltaE(_ hex: String) -> Double? {
        guard let rgb = rgb(hex) else { return nil }
        let screen = lab([Double(rgb.r) / 255, Double(rgb.g) / 255, Double(rgb.b) / 255])
        let paper = lab(printed(fromRGB(rgb.r, rgb.g, rgb.b)))
        return (0..<3).reduce(0.0) { $0 + pow(screen[$1] - paper[$1], 2) }.squareRoot()
    }

    /// Whether `hex` is a neon or very saturated colour no press reaches: a
    /// ΔE above gamutDeltaE.
    static func outOfGamut(_ hex: String) -> Bool { (deltaE(hex) ?? 0) > gamutDeltaE }

    /// The colours of `design` that will print duller, in the order the
    /// design's colours are listed (ColorTools.documentColors).
    static func dullerColours(_ design: Design) -> [String] {
        ColorTools.documentColors(design, limit: Int.max).filter { rgb($0) != nil && outOfGamut($0) }
    }

    private static func lab(_ rgb: [Double]) -> [Double] {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(rgb[0]), g = linear(rgb[1]), b = linear(rgb[2])
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)]
    }
}
