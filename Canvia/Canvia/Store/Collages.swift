// Pictures into frames, as steps: Replace, a photo dragged onto a frame, a
// picture dropped onto one from another app, and photos picked while frames
// are selected. Which elements are frames is PhotoFrames' to say. And a
// grid's Spacing and Corners, laid out again live as their sliders move;
// its Layout, moved to another with its pictures handed on; its dividers,
// dragged on the canvas; and Detach image, a picture taken out of a frame
// or cell as a photo of its own.

import CoreGraphics
import Foundation

extension DesignStore {

    /// A new picture in photo `id`'s frame, the crop reset as Replace resets
    /// it (Crop.replaced), as one step. Refused — said and felt — when the
    /// photo is locked; false when it could not be done.
    @discardableResult
    func replacePicture(_ id: String, with src: String) -> Bool {
        // A photo, or a shape whose fill picture is gone (Replace from its chip).
        guard let photo = element(id), photo.type == .image || MissingMedia.isMissing(photo) else { return false }
        guard !photo.locked else {
            buzz(.reject)
            announce(tr("This photo is locked. Tap Unlock to replace it."), undoable: false)
            return false
        }
        let gone = Set(MissingMedia.sources(of: photo).filter { !MissingMedia.exists($0) })
        applyToPage { page in
            if let i = page.elements.firstIndex(where: { $0.id == id }) {
                // A picture whose file is gone keeps its look (MissingMedia)
                // — a shape's fill picture too.
                page.elements[i] = gone.isEmpty ? Crop.replaced(page.elements[i], src: src)
                    : MissingMedia.replaced(page.elements[i], src: src, gone: gone)
            }
        }
        return true
    }

    /// The frames picked pictures go into, in the order they fill: the one
    /// empty frame selected, or the empty cells of a selected grid, top to
    /// bottom and left to right. Empty when the selection has none.
    var framesToFill: [String] {
        PhotoFrames.fillOrder(selectedElements).map(\.id)
    }

    /// The frame photo `dragged` would go into if let go at `point`, or nil
    /// when there is none there or it is not a photo that can go into one.
    func frameDropTarget(at point: CGPoint, dragging dragged: String) -> String? {
        guard let photo = element(dragged), PhotoFrames.canDrop(photo) else { return nil }
        return PhotoFrames.target(at: point, in: page.elements, excluding: dragged)?.id
    }

    /// A photo dragged onto frame `target` and let go: see PhotoFrames.dropped.
    /// Recorded in the drag's own open step, so the move and the drop are one
    /// Undo; felt, and the frame ends selected. False when there was nothing
    /// to drop, and the drag is left to end as an ordinary move.
    @discardableResult
    func dropIntoFrame(_ dragged: String, onto target: String, home: CGPoint) -> Bool {
        guard let next = PhotoFrames.dropped(page.elements, dragged: dragged, onto: target, home: home) else {
            return false
        }
        beginGesture()
        page.elements = next
        commit()
        // Selected once the step is closed: selecting can end a step of its
        // own, which must not split this one.
        selection = [target]
        buzz(.confirm)
        return true
    }

    // MARK: grid spacing and corners

    /// The selection when it is exactly one grid's cells — a grid laid out
    /// with a `grid` key, every cell of it and nothing else — with its
    /// layout, cells in cell order; nil otherwise (PhotoGrids.grid(of:)).
    var selectedGrid: (layout: PhotoGrids.Layout, cells: [Element])? {
        guard selection.count > 1 else { return nil }
        return PhotoGrids.grid(of: selectedElements)
    }

    /// Whether the selected grid can be laid out again: none of its cells
    /// keeps its place, as relaying moves and resizes every one.
    var selectedGridCanRelay: Bool {
        guard let grid = selectedGrid else { return false }
        return !grid.cells.contains { $0.holdsPlace }
    }

    /// The selected grid's spacing set to `spacing`, live, as its slider is
    /// dragged (see `relayGrid`).
    func setGridSpacingTransient(_ spacing: Double) {
        guard let grid = selectedGrid else { return }
        relayGrid(grid, spacing: spacing, corners: PhotoGrids.corners(of: grid.cells))
    }

    /// The selected grid's corners set to `corners` percent, live, as its
    /// slider is dragged (see `relayGrid`).
    func setGridCornersTransient(_ corners: Double) {
        guard let grid = selectedGrid else { return }
        relayGrid(grid, spacing: PhotoGrids.spacing(of: grid.cells), corners: corners)
    }

