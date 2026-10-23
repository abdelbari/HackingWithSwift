// Selective colour: one band of a photo's hues shifted on its own — a red
// dress made orange, a grey sky made blue — and the rest left as it is.
// Eight bands, each a colour's name, each with its own hue, saturation and
// lightness shift; a pixel belongs to the band its hue is nearest, and
// partly to the one beside it, so a shift fades out across the hues
// between two centres rather than cutting off at a line. The Android
// twin's HueBands, number for number, with one shared test table
// (SelectiveColourTests): each phone draws it through its own engine —
// here a colour cube built from `shifted`, there a pass over the pixels.

import Foundation

/// One band's shift: its hue turned by `h` × 30°, its saturation scaled
/// by `s` and its lightness moved by `l`, each −1…1. Written as the band's
/// object in `Adjustments.hsl`, all three keys always; a value missing or
/// not a number reads as 0, and one outside −1…1 is held to it.
struct HueShift: Codable, Equatable, Hashable {
    var h: Double = 0
    var s: Double = 0
    var l: Double = 0

    static let neutral = HueShift()
    var isNeutral: Bool { h == 0 && s == 0 && l == 0 }

    private enum CodingKeys: String, CodingKey { case h, s, l }

    init(h: Double = 0, s: Double = 0, l: Double = 0) {
        self.h = Self.held(h)
        self.s = Self.held(s)
        self.l = Self.held(l)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        h = Self.held((try? c.decodeIfPresent(Double.self, forKey: .h)) ?? 0)
        s = Self.held((try? c.decodeIfPresent(Double.self, forKey: .s)) ?? 0)
        l = Self.held((try? c.decodeIfPresent(Double.self, forKey: .l)) ?? 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(h, forKey: .h)
        try c.encode(s, forKey: .s)
        try c.encode(l, forKey: .l)
    }

    /// A shift held to −1…1; one that is no number is none.
    private static func held(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(max(v, -1), 1)
    }
}

enum HueBands {

    /// A band: its key in the file and the hue at its centre, in degrees.
    struct Band: Equatable {
        var key: String
        var centre: Double
        var name: String {
            switch key {
            case "red": return tr("Red")
            case "orange": return tr("Orange")
            case "yellow": return tr("Yellow")
            case "green": return tr("Green")
            case "aqua": return tr("Aqua")
            case "blue": return tr("Blue")
            case "purple": return tr("Purple")
            case "magenta": return tr("Magenta")
            default: return key
            }
        }
    }

    /// The eight bands round the hue circle, in its order.
    static let bands: [Band] = [
        Band(key: "red", centre: 0), Band(key: "orange", centre: 30), Band(key: "yellow", centre: 60),
        Band(key: "green", centre: 120), Band(key: "aqua", centre: 180), Band(key: "blue", centre: 240),
        Band(key: "purple", centre: 270), Band(key: "magenta", centre: 300),
    ]

    static let keys: [String] = bands.map(\.key)

    /// Degrees a hue shift of 1 turns a band's hues.
    static let turn = 30.0

    /// Below this saturation a colour is a grey, which no band claims for
    /// the chips' sake (`band(of:)`); the shift itself scales by saturation
    /// (`shifted`), so a grey stays put either way.
    static let greyBelow = 0.1

    /// How far the shift at 1 moves a band's lightness, 0…1.
    static let lightReach = 0.25

    /// `hsl` without its neutral bands, as it is kept and written; a band
    /// this build does not name is kept as it was read, and does nothing.
    static func kept(_ hsl: [String: HueShift]) -> [String: HueShift] {
        hsl.filter { !$0.value.isNeutral }
    }

    /// The band `key` is at, nil for one this build does not name.
    static func index(of key: String) -> Int? {
        bands.firstIndex { $0.key == key }
    }

    /// How much band `index` claims a hue `degrees`: all of it at the
    /// band's centre, falling away by a cosine to nothing at the next
    /// centre on either side — so the two bands either side of a hue claim
    /// it in shares that add up to one.
    static func weight(_ degrees: Double, band index: Int) -> Double {
        let n = bands.count
        let centre = bands[index].centre
        var d = (degrees - centre).truncatingRemainder(dividingBy: 360)
        if d < -180 { d += 360 }
        if d > 180 { d -= 360 }
        let next = round360(bands[(index + 1) % n].centre - centre)
        let prev = round360(centre - bands[(index + n - 1) % n].centre)
        let reach = d >= 0 ? next : prev
        let away = abs(d)
        guard away < reach else { return 0 }
        return 0.5 * (1 + cos(.pi * away / reach))
    }

    /// A difference of centres as a distance round the circle, in (0, 360].
    private static func round360(_ d: Double) -> Double {
        let r = d.truncatingRemainder(dividingBy: 360)
        return r <= 0 ? r + 360 : r
    }

    /// The band whose centre is nearest a hue, round the circle.
    static func band(ofHue degrees: Double) -> Int {
        var best = 0
        var nearest = Double.infinity
        for i in bands.indices {
            var d = abs((degrees - bands[i].centre).truncatingRemainder(dividingBy: 360))
            if d > 180 { d = 360 - d }
            if d < nearest { nearest = d; best = i }
        }
        return best
    }

