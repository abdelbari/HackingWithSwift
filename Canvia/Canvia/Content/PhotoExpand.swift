// Expand photo, without a model: a picture grown to a new shape, the
// original kept whole in the middle and the new border made from it — Blur
// (the picture scaled to cover, blurred `blurShare` of the long side and
// dimmed `dim`), Mirror (its edges reflected), Stretch (its edge pixels
// smeared outwards) or Fill (the object eraser's onion-peel fill over the
// border). The first three are pure and shared (`expand`, the shared rows
// in PhotoExpandTests — Fixtures/photo-expand.json, byte for byte the
// Android twin's); Fill reuses ObjectEraser.peelFill.
//
// The result is a new picture, a PNG among the uploads, and the element
// points at it, its frame grown to the new shape about its centre
// (`expanded`). What it came from is kept in its `expandedFrom`, {"src":
// <the original>, "rect": {x, y, w, h}, "mode": "blur"} — the rect where the
// original lies in the new picture, shares of it — so Undo expand
// (`undone`) and Change fill go back to the original, and Replace drops it
// (Crop.replaced). Pixels here are 0xAARRGGBB, not premultiplied, as the
// Android twin's IntArrays hold them.

import CoreGraphics
import Foundation
import UIKit

enum PhotoExpand {

    static let blur = "blur"
    static let mirror = "mirror"
    static let stretch = "stretch"
    static let fill = "fill"

    /// The fills, in the chip's order, with their names.
    static let modes: [(key: String, name: String)] = [(blur, "Blur"), (mirror, "Mirror"), (stretch, "Stretch"),
                                                       (fill, "Fill")]

    /// What the fill chip calls `mode`.
    static func name(_ mode: String) -> String {
        switch mode {
        case mirror: return tr("Mirror")
        case stretch: return tr("Stretch")
        case fill: return tr("Fill")
        default: return tr("Blur")
        }
    }

    /// The shapes offered, in the bar's order: the page's own, then the four
    /// fixed ones, width over height.
    static let page = "page"
    static let ratios: [(key: String, aspect: Double?)] = [(page, nil), ("1:1", 1), ("4:5", 4.0 / 5),
                                                           ("9:16", 9.0 / 16), ("16:9", 16.0 / 9)]

    /// Blur's spread, a share of the new picture's long side, and how much
    /// it is darkened.
    static let blurShare = 0.04
    static let dim = 0.1

    /// The longest side a new picture has; Fill's, which works harder, is
    /// shorter.
    static let maxEdge = 4096
    static let fillEdge = 2048

    /// Fill's working copy: at most the object eraser's working size.
    static let workingEdge = 384.0

    /// Where things go: the new picture `width` × `height`, and the
    /// original drawn `w` × `h` (smaller than it was when the new picture
    /// would have passed its longest side) at (`x`, `y`).
    struct Plan: Equatable {
        var width: Int
        var height: Int
        var x: Int
        var y: Int
        var w: Int
        var h: Int

        /// Where the original lies, shares of the new picture to 4 places.
        var rect: CGRect {
            CGRect(x: PhotoExpand.fourth(Double(x) / Double(width)), y: PhotoExpand.fourth(Double(y) / Double(height)),
                   width: PhotoExpand.fourth(Double(w) / Double(width)),
                   height: PhotoExpand.fourth(Double(h) / Double(height)))
        }
    }

    /// The plan for a `w` × `h` picture made `aspect` (width over height):
    /// as wide or as tall as it is, the other side grown — none shrunk —
    /// every side scaled by the same share when the new picture would pass
    /// `maxEdge`, rounded; the original centred, any odd pixel to the right
    /// and below. Nil for a shape it already has.
    static func plan(_ w: Int, _ h: Int, aspect: Double, maxEdge: Int = PhotoExpand.maxEdge) -> Plan? {
        guard w > 0, h > 0, aspect > 0, aspect.isFinite else { return nil }
        let wide = aspect > Double(w) / Double(h)
        let cw = wide ? Double(h) * aspect : Double(w)
        let ch = wide ? Double(h) : Double(w) / aspect
        let s = min(1, Double(maxEdge) / max(cw, ch))
        let width = max(1, Int((cw * s).rounded()))
        let height = max(1, Int((ch * s).rounded()))
        let ow = min(width, max(1, Int((Double(w) * s).rounded())))
        let oh = min(height, max(1, Int((Double(h) * s).rounded())))
        if ow == width && oh == height { return nil }
        return Plan(width: width, height: height, x: (width - ow) / 2, y: (height - oh) / 2, w: ow, h: oh)
    }

