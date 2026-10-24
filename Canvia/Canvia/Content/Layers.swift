// The Layers sheet's working parts, apart from the sheet: a name of your
// own for an element, the rows a page lists — a group folded into one
// "Group (n)" row — how a drag among those rows reorders the page, and what
// overlaps the selection. Pure functions of the elements, so the order a
// drag leaves is testable.

import Foundation
import CoreGraphics

/// A name typed for an element, kept as the element's `layerName`.
enum LayerNames {

    /// The longest name an element takes, in characters.
    static let maxLength = 60

    /// A name as typed, made fit to keep: trimmed and cut to `maxLength`;
    /// nil when nothing is left, so a cleared name gives back the one
    /// ElementNames makes and leaves no key behind.
    static func cleaned(_ typed: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let cut = String(trimmed.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return cut.isEmpty ? nil : cut
    }

    /// A name read from a file: as it is, so a design from the other phone
    /// comes back unchanged — or nil when there is nothing to it.
    static func kept(_ name: String) -> String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : name
    }

    /// The element's own name, when it has one.
    static func custom(of el: Element) -> String? {
        el.layerName.flatMap(kept)
    }
}

enum LayerRows {

    /// What the sheet lists: everything, or what overlaps the selection.
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case overlapping = "Overlapping"
        var id: String { rawValue }
    }

    /// One row of the sheet, top-most first. `depth` is how many opened
    /// groups it is listed under, each one indent.
    enum Row: Identifiable, Equatable {
        /// An element on its own, or — `member` — one of an opened group's,
        /// listed under its group row.
        case element(Element, member: Bool, depth: Int = 0)
        /// Two or more elements sharing `group` at one level — the outermost,
        /// or one inside an opened group — top-most first.
        case group(String, members: [Element], depth: Int = 0)

        var id: String {
            switch self {
            case .element(let el, _, _): return el.id
            case .group(let id, _, _): return "group:" + id
            }
        }

        /// The elements the row stands for, top-most first.
        var elements: [Element] {
            switch self {
            case .element(let el, _, _): return [el]
            case .group(_, let members, _): return members
            }
        }

        /// How many opened groups the row is listed under.
        var depth: Int {
            switch self {
            case .element(_, _, let depth), .group(_, _, let depth): return depth
            }
        }

        /// A row that moves when dragged: one of the page's own, not inside
        /// an opened group — its member rows and the groups inside it move
        /// with it, the whole subtree as one block.
        var movable: Bool { depth == 0 }

        /// A row whose handle drags: one that moves, or an element listed
        /// in an opened group, which a drag takes out of it (LayerRows.drop).
        var draggable: Bool {
            if movable { return true }
            if case .element = self { return true }
            return false
        }
    }

    /// What a drag of rows does: reorders the page (moved), puts the one
    /// element dragged into a group, or takes it out of the group it is
    /// listed in.
    enum Drop: Equatable {
        case reorder
        case join(String)
        case leave
    }

    /// The drag of the rows at `source` to before row `destination` — the
    /// List's own offsets. One element's row dropped among an opened
    /// group's rows — anywhere from just under its header to just above its
    /// last row — joins the innermost such group (Groups.addedToGroup). A
    /// member's row dropped past its group's last row, or above its header,
    /// leaves it (Groups.removedFromGroup). Anything else — a group's row,
    /// several rows, a row dropped where it was — reorders as ever. The
    /// Android twin's LayerRows.drop, the same rows.
    static func drop(_ rows: [Row], from source: IndexSet, to destination: Int) -> Drop {
        guard source.count == 1, let i = source.first, rows.indices.contains(i),
              case .element(let el, let member, _) = rows[i],
              destination != i, destination != i + 1 else { return .reorder }
        let target = groupSpanning(rows, gap: destination)
        if let target, !Groups.chain(el).contains(target) { return .join(target) }
        guard member, let own = listedUnder(rows, at: i), target != own else { return .reorder }
        return .leave
    }

    /// For VoiceOver's Move into group above: the group whose row is the
    /// nearest above row `at` at its own level, past that group's opened
    /// rows; nil when that row is an element's, or there is none.
    static func groupAbove(_ rows: [Row], at i: Int) -> String? {
        guard rows.indices.contains(i) else { return nil }
        let depth = rows[i].depth
        var k = i - 1
        while k >= 0 && rows[k].depth > depth { k -= 1 }
        guard k >= 0, rows[k].depth == depth, case .group(let id, _, _) = rows[k] else { return nil }
        return id
    }

    /// The innermost opened group whose rows — from just under its header
    /// to its last row — hold the gap before row `gap`.
    private static func groupSpanning(_ rows: [Row], gap: Int) -> String? {
        var found: String?
        for h in rows.indices {
            guard case .group(let id, _, let depth) = rows[h] else { continue }
            var end = h
            while end + 1 < rows.count && rows[end + 1].depth > depth { end += 1 }
            // A later header that spans it is inside this one: innermost wins.
            if end > h && gap > h && gap <= end { found = id }
        }
        return found
    }

    /// The group whose opened row row `at` is listed under.
    private static func listedUnder(_ rows: [Row], at i: Int) -> String? {
        let depth = rows[i].depth
        guard depth > 0 else { return nil }
        var k = i - 1
        while k >= 0 && rows[k].depth >= depth { k -= 1 }
        guard k >= 0, case .group(let id, _, _) = rows[k] else { return nil }
        return id
    }

    /// "Group (3)".
    static func groupName(_ count: Int) -> String { tr("Group (%d)", count) }

    /// The rows for `elements` (as the page holds them, back to front),
    /// top-most first. Elements sharing a group make one group row where the
    /// top-most of them is; what is in it follows, indented, only when the
    /// group is in `expanded` — the groups inside it as rows of their own
    /// the same way, a level deeper (Groups.chain). A group of one is listed
    /// as its element.
    static func rows(_ elements: [Element], expanded: Set<String>) -> [Row] {
        level(Array(elements.reversed()), depth: 0, expanded: expanded)
    }

    /// The rows for `front`, top-most first, all inside the same groups
    /// above `depth`, grouped by their group at `depth`.
    private static func level(_ front: [Element], depth: Int, expanded: Set<String>) -> [Row] {
        var done: Set<String> = []
        var out: [Row] = []
        for el in front {
            let levels = Groups.chain(el)
            guard levels.count > depth else {
                out.append(.element(el, member: depth > 0, depth: depth))
                continue
            }
            let group = levels[depth]
            guard !done.contains(group) else { continue }
            let members = front.filter { other in
                let chain = Groups.chain(other)
                return chain.count > depth && chain[depth] == group
            }
            guard members.count > 1 else {
                out.append(.element(el, member: depth > 0, depth: depth))
                continue
            }
            done.insert(group)
            out.append(.group(group, members: members, depth: depth))
            if expanded.contains(group) {
                out += level(members, depth: depth + 1, expanded: expanded)
            }
        }
        return out
    }

    /// Every element on its own row, top-most first, for a list that is not
    /// in the page's order to reorder: Overlapping.
    static func flat(_ elements: [Element]) -> [Row] {
        elements.reversed().map { .element($0, member: false) }
    }

    /// The page's elements, back to front, after the rows at `source` are
    /// dragged to before row `destination` — the List's own offsets. A group
    /// row carries every member with it, as one block in their order; a
    /// member row does not move on its own. Everything else keeps its place.
    /// Dropped among an opened group's members, the rows land below the
    /// whole group (one element's row joins it instead: drop).
    static func moved(_ elements: [Element], rows: [Row], from source: IndexSet, to destination: Int) -> [Element] {
        let moving = source.sorted().filter { rows.indices.contains($0) && rows[$0].movable }
        guard !moving.isEmpty else { return elements }
        let front = Array(elements.reversed())
        let movingIds = Set(moving.flatMap { rows[$0].elements.map(\.id) })
        let block = moving.flatMap { index in
            front.filter { el in rows[index].elements.contains { $0.id == el.id } }
        }
        var rest = front.filter { !movingIds.contains($0.id) }
        // The first row left in place at or after the drop, which the moved
        // rows go above; none, and they go to the very back.
        let anchor = rows.indices.first { $0 >= destination && rows[$0].movable && !moving.contains($0) }
        let anchorTop = anchor.flatMap { rows[$0].elements.first?.id }
        let at = anchorTop.flatMap { id in rest.firstIndex { $0.id == id } } ?? rest.count
        rest.insert(contentsOf: block, at: at)
        return rest.reversed()
    }

    /// The elements whose boxes overlap the box round the whole selection —
    /// the selected ones among them — in the page's order, as Android lists
    /// them. None when nothing is selected. Boxes that only touch do not
    /// overlap.
    static func overlapping(_ elements: [Element], selection: Set<String>) -> [Element] {
        let boxes = elements.filter { selection.contains($0.id) }.map(Geometry.aabb)
        guard !boxes.isEmpty else { return [] }
        let around = Geometry.union(boxes)
        return elements.filter { el in
            let box = Geometry.aabb(el)
            return selection.contains(el.id)
                || (box.minX < around.maxX && around.minX < box.maxX && box.minY < around.maxY && around.minY < box.maxY)
        }
    }
}

