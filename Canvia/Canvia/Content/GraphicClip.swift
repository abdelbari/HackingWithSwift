// Cropping graphics, as Canva crops an illustration: a shape, an icon, a
// sticker or a group — the generated graphics are groups of shapes — shows
// only part of itself. The part is the element's `clip` (ClipBox), shares
// of its own box; for a group, the same box on every member, in shares of
// the group's frame (Geometry.groupFrame, turned with the group). Drawing
// works in the member's own box (shown), clipped there before its turn and
// flip, as every renderer, export and hit test does on both phones. A
// photo keeps its own crop: its `clip` key is its playback, so a group
// with a photo in it is not cropped as a group. The Android twin's
// GraphicClip, with the same rows.

import CoreGraphics
import Foundation

enum GraphicClip {

    /// Whether `el` alone can be cropped as a graphic: a shape — an icon, a
    /// drawn line of the pen, an imported graphic — or a sticker.
    static func croppable(_ el: Element) -> Bool {
        el.type == .shape || el.type == .sticker
    }

    /// Whether `members`, a whole group, can be cropped as one: two or more,
    /// none a photo or clip, none locked or held in place.
    static func croppableGroup(_ members: [Element]) -> Bool {
        members.count >= 2 && !members.contains { $0.type == .image || $0.holdsPlace }
    }

    /// The part of `el` shown, in its own box — from its top left, before
    /// its flip and turn — in page units; nil for the whole of it, and for
    /// a group's member whose crop is still in its group's frame (shown
    /// puts it in its own box first).
    static func ownRect(_ el: Element) -> CGRect? {
        guard let box = el.clipBox, el.group == nil || el.clipIsOwn else { return nil }
        return CGRect(x: box.x * el.w, y: box.y * el.h, width: max(0, box.w) * el.w, height: max(0, box.h) * el.h)
    }

    /// The part of `el` shown, upright on the page as its frame is: its
    /// frame, or the crop in it, flipped as it is drawn. What a hit test
    /// turns the point into.
    static func visibleFrame(_ el: Element) -> CGRect {
        guard let r = ownRect(el) else { return el.frame }
        let x = el.flipH ? el.w - Double(r.maxX) : Double(r.minX)
        let y = el.flipV ? el.h - Double(r.maxY) : Double(r.minY)
        return CGRect(x: el.x + x, y: el.y + y, width: r.width, height: r.height)
    }

    /// `elements` as drawn: each group member's crop, kept in its group's
    /// frame, put into its own box — the box round the crop's corners as
    /// the member sees them, cut to the member; nothing at all of a member
    /// wholly outside it. Exact for a member turned with its group, as the
    /// graphics are; the box round it for one turned otherwise. The rest
    /// as they are.
    static func shown(_ elements: [Element]) -> [Element] {
        guard elements.contains(where: { $0.clipBox != nil && $0.group != nil && !$0.clipIsOwn }) else { return elements }
        var frames: [String: Geometry.GroupFrame] = [:]
        var out = elements
        for i in out.indices {
            guard let box = out[i].clipBox, let group = out[i].group, !out[i].clipIsOwn else { continue }
            let frame: Geometry.GroupFrame
            if let known = frames[group] {
                frame = known
            } else {
                let members = elements.filter { $0.group == group }
                frame = Geometry.groupFrame(members, angle: members.first?.groupTurn ?? 0)
                frames[group] = frame
            }
            out[i].clipBox = ownBox(out[i], clip: box, frame: frame)
            out[i].clipIsOwn = true
        }
        return out
    }

    /// The crop `clip`, in shares of `frame`, as shares of `el`'s own box.
    static func ownBox(_ el: Element, clip: ClipBox, frame: Geometry.GroupFrame) -> ClipBox {
        let upright = frame.upright
        let corners = [(clip.x, clip.y), (clip.x + clip.w, clip.y), (clip.x + clip.w, clip.y + clip.h), (clip.x, clip.y + clip.h)]
            .map { corner -> CGPoint in
                let (fx, fy) = corner
                let p = CGPoint(x: Double(upright.minX) + fx * Double(upright.width),
                                y: Double(upright.minY) + fy * Double(upright.height))
                let onPage = frame.angle == 0 ? p : Geometry.rotate(p, around: frame.center, degrees: frame.angle)
                return WordLinks.inBox(onPage, of: el)
            }
        let xs = corners.map { Double($0.x) }, ys = corners.map { Double($0.y) }
        guard el.w > 0, el.h > 0, let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return ClipBox(x: 0, y: 0, w: 0, h: 0)
        }
        let left = min(max(minX, 0), el.w), right = min(max(maxX, 0), el.w)
        let top = min(max(minY, 0), el.h), bottom = min(max(maxY, 0), el.h)
        return ClipBox(x: left / el.w, y: top / el.h, w: (right - left) / el.w, h: (bottom - top) / el.h)
    }

    /// The crop that keeps `window`, a box in page units inside `frame` —
    /// the element's own box or the group's frame upright — as shares of
    /// it; nil for the whole (ClipBox.kept).
    static func clip(window: CGRect, in frame: CGRect) -> ClipBox? {
        guard frame.width > 0, frame.height > 0 else { return nil }
        return ClipBox.kept(ClipBox(x: Double((window.minX - frame.minX) / frame.width),
                                    y: Double((window.minY - frame.minY) / frame.height),
                                    w: Double(window.width / frame.width),
                                    h: Double(window.height / frame.height)))
    }

    /// `clip` as a box in page units inside `frame`; the whole frame for
    /// none.
    static func window(_ clip: ClipBox?, in frame: CGRect) -> CGRect {
        guard let clip else { return frame }
        return CGRect(x: Double(frame.minX) + clip.x * Double(frame.width), y: Double(frame.minY) + clip.y * Double(frame.height),
                      width: clip.w * Double(frame.width), height: clip.h * Double(frame.height))
    }
}