    /// `px`, a `w` × `h` picture, grown by `plan` with `mode`'s border —
    /// Blur, Mirror or Stretch; anything else is Stretch. The original, at
    /// the plan's size, is laid over the middle as it is.
    static func expand(_ px: [Int], _ w: Int, _ h: Int, plan: Plan, mode: String) -> [Int] {
        let inner = fitted(px, w, h, plan)
        let count = plan.width * plan.height
        var out: [Int]
        switch mode {
        case blur:
            out = blurred(inner, plan)
        case mirror:
            out = (0..<count).map { i in
                inner[reflect(i / plan.width - plan.y, plan.h) * plan.w + reflect(i % plan.width - plan.x, plan.w)]
            }
        default:
            out = (0..<count).map { i in
                let row = min(max(i / plan.width - plan.y, 0), plan.h - 1)
                let col = min(max(i % plan.width - plan.x, 0), plan.w - 1)
                return inner[row * plan.w + col]
            }
        }
        paste(&out, inner, plan)
        return out
    }

    /// `px` grown by `plan` with its border filled from the picture, as the
    /// object eraser fills a hole: on a copy at most `workingEdge` across,
    /// the border peeled in from the picture's edge (ObjectEraser.peelFill)
    /// and softened, then drawn up to size round the original, which is
    /// laid over the middle as it is.
    static func filled(_ px: [Int], _ w: Int, _ h: Int, plan: Plan) -> [Int] {
        let inner = fitted(px, w, h, plan)
        var canvas = [Int](repeating: 0, count: plan.width * plan.height)
        paste(&canvas, inner, plan)
        let s = min(1, workingEdge / Double(max(plan.width, plan.height)))
        let sw = max(2, Int((Double(plan.width) * s).rounded()))
        let sh = max(2, Int((Double(plan.height) * s).rounded()))
        var small = downscaled(canvas, plan.width, plan.height, sw, sh)
        let kx = Double(sw) / Double(plan.width), ky = Double(sh) / Double(plan.height)
        // A working pixel is a hole when its middle is off the original.
        let holes = (0..<(sw * sh)).map { i -> Bool in
            let cx = (Double(i % sw) + 0.5) / kx, cy = (Double(i / sw) + 0.5) / ky
            return cx < Double(plan.x) || cx >= Double(plan.x + plan.w) || cy < Double(plan.y) || cy >= Double(plan.y + plan.h)
        }
        var bytes = premultiplied(small)
        ObjectEraser.peelFill(pixels: &bytes, masked: holes, width: sw, height: sh)
        small = unpremultiplied(bytes, count: sw * sh)
        blurPixels(&small, sw, sh, sigma: 1.5)
        for y in 0..<plan.height {
            for x in 0..<plan.width {
                if x >= plan.x && x < plan.x + plan.w && y >= plan.y && y < plan.y + plan.h { continue }
                canvas[y * plan.width + x] = sample(small, sw, sh, x: (Double(x) + 0.5) * kx - 0.5,
                                                    y: (Double(y) + 0.5) * ky - 0.5)
            }
        }
        return canvas
    }

    /// The original at the plan's size: as it is, or averaged down.
    private static func fitted(_ px: [Int], _ w: Int, _ h: Int, _ plan: Plan) -> [Int] {
        plan.w == w && plan.h == h ? Array(px.prefix(w * h)) : downscaled(px, w, h, plan.w, plan.h)
    }

