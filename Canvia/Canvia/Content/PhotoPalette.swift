// A palette pulled out of a photo.
//
// The colours a picture is made of are the colours that go with it, and
// picking them by eye from a thumbnail is guesswork. This reads the pixels
// instead: the picture is shrunk to a few thousand samples, each is dropped
// into a coarse RGB bin, and the fullest bins come out first — with a
// distance test between them so the palette is six colours, not six shades
// of the sky.
//
// All CoreGraphics, no Vision, no model: a photo palette on a device is a
// histogram, and a histogram runs in a millisecond.

import UIKit

enum PhotoPalette {

    /// The photos on a page, for its "From the photos" swatches: the
    /// background picture first, then every photo in drawing order — not a
    /// code, which is black and white by design — each once. Every photo on
    /// the page, whatever is selected, as the Android twin gathers them.
    static func sources(on page: Page) -> [String] {
        var out: [String] = []
        if case .image(let src) = page.background { out.append(src) }
        for el in page.elements where el.type == .image {
            guard let src = el.src, !CodeGenerator.isCode(src) else { continue }
            out.append(src)
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// Several photos' palettes as one row: the first colour of each, then
    /// the second of each, and so on — so every photo gets a say before any
    /// gets two — each colour once, up to `limit`.
    static func merged(_ palettes: [[String]], limit: Int = 8) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        let longest = palettes.map(\.count).max() ?? 0
        for i in 0..<longest {
            for palette in palettes where i < palette.count {
                if seen.insert(palette[i]).inserted { out.append(palette[i]) }
                if out.count == limit { return out }
            }
        }
        return out
    }

    /// Up to eight colours drawn from the first four `images`.
    static func fromPhotos(_ images: [UIImage]) -> [String] {
        merged(images.prefix(4).map { extract(from: $0) })
    }

    /// The one colour a picture averages to: what letters full of a photo
    /// draw in where the effect needs a solid ink (Neon's glow, Hollow's
    /// stroke), and what a file writes where it cannot hold the photo.
    /// Clear pixels are left out; nothing is mid-grey. The Android twin's
    /// PhotoPalette.average, channel for channel.
    static func average(of image: UIImage) -> String {
        average(samples(of: image) ?? [])
    }

    /// The same over `pixels` as RGBA bytes.
    static func average(_ pixels: [UInt8]) -> String {
        var r = 0, g = 0, b = 0, n = 0
        var i = 0
        while i + 3 < pixels.count {
            if pixels[i + 3] >= 128 {
                r += Int(pixels[i]); g += Int(pixels[i + 1]); b += Int(pixels[i + 2])
                n += 1
            }
            i += 4
        }
        guard n > 0 else { return "#808080" }
        return hex(Double(r) / Double(n), Double(g) / Double(n), Double(b) / Double(n))
    }

    private static let averages = NSCache<NSString, NSString>()

    /// The average colour of the picture `src` names, worked out once per
    /// picture; nil when it cannot be opened.
    static func averageColour(_ src: String) -> String? {
        if let known = averages.object(forKey: src as NSString) { return known as String }
        guard let image = PhotoLibrary.resolve(src) else { return nil }
        let colour = average(of: image)
        averages.setObject(colour as NSString, forKey: src as NSString)
        return colour
    }

    /// The colours of the photo `el` shows, most prominent first, up to
    /// `max`, from the same 64-pixel read as every palette here (extract):
    /// what Apply colours to page takes. None for anything that is not a
    /// photo, or whose picture cannot be opened.
    static func top(_ el: Element, max: Int = 5) -> [String] {
        guard PhotoColours.offered(el), let src = el.src, let image = PhotoLibrary.resolve(src) else { return [] }
        return extract(from: image, count: max)
    }

    /// Up to `count` colours, most prominent first, each at least `minDistance`
    /// apart (in 0…255 RGB units, Euclidean) from every colour before it.
    static func extract(from image: UIImage, count: Int = 6,
                        minDistance: Double = 48) -> [String] {
        guard let pixels = samples(of: image) else { return [] }
        return extract(pixels, count: count, minDistance: minDistance)
    }

    /// The same over `pixels` as RGBA bytes: transparent pixels — alpha
    /// under `minAlpha` — are no colour the picture has. The Android twin's
    /// PhotoPalette.extract.
    static func extract(_ pixels: [UInt8], count: Int = 6, minDistance: Double = 48,
                        minAlpha: Int = 128) -> [String] {
        guard count > 0 else { return [] }

        // Five bits per channel: 32,768 bins, fine enough to tell a navy from
        // a black and coarse enough that a gradient collapses into a few.
        var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        var i = 0
        while i + 3 < pixels.count {
            let a = Int(pixels[i + 3])
            // Transparent pixels are not colours the picture has.
            if a >= minAlpha {
                let r = Int(pixels[i]), g = Int(pixels[i + 1]), b = Int(pixels[i + 2])
                let key = (r >> 3) << 10 | (g >> 3) << 5 | (b >> 3)
                var bin = bins[key] ?? (0, 0, 0, 0)
                bin.count += 1
                bin.r += r; bin.g += g; bin.b += b
                bins[key] = bin
            }
            i += 4
        }
        guard !bins.isEmpty else { return [] }

        // The bin's average, not its centre: a bin of pixels that all sit
        // near one edge should come out as that edge.
        let ranked = bins.values
            .sorted { $0.count > $1.count }
            .map { bin -> (Double, Double, Double) in
                let n = Double(bin.count)
                return (Double(bin.r) / n, Double(bin.g) / n, Double(bin.b) / n)
            }

        var chosen: [(Double, Double, Double)] = []
        for candidate in ranked where chosen.count < count {
            let farEnough = chosen.allSatisfy { picked in
                let dr = picked.0 - candidate.0, dg = picked.1 - candidate.1, db = picked.2 - candidate.2
                return (dr * dr + dg * dg + db * db).squareRoot() >= minDistance
            }
            if farEnough { chosen.append(candidate) }
        }
        return chosen.map { hex($0.0, $0.1, $0.2) }
    }

    // MARK: a logo's colours

    /// A logo's pixels count from this alpha up: its soft edges are its
    /// colours too, its clear background is not.
    static let logoMinAlpha = 32

    /// How much of a logo near-white or near-black must cover to be one of
    /// its colours rather than its background or its outline: more than
    /// this share of the pixels that count.
    static let logoEdgeShare = 0.2

    /// Near-white: every channel at least 235. Near-black: none above 20.
    static func isNearWhite(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { min(r, g, b) >= 235 }
    static func isNearBlack(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool { max(r, g, b) <= 20 }

    /// The brand colours a logo suggests, from its `pixels` as RGBA bytes
    /// (not premultiplied) — up to `count`, as `extract` ranks them; the
    /// rule both phones share (Tests/Fixtures/brand_logo_palette.json, the
    /// Android twin's PhotoPalette.logo): pixels with alpha under
    /// `logoMinAlpha` are left out; of the rest, near-white ones are left
    /// out unless they are more than `logoEdgeShare` of them, and so are
    /// near-black ones, so a white background or a thin black outline does
    /// not crowd out the brand's own colours, but a black-and-white logo
    /// keeps them.
    static func logo(_ pixels: [UInt8], count: Int = 6) -> [String] {
        var counted: [UInt8] = []
        var whites = 0, blacks = 0
        var i = 0
        while i + 3 < pixels.count {
            if Int(pixels[i + 3]) >= logoMinAlpha {
                counted.append(contentsOf: pixels[i...(i + 3)])
                if isNearWhite(pixels[i], pixels[i + 1], pixels[i + 2]) { whites += 1 }
                if isNearBlack(pixels[i], pixels[i + 1], pixels[i + 2]) { blacks += 1 }
            }
            i += 4
        }
        let total = counted.count / 4
        guard total > 0 else { return [] }
        let keepWhite = Double(whites) / Double(total) > logoEdgeShare
        let keepBlack = Double(blacks) / Double(total) > logoEdgeShare
        var kept: [UInt8] = []
        i = 0
        while i + 3 < counted.count {
            let r = counted[i], g = counted[i + 1], b = counted[i + 2]
            let dropped = (isNearWhite(r, g, b) && !keepWhite) || (isNearBlack(r, g, b) && !keepBlack)
            if !dropped { kept.append(contentsOf: counted[i...(i + 3)]) }
            i += 4
        }
        return extract(kept, count: count, minAlpha: logoMinAlpha)
    }

    /// A logo's colours from its picture, read at 128 pixels on its longer
    /// side, its colours as they are under their alpha.
    static func logo(from image: UIImage) -> [String] {
        guard let pixels = samples(of: image, maxEdge: 128) else { return [] }
        return logo(unpremultiplied(pixels))
    }

    /// RGBA bytes whose colours were multiplied by their alpha, as a bitmap
    /// context draws them, back to the colours themselves.
    static func unpremultiplied(_ pixels: [UInt8]) -> [UInt8] {
        var out = pixels
        var i = 0
        while i + 3 < out.count {
            let a = Int(out[i + 3])
            if a > 0 && a < 255 {
                for c in i..<(i + 3) { out[c] = UInt8(min(255, (Int(out[c]) * 255 + a / 2) / a)) }
            }
            i += 4
        }
        return out
    }

    /// The picture sampled at 64 pixels on its longer side, as 8-bit RGBA.
    ///
    /// Two steps on purpose. UIKit shrinks the picture into a standard-range
    /// 8-bit image first, whatever the source was — extended-range, 16-bit,
    /// P3, orientation-tagged — and only then is that plain image read
    /// through a bitmap context of a known layout. Reading the source
    /// straight into the context worked on one OS and not the next.
    private static func samples(of image: UIImage, maxEdge: Int = 64) -> [UInt8]? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = Double(maxEdge) / Double(max(size.width, size.height))
        let w = max(1, Int((size.width * min(scale, 1)).rounded()))
        let h = max(1, Int((size.height * min(scale, 1)).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        format.preferredRange = .standard
        let small = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            // Nearest neighbour, not a filtered shrink: a filter invents
            // colours along every edge — a row of red-blue purple where a
            // red block meets a blue one — and on a graphic those blends
            // can outnumber a real small feature. Sampling picks pixels the
            // picture actually has.
            ctx.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard let cg = small.cgImage else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? pixels : nil
    }

    private static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(format: "#%02x%02x%02x",
               Int(min(255, max(0, r.rounded()))),
               Int(min(255, max(0, g.rounded()))),
               Int(min(255, max(0, b.rounded()))))
    }
}
