// Apply colours to page, from the photo's More menu and the selection
// bubble: the page on screen recoloured from the selected photo's palette
// (PhotoColours.applied), one step named "Apply photo colours" a tap, each
// tap turning the palette one place further round for a new combination.
// A locked page is refused, and said, with Unlock.

import Foundation

extension DesignStore {

    /// The one thing selected, when it offers Apply colours to page.
    var photoForColours: Element? {
        singleSelection.flatMap { PhotoColours.offered($0) ? $0 : nil }
    }

    /// Apply colours to page, once: the selected photo's colours on this
    /// page, turned photoColourTurn places, as one step; the next tap turns
    /// them one further.
    func applyPhotoColours() {
        guard let photo = photoForColours, !refusesLockedPage() else { return }
        let palette = PhotoPalette.top(photo)
        guard !palette.isEmpty else {
            buzz(.reject)
            announce(tr("This photo can't be opened, so its colours can't be read."), undoable: false)
            return
        }
        let next = PhotoColours.applied(page, palette: palette, turn: photoColourTurn, photo: photo.id)
        photoColourTurn += 1
        guard next != page else { return }
        namedStep = tr("Apply photo colours")
        applyToPage { $0 = next }
    }
}