    private static func paste(_ out: inout [Int], _ inner: [Int], _ plan: Plan) {
        for y in 0..<plan.h {
            let from = y * plan.w, to = (plan.y + y) * plan.width + plan.x
            out.replaceSubrange(to..<(to + plan.w), with: inner[from..<(from + plan.w)])
        }
    }

    /// `i` reflected into 0 until `n`, the edge pixel repeated at each
    /// turn: …2 1 0 | 0 1 2 … n−1 | n−1 n−2…
    static func reflect(_ i: Int, _ n: Int) -> Int {
        guard n > 1 else { return 0 }
        let m = ((i % (2 * n)) + 2 * n) % (2 * n)
        return m < n ? m : 2 * n - 1 - m
    }

    /// Blur's border: `inner` scaled to cover the new picture about its
    /// middle, each pixel read between its four nearest (the edges held),
    /// then blurred by `blurShare` of the long side and each colour channel
    /// taken down by `dim`, rounded half up.
    private static func blurred(_ inner: [Int], _ plan: Plan) -> [Int] {
        let k = max(Double(plan.width) / Double(plan.w), Double(plan.height) / Double(plan.h))
        var out = [Int](repeating: 0, count: plan.width * plan.height)
        for y in 0..<plan.height {
            let sy = (Double(y) + 0.5 - Double(plan.height) / 2) / k + Double(plan.h) / 2 - 0.5
            for x in 0..<plan.width {
                let sx = (Double(x) + 0.5 - Double(plan.width) / 2) / k + Double(plan.w) / 2 - 0.5
                out[y * plan.width + x] = sample(inner, plan.w, plan.h, x: sx, y: sy)
            }
        }
        blurPixels(&out, plan.width, plan.height, sigma: blurShare * Double(max(plan.width, plan.height)))
        return out.map(dimmed)
    }

    /// `c` with each colour channel × (1 − `dim`), rounded half up.
    static func dimmed(_ c: Int) -> Int {
        func channel(_ v: Int) -> Int { Int((Double(v) * (1 - dim) + 0.5).rounded(.down)) }
        let red = channel((c >> 16) & 0xff) << 16, green = channel((c >> 8) & 0xff) << 8
        return (c & 0xff00_0000) | red | green | channel(c & 0xff)
    }

    /// `px` read at (`x`, `y`) between its four nearest pixels, each
    /// channel and alpha, the edges held, rounded half up.
    static func sample(_ px: [Int], _ w: Int, _ h: Int, x: Double, y: Double) -> Int {
        let cx = min(max(x, 0), Double(w - 1)), cy = min(max(y, 0), Double(h - 1))
        let x0 = Int(cx.rounded(.down)), y0 = Int(cy.rounded(.down))
        let x1 = min(w - 1, x0 + 1), y1 = min(h - 1, y0 + 1)
        let fx = cx - Double(x0), fy = cy - Double(y0)
        let a = px[y0 * w + x0], b = px[y0 * w + x1], c = px[y1 * w + x0], d = px[y1 * w + x1]
        var out = 0
        for shift in [24, 16, 8, 0] {
            func ch(_ p: Int) -> Double { Double((p >> shift) & 0xff) }
            let top = ch(a) + (ch(b) - ch(a)) * fx
            let bottom = ch(c) + (ch(d) - ch(c)) * fx
            let value: Double = top + (bottom - top) * fy + 0.5
            let level: Int = min(max(Int(value.rounded(.down)), 0), 255)
            out |= level << shift
        }
        return out
    }

