// Generated motion backgrounds and still textures: drifting gradient
// meshes, flowing waves, rising bokeh, falling confetti, turning rays,
// grain, pulsing dots, starfields and paper with a light going round, and
// marble, paper, linen, terrazzo, skies, halftone, bokeh and grain stills.
// Each is a recipe in Motion.json, written by tools/generate_motion.py — the
// very file the Android twin bundles — and drawn here pixel by pixel with
// the same seeded maths as that script's `frame`, which is the reference:
// the same frame at the same moment on both phones (MotionArtTests checks
// each against the script's hashes).
//
// A loop goes on a page as a picture whose source is "motion:<id>": it plays
// round and round like a looping clip in Play, Present and a video or GIF,
// stamped with the moment as a clip is ("motion:<id>@1.25", MotionLibrary
// .playing), and every still export draws its first frame. A still is
// "asset:<id>" among the drawn pictures (PhotoLibrary).

import UIKit

/// One recipe: its id, what Add calls it, its category, how it is drawn, its
/// colours, its seed, the seconds one loop takes (0 for a still) and words
/// to find it by.
struct MotionDef: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var kind: String
    var colours: [String]
    var seed: Int
    var period: Double
    var tags: [String] = []

    private enum CodingKeys: String, CodingKey { case id, name, category, kind, colours, seed, period, tags }

    init(id: String, name: String, category: String, kind: String, colours: [String], seed: Int,
         period: Double, tags: [String] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.kind = kind
        self.colours = colours
        self.seed = seed
        self.period = period
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = (try? c.decodeIfPresent(String.self, forKey: .category)) ?? ""
        kind = try c.decode(String.self, forKey: .kind)
        colours = try c.decode([String].self, forKey: .colours)
        seed = (try? c.decodeIfPresent(Int.self, forKey: .seed)) ?? 0
        period = (try? c.decodeIfPresent(Double.self, forKey: .period)) ?? 0
        tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }
}

enum MotionArt {

    /// A colour, each channel 0…1 and beyond while it is worked on.
    struct RGB: Equatable {
        var r: Double, g: Double, b: Double

        init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        /// "#rrggbb"; black for anything else.
        init(hex: String) {
            let digits = Array(hex.dropFirst())
            func channel(_ i: Int) -> Double {
                guard digits.count >= i + 2, let v = UInt8(String(digits[i..<(i + 2)]), radix: 16) else { return 0 }
                return Double(v) / 255
            }
            self.init(channel(0), channel(2), channel(4))
        }

        static let white = RGB(1, 1, 1)

        func mixed(_ to: RGB, _ f: Double) -> RGB {
            RGB(r + (to.r - r) * f, g + (to.g - g) * f, b + (to.b - b) * f)
        }

        func lightened(_ k: Double) -> RGB { RGB(r + k, g + k, b + k) }
    }

    static let tau = 2 * Double.pi

    // MARK: the shared maths

