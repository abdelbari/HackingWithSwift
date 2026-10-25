// Face retouch, Canva's Edit photo ▸ Effects ▸ Face Retouch, as both phones
// keep it: the element's `retouchFace`, {"amount": 0.5, "faces": [{x, y, w,
// h, keep?}, …]} — each face's box a share of the picture as stored,
// uncropped, found once when the effect is turned on (FaceFinder) and kept,
// so either phone and every export draws the same result without looking
// again. This phone also keeps `keep`, polygons of {x, y} points in the
// same shares round the eyes, brows and lips; a face from the Android twin
// has none, and keeps a band across the eyes instead (`eyeBand`).
//
// The rule (`applyPixels`), pure and shared, done after the dials and before the
// focus, the pixelate, the fx and the vignette (ImageFilterEngine), as the
// Android twin's PixelLook does it:
// - Each face is an ellipse filling its box, its outer `feather` of the way
//   out fading to nothing.
// - Skin is a pixel whose YCbCr (full range) has Cb in 77…127 and Cr in
//   133…173, measured before the smoothing.
// - The smoothing is an edge-preserving surface blur (`Kernel`) of radius
//   `radiusShare` × the face's width × amount, mixed in by skin × the
//   ellipse's weight × amount; a kept part is left untouched.
// The shared rows in FaceRetouchTests (Fixtures/face-retouch.json, byte for
// byte the Android twin's) hold both phones to it within 2 a channel.

import CoreGraphics
import Foundation

struct FaceRetouch: Codable, Equatable, Hashable {

    /// A face's box, shares of the picture across and down, and the parts
    /// kept sharp, where the phone that found it knew them.
    struct Face: Codable, Equatable, Hashable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var keep: [[CGPoint]] = []

        private enum CodingKeys: String, CodingKey { case x, y, w, h, keep }
        private enum PointKeys: String, CodingKey { case x, y }