/// Forward, Backward, To front and To back, as the Android twin's Layers
/// steps them: a group is one layer, and a step moves the selection past
/// the next thing it is seen to overlap.
enum Layers {

    /// Layers' Select: the selection after the row `rowId` of `rows` is
    /// ticked or unticked — a group's row, every member of it: all of them
    /// out when all were in, else all of them in. Hidden and locked rows
    /// tick as any other (a locked one for Unlock). The Android twin's
    /// Layers.toggled, with the same table.
    static func toggled(_ rows: [LayerRows.Row], selection: Set<String>, rowId: String) -> Set<String> {
        guard let row = rows.first(where: { $0.id == rowId }) else { return selection }
        let ids = Set(row.elements.map(\.id))
        return ids.isSubset(of: selection) ? selection.subtracting(ids) : selection.union(ids)
    }

    /// The rows a drag from `source` moves while Select is on: every ticked
    /// row that moves — all of whose elements are selected — as one block in
    /// their order (LayerRows.moved), when the row dragged is one of them;
    /// else just `source`.
    static func dragged(_ rows: [LayerRows.Row], selection: Set<String>, source: IndexSet) -> IndexSet {
        let ticked = IndexSet(rows.indices.filter { i in
            rows[i].movable && rows[i].elements.allSatisfy { selection.contains($0.id) }
        })
        return !source.isEmpty && source.isSubset(of: ticked) ? ticked : source
    }

