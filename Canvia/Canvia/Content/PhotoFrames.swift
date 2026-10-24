// Frames and grid cells as places a picture goes.
//
// A collage is made by putting photos into frames, not by lining photos up:
// a photo dragged over a frame or a grid's cell goes into it, a picture
// dropped in from another app lands in the frame it is let go over, and
// photos picked while a grid is selected fill its empty cells. What counts
// as a frame is decided here, once, for all of those, as the Android twin
// decides it.

import CoreGraphics
import Foundation

enum PhotoFrames {

    /// Whether a picture can be put into `el`: an unlocked image that is an
    /// empty frame, or has a frame's shape, or is a decorative frame's
    /// window (`photoFrame`) full or not, or is a cell of a grid — grouped
    /// with at least one other image. A plain free photo is not one, or
    /// every photo dragged across another would swallow it. Nor is a code,
    /// which a picture would replace, and a code grouped with a logo does
    /// not make the logo a cell, as on the Android twin.
    static func isFrameLike(_ el: Element, among elements: [Element]) -> Bool {
        guard el.type == .image, !el.locked, !isCode(el) else { return false }
        if isEmpty(el) || el.maskShapeId != nil || el.photoFrame == true { return true }
        guard let group = el.group else { return false }
        return elements.contains { $0.id != el.id && $0.type == .image && !isCode($0) && $0.group == group }
    }

    /// Whether `el` is a code, whose source is its payload.
    private static func isCode(_ el: Element) -> Bool {
        CodeGenerator.isCode(el.src)
    }

    /// A frame with no picture in it yet.
    static func isEmpty(_ el: Element) -> Bool {
        el.type == .image && (el.src ?? "").isEmpty
    }

    /// Whether `el` can be dragged into a frame: one unlocked photo or clip.
    /// Not a code — a frame covers and crops what it holds, and a cropped
    /// code no longer scans — nor an empty frame, which has nothing to give.
    static func canDrop(_ el: Element) -> Bool {
        guard el.type == .image, !el.locked, let src = el.src, !src.isEmpty else { return false }
        return !CodeGenerator.isCode(src)
    }

    /// The topmost frame under `point`, never `excluding` — the thing being
    /// dragged, which is always under the finger.
    static func target(at point: CGPoint, in elements: [Element], excluding id: String?) -> Element? {
        elements.last { $0.id != id && Geometry.hits($0, point: point) && isFrameLike($0, among: elements) }
    }

    /// Whether `el`'s picture can be taken out as a photo of its own: a
    /// filled, unlocked frame-like photo — a grid's cell, a shaped frame, a
    /// decorative frame's window.
    static func canDetach(_ el: Element, among elements: [Element]) -> Bool {
        el.type == .image && !el.locked && !isEmpty(el) && isFrameLike(el, among: elements)
    }

    /// `elements` with the picture taken out of the frame `id` (one that
    /// `canDetach`) as a free photo of its own: at the frame's box, with its
    /// crop, look, corners and border kept, in no group, out of the grid and
    /// the frame's shape, laid just above the frame; the frame itself left
    /// empty, as Replace with nothing leaves it. nil when there is nothing
    /// to detach. The Android twin's PhotoFrames.detached.
    static func detached(_ elements: [Element], id: String) -> [Element]? {
        guard let at = elements.firstIndex(where: { $0.id == id }), canDetach(elements[at], among: elements) else {
            return nil
        }
        let frame = elements[at]
        var free = frame
        free.id = UID.make()
        free.group = nil
        free.subgroups = nil
        free.groupTurn = nil
        free.grid = nil
        free.maskShapeId = nil
        free.photoFrame = nil
        var out = elements
        out[at] = Crop.replaced(frame, src: nil)
        out.insert(free, at: at + 1)
        return out
    }

    /// Top to bottom, then left to right, by centre: the order photos fill a
    /// grid's cells in.
    static func readingOrder(_ elements: [Element]) -> [Element] {
        elements.sorted { a, b in
            a.center.y != b.center.y ? a.center.y < b.center.y : a.center.x < b.center.x
        }
    }

    /// Where pictures picked while `selected` is the selection go: its
    /// unlocked empty frames, in reading order — the one frame selected, or
    /// a grid's empty cells. None, and the pictures are added as photos.
    static func fillOrder(_ selected: [Element]) -> [Element] {
        readingOrder(selected.filter { isEmpty($0) && !$0.locked })
    }

    /// A photo dragged onto a frame and let go: the frame takes its picture,
    /// crop reset as Replace resets it. A photo that is itself a frame or a
    /// cell swaps — it takes the frame's picture, or is left empty, and goes
    /// back to `home`, where it was before the drag — so a grid's cells trade
    /// pictures; a free photo is used up. nil when there is no such drop to
    /// make, and the drag is an ordinary move.
    static func dropped(_ elements: [Element], dragged: String, onto target: String,
                        home: CGPoint) -> [Element]? {
        guard dragged != target,
              let from = elements.firstIndex(where: { $0.id == dragged }),
              let to = elements.firstIndex(where: { $0.id == target }) else { return nil }
        let photo = elements[from], frame = elements[to]
        guard canDrop(photo), isFrameLike(frame, among: elements) else { return nil }
        var out = elements
        out[to] = Crop.replaced(frame, src: photo.src)
        if isFrameLike(photo, among: elements) {
            var back = Crop.replaced(photo, src: isEmpty(frame) ? nil : frame.src)
            back.x = home.x
            back.y = home.y
            out[from] = back
        } else {
            out.remove(at: from)
        }
        return out
    }
}
