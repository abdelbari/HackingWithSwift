// Expand, from crop mode (ExpandSheet): a still photo grown to a new shape
// round the picture it has, the new border made from it (PhotoExpand), off
// the main thread with a ring while it is made, written as a new upload — a
// PNG — and the photo pointed at it as one step. A photo expanded already
// goes back with Undo expand, or is made again from its original with
// Change fill; one grown to the page's shape offers Set as background. As
// the Android twin's expandPhoto.

import Foundation
import UIKit

extension DesignStore {

    /// Crop mode's Expand: the crop kept, and the photo's Expand sheet asked
    /// for (`expandingPhoto`). A clip, an animated or moving picture or a
    /// code is refused, with a word.
    func openExpand() {
        guard let photo = cropElement ?? singleSelection else { return }
        guard Self.isStillPhoto(photo) else {
            buzz(.reject)
            announce(tr("Only a still photo can be expanded."), undoable: false)
            return
        }
        finishCrop()
        expandedToPage = nil
        expandingPhoto = photo.id
    }

    /// Photo `id` grown to `ratio` (PhotoExpand.ratios; the page's own for
    /// PhotoExpand.page) with `mode`'s border.
    @MainActor
    func expandPhoto(_ id: String, ratio: String, mode: String) {
        let aspect = ratio == PhotoExpand.page
            ? PhotoExpand.pageAspect(pageWidth, pageHeight)
            : PhotoExpand.ratios.first { $0.key == ratio }?.aspect
        guard let aspect else { return }
        expand(id, mode: mode, toPage: ratio == PhotoExpand.page) { _, _ in aspect }
    }

    /// The expanded photo `id` made again from its original with `mode`'s
    /// border, the same shape.
    @MainActor
    func changeExpandFill(_ id: String, mode: String) {
        guard let origin = element(id)?.expandedFrom else { return }
        expand(id, mode: mode, toPage: false) { w, h in PhotoExpand.aspect(of: origin, w, h) }
    }

    /// The work of both: from the picture the photo was first expanded from,
    /// if it was; the result kept only if the photo is still on this page,
    /// unlocked, and the page too.
    @MainActor
    private func expand(_ id: String, mode: String, toPage: Bool, aspect: @escaping (Int, Int) -> Double) {
        guard !expandBusy, let photo = element(id), Self.isStillPhoto(photo), !refusesLockedPage(),
              let original = photo.expandedFrom?.src ?? photo.src,
              let picture = PhotoLibrary.resolve(original) else { return }
        expandBusy = true
        Task { @MainActor in
            let made = await Task.detached(priority: .userInitiated) { () -> (src: String, plan: PhotoExpand.Plan)? in
                guard let grown = PhotoExpand.grownImage(picture, aspect: aspect, mode: mode),
                      let src = MediaStore.storeTransparent(grown.image) else { return nil }
                Uploads.record(source: src)
                return (src, grown.plan)
            }.value
            self.expandBusy = false
            guard let made else {
                self.buzz(.reject)
                self.announce(tr("The photo already has that shape"), undoable: false)
                return
            }
            // Moved off the page or locked meanwhile: kept as it is.
            guard self.element(id)?.locked == false, !self.isPageLocked else { return }
            self.selection = [id]
            self.updateSelected { el in
                el = PhotoExpand.expanded(el, src: made.src, original: original, plan: made.plan, mode: mode)
            }
            self.expandedToPage = toPage ? id : nil
            self.buzz(.confirm)
        }
    }

    /// Undo expand: photo `id` back to the picture it was expanded from,
    /// its frame the part of it the original covered, as one step.
    func undoExpand(_ id: String) {
        guard let photo = element(id), !photo.locked, let back = PhotoExpand.undone(photo),
              !refusesLockedPage() else { return }
        selection = [id]
        updateSelected { $0 = back }
        expandedToPage = nil
        buzz(.confirm)
    }

    /// Set as background, after a Page expand: the photo behind the page.
    @MainActor
    func expandedAsBackground(_ id: String) {
        guard element(id) != nil else { return }
        expandingPhoto = nil
        expandedToPage = nil
        useAsBackground(id)
    }
}
