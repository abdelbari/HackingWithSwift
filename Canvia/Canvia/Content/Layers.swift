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

    /// One row of the sheet, top-most first.
    enum Row: Identifiable, Equatable {
        /// An element on its own, or — `member` — one of an opened group's,
        /// listed under its group row.
        case element(Element, member: Bool)
        /// Two or more elements sharing `group`, top-most first.
        case group(String, members: [Element])

        var id: String {
            switch self {
            case .element(let el, _): return el.id
            case .group(let id, _): return "group:" + id
            }
        }

        /// The elements the row stands for, top-most first.
        var elements: [Element] {
            switch self {
            case .element(let el, _): return [el]
            case .group(_, let members): return members
            }
        }

        /// A row that moves when dragged: not a member, which moves with its
        /// group.
        var movable: Bool {
            if case .element(_, member: true) = self { return false }
            return true
        }
    }

    /// "Group (3)".
    static func groupName(_ count: Int) -> String { tr("Group (%d)", count) }

    /// The rows for `elements` (as the page holds them, back to front),
    /// top-most first. Elements sharing a group make one group row where the
    /// top-most of them is; its members follow it, indented, only when the
    /// group is in `expanded`. A group of one is listed as its element.
    static func rows(_ elements: [Element], expanded: Set<String>) -> [Row] {
        let front = Array(elements.reversed())
        var done: Set<String> = []
        var out: [Row] = []
        for el in front {
            guard let group = el.group else {
                out.append(.element(el, member: false))
                continue
            }
            guard !done.contains(group) else { continue }
            let members = front.filter { $0.group == group }
            guard members.count > 1 else {
                out.append(.element(el, member: false))
                continue
            }
            done.insert(group)
            out.append(.group(group, members: members))
            if expanded.contains(group) {
                out += members.map { .element($0, member: true) }
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
    /// whole group.
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
