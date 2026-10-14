// A photo's effects — pixelate, focus, an outline or glow round what it
// shows, and one of glitch, slice, halftone or grain (`fx`) — with the rules
// both phones draw them by. Blur is not here: it is the sharpness dial below
// zero. The numbers are pure and tested (PhotoEffectsTests, the Android
// twin's PhotoEffectsTest); the drawing is Core Image's in the filter
// engine's pass (pixelate on the picture's own pixels, before the vignette
// and the duotone; the fx after the vignette, before the duotone) and, for
// the edge, behind the photo's frame.

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// A photo's focus effect: sharp in a circle about (`x`, `y`) — a point of
/// the picture, 0…1 across and down — and blurred beyond it by `amount`.
/// `radius` is a share of the picture's shorter side. `subject` keeps the
/// subject itself sharp instead, found as Cut out finds it; the Android twin
/// keeps the flag and draws the circle.
struct FocusBlur: Codable, Equatable, Hashable {
    var x: Double = 0.5
    var y: Double = 0.5
    var radius: Double = 0.3
    var amount: Double = 0.5
    var subject: Bool = false

    private enum CodingKeys: String, CodingKey { case x, y, radius, amount, subject }

    init(x: Double = 0.5, y: Double = 0.5, radius: Double = 0.3, amount: Double = 0.5, subject: Bool = false) {
        self.x = x
        self.y = y
        self.radius = radius
        self.amount = amount
        self.subject = subject
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = (try? c.decode(Double.self, forKey: .x)) ?? 0.5
        y = (try? c.decode(Double.self, forKey: .y)) ?? 0.5
        radius = (try? c.decode(Double.self, forKey: .radius)) ?? 0.3
        amount = (try? c.decode(Double.self, forKey: .amount)) ?? 0.5
        subject = (try? c.decode(Bool.self, forKey: .subject)) ?? false
    }
}

/// A line drawn round what a photo shows — its cut-out, or its frame where
/// it has no clear parts — behind it: a solid "outline" or a soft "glow", in
/// `color`, `width` 0…100 thick (see `PhotoEffects.thickness`).
struct PhotoEdge: Codable, Equatable, Hashable {
    var kind: String = "outline"
    var color: String = "#ffffff"
    var width: Double = 30

    private enum CodingKeys: String, CodingKey { case kind, color, width }

    init(kind: String = "outline", color: String = "#ffffff", width: Double = 30) {
        self.kind = kind
        self.color = color
        self.width = width
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decode(String.self, forKey: .kind)) ?? "outline"
        color = (try? c.decode(String.self, forKey: .color)) ?? "#ffffff"
        width = (try? c.decode(Double.self, forKey: .width)) ?? 30
    }
}

/// Glitch, slice, halftone or grain on a photo's pixels: the element's `fx`
/// key, {kind, amount 0…1, seed}, as the Android twin writes it. The seed
/// keeps the same bands, strips and noise on either phone (SeededRandom);
/// the maths is PhotoLook.fx. An unknown kind is no fx; a missing amount is
/// half and a missing seed 0, and an amount out of 0…1 is drawn within it.
struct PhotoFx: Codable, Equatable, Hashable {
    var kind: String
    var amount: Double = 0.5
    var seed: Int = 0

    /// The four kinds, in the order the Filters sheet offers them.
    static let kinds = ["glitch", "slice", "halftone", "grain"]

    private enum CodingKeys: String, CodingKey { case kind, amount, seed }

    init(kind: String, amount: Double = 0.5, seed: Int = 0) {
        self.kind = kind
        self.amount = amount
        self.seed = seed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        guard Self.kinds.contains(kind) else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Not an fx")
        }
        self.kind = kind
        amount = (try? c.decode(Double.self, forKey: .amount)).flatMap { $0.isFinite ? $0 : nil } ?? 0.5
        seed = (try? c.decode(Int.self, forKey: .seed)) ?? 0
    }

    /// Its amount within 0…1.
    var share: Double { min(max(amount, 0), 1) }

    /// Whether it changes anything: a known kind, more than none of it.
    var draws: Bool { Self.kinds.contains(kind) && share > 0 }

    /// What the Filters sheet calls it: "Glitch", "Slice", "Halftone",
    /// "Grain".
    static func name(_ kind: String) -> String { kind.capitalized }
}

enum PhotoEffects {

    // MARK: what a tap turns on

    /// Blur half way, small blocks, and a glow in a warm yellow, which shows
    /// on a white page — as on the Android twin.
    static let defaultBlur = 0.5
    static let defaultPixelate = 0.2
    static let glowColour = "#ffe066"
    /// An fx comes in at half, from a seed of its own.
    static let defaultFx = 0.5

