// What an Undo or a Redo changed, so the editor can select it and bring it
// into view, as Canva does — rather than leave you guessing what just came
// back. The Android twin's History.changedIds, with the same tests.

import Foundation

enum History {

    /// The ids of the elements that differ between two states of a page:
    /// added, removed, or there in both but not the same.
    static func changedIds(before: Page, after: Page) -> Set<String> {
        let old = Dictionary(before.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(after.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = Set<String>()
        for (id, el) in new where old[id] != el { changed.insert(id) }
        for id in old.keys where new[id] == nil { changed.insert(id) }
        return changed
    }
}
