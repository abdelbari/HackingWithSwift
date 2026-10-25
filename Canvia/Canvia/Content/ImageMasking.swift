// A photo's mask and retouch drawn: MaskRaster's grids made into grey
// pictures, and laid over the picture by the filter engine (see
// ImageFilterEngine's pass) and by the edge, which follows the mask.

import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import UIKit

enum ImageMasking {

    /// Masks made, by picture, mask and grid: painting one is the better
    /// part of a frame, and the engine and the edge both ask for it.
    private static let made: NSCache<NSString, CGImage> = {
        let c = NSCache<NSString, CGImage>()
        c.countLimit = 24
        return c
    }()

    /// What a photo shows once its mask is laid over it: `picture` — the
    /// picture itself, its own edge kept at full size, as the Android twin
    /// draws it — under `alpha`, the mask's grid from all kept (nil without
    /// a stroke); and, where Restore painted, the picture before a Cut out
    /// (the mask's base) laid over it, under `restored.cover`, the grid of
    /// where Restore reached — only while the mask has a Restore stroke and
    /// the base can be read.
    struct Shown {
        var picture: UIImage
        var alpha: CGImage?
        var restored: (picture: UIImage, cover: CGImage)?
    }

    /// `el` shown through its mask. `key` names `picture`, so its masks are
    /// kept apart.
    static func drawn(_ el: Element, picture: UIImage, key: String) -> Shown {
        masking(el.mask, picture: picture, key: key)
    }

    /// The same for `mask`.
    static func masking(_ mask: ImageMask?, picture: UIImage, key: String) -> Shown {
        guard let mask, !mask.strokes.isEmpty else { return Shown(picture: picture, alpha: nil, restored: nil) }
        let pixels = CGSize(width: picture.size.width * picture.scale, height: picture.size.height * picture.scale)
        // Taps of Clear a colour read the picture itself, at the grid's size.
        let source = mask.strokes.contains(where: \.keys) ? picture : nil
        var shown = Shown(picture: picture, alpha: alphaImage(mask, picture: pixels, key: key, source: source),
                          restored: nil)
        if mask.strokes.contains(where: \.restores), let base = mask.base, let original = PhotoLibrary.resolve(base),
           let cover = restoreImage(mask, picture: pixels, key: key, source: source) {
            shown.restored = (original, cover)
        }
        return shown
    }

    /// `mask`'s strokes painted (MaskRaster.raster) into the grid for a
    /// picture `picture` pixels in size, as a grey picture — white kept,
    /// black clear, top row first — from all kept: laid over the picture's
    /// own alpha, so a cut-out's edge is its own where no stroke went.
    static func alphaImage(_ mask: ImageMask, picture: CGSize, key: String, source: UIImage? = nil) -> CGImage? {
        greyImage(mask, picture: picture, start: 1, key: key, tag: "", source: source)
    }

    /// Where `mask`'s Restore strokes reached, net of the Erase strokes
    /// after them, as a grey picture — white where the picture before the
    /// cut is painted back, black where the cut-out shows as it is.
    static func restoreImage(_ mask: ImageMask, picture: CGSize, key: String, source: UIImage? = nil) -> CGImage? {
        greyImage(mask, picture: picture, start: 0, key: key, tag: "restore", source: source)
    }

    /// `mask` painted into the grid; its taps of Clear a colour read
    /// `source` sampled at the grid's size (gridPixels), and are passed
    /// over without it.
    private static func greyImage(_ mask: ImageMask, picture: CGSize, start: Float, key: String, tag: String,
                                  source: UIImage?) -> CGImage? {
        let grid = MaskRaster.gridSize(width: Double(picture.width), height: Double(picture.height))
        let id = madeID(mask, grid: grid, key: key, tag: tag)
        if let kept = made.object(forKey: id) { return kept }
        var keyed: MaskRaster.Keyed = { _ in nil }
        if let source, let proxy = sampledPixels(source, key: key, width: grid.width, height: grid.height) {
            keyed = { entry in MaskRaster.keyCoverage(proxy, width: grid.width, height: grid.height, entry: entry) }
        }
        let painted = MaskRaster.raster(mask.strokes, width: grid.width, height: grid.height, start: start,
                                        initial: nil, keyed: keyed)
        guard let image = grey(painted, width: grid.width, height: grid.height) else { return nil }
        made.setObject(image, forKey: id)
        return image
    }