    /// A new fx's seed, or Shuffle's: any from 1 to 99 999.
    static func newSeed() -> Int { Int.random(in: 1...99_999) }

    // MARK: pixelate

    /// Pixelate's block side in page units: 2 + 48 × the element's
    /// `pixelate`, 0…1; 0 when it has none.
    static func blockSize(_ pixelate: Double?) -> Double {
        guard let v = pixelate, v.isFinite, v > 0 else { return 0 }
        return 2 + 48 * min(v, 1)
    }

    /// Pixelate's block in pixels of a picture `picture` pixels in size
    /// drawn as `el` draws it — page units over the page units each of its
    /// pixels covers, rounded, at least one. 0 when it has none.
    static func blockPixels(_ el: Element, picture: CGSize) -> Int {
        blockPixels(el, picture: picture, pixelate: el.pixelate)
    }

    /// The same for a pixelate of `pixelate` — a pixelate brush's amount.
    static func blockPixels(_ el: Element, picture: CGSize, pixelate: Double?) -> Int {
        let page = blockSize(pixelate)
        guard page > 0, picture.width > 0, picture.height > 0 else { return 0 }
        let drawn = Crop.drawnPicture(el, image: picture)
        guard drawn.width > 0 else { return 0 }
        return max(1, Int((page * Double(picture.width) / Double(drawn.width) + 0.5).rounded(.down)))
    }

    // MARK: focus

    /// Focus's blur at full amount spreads over 3% of the shorter side.
    static let focusSpread = 0.03

    /// Past the sharp circle, the blur comes in fully over 10% of the
    /// shorter side.
    static let focusFeather = 0.1

    /// How blurred a pixel `distance` from the focus point is, 0…1: none
    /// inside `radius`, all of it `feather` beyond, a straight ramp between.
    static func focusWeight(distance: Double, radius: Double, feather: Double) -> Double {
        guard feather > 0 else { return distance > radius ? 1 : 0 }
        return min(max((distance - radius) / feather, 0), 1)
    }

    // MARK: outline and glow

    static func isGlow(_ edge: PhotoEdge) -> Bool { edge.kind == "glow" }

    /// The edge's thickness in page units: width / 5, so 0…20. 0 is none.
    static func thickness(_ edge: PhotoEdge?) -> Double {
        guard let w = edge?.width, w.isFinite else { return 0 }
        return min(max(w, 0), 100) / 5
    }

    /// How far past what the photo shows its edge reaches, in page units:
    /// an outline its thickness, a glow half as far again — its blur's
    /// spread is half its thickness, and it fades out about three spreads
    /// beyond.
    static func reach(_ edge: PhotoEdge?) -> Double {
        let t = thickness(edge)
        guard let edge, isGlow(edge) else { return t }
        return t * 1.5
    }

    // MARK: drawing, in the filter engine's pass

    /// The effects the filter engine draws into the picture itself: pixelate
    /// (its block in the picture's pixels), focus, and the fx; the blur and
    /// pixelate brushed on (`retouch`, each pixelate's block in `blocks`);
    /// and the mask, while it has strokes.
    struct Plan: Hashable {
        var block = 0
        var focus: FocusBlur?
        var fx: PhotoFx?
        var retouch: [RetouchLayer] = []
        var blocks: [Int] = []
        var mask: ImageMask?

        static let none = Plan()
        var isNone: Bool { self == Plan() }

        /// For the engine's cache key; empty when there are none.
        var signature: String {
            guard !isNone else { return "" }
            var out = block > 1 ? "|px\(block)" : ""
            if let f = focus {
                out += "|fo\(f.x),\(f.y),\(f.radius),\(f.amount)\(f.subject ? "s" : "")"
            }
            if let fx { out += "|fx\(fx.kind)\(fx.share),\(fx.seed)" }
            if !retouch.isEmpty { out += "|rt\(retouch.hashValue),\(blocks)" }
            if let mask { out += "|mk\(mask.hashValue)" }
            return out
        }
    }

    /// `el`'s plan for a picture `picture` pixels in size.
    static func plan(_ el: Element, picture: CGSize) -> Plan {
        let block = blockPixels(el, picture: picture)
        let retouch = RetouchLayer.kept(el.retouch) ?? []
        let blocks = retouch.map { layer in
            layer.kind == RetouchLayer.pixelate ? blockPixels(el, picture: picture, pixelate: layer.share) : 0
        }
        return Plan(block: block > 1 ? block : 0, focus: el.focusBlur.flatMap { $0.amount > 0 ? $0 : nil },
                    fx: el.fx.flatMap { $0.draws ? $0 : nil }, retouch: retouch, blocks: blocks,
                    mask: el.mask.flatMap { $0.strokes.isEmpty ? nil : $0 })
    }

