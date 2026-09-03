// Photo import: decode the picture at the size we keep, not the size it was
// shot at.
//
// `UIImage(data:)` fully decodes the source before anything can be scaled, so
// importing a picture cost one uncompressed copy of the *camera's* bitmap. A
// 24 MP iPhone photo is 24,000,000 x 4 bytes = ~96 MB; the 48 MP mode is
// ~195 MB. Two of those alive at once — the decoded original and the scaled
// copy being drawn — is a jetsam kill on a small device, and it happened on
// the main actor, so the sheet froze on the way there.
//
// ImageIO can scale during decode instead: CGImageSourceCreateThumbnailAtIndex
// reads the source progressively and never materialises the full bitmap. At
// the 1600pt edge we store, peak allocation is under 10 MB regardless of what
// the camera produced.

import CoreGraphics
import ImageIO
import UIKit

enum ImageDownsampler {

    /// The picture's size *as displayed*, in pixels, read from the header
    /// alone — no decode.
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let source = makeSource(data),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Double,
              let height = props[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0
        else { return nil }
        // EXIF orientations 5-8 are the quarter turns, where the stored pixel
        // grid is transposed relative to what a viewer shows. Handing back the
        // stored size for those would give every camera portrait a landscape
        // frame on insert.
        let orientation = props[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let quarterTurned = (5...8).contains(orientation)
        return quarterTurned ? CGSize(width: height, height: width)
                             : CGSize(width: width, height: height)
    }

    /// Decode `data` no larger than `maxEdge` on its longest side. Sources
    /// already smaller come back at their own size — this never upscales.
    static func downsample(_ data: Data, maxEdge: CGFloat) -> UIImage? {
        guard maxEdge > 0, let source = makeSource(data) else { return nil }
        let options: [CFString: Any] = [
            // Without this a source carrying no embedded thumbnail returns
            // nothing at all, which is most PNGs and every screenshot.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Rotate during decode. Omitting it returns the stored pixel grid
            // with the EXIF tag dropped, so every photo taken in portrait
            // imports lying on its side — and unlike UIImage.imageOrientation
            // there is no tag left downstream to correct it with.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        return UIImage(cgImage: cg, scale: 1, orientation: .up)
    }

    /// Everything the store needs from a picked photo, produced in one pass.
    /// Deliberately not Sendable: it is built and consumed inside a single
    /// off-actor task, and the UIImage never crosses back.
    struct Prepared {
        /// Re-encoded at the stored size.
        let jpeg: Data
        /// The decoded image, to seed the media cache so the first draw after
        /// an insert does not go back to disk.
        let image: UIImage
        /// The original's displayed size, which is what gives the inserted
        /// element its aspect ratio.
        let natural: CGSize
    }

    static func prepare(_ data: Data, maxEdge: CGFloat = 1600,
                        quality: CGFloat = 0.85) -> Prepared? {
        autoreleasepool {
            guard let image = downsample(data, maxEdge: maxEdge),
                  let jpeg = image.jpegData(compressionQuality: quality)
            else { return nil }
            // Fall back to the decoded size if the header could not be read:
            // the ratio is the same either way, and a missing header should
            // not lose the import.
            let natural = pixelSize(data) ?? image.size
            return Prepared(jpeg: jpeg, image: image, natural: natural)
        }
    }

    private static func makeSource(_ data: Data) -> CGImageSource? {
        // kCGImageSourceShouldCache: false keeps the source from holding on to
        // a decoded copy of the original, which is the whole point here.
        CGImageSourceCreateWithData(data as CFData,
                                    [kCGImageSourceShouldCache: false] as CFDictionary)
    }
}
