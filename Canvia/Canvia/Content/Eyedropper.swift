// Sample a colour from the rendered design.
//
// The colour picker offers what the document declares; the eyedropper
// offers what the document shows — the exact tone of a photo's sky, the
// blend where a gradient meets a shape. The page is rendered once and read
// at the tapped point.

import UIKit

enum Eyedropper {

    /// The colour at a unit point of the image, as a hex string. Alpha is
    /// ignored: a picked colour is a paint, and paints are opaque.
    static func color(in image: CGImage, at unit: CGPoint) -> String? {
        guard image.width > 0, image.height > 0 else { return nil }
        let x = min(max(Int(unit.x * Double(image.width)), 0), image.width - 1)
        let y = min(max(Int(unit.y * Double(image.height)), 0), image.height - 1)
        var pixel: [UInt8] = [0, 0, 0, 0]
        let drawn = pixel.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .none
            // Row 0 of a CGImage is the top; the context's origin is its
            // bottom-left, so the image is placed so that pixel (x, y) lands
            // on the one cell.
            ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        return String(format: "#%02x%02x%02x", Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}
