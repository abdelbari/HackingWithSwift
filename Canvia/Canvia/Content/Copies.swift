// Copies of elements and pages that stand on their own: fresh ids, groups
// kept together under new keys, and arrows joined to the copies of what they
// joined.
//
// Each copy used to keep its arrow's ends as they were — the ids of the
// originals. A duplicated arrow was then laid back between the original boxes,
// on top of the original arrow, while the copied boxes had none; and on a
// duplicated or pasted page, or a component, the ends named nothing there,
// so every arrow stopped following its boxes. An arrow whose end did not come
// along now lets go of it instead of reaching back to the original. The
// Android twin copies by the same rule (core/content/Copies.kt).

import Foundation

enum Copies {

    /// `elements` copied as a batch, moved `offset` down and right. Each gets
    /// a fresh id, each source group one fresh key its copies share, and each
    /// arrow its ends' copies — or no end, where that end was not copied.
    /// Unlocked unless `keepingLocks`: locked belongs to the original, and a
    /// pasted element that cannot be moved is a dead end.
    static func of(_ elements: [Element], offset: Double = 0, keepingLocks: Bool = false) -> [Element] {
        var ids: [String: String] = [:]
        for el in elements { ids[el.id] = UID.make() }
        var groups: [String: String] = [:]
        return elements.map { el in
            var copy = el
            copy.id = ids[el.id] ?? UID.make()
            copy.x += offset
            copy.y += offset
            if !keepingLocks { copy.locked = false }
            if let group = el.group {
                if groups[group] == nil { groups[group] = UID.make("grp") }
                copy.group = groups[group]
            }
            copy.connectFrom = el.connectFrom.flatMap { ids[$0] }
            copy.connectTo = el.connectTo.flatMap { ids[$0] }
            return copy
        }
    }

    /// A page copied whole: a fresh id, and its elements copied in place —
    /// locks and all, since it is the same page again.
    static func of(_ page: Page) -> Page {
        var copy = page
        copy.id = UID.make("page")
        copy.elements = of(page.elements, keepingLocks: true)
        return copy
    }
}
