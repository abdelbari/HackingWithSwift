// Groups inside groups, as Canva keeps them: an element's `group` is its
// outermost group — so a build that knows one level still sees today's flat
// group — and `subgroups` the groups below it, outer to inner. Grouping a
// group keeps it, Ungroup takes off one level at a time, and a tap on a
// selected group goes one level deeper. The Android twin's core Groups holds
// the same rules, and both phones' tests the same rows.

import Foundation

enum Groups {

    /// Every group `el` belongs to, outer to inner: its `group`, then its
    /// `subgroups`. Empty for an element in no group.
    static func chain(_ el: Element) -> [String] {
        guard let group = el.group else { return [] }
        return [group] + (el.subgroups ?? [])
    }

    /// `el` in the groups `chain`, outermost first: the first its `group`,
    /// the rest its `subgroups`, none when there are none — the Android
    /// twin's Groups.withChain.
    static func withChain(_ el: Element, _ chain: [String]) -> Element {
        var e = el
        let inner = Array(chain.dropFirst())
        e.group = chain.first
        e.subgroups = inner.isEmpty ? nil : inner
        return e
    }

    /// The ids of the elements in group `id`, at whatever level it is.
    static func members(_ elements: [Element], of id: String) -> Set<String> {
        Set(elements.filter { chain($0).contains(id) }.map(\.id))
    }

    /// A group's turn as read and kept: a finite angle other than 0; nil is
    /// none, and no key in the file.
    static func keptTurn(_ degrees: Double) -> Double? {
        degrees.isFinite && degrees != 0 ? degrees : nil
    }

    /// An angle as a group keeps it: 0 up to 360, as an element's
    /// rotation is kept.
    static func normalisedTurn(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let turned = degrees.truncatingRemainder(dividingBy: 360)
        return turned < 0 ? turned + 360 : turned
    }

    /// Group: the elements `ids` all take the new group `id` as their
    /// outermost, and the group each was in, if any, goes to the front of
    /// its `subgroups` — so a group grouped with something else is still a
    /// group inside the new one. Any turn of a group is let go
    /// (groupTurn): the new group starts upright. A crop stays where it
    /// shows (GraphicClip.regrouped).
    static func grouped(_ elements: [Element], ids: Set<String>, into id: String) -> [Element] {
        let out = elements.map { el in
            guard ids.contains(el.id) else { return el }
            var e = el
            let levels = chain(el)
            e.group = id
            e.subgroups = levels.isEmpty ? nil : levels
            e.groupTurn = nil
            return e
        }
        return GraphicClip.regrouped(before: elements, after: out)
    }

    /// Ungroup: each of the elements `ids` takes off its outermost group —
    /// its first subgroup becomes its group, or it is in none — so the group
    /// inside comes back as it was. Its turn is let go too. A group's crop
    /// stays where it shows, put into each member's own box or its inner
    /// group's frame (GraphicClip.regrouped), so ungrouping a cropped
    /// graphic changes nothing on the page.
    static func ungrouped(_ elements: [Element], ids: Set<String>) -> [Element] {
        let out = elements.map { el in
            guard ids.contains(el.id), el.group != nil else { return el }
            var e = el
            let inner = Array((el.subgroups ?? []).dropFirst())
            e.group = el.subgroups?.first
            e.subgroups = inner.isEmpty || e.group == nil ? nil : inner
            e.groupTurn = nil
            return e
        }
        return GraphicClip.regrouped(before: elements, after: out)
    }

