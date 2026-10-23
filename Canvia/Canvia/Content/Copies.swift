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
    /// a fresh id, each source group — every level of a nested one — one
    /// fresh key its copies share, each table one fresh id its cells' copies
    /// share — so the copy is a table of its own — each source chart one
    /// fresh chart id, so Edit chart on the copy leaves the original alone,
    /// and each arrow its ends' copies, or no end, where that end was not
    /// copied.
    /// Unlocked unless `keepingLocks` — both locks, the whole and the
    /// position one: a lock belongs to the original, and a pasted element
    /// that cannot be moved is a dead end.
    static func of(_ elements: [Element], offset: Double = 0, keepingLocks: Bool = false) -> [Element] {
        var ids: [String: String] = [:]
        for el in elements { ids[el.id] = UID.make() }
        var groups: [String: String] = [:]
        var tables: [String: String] = [:]
        var charts: [String: String] = [:]
        return elements.map { el in
            var copy = el
            copy.id = ids[el.id] ?? UID.make()
            copy.x += offset
            copy.y += offset
            if !keepingLocks {
                copy.locked = false
                copy.lockPosition = nil
            }
            // Every level of a nested group (Groups) a fresh key of its own.
            copy.group = el.group.map { freshGroup($0, &groups) }
            copy.subgroups = el.subgroups.map { $0.map { freshGroup($0, &groups) } }
            if let cell = el.table {
                if tables[cell.id] == nil { tables[cell.id] = UID.make("tbl") }
                // Its place, merged cells' spans and all, in the copy's own table.
                copy.table?.id = tables[cell.id] ?? cell.id
            }
            if let chart = el.chart {
                if charts[chart.id] == nil { charts[chart.id] = UID.make("chart") }
                copy.chart?.id = charts[chart.id] ?? chart.id
            }
            copy.connectFrom = el.connectFrom.flatMap { ids[$0] }
            copy.connectTo = el.connectTo.flatMap { ids[$0] }
            return copy
        }
    }

    /// The fresh key a batch gives source group `id`, the same for each of
    /// its copies.
    private static func freshGroup(_ id: String, _ groups: inout [String: String]) -> String {
        if let made = groups[id] { return made }
        let made = UID.make("grp")
        groups[id] = made
        return made
    }

    /// Where a paste goes: added to the page as ever, into the frame `id`
    /// as its picture, or in place of photo `id`'s picture.
    enum PasteTarget: Equatable {
        case add
        case fill(String)
        case replace(String)
    }

    /// Where pasting `payload` goes while `selected` is the selection on a
    /// page of `elements` — `foreign` when it is a picture another app left
    /// (as ElementClipboard.foreign makes one), else what was copied in the
    /// app. One unlocked thing selected that a picture goes into
    /// (PhotoFrames.isFrameLike: an empty frame, a shaped or decorative
    /// frame, a grid's cell), and a picture to paste — a foreign one, or one
    /// copied photo or clip (PhotoFrames.canDrop) — and it fills the frame.
    /// One plain photo selected takes a foreign picture in place of its own,
    /// as Replace does. Anything else is added: words, several things, two
    /// selected, a locked one, a copied photo over a plain one — so
    /// duplicating photos keeps working. The Android twin's
    /// Copies.pasteTarget, with the same table.
    static func pasteTarget(_ selected: [Element], among elements: [Element], payload: [Element],
                            foreign: Bool) -> PasteTarget {
        guard selected.count == 1, let target = selected.first, !target.locked,
              payload.count == 1, let picture = payload.first, PhotoFrames.canDrop(picture) else { return .add }
        if PhotoFrames.isFrameLike(target, among: elements) { return .fill(target.id) }
        if foreign && PhotoFrames.canDrop(target) { return .replace(target.id) }
        return .add
    }

    /// Frame `frame` given the picture of `photo` as a drag into it gives it
    /// (Crop.replaced: the crop reset to cover, the source replaced), keeping
    /// the look of the photo pasted — its filter and strength, adjustments,
    /// duotone and effect — when it had one.
    static func filled(_ frame: Element, with photo: Element) -> Element {
        var out = Crop.replaced(frame, src: photo.src)
        if photo.filter != nil { out.filter = photo.filter }
        if photo.filterStrength != nil { out.filterStrength = photo.filterStrength }
        if photo.adjustments != nil { out.adjustments = photo.adjustments }
        if photo.duotone != nil { out.duotone = photo.duotone }
        if photo.fx != nil { out.fx = photo.fx }
        return out
    }

    /// How far the `nth` paste (one-based) of a clipboard is moved down and
    /// right. Pasted onto another page than the one it was copied from, or
    /// where none of the copied elements is any longer — after a cut — the
    /// first paste lands where the copy was, and each one after steps 24
    /// further; on the page beside the originals, every paste steps, the
    /// first by 24. A clipboard whose page is not known (nil) goes by the
    /// elements alone. The Android twin pastes by the same rule.
    static func pasteOffset(nth: Int, sourcePage: String?, onto page: Page, copied ids: [String]) -> Double {
        let here = Set(page.elements.map(\.id))
        let inPlace = (sourcePage != nil && sourcePage != page.id) || !ids.contains(where: here.contains)
        return 24 * Double(inPlace ? max(nth - 1, 0) : nth)
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