    /// The band a colour 0xRRGGBB chiefly belongs to, by key; nil for a
    /// grey — one with less than `greyBelow` saturation — which no band
    /// claims.
    static func band(of rgb: Int) -> String? {
        let hsl = toHSL(Double((rgb >> 16) & 0xff) / 255, Double((rgb >> 8) & 0xff) / 255, Double(rgb & 0xff) / 255)
        guard hsl.s >= greyBelow else { return nil }
        return bands[band(ofHue: hsl.h)].key
    }

    /// The bands of `colours` ("#rrggbb"), most prominent first, each once
    /// and the greys left out: what the Adjust panel's chips lead with.
    static func present(in colours: [String]) -> [String] {
        var out: [String] = []
        for hex in colours {
            guard let c = ColorTools.rgb255(hex) else { continue }
            let rgb = (c.r << 16) | (c.g << 8) | c.b
            if let key = band(of: rgb), !out.contains(key) { out.append(key) }
        }
        return out
    }

    /// The chips' order: the bands present in the photo first, in their
    /// order, then the rest in the circle's.
    static func chipOrder(present: [String]) -> [String] {
        present.filter { keys.contains($0) } + keys.filter { !present.contains($0) }
    }

    /// One colour, unit channels, through the shifts in `hsl`: in HSL, each
    /// shifted band's weight for the hue, times the colour's own saturation
    /// so a grey stays put; the hue turned by the weighted sum of the hue
    /// shifts × `turn` degrees, the saturation scaled by one plus the
    /// weighted saturation shifts, the lightness moved by the weighted
    /// lightness shifts × `lightReach`, each held to 0…1; and back.
    static func shifted(r: Double, g: Double, b: Double, by hsl: [String: HueShift]) -> (r: Double, g: Double, b: Double) {
        bandShifted(r: r, g: g, b: b, shifts: shifts(hsl))
    }

    /// The shifts in `hsl` by band index, nil for a band left alone: worked
    /// out once for a whole colour cube rather than once a colour.
    static func shifts(_ hsl: [String: HueShift]) -> [HueShift?] {
        let live = kept(hsl)
        return bands.map { live[$0.key] }
    }

    /// `shifted`, with the shifts already by band index (`shifts`), so a
    /// cube of a quarter of a million colours makes nothing for each.
    static func bandShifted(r: Double, g: Double, b: Double, shifts: [HueShift?]) -> (r: Double, g: Double, b: Double) {
        let c = toHSL(r, g, b)
        guard c.s > 0 else { return (r, g, b) }
        var dh = 0.0, ds = 0.0, dl = 0.0
        for (i, shift) in shifts.enumerated() where i < bands.count {
            guard let shift else { continue }
            let w = weight(c.h, band: i) * c.s
            guard w > 0 else { continue }
            dh += w * shift.h
            ds += w * shift.s
            dl += w * shift.l
        }
        guard dh != 0 || ds != 0 || dl != 0 else { return (r, g, b) }
        // Scaled once the sums are made, as Android's HueBands.shifted
        // does, so both phones round the same table alike.
        var h = (c.h + dh * turn).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        let s = min(max(c.s * (1 + ds), 0), 1)
        let l = min(max(c.l + dl * lightReach, 0), 1)
        return toRGB(h, s, l)
    }

    /// One opaque colour, 0xRRGGBB, through `hsl`, each channel rounded
    /// half up as the Android twin rounds — the shared table's rows.
    static func pixel(_ rgb: Int, hsl: [String: HueShift]) -> Int {
        let out = shifted(r: Double((rgb >> 16) & 0xff) / 255, g: Double((rgb >> 8) & 0xff) / 255,
                          b: Double(rgb & 0xff) / 255, by: hsl)
        return (PhotoLook.byte(out.r * 255) << 16) | (PhotoLook.byte(out.g * 255) << 8) | PhotoLook.byte(out.b * 255)
    }

    // MARK: HSL

    /// Unit RGB as hue in degrees, 0 ≤ h < 360, saturation and lightness
    /// 0…1: a grey has hue 0 and no saturation.
    ///
    /// Worked as Android's HueBands.hsl works it, step for step, so the
    /// shared table of colours rounds alike on both phones.
    static func toHSL(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, l: Double) {
        let hi = max(r, g, b), lo = min(r, g, b)
        let l = (hi + lo) / 2
        let d = hi - lo
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        if hi == r {
            h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        } else if hi == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, min(max(s, 0), 1), l)
    }

    /// Hue in degrees, saturation and lightness as unit RGB.
    ///
    /// By chroma and sextant, as Android's HueBands.rgb works it: the
    /// textbook hue-to-channel formula lands a hair under a half where
    /// this one lands on it (blue turned to 210° is 0x0080ff on both
    /// phones, not 0x007fff).
    static func toRGB(_ h: Double, _ s: Double, _ l: Double) -> (r: Double, g: Double, b: Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hh = ((h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)) / 60
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let one: (Double, Double, Double)
        if hh < 1 { one = (c, x, 0) }
        else if hh < 2 { one = (x, c, 0) }
        else if hh < 3 { one = (0, c, x) }
        else if hh < 4 { one = (0, x, c) }
        else if hh < 5 { one = (x, 0, c) }
        else { one = (c, 0, x) }
        return (one.0 + m, one.1 + m, one.2 + m)
    }
}