    /// The page's elements, back to front, as blocks: each group's members
    /// one block, in their order, where its front-most member is (where
    /// LayerRows lists it); each element on its own a block of one.
    static func blocks(_ elements: [Element]) -> [[Element]] {
        var out: [[Element]] = []
        var groupAt: [String: Int] = [:]
        // Front to back, so a group's block lands at its front-most member.
        for el in elements.reversed() {
            if let group = el.group, let at = groupAt[group] {
                out[at].insert(el, at: 0)
                continue
            }
            if let group = el.group { groupAt[group] = out.count }
            out.append([el])
        }
        return out.reversed()
    }

    /// Forward (or, not `forward`, Backward) for the elements `ids`: the
    /// blocks holding them move together, above the next block in front
    /// that overlaps the union of their turned bounds — or, where none
    /// does, above the very next block. Backward mirrors it. A member
    /// selected alone inside its group steps only within its group's run.
    /// Every group's run comes out whole: the selection is never left
    /// between a group's members. The elements as they are when there is
    /// nothing in front (or behind) to step past: already at the front, or
    /// the back — as on the Android twin.
    static func stepped(_ elements: [Element], ids: Set<String>, forward: Bool) -> [Element] {
        rearranged(elements, ids: ids) { step($0, ids: ids, forward: forward) }
    }

    /// To front (or, not `front`, To back) for the elements `ids`: the
    /// blocks holding them, in their order, in front of every other block —
    /// a member selected alone, in front of the rest of its group's run.
    static func sentToEnd(_ elements: [Element], ids: Set<String>, front: Bool) -> [Element] {
        rearranged(elements, ids: ids) { blocks in
            let chosen = blocks.filter { holds($0, ids) }
            guard !chosen.isEmpty else { return nil }
            let rest = blocks.filter { !holds($0, ids) }
            let out = front ? rest + chosen : chosen + rest
            return same(out, blocks) ? nil : out
        }
    }