    /// Remove from group: each of the elements `ids` leaves its innermost
    /// group (withChain, its chain less the last level) and the rest of
    /// that group stays grouped. A group it left with one member lets it go
    /// too, so the edit leaves no group of one behind (letGoOfOnes). An element whose outermost
    /// group is no longer the one it was in loses its groupTurn: the turn
    /// belongs to a group it has left. A crop stays where it shows
    /// (GraphicClip.regrouped). The Android twin's Groups.removedFromGroup,
    /// the same rows.
    static func removedFromGroup(_ elements: [Element], ids: Set<String>) -> [Element] {
        let taken = elements.map { el -> Element in
            let levels = chain(el)
            guard ids.contains(el.id), !levels.isEmpty else { return el }
            return withChain(el, Array(levels.dropLast()))
        }
        let out = letGoOfOnes(before: elements, after: taken, moved: ids).map { el in
            turnLetGo(el, was: elements.first { $0.id == el.id })
        }
        return GraphicClip.regrouped(before: elements, after: out)
    }

    /// Whether More offers Remove from group for `selection`: something is
    /// selected, every one of it is in a group, and some other member of
    /// the outermost groups it is in is not selected — a part of a group,
    /// reached by tapping in, never one or more whole groups. The Android
    /// twin's Groups.removable, the same rows.
    static func removable(_ elements: [Element], selection: Set<String>) -> Bool {
        let chosen = elements.filter { selection.contains($0.id) }
        guard !chosen.isEmpty, chosen.allSatisfy({ $0.group != nil }) else { return false }
        let outer = Set(chosen.compactMap(\.group))
        return elements.contains { el in
            guard let g = el.group else { return false }
            return outer.contains(g) && !selection.contains(el.id)
        }
    }

    /// Add to group: each of the elements `ids` takes the chain of group
    /// `groupId`'s members, outermost first down to `groupId` — and so the
    /// group's turn, written the same on each member — and moves in the
    /// page's order to just above the group's top-most member, in the order
    /// they were in. One already in the group, and a group with no members,
    /// change nothing. A group they left with one member lets it go, its
    /// groupTurn with it, as removedFromGroup does (letGoOfOnes). The
    /// Android twin's Groups.addedToGroup, the same rows.
    static func addedToGroup(_ elements: [Element], ids: Set<String>, groupId: String) -> [Element] {
        guard let member = elements.first(where: { chain($0).contains(groupId) }) else { return elements }
        let levels = chain(member)
        let target = Array(levels.prefix(through: levels.firstIndex(of: groupId) ?? levels.count - 1))
        let joining = Set(elements.filter { ids.contains($0.id) && !chain($0).contains(groupId) }.map(\.id))
        guard !joining.isEmpty else { return elements }
        let changed = elements.map { el -> Element in
            guard joining.contains(el.id) else { return el }
            var e = withChain(el, target)
            e.groupTurn = member.groupTurn
            return e
        }
        let moving = changed.filter { joining.contains($0.id) }
        var rest = changed.filter { !joining.contains($0.id) }
        let top = rest.lastIndex { chain($0).contains(groupId) } ?? rest.count - 1
        rest.insert(contentsOf: moving, at: top + 1)
        let out = letGoOfOnes(before: elements, after: rest, moved: joining).map { el in
            joining.contains(el.id) ? el : turnLetGo(el, was: elements.first { $0.id == el.id })
        }
        return GraphicClip.regrouped(before: elements, after: out)
    }

    /// `after` with each group the `moved` elements left — in their chain
    /// in `before`, not in `after` — let go of by its last member when only
    /// one is left in it. Only the groups the edit touched: a group of one
    /// already on the page stays as it is. The Android twin's Groups.tidied.
    private static func letGoOfOnes(before: [Element], after: [Element], moved: Set<String>) -> [Element] {
        var left: Set<String> = []
        for el in after where moved.contains(el.id) {
            let was = before.first { $0.id == el.id }.map(chain) ?? []
            left.formUnion(Set(was).subtracting(chain(el)))
        }
        let ones = left.filter { members(after, of: $0).count == 1 }
        guard !ones.isEmpty else { return after }
        return after.map { el in
            let levels = chain(el)
            let kept = levels.filter { !ones.contains($0) }
            return kept == levels ? el : withChain(el, kept)
        }
    }