    /// `bytes` — RGBA, premultiplied, `width` × `height` — in square blocks
    /// `block` pixels across, counted from the top left corner (the last row
    /// and column of blocks may be cut short): each block its pixels' mean,
    /// rounded half up. Premultiplied, the mean colour is weighted by alpha,
    /// so a clear pixel adds no black, as on the Android twin.
    static func pixelate(_ bytes: inout [UInt8], width: Int, height: Int, block: Int) {
        guard block > 1, width > 0, height > 0, bytes.count >= width * height * 4 else { return }
        var top = 0
        while top < height {
            let bottom = min(height, top + block)
            var left = 0
            while left < width {
                let right = min(width, left + block)
                var sums = [Int](repeating: 0, count: 4)
                for y in top..<bottom {
                    for x in left..<right {
                        let i = (y * width + x) * 4
                        for c in 0..<4 { sums[c] += Int(bytes[i + c]) }
                    }
                }
                let n = (bottom - top) * (right - left)
                let mean = sums.map { UInt8(min(255, (2 * $0 + n) / (2 * n))) }
                for y in top..<bottom {
                    for x in left..<right {
                        let i = (y * width + x) * 4
                        for c in 0..<4 { bytes[i + c] = mean[c] }
                    }
                }
                left = right
            }
            top = bottom
        }
    }

    /// `image` with `work` done to its pixels — RGBA, premultiplied, sRGB,
    /// `width` × `height`, top row first; nil when it cannot be drawn.
    static func withPixels(_ image: CGImage, _ work: (inout [UInt8], Int, Int) -> Void) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        work(&bytes, width, height)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// The focus effect: a copy blurred with a Gaussian of spread
    /// amount × 3% of the shorter side, mixed in by `focusWeight` from the
    /// focus point (x × width, y × height from the top) — or, given the
    /// picture's `subject` (its cut-out), everywhere but the subject.
    static func focused(_ image: CIImage, focus: FocusBlur, subject: CIImage?, extent: CGRect) -> CIImage {
        let short = Double(min(extent.width, extent.height))
        let sigma = min(max(focus.amount, 0), 1) * focusSpread * short
        guard sigma > 0 else { return image }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = Float(sigma)
        let soft = (blur.outputImage ?? image).cropped(to: extent)
        if let subject {
            let keep = CIFilter.blendWithAlphaMask()
            keep.inputImage = image
            keep.backgroundImage = soft
            keep.maskImage = subject
            return (keep.outputImage ?? soft).cropped(to: extent)
        }
        let radius = min(max(focus.radius, 0), 1) * short
        let ramp = CIFilter.radialGradient()
        ramp.center = CGPoint(x: Double(extent.minX) + min(max(focus.x, 0), 1) * Double(extent.width),
                              y: Double(extent.maxY) - min(max(focus.y, 0), 1) * Double(extent.height))
        ramp.radius0 = Float(radius)
        ramp.radius1 = Float(radius + focusFeather * short)
        ramp.color0 = CIColor(red: 0, green: 0, blue: 0)
        ramp.color1 = CIColor(red: 1, green: 1, blue: 1)
        let mix = CIFilter.blendWithMask()
        mix.inputImage = soft
        mix.backgroundImage = image
        mix.maskImage = ramp.outputImage?.cropped(to: extent)
        return (mix.outputImage ?? image).cropped(to: extent)
    }

    // MARK: drawing the edge, behind the frame

    /// An edge as drawn: the picture to lay behind the photo, centred on
    /// its frame, and how far it reaches past the frame on every side.
    final class EdgeImage {
        let image: UIImage
        let pad: Double
        init(image: UIImage, pad: Double) {
            self.image = image
            self.pad = pad
        }
    }

    private static let edges: NSCache<NSString, EdgeImage> = {
        let c = NSCache<NSString, EdgeImage>()
        c.countLimit = 24
        return c
    }()