        init(x: Double, y: Double, w: Double, h: Double, keep: [[CGPoint]] = []) {
            self.x = x
            self.y = y
            self.w = w
            self.h = h
            self.keep = keep
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try FaceRetouch.number(c, .x)
            y = try FaceRetouch.number(c, .y)
            w = try FaceRetouch.number(c, .w)
            h = try FaceRetouch.number(c, .h)
            guard w > 0, h > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .w, in: c, debugDescription: "No face")
            }
            // A polygon of fewer than three points that read keeps nothing.
            let polygons = (try? c.decode([[Lossy<Point>]].self, forKey: .keep)) ?? []
            keep = polygons.compactMap { list in
                let points = list.compactMap(\.value).map { CGPoint(x: $0.x, y: $0.y) }
                return points.count >= 3 ? points : nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
            try c.encode(w, forKey: .w)
            try c.encode(h, forKey: .h)
            if !keep.isEmpty {
                try c.encode(keep.map { $0.map { Point(x: Double($0.x), y: Double($0.y)) } }, forKey: .keep)
            }
        }

        /// A point of a kept part, as the file writes it.
        struct Point: Codable {
            var x: Double
            var y: Double

            init(x: Double, y: Double) {
                self.x = x
                self.y = y
            }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: PointKeys.self)
                x = try FaceRetouch.number(c, .x)
                y = try FaceRetouch.number(c, .y)
            }

            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: PointKeys.self)
                try c.encode(x, forKey: .x)
                try c.encode(y, forKey: .y)
            }
        }

        static func == (a: Face, b: Face) -> Bool {
            a.x == b.x && a.y == b.y && a.w == b.w && a.h == b.h
                && a.keep.map { $0.map { [$0.x, $0.y] } } == b.keep.map { $0.map { [$0.x, $0.y] } }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(x)
            hasher.combine(y)
            hasher.combine(w)
            hasher.combine(h)
            for polygon in keep { for p in polygon { hasher.combine(p.x); hasher.combine(p.y) } }
        }
    }

    var amount: Double = FaceRetouch.defaultAmount
    var faces: [Face]

    /// What the effect is turned on at.
    static let defaultAmount = 0.5
    /// The surface blur's radius at full amount: 1.5% of the face's width.
    static let radiusShare = 0.015
    /// The outer fifth of a face's ellipse fades out.
    static let feather = 0.2
    /// Skin's chroma, full-range YCbCr.
    static let cb = 77.0...127.0
    static let cr = 133.0...173.0
    /// How far apart in lightness (0…255) two pixels are for the blur to
    /// count the other at e^-½ of its weight: what keeps an edge.
    static let rangeSigma = 20.0
    /// At most this many taps each side of a pixel, spread over the radius,
    /// so a large face costs no more than a small one.
    static let maxTaps = 4
    /// Where a face without `keep` parts is left sharp: this much of its box
    /// down, across the middle of it — the eyes and the brows above them.
    static let eyeBand = 0.25..<0.5
    static let eyeAcross = 0.1..<0.9

    private enum CodingKeys: String, CodingKey { case amount, faces }

    init(amount: Double = FaceRetouch.defaultAmount, faces: [Face]) {
        self.amount = amount
        self.faces = faces
    }

    /// Read leniently: a missing or unreadable amount is the default, one
    /// out of 0…1 held within it, and a face that does not read is left
    /// out. No face at all is no retouch (see `kept`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let read = (try? c.decode(Double.self, forKey: .amount)).flatMap { $0.isFinite ? $0 : nil }
        amount = min(max(read ?? Self.defaultAmount, 0), 1)
        faces = ((try? c.decode([Lossy<Face>].self, forKey: .faces)) ?? []).compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(amount, forKey: .amount)
        try c.encode(faces, forKey: .faces)
    }

    fileprivate static func number<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> Double {
        let v = try c.decode(Double.self, forKey: key)
        guard v.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not a number")
        }
        return v
    }

    /// A retouch as an element keeps it: one with a face, nil for none — a
    /// build without the key draws the plain photo.
    static func kept(_ retouch: FaceRetouch?) -> FaceRetouch? {
        guard let retouch, !retouch.faces.isEmpty else { return nil }
        return retouch
    }

    /// Whether it changes anything: a face, more than none of it.
    var draws: Bool { !faces.isEmpty && amount > 0 }

    /// A value to four places, as boxes are kept.
    static func fourth(_ v: Double) -> Double { (v * 10_000 + 0.5).rounded(.down) / 10_000 }

    // MARK: the rule

    /// Whether `rgb` (0xRRGGBB) is skin by its chroma (`cb`, `cr`).
    static func isSkin(_ rgb: Int) -> Bool {
        let r = Double((rgb >> 16) & 0xff), g = Double((rgb >> 8) & 0xff), b = Double(rgb & 0xff)
        let cbValue = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b
        let crValue = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b
        return cb.contains(cbValue) && cr.contains(crValue)
    }

    /// A colour's lightness as the surface blur weighs it, 0…255 whole.
    static func luma(_ c: Int) -> Int {
        // A term at a time: the shifts are generic, and one long line of
        // them is more than the compiler will type-check in time.
        let red: Int = 299 * ((c >> 16) & 0xff)
        let green: Int = 587 * ((c >> 8) & 0xff)
        let blue: Int = 114 * (c & 0xff)
        return (red + green + blue + 500) / 1000
    }

    /// How much of the smoothing lands at the centre of pixel (`x`, `y`) of
    /// a `w` × `h` picture for `face`: 1 inside its ellipse, fading over its
    /// outer `feather`, 0 outside — and 0 in a kept part.
    static func weight(_ face: Face, x: Int, y: Int, w: Int, h: Int) -> Double {
        let px = Double(x) + 0.5, py = Double(y) + 0.5
        let rx = face.w * Double(w) / 2, ry = face.h * Double(h) / 2
        guard rx > 0, ry > 0 else { return 0 }
        let dx = (px - (face.x * Double(w) + rx)) / rx
        let dy = (py - (face.y * Double(h) + ry)) / ry
        let d = (dx * dx + dy * dy).squareRoot()
        if d >= 1 { return 0 }
        if kept(face, u: px / Double(w), v: py / Double(h)) { return 0 }
        return d <= 1 - feather ? 1 : (1 - d) / feather
    }

    /// Whether the point (`u`, `v`), shares of the picture, is one `face`
    /// keeps sharp: in a `keep` polygon, or for a face with none, in its
    /// eye band.
    static func kept(_ face: Face, u: Double, v: Double) -> Bool {
        if !face.keep.isEmpty { return face.keep.contains { inside($0, u: u, v: v) } }
        let across = (u - face.x) / face.w
        let down = (v - face.y) / face.h
        return eyeBand.contains(down) && eyeAcross.contains(across)
    }

    /// Even-odd: whether (`u`, `v`) is inside `polygon`.
    private static func inside(_ polygon: [CGPoint], u: Double, v: Double) -> Bool {
        var odd = false
        var j = polygon.count - 1
        for i in polygon.indices {
            let a = polygon[i], b = polygon[j]
            let ay = Double(a.y), by = Double(b.y), ax = Double(a.x), bx = Double(b.x)
            if (ay > v) != (by > v) && u < (bx - ax) * (v - ay) / (by - ay) + ax { odd.toggle() }
            j = i
        }
        return odd
    }

    /// Each channel, alpha too, `t` of the way from `from` to `to`, rounded
    /// half up — as the Android twin's MaskRaster.mixed lays every retouch
    /// layer in.
    static func mixed(_ from: Int, _ to: Int, _ t: Float) -> Int {
        var out = 0
        for shift in [24, 16, 8, 0] {
            let a = (from >> shift) & 0xff, b = (to >> shift) & 0xff
            let v = Int((Float(a) + Float(b - a) * t).rounded())
            out |= min(max(v, 0), 255) << shift
        }
        return out
    }

    /// `retouch` done to `px`, `w` × `h` 0xAARRGGBB (not premultiplied), in
    /// place: each face in turn, over its box only — the skin in it smoothed
    /// by a surface blur of its own radius and mixed in as the rule says.
    static func applyPixels(_ px: inout [Int], width w: Int, height h: Int, retouch: FaceRetouch) {
        guard w > 0, h > 0, px.count >= w * h else { return }
        let amount = min(max(retouch.amount, 0), 1)
        guard amount > 0 else { return }
        for face in retouch.faces {
            let left = max(0, Int((face.x * Double(w)).rounded(.down)))
            let top = max(0, Int((face.y * Double(h)).rounded(.down)))
            let right = min(w, Int(((face.x + face.w) * Double(w)).rounded(.up)))
            let bottom = min(h, Int(((face.y + face.h) * Double(h)).rounded(.up)))
            guard right > left, bottom > top,
                  let kernel = Kernel(radius: radiusShare * face.w * Double(w) * amount) else { continue }
            let source = px
            for y in top..<bottom {
                for x in left..<right {
                    let i = y * w + x
                    guard isSkin(source[i]) else { continue }
                    let t = weight(face, x: x, y: y, w: w, h: h) * amount
                    guard t > 0 else { continue }
                    px[i] = mixed(source[i], kernel.at(source, w: w, h: h, x: x, y: y), Float(t))
                }
            }
        }
    }

    /// The surface blur at pixel (`x`, `y`) of `px`: a bilateral filter of
    /// radius `radius` pixels rounded (none below 1). Its taps are the
    /// offsets k × R / n for k in −n…n each way, rounded half away from
    /// nought, n = min(R, `maxTaps`), the picture's edge pixels repeated
    /// beyond it; each weighs e^(−(dx² + dy²) / 2(R/2)²) × e^(−Δ² / 2
    /// `rangeSigma`²), Δ the taps' difference in `luma`. Each colour
    /// channel is the weighted mean, rounded half up; alpha is the pixel's
    /// own.
    static func surfaceBlur(_ px: [Int], width w: Int, height h: Int, x: Int, y: Int, radius: Double) -> Int {
        Kernel(radius: radius)?.at(px, w: w, h: h, x: x, y: y) ?? px[y * w + x]
    }

    /// The surface blur's taps and weights for one radius, made once for a
    /// face rather than at every pixel.
    struct Kernel {
        let offsets: [Int]
        let spatial: [Double]
        private static let range: [Double] = (0..<256).map { d in
            exp(-Double(d * d) / (2 * FaceRetouch.rangeSigma * FaceRetouch.rangeSigma))
        }

        /// The kernel of `radius` pixels; nil below one, which blurs
        /// nothing.
        init?(radius: Double) {
            guard radius.isFinite else { return nil }
            let r = Int(radius.rounded())
            guard r >= 1 else { return nil }
            let n = min(r, FaceRetouch.maxTaps)
            let sigma = Double(r) / 2
            // Rounded half away from nought, so the taps lie the same either side.
            let taps = (0...(2 * n)).map { k -> Int in
                let d = k - n
                let size = Int((Double(abs(d)) * Double(r) / Double(n) + 0.5).rounded(.down))
                return d < 0 ? -size : size
            }
            let side = taps.count
            var weights = [Double](repeating: 0, count: side * side)
            for j in 0..<side {
                for i in 0..<side {
                    let dx = Double(taps[i]), dy = Double(taps[j])
                    weights[j * side + i] = exp(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                }
            }
            offsets = taps
            spatial = weights
        }

        func at(_ px: [Int], w: Int, h: Int, x: Int, y: Int) -> Int {
            let c = px[y * w + x]
            let l0 = FaceRetouch.luma(c)
            var sr = 0.0, sg = 0.0, sb = 0.0, sw = 0.0
            let side = offsets.count
            for j in 0..<side {
                let yy = min(max(y + offsets[j], 0), h - 1)
                for i in 0..<side {
                    let xx = min(max(x + offsets[i], 0), w - 1)
                    let o = px[yy * w + xx]
                    let k = spatial[j * side + i] * Self.range[min(255, abs(FaceRetouch.luma(o) - l0))]
                    sr += k * Double((o >> 16) & 0xff)
                    sg += k * Double((o >> 8) & 0xff)
                    sb += k * Double(o & 0xff)
                    sw += k
                }
            }
            func channel(_ v: Double) -> Int { min(max(Int((v / sw).rounded()), 0), 255) }
            return (c & ~0xffffff) | (channel(sr) << 16) | (channel(sg) << 8) | channel(sb)
        }
    }

    // MARK: on the picture's bytes

    /// `retouch` done to `bytes` — RGBA, premultiplied, `width` × `height`,
    /// top row first, as the filter engine hands its pixels over — on the
    /// colours as they are (PhotoLook.unpremultiplied), as the Android
    /// twin's pixels hold them.
    static func applyBytes(_ bytes: inout [UInt8], width: Int, height: Int, retouch: FaceRetouch) {
        let n = width * height
        guard n > 0, bytes.count >= n * 4 else { return }
        var px = unpacked(bytes, count: n)
        applyPixels(&px, width: width, height: height, retouch: retouch)
        packed(px, into: &bytes)
    }

    /// A smoothing brush (`RetouchLayer.smooth`) laid over `bytes`, as
    /// `applyBytes` takes them: the surface blur of radius amount ×
    /// `RetouchLayer.smoothShare` of the shorter side, skin or not, mixed in
    /// by what the layer's strokes cover (MaskRaster.coverage), worked out
    /// only where they do.
    static func smoothed(_ bytes: inout [UInt8], width w: Int, height h: Int, layer: RetouchLayer) {
        let n = w * h
        guard n > 0, bytes.count >= n * 4,
              let kernel = Kernel(radius: layer.share * RetouchLayer.smoothShare * Double(min(w, h))) else { return }
        let grid = MaskRaster.gridSize(width: Double(w), height: Double(h))
        let cover = MaskRaster.coverage(of: layer, width: grid.width, height: grid.height)
        let source = unpacked(bytes, count: n)
        var px = source
        for y in 0..<h {
            for x in 0..<w {
                let t = MaskRaster.sample(cover, width: grid.width, height: grid.height,
                                          x: (Double(x) + 0.5) / Double(w), y: (Double(y) + 0.5) / Double(h))
                guard t > 0 else { continue }
                let i = y * w + x
                px[i] = mixed(source[i], kernel.at(source, w: w, h: h, x: x, y: y), min(t, 1))
            }
        }
        packed(px, into: &bytes)
    }

    private static func unpacked(_ bytes: [UInt8], count n: Int) -> [Int] {
        (0..<n).map { i in (Int(bytes[i * 4 + 3]) << 24) | PhotoLook.unpremultiplied(bytes, at: i) }
    }

    private static func packed(_ px: [Int], into bytes: inout [UInt8]) {
        for (i, c) in px.enumerated() {
            let a = (c >> 24) & 0xff
            bytes[i * 4] = UInt8((((c >> 16) & 0xff) * a + 127) / 255)
            bytes[i * 4 + 1] = UInt8((((c >> 8) & 0xff) * a + 127) / 255)
            bytes[i * 4 + 2] = UInt8(((c & 0xff) * a + 127) / 255)
            bytes[i * 4 + 3] = UInt8(a)
        }
    }

    // MARK: faces found by their eyes

    /// How far down a face's box found by its eyes the eyes are.
    static let eyeDown = 0.4

    /// A face found by its eyes — the point between them and how far apart
    /// they are, in pixels of a `pictureW` × `pictureH` picture: a box 2.2
    /// eye-distances wide and 2.6 tall, centred across on that point with
    /// the eyes `eyeDown` of the way down, cut to the picture. How the
    /// Android twin, whose finder gives only the eyes, makes its boxes.
    static func fromEyes(midX: Double, midY: Double, eyes: Double, pictureW: Double, pictureH: Double) -> Face? {
        guard eyes > 0, pictureW > 0, pictureH > 0 else { return nil }
        let w = 2.2 * eyes, h = 2.6 * eyes
        let left = max(0, midX - w / 2), top = max(0, midY - eyeDown * h)
        let right = min(pictureW, midX + w / 2), bottom = min(pictureH, midY + (1 - eyeDown) * h)
        guard right > left, bottom > top else { return nil }
        return Face(x: fourth(left / pictureW), y: fourth(top / pictureH),
                    w: fourth((right - left) / pictureW), h: fourth((bottom - top) / pictureH))
    }

    // MARK: on the element

    /// `el` with its retouch's amount at `amount`, its faces — keep and
    /// all — kept as they came; as it is without one.
    static func withAmount(_ el: Element, _ amount: Double) -> Element {
        guard var retouch = el.retouchFace else { return el }
        var out = el
        retouch.amount = min(max(amount, 0), 1)
        out.retouchFace = retouch
        return out
    }
}
