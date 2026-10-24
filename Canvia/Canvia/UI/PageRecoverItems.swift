// Unlock all and Show hidden in a page's menus — the pages bar's, the ⋮ over
// each page in the column, and the organiser's — after the rest, in the
// order the hold menu has them (HoldMenu): each only when the page has
// something locked (and is not itself locked) or hidden on it, with how many.

import SwiftUI

struct PageRecoverItems: View {
    @Bindable var store: DesignStore
    let index: Int
    /// Done before either, from the organiser: the sheet put away so the
    /// page and what it selects are seen.
    var then: () -> Void = {}

    var body: some View {
        let locked = store.lockedCount(onPage: index)
        let hidden = store.hiddenCount(onPage: index)
        let pageLocked = store.design.pages.indices.contains(index) && PageLocks.isLocked(store.design.pages[index])
        if locked > 0 && !pageLocked {
            Button {
                store.unlockAll(onPage: index)
                then()
            } label: { Label(HoldMenu.unlockAllTitle(locked), systemImage: "lock.open") }
        }
        if hidden > 0 {
            Button {
                store.showAllHidden(onPage: index)
                then()
            } label: { Label(HoldMenu.showHiddenTitle(hidden), systemImage: "eye") }
        }
    }
}