    static func hash01(_ i: Int, _ j: Int, _ s: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: i) &* 374761393 &+ UInt32(truncatingIfNeeded: j) &* 668265263
            &+ UInt32(truncatingIfNeeded: s) &* 2246822519
        h = (h ^ (h >> 13)) &* 1274126177
        h ^= h >> 16
        return Double(h) / 4294967296
    }

    static func smooth(_ f: Double) -> Double { f * f * (3 - 2 * f) }

    static func noise(_ x: Double, _ y: Double, _ s: Int) -> Double {
        let fx0 = x.rounded(.down), fy0 = y.rounded(.down)
        let ix = Int(fx0), iy = Int(fy0)
        let fx = x - fx0, fy = y - fy0
        let a = hash01(ix, iy, s), b = hash01(ix + 1, iy, s)
        let c = hash01(ix, iy + 1, s), d = hash01(ix + 1, iy + 1, s)
        let sx = smooth(fx), sy = smooth(fy)
        let top = a + (b - a) * sx
        let bottom = c + (d - c) * sx
        return top + (bottom - top) * sy
    }

    static func fbm(_ x: Double, _ y: Double, _ s: Int) -> Double {
        (noise(x, y, s) + noise(2 * x, 2 * y, s + 1) / 2 + noise(4 * x, 4 * y, s + 2) / 4) / 1.75
    }

    static func clamp01(_ v: Double) -> Double { v < 0 ? 0 : v > 1 ? 1 : v }

    /// `colours` spread evenly over 0…1, `f` kept within it.
    static func grad(_ colours: [RGB], _ f: Double) -> RGB {
        let f = clamp01(f)
        guard colours.count > 1 else { return colours.first ?? RGB(0, 0, 0) }
        let pos = f * Double(colours.count - 1)
        let i = min(Int(pos.rounded(.down)), colours.count - 2)
        return colours[i].mixed(colours[i + 1], pos - Double(i))
    }

    static func fract(_ v: Double) -> Double { v - v.rounded(.down) }

    static func floorInt(_ v: Double) -> Int { Int(v.rounded(.down)) }

    // MARK: a frame

    /// What one pixel is: of its centre (X, Y) in frame heights, its own
    /// (x, y), and its centre (u, v) as shares of the frame.
    typealias Painter = (_ X: Double, _ Y: Double, _ x: Int, _ y: Int, _ u: Double, _ v: Double) -> RGB

    /// A shape laid over the base, kept within its reach: drawn only on the
    /// pixels within `reach` of `centre`, in frame heights, where `paint`
    /// gives it a colour.
    struct Overlay {
        var cx: Double, cy: Double, reach: Double
        var paint: (_ X: Double, _ Y: Double, _ under: RGB) -> RGB?
    }

    /// The loop's place, 0…1, at `t` seconds: 0 for a still.
    static func phase(_ def: MotionDef, t: Double) -> Double {
        guard def.period > 0 else { return 0 }
        let turns = t / def.period
        return turns - turns.rounded(.down)
    }

    /// `def`'s frame at `t` seconds, `width` × `height`, as red, green and
    /// blue bytes row by row.
    static func frame(_ def: MotionDef, t: Double, width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        let p = phase(def, t: t)
        let ang = tau * p
        let A = Double(width) / Double(height)
        var colours = def.colours.map { RGB(hex: $0) }
        if colours.isEmpty { colours = [RGB(0, 0, 0)] }
        var rng = SeededRandom(seed: Double(def.seed))
        let (base, overlays) = painter(def.kind, colours, &rng, A: A, p: p, ang: ang, seed: def.seed)
        var pixels = [RGB](repeating: RGB(0, 0, 0), count: width * height)
        for y in 0..<height {
            let v = (Double(y) + 0.5) / Double(height)
            for x in 0..<width {
                let u = (Double(x) + 0.5) / Double(width)
                pixels[y * width + x] = base(u * A, v, x, y, u, v)
            }
        }
        // Each shape in turn over the pixels it can reach, as the script
        // lays them over every pixel.
        let h = Double(height)
        for shape in overlays {
            let x0 = max(0, floorInt((shape.cx - shape.reach) * h - 0.5) - 1)
            let x1 = min(width - 1, floorInt((shape.cx + shape.reach) * h - 0.5) + 1)
            let y0 = max(0, floorInt((shape.cy - shape.reach) * h - 0.5) - 1)
            let y1 = min(height - 1, floorInt((shape.cy + shape.reach) * h - 0.5) + 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 {
                let v = (Double(y) + 0.5) / Double(height)
                for x in x0...x1 {
                    let u = (Double(x) + 0.5) / Double(width)
                    if let next = shape.paint(u * A, v, pixels[y * width + x]) { pixels[y * width + x] = next }
                }
            }
        }
        var out = [UInt8](repeating: 0, count: width * height * 3)
        for (i, px) in pixels.enumerated() {
            out[i * 3] = byte(px.r)
            out[i * 3 + 1] = byte(px.g)
            out[i * 3 + 2] = byte(px.b)
        }
        return out
    }

    static func byte(_ v: Double) -> UInt8 {
        let n = (v * 255 + 0.5).rounded(.down)
        return n <= 0 ? 0 : n >= 255 ? 255 : UInt8(n)
    }

    /// FNV-1a 32 over the bytes, as eight hex digits: the fixture's hash.
    static func hash(_ bytes: [UInt8]) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in bytes { h = (h ^ UInt32(b)) &* 0x01000193 }
        return String(format: "%08x", h)
    }

    /// `def`'s frame at `t` as a picture `width` × `height`.
    static func image(_ def: MotionDef, t: Double, width: Int, height: Int) -> UIImage? {
        let rgb = frame(def, t: t, width: width, height: height)
        guard !rgb.isEmpty else { return nil }
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            rgba[i * 4] = rgb[i * 3]
            rgba[i * 4 + 1] = rgb[i * 3 + 1]
            rgba[i * 4 + 2] = rgb[i * 3 + 2]
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: the kinds

    private static func painter(_ kind: String, _ c: [RGB], _ rng: inout SeededRandom, A: Double, p: Double,
                                ang: Double, seed: Int) -> (Painter, [Overlay]) {
        switch kind {
        case "mesh": return (mesh(c, &rng, A: A, ang: ang), [])
        case "waves": return (waves(c, &rng, ang: ang), [])
        case "bokeh": return bokeh(c, &rng, A: A, p: p, ang: ang)
        case "confetti": return confetti(c, &rng, A: A, p: p, ang: ang)
        case "rays": return (rays(c, A: A, p: p), [])
        case "grain": return (grain(c, A: A, p: p, ang: ang, seed: seed), [])
        case "dots": return (dots(c, ang: ang), [])
        case "stars": return (stars(c, ang: ang, seed: seed), [])
        case "paper": return (paper(c, A: A, ang: ang, seed: seed), [])
        case "marble": return (marble(c, ang: ang, seed: seed), [])
        case "linen": return (linen(c, A: A, ang: ang, seed: seed), [])
        case "terrazzo": return (terrazzo(c, seed: seed), [])
        case "sky": return (sky(c, ang: ang, seed: seed), [])
        case "halftone": return (halftone(c, ang: ang), [])
        default: return ({ _, _, _, _, _, _ in c[0] }, [])
        }
    }

    private static func at(_ c: [RGB], _ i: Int) -> RGB { c[i % c.count] }

    private static func mesh(_ c: [RGB], _ rng: inout SeededRandom, A: Double, ang: Double) -> Painter {
        var blobs: [(cx: Double, cy: Double, r: Double, colour: RGB)] = []
        for i in 0..<c.count {
            let bx = rng.next() * A
            let by = rng.next()
            let r = 0.35 + 0.3 * rng.next()
            let ph = rng.next()
            blobs.append((bx + 0.12 * sin(ang + tau * ph), by + 0.12 * cos(ang + tau * ph), r, at(c, i + 1)))
        }
        let from = c[0], to = at(c, 1)
        return { X, Y, _, _, u, v in
            var col = grad([from, to], (u + v) / 2)
            for blob in blobs {
                let d = hypot(X - blob.cx, Y - blob.cy) / blob.r
                if d < 1 { col = col.mixed(blob.colour, 0.85 * ((1 - d) * (1 - d))) }
            }
            return col
        }
    }

    private static func waves(_ c: [RGB], _ rng: inout SeededRandom, ang: Double) -> Painter {
        let n = c.count
        var bands: [(i: Int, ph: Double, f: Double)] = []
        if n > 1 {
            for i in 1..<n {
                let ph = rng.next()
                let f = 1 + (rng.next() * 3).rounded(.down)
                bands.append((i, ph, f))
            }
        }
        return { _, _, _, _, u, v in
            var col = c[0]
            for band in bands {
                let edge = Double(band.i) / Double(n)
                    + 0.05 * sin(tau * (band.f * u + band.ph) + ang * (band.i % 2 == 0 ? 1 : -1))
                if v > edge { col = c[band.i] }
            }
            return col
        }
    }

    private static func bokeh(_ c: [RGB], _ rng: inout SeededRandom, A: Double, p: Double,
                              ang: Double) -> (Painter, [Overlay]) {
        var discs: [Overlay] = []
        for k in 0..<24 {
            let x0 = rng.next() * A
            let y0 = rng.next()
            let r = 0.03 + 0.07 * rng.next()
            let speed = 1 + (rng.next() * 2).rounded(.down)
            let cy = fract(y0 - p * speed)
            let cx = x0 + 0.03 * sin(ang * speed + tau * y0)
            let colour = at(c, 2 + k)
            let centreY = cy * 1.3 - 0.15
            discs.append(Overlay(cx: cx, cy: centreY, reach: r) { X, Y, under in
                let d = hypot(X - cx, Y - centreY)
                guard d < r else { return nil }
                return under.mixed(colour, 0.5 * min(1.0, (1 - d / r) / 0.3))
            })
        }
        let from = c[0], to = at(c, 1)
        return ({ _, _, _, _, _, v in grad([from, to], v) }, discs)
    }

    private static func confetti(_ c: [RGB], _ rng: inout SeededRandom, A: Double, p: Double,
                                 ang: Double) -> (Painter, [Overlay]) {
        var pieces: [Overlay] = []
        for k in 0..<70 {
            let x0 = rng.next() * A
            let y0 = rng.next()
            let s = 0.012 + 0.014 * rng.next()
            let turn = rng.next()
            let spin: Double = rng.next() < 0.5 ? 1 : -1
            let fall = y0 + p * Double(1 + k % 2)
            let cy = fract(fall) * 1.1 - 0.05
            let th = tau * (turn + p * spin)
            let co = cos(th), si = sin(th)
            let cx = x0 + 0.02 * sin(ang + tau * turn)
            let colour = c.count > 1 ? c[1 + k % (c.count - 1)] : c[0]
            pieces.append(Overlay(cx: cx, cy: cy, reach: s * 1.1) { X, Y, _ in
                let dx = X - cx, dy = Y - cy
                let lx = dx * co + dy * si
                let ly = -dx * si + dy * co
                return abs(lx) <= s && abs(ly) <= s * 0.45 ? colour : nil
            })
        }
        let ground = c[0]
        return ({ _, _, _, _, _, _ in ground }, pieces)
    }

    private static func rays(_ c: [RGB], A: Double, p: Double) -> Painter {
        let m = 12.0
        let stripe = c[0].mixed(at(c, 1), 0.6)
        let glow = at(c, 2)
        return { X, Y, _, _, _, _ in
            let turn = atan2(Y - 0.5, X - A / 2) / tau + 0.5 - p / m
            let f = turn - turn.rounded(.down)
            var col = floorInt(f * 2 * m) % 2 == 1 ? stripe : c[0]
            let d = hypot(X - A / 2, Y - 0.5)
            if d < 0.45 { col = col.mixed(glow, 0.7 * ((1 - d / 0.45) * (1 - d / 0.45))) }
            return col
        }
    }

    private static func grain(_ c: [RGB], A: Double, p: Double, ang: Double, seed: Int) -> Painter {
        let frame = floorInt(p * 24)
        let co = cos(ang), si = sin(ang)
        return { X, Y, x, y, _, _ in
            let col = grad(c, 0.5 + ((X - A / 2) * co + (Y - 0.5) * si) / (A + 1))
            return col.lightened((hash01(x, y, seed + frame) - 0.5) * 0.1)
        }
    }

    private static func dots(_ c: [RGB], ang: Double) -> Painter {
        let S = 1.0 / 14
        return { X, Y, _, _, _, _ in
            let gx = floorInt(X / S), gy = floorInt(Y / S)
            let r = S * 0.32 * (0.65 + 0.35 * sin(ang + Double(gx + gy) * 0.7))
            if hypot(X - (Double(gx) + 0.5) * S, Y - (Double(gy) + 0.5) * S) < r {
                return c.count > 1 ? c[1 + (gx + gy) % (c.count - 1)] : c[0]
            }
            return c[0]
        }
    }

    private static func stars(_ c: [RGB], ang: Double, seed: Int) -> Painter {
        let C = 1.0 / 36
        let star = c.count > 2 ? c[2] : RGB.white
        let from = c[0], to = at(c, 1)
        return { X, Y, _, _, _, v in
            var col = grad([from, to], v)
            let gx = floorInt(X / C), gy = floorInt(Y / C)
            let h = hash01(gx, gy, seed)
            guard h < 0.3 else { return col }
            let sx = (Double(gx) + 0.2 + 0.6 * hash01(gx, gy, seed + 1)) * C
            let sy = (Double(gy) + 0.2 + 0.6 * hash01(gx, gy, seed + 2)) * C
            let r = C * (0.05 + 0.05 * hash01(gx, gy, seed + 4))
            let b = 0.55 + 0.45 * sin(ang * (1 + (hash01(gx, gy, seed + 3) * 3).rounded(.down)) + tau * 3.3 * h)
            let d = hypot(X - sx, Y - sy)
            if d < 2 * r { col = col.mixed(star, b * (1 - d / (2 * r))) }
            return col
        }
    }

    private static func paper(_ c: [RGB], A: Double, ang: Double, seed: Int) -> Painter {
        let lx = A / 2 + 0.35 * A * cos(ang), ly = 0.45 + 0.2 * sin(ang)
        let light = at(c, 1)
        return { X, Y, _, _, _, _ in
            let k = (fbm(24 * X + 64, 24 * Y + 64, seed) - 0.5) * 0.08
                + (noise(160 * X + 64, 160 * Y + 64, seed + 7) - 0.5) * 0.04
            var col = c[0].lightened(k)
            let d = hypot(X - lx, Y - ly) / 0.8
            if d < 1 { col = col.mixed(light, 0.4 * ((1 - d) * (1 - d))) }
            return col
        }
    }

    private static func marble(_ c: [RGB], ang: Double, seed: Int) -> Painter {
        let ox = 0.3 * cos(ang), oy = 0.3 * sin(ang)
        let vein = at(c, 1), fine = at(c, 2)
        return { X, Y, _, _, _, _ in
            let q = fbm(2.5 * X + 64 + ox, 2.5 * Y + 64 + oy, seed)
            let w = sin(tau * (1.5 * X + 2.5 * Y) + 8 * q)
            let col = c[0].mixed(vein, pow(1 - abs(w), 10) * 0.85)
            let q2 = fbm(5 * X + 128, 5 * Y + 128, seed + 3)
            let w2 = sin(tau * (3 * X - 1.2 * Y) + 6 * q2)
            return col.mixed(fine, pow(1 - abs(w2), 16) * 0.5)
        }
    }

    private static func linen(_ c: [RGB], A: Double, ang: Double, seed: Int) -> Painter {
        let lx = A / 2 + 0.3 * A * cos(ang), ly = 0.5 + 0.2 * sin(ang)
        let light = at(c, 1)
        return { X, Y, _, _, _, _ in
            let tx = 0.5 + 0.5 * sin(tau * 110 * X)
            let ty = 0.5 + 0.5 * sin(tau * 110 * Y)
            let rows = tx * noise(4 * X + 64, 220 * Y + 64, seed)
            let k = (rows + ty * noise(220 * X + 64, 4 * Y + 64, seed + 1) - 0.5) * 0.08
            var col = c[0].lightened(k)
            let d = hypot(X - lx, Y - ly) / 0.9
            if d < 1 { col = col.mixed(light, 0.25 * ((1 - d) * (1 - d))) }
            return col
        }
    }

    private static func terrazzo(_ c: [RGB], seed: Int) -> Painter {
        let n = c.count
        func chip(_ X: Double, _ Y: Double, size: Double, s: Int, small: Bool) -> RGB? {
            let gx = floorInt(X / size), gy = floorInt(Y / size)
            let h = hash01(gx, gy, s)
            if small && h >= 0.6 { return nil }
            let cx = (Double(gx) + 0.3 + 0.4 * hash01(gx, gy, s + 1)) * size
            let cy = (Double(gy) + 0.3 + 0.4 * hash01(gx, gy, s + 2)) * size
            let rx = size * (small ? 0.08 + 0.1 * hash01(gx, gy, s + 3) : 0.12 + 0.16 * hash01(gx, gy, s + 3))
            let ry = rx * (0.5 + 0.5 * hash01(gx, gy, s + 4))
            let th = tau * hash01(gx, gy, s + 5)
            let dx = X - cx, dy = Y - cy
            let lx = dx * cos(th) + dy * sin(th)
            let ly = -dx * sin(th) + dy * cos(th)
            guard (lx / rx) * (lx / rx) + (ly / ry) * (ly / ry) <= 1 else { return nil }
            return n > 1 ? c[1 + floorInt(h * Double(n - 1))] : c[0]
        }
        return { X, Y, _, _, _, _ in
            var col = c[0]
            if let big = chip(X, Y, size: 1.0 / 9, s: seed, small: false) { col = big }
            if let fleck = chip(X, Y, size: 1.0 / 23, s: seed + 10, small: true) { col = fleck }
            return col
        }
    }

    private static func sky(_ c: [RGB], ang: Double, seed: Int) -> Painter {
        let ox = 0.5 * cos(ang), oy = 0.5 * sin(ang)
        return { X, Y, _, _, _, v in
            let col = grad(c, v)
            let cl = fbm(2 * X + 64 + ox, 4 * Y + 64 + oy, seed)
            return col.mixed(.white, clamp01((cl - 0.55) / 0.2) * 0.45 * (1 - v))
        }
    }

    private static func halftone(_ c: [RGB], ang: Double) -> Painter {
        let S = 1.0 / 40
        let root2 = 2.0.squareRoot()
        let ink = at(c, 1)
        return { X, Y, _, _, u, v in
            let rx = (X + Y) / root2, ry = (Y - X) / root2 + 64
            let gx = floorInt(rx / S), gy = floorInt(ry / S)
            let tone = clamp01(0.5 * (u + v) + 0.15 * sin(ang + tau * u))
            if hypot(rx - (Double(gx) + 0.5) * S, ry - (Double(gy) + 0.5) * S) < S * 0.475 * tone { return ink }
            return c[0]
        }
    }
}