    /// `el`'s outline or glow, made from what the photo shows — `picture`'s
    /// own alpha, placed, zoomed, straightened and cut to its frame as the
    /// canvas draws it — so it follows a cut-out's shape, and a plain
    /// photo's frame. Grown (an outline) or blurred (a glow) at one to two
    /// pixels a page unit and laid down in the edge's colour; kept while
    /// nothing that shapes it changes. nil when there is none.
    @MainActor
    static func edge(_ el: Element, picture: UIImage, key: String) -> EdgeImage? {
        guard let edge = el.edge, el.w > 0, el.h > 0, picture.size.width > 0, picture.size.height > 0 else { return nil }
        let t = thickness(edge)
        guard t > 0 else { return nil }
        let far = reach(edge)
        let pixels = Double(picture.size.width * picture.scale)
        let drawn = Crop.drawnPicture(el, image: picture.size)
        let detail = min(max(pixels / max(Double(drawn.width), 1), 1), 2)
        let scale = min(detail, 1024 / max(el.w + 2 * far, el.h + 2 * far, 1))
        let pad = ((far * scale).rounded(.up) + 1) / scale
        let id = [key, "\(el.w)x\(el.h)", "\(el.cropScale ?? 1),\(el.cropX ?? 0.5),\(el.cropY ?? 0.5)",
                  "\(el.cropFit == true)", "\(el.straighten ?? 0)", el.maskShapeId ?? "", "\(el.radius ?? 0)",
                  "\(edge.kind)\(edge.color)\(edge.width)", "\(scale)",
                  "\(el.mask?.hashValue ?? 0)"].joined(separator: "|") as NSString
        if let made = edges.object(forKey: id) { return made }
        // What the photo shows once its mask is laid over it, so the edge
        // follows what was erased and restored.
        let shown = ImageMasking.drawn(el, picture: picture, key: key)

        let canvas = CGSize(width: el.w + 2 * pad, height: el.h + 2 * pad)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let silhouette = UIGraphicsImageRenderer(size: canvas, format: format).image { ctx in
            let cg = ctx.cgContext
            cg.translateBy(x: pad, y: pad)
            let frame = FrameShape(definition: el.maskShapeId.flatMap { ContentLibrary.shapeMap[$0] },
                                   cornerRadius: el.radius ?? 0)
            cg.addPath(frame.path(in: CGRect(x: 0, y: 0, width: el.w, height: el.h)).cgPath)
            cg.clip()
            // ImageElementView's placing, step for step: fill or fit, the
            // focus fraction, the zoom about it, and the straightening.
            let fit = el.cropFit == true
            let iw = Double(picture.size.width), ih = Double(picture.size.height)
            let s = fit ? min(el.w / iw, el.h / ih) : max(el.w / iw, el.h / ih)
            let dispW = iw * s, dispH = ih * s
            let cropX = el.cropX ?? 0.5, cropY = el.cropY ?? 0.5
            let tilt = el.straighten ?? 0
            let level = fit ? 1 : Geometry.coverScale(width: el.w, height: el.h, degrees: tilt)
            let zoom = (el.cropScale ?? 1) * level
            cg.translateBy(x: cropX * el.w, y: cropY * el.h)
            cg.scaleBy(x: zoom, y: zoom)
            cg.translateBy(x: -cropX * el.w, y: -cropY * el.h)
            cg.translateBy(x: el.w / 2 + (dispW - el.w) * (0.5 - cropX), y: el.h / 2 + (dispH - el.h) * (0.5 - cropY))
            cg.rotate(by: tilt * .pi / 180)
            let placed = CGRect(x: -dispW / 2, y: -dispH / 2, width: dispW, height: dispH)
            if let alpha = shown.alpha {
                // The mask's top row at the picture's top: the context's own
                // way up turned over to clip, and back.
                let over = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: placed.minX, ty: placed.maxY)
                cg.concatenate(over)
                cg.clip(to: CGRect(origin: .zero, size: placed.size), mask: alpha)
                cg.concatenate(over.inverted())
            }
            shown.picture.draw(in: placed)
        }
        guard let cg = silhouette.cgImage else { return nil }
        let shape = CIImage(cgImage: cg)
        let extent = shape.extent
        let cover: CIImage
        if isGlow(edge) {
            // Blurred by half the thickness, doubled and held to one: solid
            // at the edge, fading out about three spreads beyond.
            let blur = CIFilter.gaussianBlur()
            blur.inputImage = shape
            blur.radius = Float(t * scale / 2)
            let doubled = CIFilter.colorMatrix()
            doubled.inputImage = (blur.outputImage ?? shape).cropped(to: extent)
            doubled.aVector = CIVector(x: 0, y: 0, z: 0, w: 2)
            let held = CIFilter.colorClamp()
            held.inputImage = doubled.outputImage
            held.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
            held.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
            cover = held.outputImage ?? shape
        } else {
            // Everything within the thickness of what the photo shows.
            let grow = CIFilter.morphologyMaximum()
            grow.inputImage = shape
            grow.radius = Float(t * scale)
            cover = (grow.outputImage ?? shape).cropped(to: extent)
        }
        let ink = CIFilter.blendWithAlphaMask()
        ink.inputImage = CIImage(color: CIColor(color: UIColor(hex: edge.color))).cropped(to: extent)
        ink.backgroundImage = CIImage.empty()
        ink.maskImage = cover
        guard let out = ink.outputImage,
              let laid = ImageFilterEngine.cgImage(out, from: extent) else { return nil }
        let made = EdgeImage(image: UIImage(cgImage: laid, scale: scale, orientation: .up), pad: pad)
        edges.setObject(made, forKey: id)
        return made
    }
}
