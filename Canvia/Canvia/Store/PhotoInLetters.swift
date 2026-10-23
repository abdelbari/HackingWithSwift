// A photo inside a text's letters: poured in from the Text controls' Photo
// chip, the colour sheet's Photo fill row or a photo dropped on the box
// ("Fill the letters?"), kept as the box's textFill with the shape fill's
// keys (Paint.photo, PhotoFills), and adjusted by Adjust photo — a drag
// moving the focus, a pinch the zoom, each one undo step. The Android
// twin's EditorViewModel, rule for rule.

import CoreGraphics
import Foundation

/// A photo dropped over a selected text box: which box, the picture, and
/// where it would land on the page as a photo of its own.
struct LetterFillOffer: Equatable {
    var id: String
    var src: String
    var frame: CGRect
}

extension DesignStore {

    static let fillLettersQuestion = tr("Fill the letters?")
    static let fillLettersNote = tr("The photo goes inside the letters of the selected text, or stays on the page as it is.")
    static let fillLetters = tr("Fill the letters")
    static let keepPhoto = tr("Keep the photo")
    static let adjustPhotoTitle = tr("Adjust photo")
    static let adjustPhotoNote = tr("Drag the photo to move it, pinch to zoom it.")
    static let removePhoto = tr("Remove photo")
    static let photoCannotOpen = tr("This photo can't be opened, so it can't be adjusted.")

    /// The selected text box a photo let go at `point` may fill: one text
    /// box selected, unlocked, under the finger. nil, and the photo lands
    /// on the page as any does.
    func letterFillTarget(at point: CGPoint) -> Element? {
        guard let el = singleSelection, el.type == .text, !el.locked, Geometry.hits(el, point: point) else { return nil }
        return el
    }

    /// `src` poured into every selected, unlocked text box's letters, as one
    /// step: a photo looked at from its middle, just covering the box.
    func pourPhoto(_ src: String) {
        guard !refusesLockedPage() else { return }
        updateSelected { el in
            guard el.type == .text else { return }
            el.textFill = Paint.photo(src)
        }
    }

    /// The photo taken out of the selected texts' letters, which draw in
    /// their colour again. One step.
    func removePhotoFromLetters() {
        updateSelected { el in
            guard el.type == .text, el.textFill?.isPhoto == true else { return }
            el.textFill = nil
        }
    }

    /// The offer taken: the photo into the box's letters.
    func acceptLetterFill() {
        guard let offer = letterFillOffer else { return }
        letterFillOffer = nil
        guard let el = element(offer.id), el.type == .text, !el.locked else { return }
        selection = [offer.id]
        pourPhoto(offer.src)
        buzz(.confirm)
    }

    /// The offer declined: the photo on the page where it was let go.
    func declineLetterFill() {
        guard let offer = letterFillOffer else { return }
        letterFillOffer = nil
        var el = Element.image(offer.src, w: Double(offer.frame.width), h: Double(offer.frame.height))
        el.x = Double(offer.frame.minX)
        el.y = Double(offer.frame.minY)
        add(el, centered: false)
    }

    // MARK: adjust photo

    /// Adjust photo opened for the text `id`, when its letters hold a photo
    /// this phone can open — or why it cannot be, said.
    @discardableResult
    func startPhotoAdjust(_ id: String) -> Bool {
        guard let el = element(id), el.type == .text, let fill = el.textFill, fill.isPhoto, !refusesLockedPage() else {
            return false
        }
        guard !el.locked else {
            announce(tr("This photo is locked. Tap Unlock to edit it."), undoable: false)
            return false
        }
        guard let image = PhotoLibrary.resolve(fill.src), image.size.width > 0, image.size.height > 0 else {
            announce(Self.photoCannotOpen, undoable: false)
            return false
        }
        selection = [id]
        photoAdjustTarget = id
        return true
    }

    /// The photo in the box's letters slid by `dx`, `dy` of the box's own
    /// units from `start`, the paint as the drag began — the focus moving
    /// against the picture's slack (PhotoFills.moved) — shown as the finger
    /// moves; the drag's end is one step (endPhotoAdjust).
    func movePhotoInLetters(from start: Paint, dx: Double, dy: Double) {
        guard let id = photoAdjustTarget, let el = element(id), let image = PhotoLibrary.resolve(start.src) else { return }
        let moved = PhotoFills.moved(start, imageW: Double(image.size.width), imageH: Double(image.size.height),
                                     boxW: el.w, boxH: el.h, dx: dx, dy: dy)
        updateSelectedTransient { e in
            guard e.id == id else { return }
            e.textFill = moved
        }
    }

    /// The photo in the box's letters zoomed `factor` times closer than
    /// `start`, the paint as the pinch began (PhotoFills.zoomed).
    func zoomPhotoInLetters(from start: Paint, by factor: Double) {
        guard let id = photoAdjustTarget else { return }
        let zoomed = PhotoFills.zoomed(start, by: factor)
        updateSelectedTransient { e in
            guard e.id == id else { return }
            e.textFill = zoomed
        }
    }

    /// A drag or a pinch let go: what it moved, as one step.
    func endPhotoAdjust() {
        if hasPendingChanges { commit() }
    }

    /// The paint the letters of the text Adjust photo is open for hold now.
    var adjustedPhoto: Paint? {
        guard let id = photoAdjustTarget, let fill = element(id)?.textFill, fill.isPhoto else { return nil }
        return fill
    }
}
