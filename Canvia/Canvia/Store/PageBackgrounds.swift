// The page's background from your own pictures, and back out again: a photo
// on the page made the background, and a background picture detached as a
// photo to move, crop and frame like any other. As the Android twin does
// both.

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
        // A locked page keeps its background; the pick itself is refused
        // (setBackground), once, rather than every turn of the wheel.
        guard !isPageLocked else { return }
        beginGesture()
        page.background = background
    }

    /// Whether photo `el` can become the page's background: unlocked, with a
    /// picture in it — not an empty frame — and a still, or a generated
    /// loop, which plays behind the page as it does. A clip or an animated
    /// picture would stop moving, and a code would be cropped to the page
    /// and stop scanning.
    static func canBecomeBackground(_ el: Element) -> Bool {
        guard el.type == .image, !el.locked, let src = el.src, !src.isEmpty else { return false }
        return !VideoStore.isVideo(src) && !AnimStore.isAnim(src) && !CodeGenerator.isCode(src)
    }

    /// Whether a photo shows its picture other than plain: a filter,
    /// adjustments, a duotone, an effect, a crop, a frame's shape, a flip,
    /// straightening, rounded corners or parts erased with the brush. A
    /// background draws its picture plain, so a photo like this is baked
    /// into a picture of its own first.
    static func hasLook(_ el: Element) -> Bool {
        PhotoEdits.any(el) || Crop.isAdjusted(el) || el.maskShapeId != nil
            || el.flipH || el.flipV || (el.radius ?? 0) > 0 || el.mask?.strokes.isEmpty == false
    }

    /// Photo `id` becomes the page's background and leaves the page, as one
    /// step. A photo with a look is baked first, so the background shows
    /// what the photo showed: drawn here, then encoded and written off the
    /// main actor, as the Android twin bakes it, and made the background
    /// only if the photo is still on this page and may still become it.
    /// Returns the baking, when there is one, for a caller to wait on.
    @MainActor
    @discardableResult
    func useAsBackground(_ id: String) -> Task<Void, Never>? {
        guard let photo = element(id), Self.canBecomeBackground(photo), let src = photo.src else {
            buzz(.reject)
            return nil
        }
        guard Self.hasLook(photo) else {
            takeAsBackground(id, picture: src)
            return nil
        }
        guard let image = Self.bakedImage(photo) else {
            buzz(.reject)
            announce(tr("Couldn't make that photo the background"), undoable: false)
            return nil
        }
        return Task { @MainActor in
            let stored = await Task.detached(priority: .userInitiated) { DesignStore.storeBaked(image) }.value
            // The photo may have gone meanwhile, or the page with it; it is
            // this photo, on this page, that becomes the background.
            guard let picture = stored, let now = self.element(id), DesignStore.canBecomeBackground(now) else {
                self.buzz(.reject)
                self.announce(tr("Couldn't make that photo the background"), undoable: false)
                return
            }
            self.takeAsBackground(id, picture: picture)
        }
    }

    /// Photo `id` off the page and `picture` behind it, as one step.
    @MainActor
    private func takeAsBackground(_ id: String, picture: String) {
        applyToPage { page in
            page.elements.removeAll { $0.id == id }
            page.background = .image(picture)
        }
        selection.remove(id)
        buzz(.confirm)
    }

    /// The page's background picture taken out as a photo covering the whole
    /// page and its print bleed, filling them as the background did — so the
    /// crop holds still and the band stays filled — behind everything else
    /// and selected; the page is left white. One step, as on the Android twin.
    func detachBackground() {
        guard case .image(let src) = page.background else { return }
        let b = Bleed.of(design)
        var photo = Element.image(src, w: pageWidth + 2 * b, h: pageHeight + 2 * b)
        photo.x = -b
        photo.y = -b
        applyToPage { page in
            page.elements.insert(photo, at: 0)
            page.background = .color("#ffffff")
        }
        selection = [photo.id]
        buzz(.confirm)
    }

    /// The photo drawn as it shows on the page — its look, crop, frame,
    /// flips, straightening and corners — as a new picture to store (see
    /// storeBaked); not where it sits, its turn, fade, shadow, blend or
    /// border, which belong to the element and not to the picture. Drawn
    /// through the canvas's own view, as the SVG export draws a picture, so
    /// it is what the editor showed. nil when the picture cannot be read.
    @MainActor
    static func bakedImage(_ el: Element) -> UIImage? {
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
        return renderer.uiImage
    }

    /// A baked picture stored, off the main actor, where its encode and
    /// write belong; nil when it cannot be.
    static func storeBaked(_ image: UIImage) -> String? {
        guard let cg = image.cgImage else { return nil }
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
