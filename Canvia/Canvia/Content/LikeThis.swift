// More like this, swapped in: a graphic, sticker, icon or shape replaced by
// one of ElementSearch.similar's, in place, as Canva swaps one — the
// Android twin's LikeThis, rule for rule, with the same rows
// (LikeThisTests).
//
// What it keeps of what it replaces (`old`, one element or a graphic's
// whole group):
// - its box: the new thing at its own shape, as large as fits in the old
//   box, centred in it;
// - its turn and its opacity, those of the old thing's first part;
// - its entrance, exit, timing and link, from the old first part, given to
//   each new part;
// - its main colour: the new thing's first colour (ColourSwap.colours)
//   becomes the old thing's first, the rest left as drawn;
// - its group, when it was one and the new thing is several parts; a new
//   group for several parts that replace one;
// - its id, when one part replaces one part, so it stays selected and
//   named.

import Foundation

enum LikeThis {

    static func replaced(_ old: [Element], with fresh: [Element]) -> [Element] {
        guard let first = old.first, !fresh.isEmpty else { return old }
        let o = bounds(old)
        let f = bounds(fresh)
        let scale = f.width <= 0 || f.height <= 0 ? 1 : min(o.width / f.width, o.height / f.height)
        let cx = o.x + o.width / 2
        let cy = o.y + o.height / 2
        let fcx = f.x + f.width / 2
        let fcy = f.y + f.height / 2
        let turn = first.rotation * Double.pi / 180
        let group: String?
        if fresh.count < 2 {
            group = old.count == 1 ? first.group : nil
        } else if old.count >= 2, first.group != nil, old.allSatisfy({ $0.group == first.group }) {
            group = first.group
        } else {
            group = UID.make("grp")
        }
        var placed = fresh.map { el -> Element in
            // Its middle, scaled about the new thing's, then turned with the
            // old thing about the old box's middle.
            let mx = (el.x + el.w / 2 - fcx) * scale
            let my = (el.y + el.h / 2 - fcy) * scale
            let tx = cx + mx * cos(turn) - my * sin(turn)
            let ty = cy + mx * sin(turn) + my * cos(turn)
            var out = el
            if old.count == 1 && fresh.count == 1 { out.id = first.id }
            out.w = el.w * scale
            out.h = el.h * scale
            out.x = tx - out.w / 2
            out.y = ty - out.h / 2
            out.rotation = el.rotation + first.rotation
            out.opacity = first.opacity
            out.group = group
            out.animation = first.animation
            out.exitAnimation = first.exitAnimation
            out.timing = first.timing
            out.link = first.link
            out.strokeWidth = el.strokeWidth.map { $0 * scale }
            return out
        }
        if let from = ColourSwap.colours(placed).first, let to = ColourSwap.colours(old).first, from != to {
            placed = ColourSwap.swapped(placed, from: from, to: to)
        }
        return placed
    }

    /// The box round `elements`, turns aside.
    private static func bounds(_ elements: [Element]) -> (x: Double, y: Double, width: Double, height: Double) {
        let minX = elements.map(\.x).min() ?? 0
        let minY = elements.map(\.y).min() ?? 0
        let maxX = elements.map { $0.x + $0.w }.max() ?? 0
        let maxY = elements.map { $0.y + $0.h }.max() ?? 0
        return (minX, minY, max(0, maxX - minX), max(0, maxY - minY))
    }
}
