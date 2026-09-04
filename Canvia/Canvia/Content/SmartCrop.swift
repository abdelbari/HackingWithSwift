// Where the subject of a photo is.
//
// Vision's attention saliency answers "where would a person look first",
// which is what a crop should keep. The answer is a point in unit
// coordinates, which is exactly what the crop's focus already is — so
// "focus on the subject" is one request and two assignments.

import UIKit
import Vision

enum SmartCrop {

    /// The centre of the salient region, in unit coordinates with the
    /// origin top-left like everything else in the app. nil when Vision
    /// finds nothing it would call a subject.
    static func focalPoint(in image: UIImage) -> CGPoint? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        guard let observation = request.results?.first as? VNSaliencyImageObservation,
              let objects = observation.salientObjects, !objects.isEmpty else { return nil }
        // One box around everything salient: two faces should be framed
        // together, not the crop yanked to whichever won by a hair.
        var union = objects[0].boundingBox
        for o in objects.dropFirst() { union = union.union(o.boundingBox) }
        // Vision's y runs upward from the bottom.
        return CGPoint(x: min(1, max(0, union.midX)), y: min(1, max(0, 1 - union.midY)))
    }
}
