// A photo poured into a text's letters, or a shape: which part of the
// picture shows.
//
// The paint is the shape fill's ("kind" image, "src") with "focusX",
// "focusY" and "zoom" beside it (Paint.photo); `window` says where the
// picture is drawn to fill the box through them — the rule both phones
// share, which the canvas, the SVG and the PowerPoint all draw the letters
// by — and Adjust photo's drag and pinch move the focus and the zoom
// (moved, zoomed). The Android twin's PhotoFills, sum for sum.

import CoreGraphics
import Foundation
import UIKit

enum PhotoFills {

    /// Where a picture `imageW` by `imageH` is drawn to fill a box `boxW` by
    /// `boxH` through `paint`'s focus and zoom, in the box's own space: the
    /// picture scaled to just cover the box, times the zoom, and slid so
    /// that the share of it at focusX, focusY sits at the same share of the
    /// box — focus 0.5 centres it, 0 shows its left or top edge, 1 its
    /// right or bottom. Nothing to draw by is the box itself.
    static func window(imageW: Double, imageH: Double, boxW: Double, boxH: Double, paint: Paint) -> CGRect {
        guard imageW > 0, imageH > 0, boxW > 0, boxH > 0 else { return CGRect(x: 0, y: 0, width: boxW, height: boxH) }
        let scale = max(boxW / imageW, boxH / imageH) * paint.zoomFactor
        let w = imageW * scale
        let h = imageH * scale
        let focus = paint.focus
        // Plus zero, so a picture no wider than the box sits at 0, not -0.
        return CGRect(x: (boxW - w) * focus.x + 0, y: (boxH - h) * focus.y + 0, width: w, height: h)
    }

    /// The same for `image` over `box`.
    static func window(_ image: UIImage, box: CGSize, paint: Paint) -> CGRect {
        window(imageW: Double(image.size.width), imageH: Double(image.size.height),
               boxW: Double(box.width), boxH: Double(box.height), paint: paint)
    }

    /// `paint` with its focus moved by `dx`, `dy` in the box's space — the
    /// Adjust photo drag, which moves the picture with the finger — for a
    /// picture `imageW` by `imageH` in a box `boxW` by `boxH`: the focus
    /// held between 0 and 1, the picture never leaving a gap.
    static func moved(_ paint: Paint, imageW: Double, imageH: Double, boxW: Double, boxH: Double,
                      dx: Double, dy: Double) -> Paint {
        guard let src = paint.src, paint.isPhoto else { return paint }
        let at = window(imageW: imageW, imageH: imageH, boxW: boxW, boxH: boxH, paint: paint)
        let slackX = Double(at.width) - boxW
        let slackY = Double(at.height) - boxH
        let focus = paint.focus
        let x = slackX > 1e-9 ? min(max(focus.x - dx / slackX, 0), 1) : focus.x
        let y = slackY > 1e-9 ? min(max(focus.y - dy / slackY, 0), 1) : focus.y
        return Paint.photo(src, focusX: x, focusY: y, zoom: paint.zoomFactor)
    }

    /// `paint` zoomed `factor` times closer — the Adjust photo pinch — never
    /// under 1 or past Paint.maxZoom, its focus kept.
    static func zoomed(_ paint: Paint, by factor: Double) -> Paint {
        guard let src = paint.src, paint.isPhoto else { return paint }
        let focus = paint.focus
        return Paint.photo(src, focusX: focus.x, focusY: focus.y, zoom: min(max(paint.zoomFactor * factor, 1), Paint.maxZoom))
    }

    /// A photo as it is stored, for a file to carry whole: its bytes, its
    /// type ("jpeg" or "png") and its pixels — one of your uploads from its
    /// file, a library picture as a JPEG — or nil when it cannot be read.
    static func stored(_ src: String) -> (data: Data, type: String, size: CGSize)? {
        if src.hasPrefix("media:") {
            let id = String(src.dropFirst("media:".count))
            for ext in MediaStore.pictureExtensions {
                let url = MediaStore.directory.appendingPathComponent("\(id).\(ext)")
                guard let data = try? Data(contentsOf: url), let size = ImageDownsampler.pixelSize(data) else { continue }
                return (data, ext == "png" ? "png" : "jpeg", size)
            }
            return nil
        }
        guard let image = PhotoLibrary.resolve(src), let data = image.jpegData(compressionQuality: 0.9) else { return nil }
        return (data, "jpeg", CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale))
    }

    /// The type a stored photo is written as in a deck or an SVG: "png" for
    /// an upload kept as one, else "jpeg".
    static func storedType(_ src: String) -> String {
        guard src.hasPrefix("media:") else { return "jpeg" }
        let id = String(src.dropFirst("media:".count))
        let png = MediaStore.directory.appendingPathComponent("\(id).png")
        return FileManager.default.fileExists(atPath: png.path) ? "png" : "jpeg"
    }
}