    /// `px` averaged down to `sw` × `sh`, each cell the alpha-weighted mean
    /// of the pixels it covers, as the Android twin's ObjectEraser.downscaled.
    static func downscaled(_ px: [Int], _ w: Int, _ h: Int, _ sw: Int, _ sh: Int) -> [Int] {
        var out = [Int](repeating: 0, count: sw * sh)
        for sy in 0..<sh {
            let y0 = sy * h / sh, y1 = max(y0 + 1, (sy + 1) * h / sh)
            for sx in 0..<sw {
                let x0 = sx * w / sw, x1 = max(x0 + 1, (sx + 1) * w / sw)
                var a = 0, r = 0, g = 0, b = 0
                for y in y0..<min(y1, h) {
                    for x in x0..<min(x1, w) {
                        let c = px[y * w + x]
                        let alpha = (c >> 24) & 0xff
                        a += alpha
                        r += ((c >> 16) & 0xff) * alpha
                        g += ((c >> 8) & 0xff) * alpha
                        b += (c & 0xff) * alpha
                    }
                }
                let n = (min(y1, h) - y0) * (min(x1, w) - x0)
                guard a > 0 else { continue }
                let alphaBits: Int = (a / n) << 24
                let redBits: Int = (r / a) << 16
                let greenBits: Int = (g / a) << 8
                out[sy * sw + sx] = alphaBits | redBits | greenBits | (b / a)
            }
        }
        return out
    }

    /// A Gaussian of spread `sigma` over `px`, each colour weighted by its
    /// alpha (PhotoLook.gauss on each plane), as the Android twin's
    /// PixelLook.blur: an opaque picture stays opaque.
    static func blurPixels(_ px: inout [Int], _ w: Int, _ h: Int, sigma: Double) {
        guard sigma > 0, w > 0, h > 0 else { return }
        let n = w * h
        let opaque = px.allSatisfy { (($0 >> 24) & 0xff) == 255 }
        var alpha: [Float]?
        if !opaque {
            var plane = px.map { Float(($0 >> 24) & 0xff) / 255 }
            PhotoLook.gauss(&plane, width: w, height: h, sigma: sigma)
            alpha = plane
        }
        var plane = [Float](repeating: 0, count: n)
        for shift in [16, 8, 0] {
            for i in 0..<n {
                let c = px[i]
                plane[i] = Float((c >> shift) & 0xff) * (Float((c >> 24) & 0xff) / 255)
            }
            PhotoLook.gauss(&plane, width: w, height: h, sigma: sigma)
            for i in 0..<n {
                let a = alpha?[i] ?? 1
                let v = a <= 0.0001 ? 0 : min(max(Int((plane[i] / a).rounded()), 0), 255)
                px[i] = (px[i] & ~(0xff << shift)) | (v << shift)
            }
        }
        if let alpha {
            for i in 0..<n {
                let a = alpha[i]
                px[i] = a <= 0.0001 ? 0 : (px[i] & 0xffffff) | (min(max(Int((a * 255).rounded()), 0), 255) << 24)
            }
        }
    }

    // MARK: pictures