    /// `el` without its groupTurn when its outermost group is no longer the
    /// one it had `was` it in.
    private static func turnLetGo(_ el: Element, was: Element?) -> Element {
        guard el.groupTurn != nil, el.group != was?.group else { return el }
        var e = el
        e.groupTurn = nil
        return e
    }

    /// A tap on `tapped` while `selection` is one of its groups, at any
    /// level: the next level down — the members of its next group below
    /// that one, passing over a level that is only the selection again or
    /// the element alone — or, with no level left, the element alone. Nil
    /// when the selection is not one of its groups: the tap selects as ever,
    /// its outermost group (DesignStore.select). So a first tap takes the
    /// outermost group, a second the next level, and the last the element,
    /// where further taps stay — the Android twin's Groups.tapped.
    static func deeper(_ elements: [Element], selection: Set<String>, tapped: String) -> Set<String>? {
        guard selection.contains(tapped), let el = elements.first(where: { $0.id == tapped }) else { return nil }
        let levels = chain(el)
        if selection == [tapped] { return levels.isEmpty ? nil : selection }
        guard let at = levels.lastIndex(where: { members(elements, of: $0) == selection }) else { return nil }
        for level in levels.dropFirst(at + 1) {
            let ids = members(elements, of: level)
            if ids.count > 1 && ids != selection { return ids }
        }
        return [tapped]
    }

    /// The outermost group `selection` is the whole of, every member and
    /// nothing else; nil for anything else — one thing, several that are no
    /// group, or a level inside a group.
    static func whole(_ elements: [Element], selection: Set<String>) -> String? {
        guard selection.count > 1,
              let first = elements.first(where: { selection.contains($0.id) }), let group = first.group,
              Set(elements.filter { $0.group == group }.map(\.id)) == selection else { return nil }
        return group
    }

    /// How far the selected group is turned as a whole (groupTurn): the
    /// angle on its members, when `selection` is a whole outermost group;
    /// 0 for anything else, which keeps an upright box.
    static func turn(_ elements: [Element], selection: Set<String>) -> Double {
        guard let group = whole(elements, selection: selection) else { return 0 }
        return elements.first { $0.group == group }?.groupTurn ?? 0
    }

    /// The elements with the members of group `id` turned to `degrees` as a
    /// group — the key alone, written the same on each, and none at 0.
    static func turned(_ elements: [Element], group id: String, to degrees: Double) -> [Element] {
        elements.map { el in
            guard el.group == id else { return el }
            var e = el
            e.groupTurn = keptTurn(degrees)
            return e
        }
    }

    /// What an export writes for each element, in the page's order — `el`
    /// nil for a part that is no element's, a backdrop — with each run of
    /// neighbours in one group, two elements or more, wrapped by `wrap` as
    /// one part: the group's id, its elements and their parts, already
    /// wrapped a level in. So nested groups go out as nested <g> in an SVG
    /// and nested grpSp on a slide. A group whose members are not side by
    /// side goes out as a run for each stretch of them.
    static func nested<Part>(_ items: [(el: Element?, part: Part)], depth: Int = 0,
                             wrap: (String, [Element], [Part]) -> Part) -> [Part] {
        func level(_ item: (el: Element?, part: Part)) -> String? {
            guard let el = item.el else { return nil }
            let levels = chain(el)
            return levels.count > depth ? levels[depth] : nil
        }
        var out: [Part] = []
        var i = 0
        while i < items.count {
            guard let group = level(items[i]) else {
                out.append(items[i].part)
                i += 1
                continue
            }
            var end = i + 1
            while end < items.count && level(items[end]) == group { end += 1 }
            let run = Array(items[i..<end])
            var members: [Element] = []
            for item in run {
                if let el = item.el, !members.contains(where: { $0.id == el.id }) { members.append(el) }
            }
            if members.count < 2 {
                out += run.map { $0.part }
            } else {
                out.append(wrap(group, members, nested(run, depth: depth + 1, wrap: wrap)))
            }
            i = end
        }
        return out
    }
}
