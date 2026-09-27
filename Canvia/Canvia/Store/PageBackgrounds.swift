// The page's background from your own pictures, and back out again: a photo
// on the page made the background, and a background picture detached as a
// photo to move, crop and frame like any other. As the Android twin does
// both, so a design made either way opens the same on either phone.

import SwiftUI
import UIKit

extension DesignStore {

    /// The page's background as one step — none when it already is that.
    func setBackground(_ background: Background) {
        guard page.background != background else { return }
        applyToPage { $0.background = background }
    }

    /// The page's background changed live, as the colour wheel turns; the
    /// colour sheet closes the step when it goes.
    func setBackgroundTransient(_ background: Background) {
        beginGesture()
        page.background = background
    }

    /// Whether photo `el` can become the page's background: unlocked, with a
    /// picture in it — not an empty frame — and a still. A clip would stop
    /// moving, and a code would be cropped to the page and stop scanning.
    static func canBecomeBackground(_ el: Element) -> Bool {
        guard el.type == .image, !el.locked, let src = el.src, !src.isEmpty else { return false }
        return !VideoStore.isVideo(src) && CodeGenerator.payload(from: src) == nil
    }

    /// Whether a photo shows its picture other than plain: a filter,
    /// adjustments, a duotone, a crop, a frame's shape, a flip, straightening
    /// or rounded corners. A background draws its picture plain, so a photo
    /// like this is baked into a picture of its own first.
    static func hasLook(_ el: Element) -> Bool {
        PhotoEdits.any(el) || Crop.isAdjusted(el) || el.maskShapeId != nil
            || el.flipH || el.flipV || (el.radius ?? 0) > 0
    }

    /// Photo `id` becomes the page's background and leaves the page, as one
    /// step. A photo with a look is baked first, so the background shows
    /// what the photo showed.
    @MainActor
    func useAsBackground(_ id: String) {
        guard let photo = element(id), Self.canBecomeBackground(photo), let src = photo.src else {
            buzz(.reject)
            return
        }
        let picture: String? = Self.hasLook(photo) ? Self.bakedPicture(photo) : src
        guard let picture else {
            buzz(.reject)
            announce("Couldn't make that photo the background", undoable: false)
            return
        }
        applyToPage { page in
            page.elements.removeAll { $0.id == id }
            page.background = .image(picture)
        }
        selection.remove(id)
        buzz(.confirm)
    }

    /// The page's background picture taken out as a photo covering the whole
    /// page, filling it as the background did, behind everything else and
    /// selected; the page is left white. One step.
    func detachBackground() {
        guard case .image(let src) = page.background else { return }
        var photo = Element.image(src, w: pageWidth, h: pageHeight)
        photo.x = 0
        photo.y = 0
        applyToPage { page in
            page.elements.insert(photo, at: 0)
            page.background = .color("#ffffff")
        }
        selection = [photo.id]
        buzz(.confirm)
    }

    /// The photo drawn as it shows on the page — its look, crop, frame,
    /// flips, straightening and corners — and stored as a new picture; not
    /// where it sits, its turn, fade, shadow, blend or border, which belong
    /// to the element and not to the picture. Drawn through the canvas's own
    /// view, as the SVG export draws a picture, so it is what the editor
    /// showed. nil when the picture cannot be read or stored.
    @MainActor
    static func bakedPicture(_ el: Element) -> String? {
        guard el.w > 0, el.h > 0, let picture = PhotoLibrary.resolve(el.src) else { return nil }
        var upright = el
        upright.x = 0
        upright.y = 0
        upright.rotation = 0
        upright.opacity = 1
        upright.shadow = nil
        upright.blendMode = nil
        upright.stroke = nil
        upright.strokeWidth = nil
        let renderer = ImageRenderer(content: ElementView(element: upright).frame(width: el.w, height: el.h))
        renderer.scale = bakeScale(el, picture: picture.size)
        renderer.isOpaque = false
        guard let image = renderer.uiImage, let cg = image.cgImage else { return nil }
        // A frame's shape or round corners leave the corners clear, which
        // only PNG keeps; anything square goes as a photograph.
        return ImageDownsampler.hasTransparentPixels(cg)
            ? MediaStore.storeTransparent(image) : MediaStore.storeOpaque(image)
    }

    /// Pixels per page unit for baking photo `el`: its picture's own, as the
    /// frame shows it, so the background is as sharp as the photo was — but
    /// no more than a picked photo keeps on its long side.
    static func bakeScale(_ el: Element, picture: CGSize) -> Double {
        guard el.w > 0, el.h > 0, picture.width > 0, picture.height > 0 else { return 1 }
        let base = el.cropFit == true
            ? Crop.fit(w: el.w, h: el.h, image: picture)
            : Crop.cover(w: el.w, h: el.h, image: picture)
        let natural = 1 / (base * max(1, el.cropScale ?? 1))
        let ceiling = Double(ImageDownsampler.keptEdge) / max(el.w, el.h)
        return max(min(natural, ceiling), 0.1)
    }
}