    /// A picture's pixels, 0xAARRGGBB, top row first; nil when it cannot
    /// be drawn.
    static func pixels(of image: CGImage) -> (px: [Int], w: Int, h: Int)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        return (unpremultiplied(bytes, count: w * h), w, h)
    }

    /// `px`, `w` × `h`, as a picture to store.
    static func image(_ px: [Int], _ w: Int, _ h: Int) -> UIImage? {
        guard w > 0, h > 0, px.count >= w * h, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(premultiplied(px)) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                               space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    private static func unpremultiplied(_ bytes: [UInt8], count n: Int) -> [Int] {
        (0..<n).map { i in (Int(bytes[i * 4 + 3]) << 24) | PhotoLook.unpremultiplied(bytes, at: i) }
    }

    private static func premultiplied(_ px: [Int]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: px.count * 4)
        for (i, c) in px.enumerated() {
            let a = (c >> 24) & 0xff
            bytes[i * 4] = UInt8((((c >> 16) & 0xff) * a + 127) / 255)
            bytes[i * 4 + 1] = UInt8((((c >> 8) & 0xff) * a + 127) / 255)
            bytes[i * 4 + 2] = UInt8(((c & 0xff) * a + 127) / 255)
            bytes[i * 4 + 3] = UInt8(a)
        }
        return bytes
    }

    /// `image` grown to `aspect` with `mode`'s border, at most `maxEdge`
    /// (or `fillEdge` for Fill) on its long side, and the plan it was made
    /// by; nil when it already has that shape or cannot be read. Slow:
    /// called off the main thread.
    static func grownImage(_ image: UIImage, aspect: (Int, Int) -> Double, mode: String) -> (image: UIImage, plan: Plan)? {
        guard let cg = SubjectMask.upright(image), let read = pixels(of: cg) else { return nil }
        let edge = mode == fill ? fillEdge : maxEdge
        guard let layout = plan(read.w, read.h, aspect: aspect(read.w, read.h), maxEdge: edge) else { return nil }
        let out = mode == fill ? filled(read.px, read.w, read.h, plan: layout)
            : expand(read.px, read.w, read.h, plan: layout, mode: mode)
        return self.image(out, layout.width, layout.height).map { ($0, layout) }
    }

    // MARK: the element

    /// What an expanded photo came from: the picture before, where it lies
    /// in the new one (shares of it) and the fill it was grown with. Read
    /// leniently: an unknown fill is Blur; no source or no rect is none.
    struct Origin: Codable, Equatable, Hashable {
        var src: String
        var rect: CGRect
        var mode: String

        private enum CodingKeys: String, CodingKey { case src, rect, mode }
        private enum RectKeys: String, CodingKey { case x, y, w, h }

        init(src: String, rect: CGRect, mode: String) {
            self.src = src
            self.rect = rect
            self.mode = mode
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            src = try c.decode(String.self, forKey: .src)
            let r = try c.nestedContainer(keyedBy: RectKeys.self, forKey: .rect)
            let x = try r.decode(Double.self, forKey: .x), y = try r.decode(Double.self, forKey: .y)
            let w = try r.decode(Double.self, forKey: .w), h = try r.decode(Double.self, forKey: .h)
            guard [x, y, w, h].allSatisfy(\.isFinite), w > 0, h > 0 else {
                throw DecodingError.dataCorruptedError(forKey: .w, in: r, debugDescription: "No rect")
            }
            rect = CGRect(x: x, y: y, width: w, height: h)
            let named = (try? c.decode(String.self, forKey: .mode)) ?? PhotoExpand.blur
            mode = PhotoExpand.modes.contains { $0.key == named } ? named : PhotoExpand.blur
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(src, forKey: .src)
            var r = c.nestedContainer(keyedBy: RectKeys.self, forKey: .rect)
            try r.encode(Double(rect.minX), forKey: .x)
            try r.encode(Double(rect.minY), forKey: .y)
            try r.encode(Double(rect.width), forKey: .w)
            try r.encode(Double(rect.height), forKey: .h)
            try c.encode(mode, forKey: .mode)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(src)
            hasher.combine(mode)
            for v in [rect.minX, rect.minY, rect.width, rect.height] { hasher.combine(Double(v)) }
        }
    }

    /// The frame `frame` grown to `aspect` about its centre: as wide or as
    /// tall as it is, the other side longer.
    static func grown(_ frame: CGRect, aspect: Double) -> CGRect {
        guard frame.width > 0, frame.height > 0, aspect > 0 else { return frame }
        let wide = aspect > Double(frame.width / frame.height)
        let w = wide ? Double(frame.height) * aspect : Double(frame.width)
        let h = wide ? Double(frame.height) : Double(frame.width) / aspect
        return CGRect(x: Double(frame.minX) + (Double(frame.width) - w) / 2,
                      y: Double(frame.minY) + (Double(frame.height) - h) / 2, width: w, height: h)
    }

    /// `el` showing the expanded picture `src`, made by `plan` from
    /// `original` with `mode`: its frame grown to the new picture's shape
    /// about its centre, the picture centred and covering it, and
    /// `expandedFrom` saying where it came from. A photo expanded again
    /// keeps the first original (the caller passes it), and is grown from
    /// it: its frame and faces are first put back as `undone` leaves them,
    /// so a second expand or a Change fill sizes the original as one expand
    /// would. Its Erase and Restore strokes and brushed layers were laid on
    /// the old picture and go, as a Replace drops them; its retouched faces
    /// move to where they now lie.
    static func expanded(_ el: Element, src: String, original: String, plan: Plan, mode: String) -> Element {
        let base = undone(el) ?? el
        let frame = grown(base.frame, aspect: Double(plan.width) / Double(plan.height))
        let rect = plan.rect
        var out = base
        out.mask = nil
        out.retouch = nil
        if var faces = base.retouchFace {
            faces.faces = faces.faces.map { inRect($0, rect) }
            out.retouchFace = faces
        }
        out.src = src
        out.x = Double(frame.minX)
        out.y = Double(frame.minY)
        out.w = Double(frame.width)
        out.h = Double(frame.height)
        out.cropScale = 1
        out.cropX = 0.5
        out.cropY = 0.5
        out.cropFit = nil
        out.expandedFrom = Origin(src: original, rect: rect, mode: mode)
        return out
    }

    /// A face's box, shares of the original, as shares of the expanded
    /// picture that holds it in `rect`; `outOf` turns it back.
    private static func inRect(_ f: FaceRetouch.Face, _ rect: CGRect) -> FaceRetouch.Face {
        let rx = Double(rect.minX), ry = Double(rect.minY), rw = Double(rect.width), rh = Double(rect.height)
        // Each point on its own line, typed: arithmetic in a closure inside
        // the initialiser's arguments is more than the compiler checks in time.
        func placed(_ p: CGPoint) -> CGPoint {
            let x: Double = rx + Double(p.x) * rw
            let y: Double = ry + Double(p.y) * rh
            return CGPoint(x: x, y: y)
        }
        let keep: [[CGPoint]] = f.keep.map { (poly: [CGPoint]) -> [CGPoint] in poly.map(placed) }
        return FaceRetouch.Face(x: fourth(rx + f.x * rw), y: fourth(ry + f.y * rh), w: fourth(f.w * rw),
                                h: fourth(f.h * rh), keep: keep)
    }

    private static func outOf(_ f: FaceRetouch.Face, _ rect: CGRect) -> FaceRetouch.Face {
        let rx = Double(rect.minX), ry = Double(rect.minY), rw = Double(rect.width), rh = Double(rect.height)
        func unplaced(_ p: CGPoint) -> CGPoint {
            let x: Double = (Double(p.x) - rx) / rw
            let y: Double = (Double(p.y) - ry) / rh
            return CGPoint(x: x, y: y)
        }
        let keep: [[CGPoint]] = f.keep.map { (poly: [CGPoint]) -> [CGPoint] in poly.map(unplaced) }
        return FaceRetouch.Face(x: fourth((f.x - rx) / rw), y: fourth((f.y - ry) / rh), w: fourth(f.w / rw),
                                h: fourth(f.h / rh), keep: keep)
    }

    /// The new picture's shape for a Change fill: the original's, `w` ×
    /// `h`, grown as `origin`'s rect says it was.
    static func aspect(of origin: Origin, _ w: Int, _ h: Int) -> Double {
        (Double(w) / Double(origin.rect.width)) / (Double(h) / Double(origin.rect.height))
    }

    /// `el` back to the picture it was expanded from: its frame the part of
    /// it the original covered, about the same centre, the picture centred
    /// and covering it; nil when it was never expanded.
    static func undone(_ el: Element) -> Element? {
        guard let origin = el.expandedFrom else { return nil }
        let w = el.w * Double(origin.rect.width), h = el.h * Double(origin.rect.height)
        var out = el
        if var faces = el.retouchFace {
            faces.faces = faces.faces.map { outOf($0, origin.rect) }
            out.retouchFace = faces
        }
        out.src = origin.src
        out.x = el.x + (el.w - w) / 2
        out.y = el.y + (el.h - h) / 2
        out.w = w
        out.h = h
        out.cropScale = 1
        out.cropX = 0.5
        out.cropY = 0.5
        out.expandedFrom = nil
        out.mask = nil
        out.retouch = nil
        return out
    }

    /// The page's shape, width over height, for the Page chip.
    static func pageAspect(_ width: Double, _ height: Double) -> Double? {
        guard width > 0, height > 0 else { return nil }
        let a = width / height
        return a.isFinite ? a : nil
    }

    static func fourth(_ v: Double) -> Double { FaceRetouch.fourth(v) }
}
