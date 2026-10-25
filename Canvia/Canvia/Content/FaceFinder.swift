// The faces Face retouch smooths, found once on the device as the effect is
// turned on (FaceRetouch): Vision's face landmarks, each face's box and the
// outlines of its eyes, brows and lips — the parts kept sharp — as shares
// of the picture, top left first, to four places. The Android twin finds
// faces by their eyes (FaceRetouch.fromEyes) and keeps an eye band instead.

import CoreGraphics
import UIKit
import Vision

enum FaceFinder {

    /// The faces in `image`, largest first; none when Vision finds none or
    /// cannot read it. Slow enough to be called off the main thread.
    static func faces(in image: UIImage) -> [FaceRetouch.Face] {
        guard image.size.width >= 1, image.size.height >= 1, let cg = SubjectMask.upright(image) else { return [] }
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return [] }
        let found = (request.results ?? []).compactMap { face(of: $0) }
        return found.sorted { $0.w * $0.h > $1.w * $1.h }
    }

    /// One observation as a face: Vision's box, whose origin is the bottom
    /// left, turned to the top left; its landmarks' points the same way.
    private static func face(of observation: VNFaceObservation) -> FaceRetouch.Face? {
        let box = observation.boundingBox.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !box.isNull, box.width > 0, box.height > 0 else { return nil }
        let keep = kept(observation.landmarks).map { region in
            region.map { p in
                CGPoint(x: FaceRetouch.fourth(Double(box.minX + p.x * box.width)),
                        y: FaceRetouch.fourth(Double(1 - (box.minY + p.y * box.height))))
            }
        }
        return FaceRetouch.Face(x: FaceRetouch.fourth(Double(box.minX)), y: FaceRetouch.fourth(Double(1 - box.maxY)),
                                w: FaceRetouch.fourth(Double(box.width)), h: FaceRetouch.fourth(Double(box.height)),
                                keep: keep)
    }

    /// The parts kept sharp — each eye, each brow and the lips — as points
    /// in the face's box, 0…1 from its bottom left; those Vision did not
    /// find left out, and a part of fewer than three points too.
    private static func kept(_ landmarks: VNFaceLandmarks2D?) -> [[CGPoint]] {
        guard let landmarks else { return [] }
        let regions = [landmarks.leftEye, landmarks.rightEye, landmarks.leftEyebrow, landmarks.rightEyebrow,
                       landmarks.outerLips]
        return regions.compactMap { region in
            guard let region, region.pointCount >= 3 else { return nil }
            return region.normalizedPoints
        }
    }
}