    /// The page's blocks put in a new order by `move` — or, when the
    /// selection is part of one group, that group's members, each a block
    /// of its own — and laid out as elements again.
    private static func rearranged(_ elements: [Element], ids: Set<String>,
                                   _ move: ([[Element]]) -> [[Element]]?) -> [Element] {
        var blocks = Self.blocks(elements)
        if let run = innerRun(blocks, ids) {
            guard let moved = move(blocks[run].map { [$0] }) else { return elements }
            blocks[run] = moved.flatMap { $0 }
            return blocks.flatMap { $0 }
        }
        guard let moved = move(blocks) else { return elements }
        return moved.flatMap { $0 }
    }

    /// Tab (or, not `forward`, Shift-Tab): the ids of the next block in
    /// front of the front-most block holding the selection `ids` — or the
    /// one behind it — a group as one, round again past the front and the
    /// back, and nothing hidden counted; with several selected, both keys
    /// step from the front-most of them. With nothing selected, Tab takes
    /// the back-most block and Shift-Tab the front-most. Empty for a page
    /// with nothing shown on it. The same rule as the Android twin's.
    static func neighbour(of ids: Set<String>, in elements: [Element], forward: Bool) -> Set<String> {
        let blocks = Self.blocks(elements.filter { !$0.isHidden })
        guard !blocks.isEmpty else { return [] }
        let count = blocks.count
        let at: Int
        if let held = blocks.indices.last(where: { holds(blocks[$0], ids) }) {
            at = (held + (forward ? 1 : count - 1)) % count
        } else {
            at = forward ? 0 : count - 1
        }
        return Set(blocks[at].map(\.id))
    }

    /// The block of a group of which the selection `ids` is some members
    /// but not all, and nothing else: the run a member selected alone
    /// steps within.
    private static func innerRun(_ blocks: [[Element]], _ ids: Set<String>) -> Int? {
        let holding = blocks.indices.filter { holds(blocks[$0], ids) }
        guard holding.count == 1, let i = holding.first, blocks[i].count > 1,
              blocks[i].contains(where: { !ids.contains($0.id) }) else { return nil }
        return i
    }

    private static func holds(_ block: [Element], _ ids: Set<String>) -> Bool {
        block.contains { ids.contains($0.id) }
    }

    private static func same(_ a: [[Element]], _ b: [[Element]]) -> Bool {
        a.flatMap { $0 }.map(\.id) == b.flatMap { $0 }.map(\.id)
    }

    /// One step of the blocks holding `ids`; nil when there is no block in
    /// front of the front-most of them (or, Backward, behind the back-most)
    /// to step past.
    private static func step(_ blocks: [[Element]], ids: Set<String>, forward: Bool) -> [[Element]]? {
        let chosen = blocks.indices.filter { holds(blocks[$0], ids) }
        guard let first = chosen.first, let last = chosen.last else { return nil }
        // The selection's own turned bounds, not its groups' other members.
        let around = Geometry.union(blocks.flatMap { $0 }.filter { ids.contains($0.id) }.map(Geometry.aabb))
        let past = forward ? Array((last + 1)..<blocks.count) : Array((0..<first).reversed())
        guard let next = past.first else { return nil }
        let target = past.first { overlaps(blocks[$0], around) } ?? next
        let rest = blocks.indices.filter { !chosen.contains($0) }
        guard let standing = rest.firstIndex(of: target) else { return nil }
        var out = rest.map { blocks[$0] }
        out.insert(contentsOf: chosen.map { blocks[$0] }, at: forward ? standing + 1 : standing)
        return out
    }

    /// Whether any of `block` overlaps `box`, by turned bounds. Boxes that
    /// only touch do not overlap, as in LayerRows.overlapping.
    private static func overlaps(_ block: [Element], _ box: CGRect) -> Bool {
        block.contains { el in
            let b = Geometry.aabb(el)
            return b.minX < box.maxX && box.minX < b.maxX && b.minY < box.maxY && box.minY < b.maxY
        }
    }
}