    /// What a mask painted into its grid is kept under in `made`.
    private static func madeID(_ mask: ImageMask, grid: (width: Int, height: Int), key: String, tag: String) -> NSString {
        "\(key)|\(mask.hashValue)|\(grid.width)x\(grid.height)|\(tag)" as NSString
    }

    /// A picture's grid pixels as Clear a colour reads them, kept.
    private final class SampledPixels {
        let bytes: [UInt8]
        init(_ bytes: [UInt8]) { self.bytes = bytes }
    }

    /// The pictures sampled onto their grids, by picture and grid: a step
    /// of the Tolerance slider, or Everywhere turned, only keys again,
    /// never reading the whole picture back.
    private static let sampled: NSCache<NSString, SampledPixels> = {
        let c = NSCache<NSString, SampledPixels>()
        c.countLimit = 4
        return c
    }()

    /// `source`, named by `key`, sampled onto `width` × `height`
    /// (gridPixels), kept.
    private static func sampledPixels(_ source: UIImage, key: String, width: Int, height: Int) -> [UInt8]? {
        let id = "\(key)|\(width)x\(height)" as NSString
        if let kept = sampled.object(forKey: id) { return kept.bytes }
        guard let bytes = gridPixels(source, width: width, height: height) else { return nil }
        sampled.setObject(SampledPixels(bytes), forKey: id)
        return bytes
    }

    /// Moves on each time a mask with taps of Clear a colour is made off
    /// the main thread, so the photos whose edge waits for it — which read
    /// it — draw again with it.
    @Observable
    final class MasksMade {
        fileprivate(set) var version = 0
    }

    static let prepared = MasksMade()

    /// The masks being made on the worker, by the key they are kept under;
    /// guarded by `preparingLock`.
    private static var preparing = Set<String>()
    private static let preparingLock = NSLock()
    private static let preparer = DispatchQueue(label: "canvia.photo-masks", qos: .userInitiated)

    /// Whether `mask` over `picture`, named by `key`, is made and kept. A
    /// mask with a tap of Clear a colour reads the picture pixel by pixel,
    /// too slow for a frame: when it is not kept it is made on a worker —
    /// once, however often it is asked for meanwhile — and `prepared` moves
    /// on when it is ready. A mask without a tap is quick, and always ready.
    static func isReady(_ mask: ImageMask?, picture: UIImage, key: String) -> Bool {
        guard let mask, mask.strokes.contains(where: \.keys) else { return true }
        let pixels = CGSize(width: picture.size.width * picture.scale, height: picture.size.height * picture.scale)
        let grid = MaskRaster.gridSize(width: Double(pixels.width), height: Double(pixels.height))
        let id = madeID(mask, grid: grid, key: key, tag: "")
        if made.object(forKey: id) != nil { return true }
        preparingLock.lock()
        let start = preparing.insert(id as String).inserted
        preparingLock.unlock()
        if start {
            preparer.async {
                _ = ImageMasking.masking(mask, picture: picture, key: key)
                ImageMasking.preparingLock.lock()
                ImageMasking.preparing.remove(id as String)
                ImageMasking.preparingLock.unlock()
                DispatchQueue.main.async { ImageMasking.prepared.version &+= 1 }
            }
        }
        return false
    }

    /// `picture` sampled onto `width` × `height` — the mask's grid — as
    /// RGBA, not premultiplied, top row first: what a tap of Clear a colour
    /// reads. Each grid pixel is the picture's own pixel under its centre —
    /// column ⌊(gx + 0.5) × w / width⌋, row ⌊(gy + 0.5) × h / height⌋ —
    /// never a blend, as the Android twin's MaskRaster.proxy samples, so
    /// both phones measure a colour on the same pixels.
    static func gridPixels(_ picture: UIImage, width: Int, height: Int) -> [UInt8]? {
        guard width > 0, height > 0, let cg = picture.cgImage, cg.width > 0, cg.height > 0,
              let full = rgba(cg) else { return nil }
        let w = cg.width, h = cg.height
        if w == width && h == height { return full }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for gy in 0..<height {
            let y = min(h - 1, Int(((Double(gy) + 0.5) * Double(h) / Double(height)).rounded(.down)))
            for gx in 0..<width {
                let x = min(w - 1, Int(((Double(gx) + 0.5) * Double(w) / Double(width)).rounded(.down)))
                let from = (y * w + x) * 4, to = (gy * width + gx) * 4
                for c in 0..<4 { bytes[to + c] = full[from + c] }
            }
        }
        return bytes
    }

