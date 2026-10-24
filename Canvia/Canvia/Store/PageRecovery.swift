// Freeing a page at once, as Canva's locked or hidden template parts want:
// Unlock all (ElementLock.unlockedAll) and Show hidden
// (PageVisibility.shownAll), from the hold menu on the empty page, the page
// menus and the organiser. Each is one undo step — Unlock, Show — and what
// it changed is selected after, so the result is seen. A locked page still
// refuses, with its Unlock.

import Foundation

extension DesignStore {

    /// How many things on page `index` are locked; 0 for a page that is not
    /// there.
    func lockedCount(onPage index: Int) -> Int {
        design.pages.indices.contains(index) ? ElementLock.lockedIds(design.pages[index]).count : 0
    }

    /// How many things on page `index` are hidden.
    func hiddenCount(onPage index: Int) -> Int {
        design.pages.indices.contains(index) ? PageVisibility.hiddenIds(design.pages[index]).count : 0
    }

    /// Unlock all on page `index`, which is brought up first: every lock on
    /// it let go, as one step named Unlock, and what was locked selected.
    func unlockAll(onPage index: Int) {
        recover(onPage: index, step: tr("Unlock"), ids: ElementLock.lockedIds, change: ElementLock.unlockedAll)
    }

    /// Show hidden on page `index`: everything hidden on it shown, as one
    /// step named Show, and selected.
    func showAllHidden(onPage index: Int) {
        recover(onPage: index, step: tr("Show"), ids: PageVisibility.hiddenIds, change: PageVisibility.shownAll)
    }

    private func recover(onPage index: Int, step: String, ids: (Page) -> [String], change: (Page) -> Page) {
        guard design.pages.indices.contains(index) else { return }
        if index != pageIndex { setPage(index) }
        guard !refusesLockedPage() else { return }
        let changed = Set(ids(page))
        guard !changed.isEmpty else { return }
        endTextEdit()
        namedStep = step
        applyToPage { $0 = change($0) }
        selection = changed
        buzz(.confirm)
    }
}
