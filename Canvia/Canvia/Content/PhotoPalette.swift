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

    /// Up to `count` colours, most prominent first, each at least `minDistance`
    /// apart (in 0…255 RGB units, Euclidean) from every colour before it.
    static func extract(from image: UIImage, count: Int = 6,
                        minDistance: Double = 48) -> [String] {
        guard count > 0, let pixels = samples(of: image) else { return [] }

        // Five bits per channel: 32,768 bins, fine enough to tell a navy from
        // a black and coarse enough that a gradient collapses into a few.
        var bins: [Int: (count: Int, r: Int, g: Int, b: Int)] = [:]
        var i = 0
        while i + 3 < pixels.count {
            let a = Int(pixels[i + 3])
            // Transparent pixels are not colours the picture has.
            if a >= 128 {
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

    /// The picture at 64 pixels on its longer side, as straight 8-bit RGBA.
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
        let small = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { _ in
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