    /// `cg` at its own size as RGBA, not premultiplied, top row first.
    private static func rgba(_ cg: CGImage) -> [UInt8]? {
        let width = cg.width, height = cg.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        // Back from premultiplied, rounded, as the colours were.
        for p in 0..<(width * height) {
            let i = p * 4, alpha = Int(bytes[i + 3])
            guard alpha > 0, alpha < 255 else { continue }
            for c in 0..<3 { bytes[i + c] = UInt8(min(255, (Int(bytes[i + c]) * 255 + alpha / 2) / alpha)) }
        }
        return bytes
    }

    /// A grid of 0…1, top row first, as a grey picture.
    static func grey(_ grid: [Float], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, grid.count == width * height else { return nil }
        let bytes = grid.map { UInt8((min(max($0, 0), 1) * 255).rounded()) }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    /// A grey picture as a mask over `extent`: stretched to it, its values
    /// read as they are (no colour space), so a feather is the ramp painted.
    static func maskImage(_ grey: CGImage, over extent: CGRect) -> CIImage {
        let image = CIImage(cgImage: grey, options: [.colorSpace: NSNull()])
        let sx = extent.width / max(image.extent.width, 1), sy = extent.height / max(image.extent.height, 1)
        return image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
    }

    /// `image` clear where `grey` is black, kept where it is white.
    static func masked(_ image: CIImage, by grey: CGImage, extent: CGRect) -> CIImage {
        let blend = CIFilter.blendWithMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage.empty()
        blend.maskImage = maskImage(grey, over: extent)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    /// `effect` laid over `image` where `grey` is white, `image` where it is
    /// black, mixed between.
    static func mixed(_ effect: CIImage, over image: CIImage, by grey: CGImage, extent: CGRect) -> CIImage {
        let blend = CIFilter.blendWithMask()
        blend.inputImage = effect
        blend.backgroundImage = image
        blend.maskImage = maskImage(grey, over: extent)
        return (blend.outputImage ?? image).cropped(to: extent)
    }

    /// A retouch layer's blur of `image`: a Gaussian of MaskRaster's radius
    /// for the picture's shorter side; nil for none.
    static func blurred(_ image: CIImage, amount: Double, extent: CGRect) -> CIImage? {
        let radius = MaskRaster.blurRadius(amount: amount, shortSide: Double(min(extent.width, extent.height)))
        guard radius > 0 else { return nil }
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = Float(radius)
        return blur.outputImage?.cropped(to: extent)
    }

    /// A retouch layer's coverage as a grey picture, for a picture
    /// `picture` pixels in size.
    static func coverage(_ layer: RetouchLayer, picture: CGSize) -> CGImage? {
        let grid = MaskRaster.gridSize(width: Double(picture.width), height: Double(picture.height))
        let id = "retouch|\(layer.strokes.hashValue)|\(grid.width)x\(grid.height)" as NSString
        if let kept = made.object(forKey: id) { return kept }
        let painted = MaskRaster.coverage(of: layer, width: grid.width, height: grid.height)
        guard let image = grey(painted, width: grid.width, height: grid.height) else { return nil }
        made.setObject(image, forKey: id)
        return image
    }

    /// `el` as Show original shows it in a brush: for the Erase and Restore
    /// brush, the picture as it was before any of it — before a Cut out,
    /// too — and for a blur or pixelate brush, with no retouch. Drawn only,
    /// never written.
    static func original(_ el: Element, retouching: Bool) -> Element {
        var out = el
        if retouching {
            out.retouch = nil
        } else {
            if let base = el.mask?.base { out.src = base }
            out.mask = nil
        }
        return out
    }
}
