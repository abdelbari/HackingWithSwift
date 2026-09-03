// QR codes, drawn on device.
//
// A design tool without one sends people to a website to make a picture and
// then back to import it — for something Core Image has generated locally
// since iOS 7. Menus, posters, business cards and event flyers all want one,
// which is most of what this app is for.
//
// Codes are not stored: the payload is the element's src ("qr:<text>"), so a
// code is regenerated from the document rather than kept as a file. That
// keeps them editable, keeps documents self-contained, and keeps resolution
// synchronous and deterministic, which is what lets ElementView stay
// Equatable on its element.

import CoreImage
import UIKit

enum CodeGenerator {

    /// Element sources for a code carry the payload inline.
    static let prefix = "qr:"

    static func source(for payload: String) -> String { prefix + payload }

    static func payload(from source: String) -> String? {
        source.hasPrefix(prefix) ? String(source.dropFirst(prefix.count)) : nil
    }

    /// Generated codes are small and cheap, but they are re-resolved on every
    /// canvas render, so they are worth keeping.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 32
        return c
    }()

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// A black-on-white QR code for `payload`, `side` points on each edge.
    ///
    /// Nothing here is configurable on purpose. A tinted or low-contrast code
    /// is a code that does not scan, and a design tool that lets you make one
    /// has helped you print a thousand useless flyers.
    static func qr(_ payload: String, side: CGFloat = 512) -> UIImage? {
        guard !payload.isEmpty, side >= 1 else { return nil }
        let key = "\(Int(side))|\(payload)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        guard let data = payload.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        // Medium recovers ~15% of a damaged or partly covered code, which is
        // the level almost every printed code in the world uses.
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let modules = ciContext.createCGImage(output, from: output.extent) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        // A code needs a quiet zone around it or a scanner cannot find its
        // edges; the generator emits only a hairline of one. 8% a side is
        // comfortably past the four modules the spec asks for at every size
        // a payload this app can hold produces.
        let quiet = (side * 0.08).rounded()
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                            format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            // Nearest-neighbour: a QR scaled with smoothing has grey edges on
            // every module, and a scanner thresholds those into the wrong bit.
            ctx.cgContext.interpolationQuality = .none
            ctx.cgContext.draw(modules, in: CGRect(x: quiet, y: quiet,
                                                   width: side - quiet * 2,
                                                   height: side - quiet * 2))
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
