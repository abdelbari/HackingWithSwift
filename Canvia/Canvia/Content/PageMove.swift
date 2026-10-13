// Move to page: the selection taken off this page and put on another, where
// it sat — the way Canva lets a thing be carried from one page to the next,
// rather than Cut, a change of page and Paste, which put it 24 further down
// every time. The Android twin moves by the same rules (its core PageMove),
// and both phones' tests hold the same rows.

import CoreGraphics
import Foundation

enum PageMove {

    /// The ids that go when `selection` moves to another page: the
    /// selection, every member of a group any of it belongs to, and every
    /// connector joined to any of that — less whatever holds its place (a
    /// lock, whole or of its position), which stays.
    static func moving(_ elements: [Element], selection: Set<String>) -> Set<String> {
        var ids = selection.intersection(elements.map(\.id))
        let groups = Set(elements.filter { ids.contains($0.id) }.compactMap(\.group))
        for el in elements where el.group.map(groups.contains) == true { ids.insert(el.id) }
        for el in elements where el.type == .line {
            if el.connectFrom.map(ids.contains) == true || el.connectTo.map(ids.contains) == true {
                ids.insert(el.id)
            }
        }
        for el in elements where el.holdsPlace { ids.remove(el.id) }
        return ids
    }

    /// `elements`, from a page of size `from`, placed on one of size `to`:
    /// just where they were when the two are the same size; otherwise all
    /// moved together — so they keep their places relative to each other —
    /// by the least shift that brings the box round them inside the new
    /// page, flush with its left or top edge on an axis where the box is
    /// bigger than the page. Never scaled.
    static func clamped(_ elements: [Element], from: CGSize, to: CGSize) -> [Element] {
        guard from != to, !elements.isEmpty else { return elements }
        let box = Geometry.union(elements.map(Geometry.aabb))
        let dx = shift(box.minX, box.maxX, within: to.width)
        let dy = shift(box.minY, box.maxY, within: to.height)
        guard dx != 0 || dy != 0 else { return elements }
        return elements.map { el in
            var e = el
            e.x += dx
            e.y += dy
            return e
        }
    }

    /// How far a span from `low` to `high` moves to lie inside 0…`size`.
    static func shift(_ low: Double, _ high: Double, within size: Double) -> Double {
        if high - low > size || low < 0 { return -low }
        if high > size { return size - high }
        return 0
    }
}
