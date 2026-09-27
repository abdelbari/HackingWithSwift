// Pictures into frames, as steps: Replace, a photo dragged onto a frame, a
// picture dropped onto one from another app, and photos picked while frames
// are selected. Which elements are frames is PhotoFrames' to say.

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
            announce("This photo is locked. Tap Unlock to replace it.", undoable: false)
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
}
