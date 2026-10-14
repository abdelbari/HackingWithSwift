// Pictures into frames, as steps: Replace, a photo dragged onto a frame, a
// picture dropped onto one from another app, and photos picked while frames
// are selected. Which elements are frames is PhotoFrames' to say. And a
// grid's Spacing and Corners, laid out again live as their sliders move.

import CoreGraphics
import Foundation

extension DesignStore {

    /// A new picture in photo `id`'s frame, the crop reset as Replace resets
    /// it (Crop.replaced), as one step. Refused — said and felt — when the
    /// photo is locked; false when it could not be done.
    @discardableResult
    func replacePicture(_ id: String, with src: String) -> Bool {
        guard let photo = element(id), photo.type == .image else { return false }
        guard !photo.locked else {
            buzz(.reject)
            announce(tr("This photo is locked. Tap Unlock to replace it."), undoable: false)
            return false
        }
        applyToPage { page in
            if let i = page.elements.firstIndex(where: { $0.id == id }) {
                page.elements[i] = Crop.replaced(page.elements[i], src: src)
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
}