    /// `grid` laid out again within the box round it now, with `spacing`
    /// between its cells and its corners `corners` percent of each cell's
    /// shorter side, as the Android twin lays it, and any line joined to a
    /// cell laid again with it. The slider closes the step on release, so
    /// each release is one Undo. Nothing when a cell keeps its place.
    private func relayGrid(_ grid: (layout: PhotoGrids.Layout, cells: [Element]), spacing: Double, corners: Double) {
        guard selectedGridCanRelay else { return }
        let laid = PhotoGrids.relaid(grid.layout, cells: grid.cells, gutter: spacing, corners: corners)
        beginGesture()
        for cell in laid {
            if let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == cell.id }) {
                design.pages[pageIndex].elements[i] = cell
            }
        }
        Connectors.resolve(&design.pages[pageIndex])
    }

    // MARK: dividers

    /// The box round the selected grid's cells; nil for no grid.
    var selectedGridBox: CGRect? {
        selectedGrid.map { PhotoGrids.bounds(of: $0.cells) }
    }

    /// The selected grid's dividers — each lattice line no cell runs across
    /// (PhotoGrids.dividers) — with where its handle stands on the page:
    /// the middle of the line. Only while the whole of a level grid that
    /// can be laid out again is selected, as on the Android twin — and none
    /// on a locked page, whose cells stay where they are.
    var gridDividers: [(divider: PhotoGrids.GridDivider, at: CGPoint)] {
        guard !isPageLocked, selectedGridCanRelay, let grid = selectedGrid, !grid.cells.contains(where: { $0.rotation != 0 }) else {
            return []
        }
        let box = PhotoGrids.bounds(of: grid.cells)
        return PhotoGrids.dividers(grid.layout, splits: PhotoGrids.splits(of: grid.cells)).map { divider in
            let at = divider.vertical
                ? CGPoint(x: box.minX + divider.at * box.width, y: box.midY)
                : CGPoint(x: box.midX, y: box.minY + divider.at * box.height)
            return (divider, at)
        }
    }

    /// Divider `index` of the selected grid (gridDividers) taken to `to`, a
    /// share of the grid's side: the line moved there — no cell narrower
    /// than eight percent, snapped to the middle (PhotoGrids.dragged) — and
    /// the whole grid laid out again on it, live; letting go closes the
    /// step (commit). Where the line now stands, as a share, for the
    /// readout; nil when there is no such divider.
    @discardableResult
    func dragGridDivider(_ index: Int, to: Double) -> Double? {
        guard !isPageLocked, selectedGridCanRelay, let grid = selectedGrid else { return nil }
        let custom = PhotoGrids.splits(of: grid.cells)
        let dividers = PhotoGrids.dividers(grid.layout, splits: custom)
        guard dividers.indices.contains(index) else { return nil }
        let divider = dividers[index]
        let splits = PhotoGrids.dragged(grid.layout, splits: custom, divider: divider, to: to)
            ?? PhotoGrids.ownSplits(grid.layout)
        let laid = PhotoGrids.relaid(grid.layout, cells: grid.cells, gutter: PhotoGrids.spacing(of: grid.cells),
                                     corners: PhotoGrids.corners(of: grid.cells), splits: splits)
        beginGesture()
        for cell in laid {
            if let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == cell.id }) {
                design.pages[pageIndex].elements[i] = cell
            }
        }
        Connectors.resolve(&design.pages[pageIndex])
        let lines = divider.vertical ? splits.x : splits.y
        return lines.indices.contains(divider.index) ? lines[divider.index] : divider.at
    }

    // MARK: layout and detach

    /// The selected grid moved to `layout` — its box, spacing, corners and
    /// group kept, its pictures handed on in fill order, any the new layout
    /// has no cell for set free beside it (PhotoGrids.relayout) — as one
    /// undo step, the new cells selected. Not when a cell keeps its place,
    /// nor on a locked page.
    func changeGridLayout(to layout: PhotoGrids.Layout) {
        guard selectedGridCanRelay, let grid = selectedGrid, grid.layout.id != layout.id else { return }
        guard !refusesLockedPage() else { return }
        let out = PhotoGrids.relayout(grid.cells, to: layout)
        let ids = Set(grid.cells.map(\.id))
        applyToPage { page in
            // The new cells where the old ones stood in the stack, the freed
            // photos over them.
            let at = page.elements.firstIndex { ids.contains($0.id) } ?? 0
            var rest = page.elements.filter { !ids.contains($0.id) }
            rest.insert(contentsOf: out, at: min(at, rest.count))
            page.elements = rest
        }
        selection = Set(out.prefix(layout.cells.count).map(\.id))
        buzz(.confirm)
    }

    /// Whether the one thing selected is a filled frame or cell a picture
    /// can be taken out of (PhotoFrames.canDetach).
    var canDetachImage: Bool {
        guard let el = singleSelection else { return false }
        return PhotoFrames.canDetach(el, among: page.elements)
    }

    /// Detach image: the selected frame's or cell's picture made a free
    /// photo of its own over the frame, which is left empty, as one undo
    /// step; the photo is selected.
    func detachImage() {
        guard let el = singleSelection, !refusesLockedPage(),
              let out = PhotoFrames.detached(page.elements, id: el.id) else { return }
        applyToPage { $0.elements = out }
        if let at = out.firstIndex(where: { $0.id == el.id }), at + 1 < out.count { selection = [out[at + 1].id] }
        buzz(.confirm)
    }
}
