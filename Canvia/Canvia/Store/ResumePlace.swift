// Where the editor was in a design, kept on this phone for the next time it
// opens (LastPlace): the page, and the zoom unless the view was at fit —
// for a Doc, how far down it was scrolled. Never part of the design, so
// keeping it touches neither its edit time nor its versions.

import Foundation

extension DesignStore {

    /// This page and the zoom, kept for the design — as the editor leaves a
    /// page, closes or goes into the background.
    func rememberPlace() {
        guard design.pages.indices.contains(pageIndex) else { return }
        let place = LastPlace.Place(page: design.pages[pageIndex].id, zoom: LastPlace.keptZoom(zoom, fit: fitZoom),
                                    scroll: nil, t: LastPlace.now)
        LastPlace.remember(design.id, place)
    }

    /// A Doc's place: how far down its blocks the view is, 0 to 1.
    func rememberDocPlace(scroll: Double) {
        let first = design.pages.first?.id ?? ""
        let place = LastPlace.Place(page: first, zoom: nil, scroll: min(max(scroll, 0), 1), t: LastPlace.now)
        LastPlace.remember(design.id, place)
    }

    /// The design opened where it was left, while Settings ▸ Editing's
    /// "Open designs where I left off" is on: its page made the one worked
    /// (LastPlace.pageIndex). What it gives back is the place, whose zoom
    /// (none at fit) and scroll the editor brings back itself.
    @discardableResult
    func resumePlace() -> LastPlace.Place? {
        guard LastPlace.resumes(), let place = LastPlace.place(for: design.id) else { return nil }
        let index = LastPlace.pageIndex(design, place: place)
        if index != pageIndex {
            pageIndex = index
            selection.removeAll()
        }
        return place
    }
}
