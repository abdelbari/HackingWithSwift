// A carousel's slides (PageSplit): the "Slides: 3" stepper in a page's
// More menu, which makes the page a slide wider or narrower each step.
// The seams themselves are drawn by the canvas, and cut by the export.

import Foundation

extension DesignStore {

    /// The page on screen's carousel slides, or nil for a page that is not
    /// cut.
    var slides: PageSplit? { page.split }

    /// The carousel on screen given `columns` slides (PageSplit.resized):
    /// its width a slide's times that many, everything on it where it was,
    /// as one step. False, with nothing recorded, on a locked page, one
    /// that is not cut, or one that has that many already. The Android
    /// twin's DesignStore.setSlides.
    @discardableResult
    func setSlides(_ columns: Int) -> Bool {
        guard !isPageLocked, let next = PageSplit.resized(design, pageId: page.id, columns: columns) else {
            return false
        }
        apply { $0 = next }
        return true
    }

    /// The stepper: refused, and said, on a locked page; felt; the view
    /// fitted to the page's new width.
    func stepSlides(to columns: Int) {
        guard !refusesLockedPage() else { return }
        guard setSlides(columns) else { return }
        buzz(.tick)
        requestCanvas(.fit)
    }
}
