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

// Pages put in a new order — dragged in the organiser's grid or along the
// pages bar, several ticked pages at once, or moved by VoiceOver's actions —
// as the Android twin orders them (its core PageMoves).
enum PageOrder {

    /// `pages` with the pages `ids` lifted out, in the order they stood, and
    /// put down together in the gap `toIndex`: a gap counted in the pages as
    /// they were before the move, 0 before the first and `pages.count` after
    /// the last — as List's move(fromOffsets:toOffset:) counts it — and kept
    /// to that range. Ids of no page are passed over; with none, the pages
    /// are as they were.
    static func moved(_ pages: [Page], ids: Set<String>, toIndex: Int) -> [Page] {
        let lifted = pages.filter { ids.contains($0.id) }
        guard !lifted.isEmpty else { return pages }
        let gap = min(max(toIndex, 0), pages.count)
        let before = pages[..<gap].filter { !ids.contains($0.id) }
        let after = pages[gap...].filter { !ids.contains($0.id) }
        return before + lifted + after
    }

    /// The gap a finger at `point` is over, among thumbnails at `frames` by
    /// index: beside the nearest thumbnail — before it in its left half,
    /// after it in its right — the lower index on a tie. Nil with none.
    static func gap(at point: CGPoint, frames: [Int: CGRect]) -> Int? {
        let nearest = frames.min { a, b in
            let da = distance(point, a.value), db = distance(point, b.value)
            return da == db ? a.key < b.key : da < db
        }
        guard let nearest else { return nil }
        return point.x < nearest.value.midX ? nearest.key : nearest.key + 1
    }

    /// How far `point` is from `rect`: 0 inside it.
    private static func distance(_ point: CGPoint, _ rect: CGRect) -> Double {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return Double(hypot(dx, dy))
    }

    /// The organiser's columns at a width in points: 2 under 400, 3 under
    /// 700, else 4.
    static func columns(forWidth width: Double) -> Int {
        width < 400 ? 2 : width < 700 ? 3 : 4
    }

    /// Which way a drag scrolls at the ends of a strip or a grid `length`
    /// long, the finger at `position` along it: -1 within `margin` of the
    /// start, 1 within it of the end, else 0.
    static func edgeScroll(_ position: Double, length: Double, margin: Double) -> Int {
        guard length > margin * 2 else { return 0 }
        if position < margin { return -1 }
        if position > length - margin { return 1 }
        return 0
    }

    /// A blank page to put in at `index`: the background of the page to its
    /// left — of the first page, when it goes in first — and nothing else of
    /// it.
    static func blank(at index: Int, in pages: [Page]) -> Page {
        let left = min(max(index - 1, 0), pages.count - 1)
        return pages.indices.contains(left) ? Page(background: pages[left].background) : Page()
    }

    /// VoiceOver's moves for a page, by name, as the Android twin names them.
    enum Step: String, CaseIterable {
        case earlier = "Move page earlier"
        case later = "Move page later"
        case start = "Move to start"
        case end = "Move to end"
    }

    /// The gap `step` moves page `index` of `count` to; nil when it is
    /// already there — the first page is moved no earlier, the last no
    /// later.
    static func gap(_ step: Step, from index: Int, count: Int) -> Int? {
        switch step {
        case .earlier, .start: return index > 0 ? (step == .start ? 0 : index - 1) : nil
        case .later, .end: return index < count - 1 ? (step == .end ? count : index + 2) : nil
        }
    }
}
