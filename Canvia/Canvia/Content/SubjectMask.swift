// Background removal, on device.
//
// This is the one thing people open Canva for and then hit a paywall on. It
// needs no server and no subscription: Vision has shipped a foreground
// instance segmenter since iOS 17, the same model the Photos app lifts a
// subject with. It runs on the neural engine in well under a second for the
// 1600pt images we store.
//
// The output keeps the source's full extent rather than cropping to the
// subject (croppedToInstancesExtent: false), so the cutout drops into the
// element's existing frame unchanged — the picture loses its background and
// nothing on the canvas moves.

import CoreImage
import UIKit
import Vision

enum SubjectMask {

    enum Failure: LocalizedError {
        case noSubject
        case failed

        var errorDescription: String? {
            switch self {
            case .noSubject:
                return "Couldn't find a subject in this picture. It works best on a photo with a clear foreground."
            case .failed:
                return "Couldn't separate the background from this picture."
            }
        }
    }

    /// Every CIContext holds its own render pipeline and caches, so building
    /// one per call is most of the cost of a cutout.
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// The subject of `image` on a transparent background, at the original
    /// size. Throws rather than returning nil so the caller can say which of
    /// the two failures it was — "no subject here" is a different message
    /// from "that didn't work".
    static func cutout(_ image: UIImage) throws -> UIImage {
        // A zero-sized image would take the redraw path below into a
        // zero-sized renderer, which is undefined rather than merely empty.
        guard image.size.width >= 1, image.size.height >= 1,
              let source = upright(image) else { throw Failure.failed }

        let handler = VNImageRequestHandler(cgImage: source, orientation: .up)
        let request = VNGenerateForegroundInstanceMaskRequest()
        do {
            try handler.perform([request])
        } catch {
            throw Failure.failed
        }

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else {
            throw Failure.noSubject
        }

        let masked: CVPixelBuffer
        do {
            masked = try observation.generateMaskedImage(
                ofInstances: observation.allInstances,
                from: handler,
                croppedToInstancesExtent: false)
        } catch {
            throw Failure.failed
        }

        let ci = CIImage(cvPixelBuffer: masked)
        guard let out = ciContext.createCGImage(ci, from: ci.extent) else {
            throw Failure.failed
        }
        return UIImage(cgImage: out, scale: 1, orientation: .up)
    }

    /// Vision reads the pixel grid, not UIImage's orientation flag, so an
    /// image still carrying one has to be redrawn first — otherwise the mask
    /// comes back for a rotated version of the picture and the cutout is
    /// nonsense. Everything the media store holds is already upright, so this
    /// is a guard against a future source rather than a cost paid today.
    private static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let redrawn = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return redrawn.cgImage
    }
}
