// Locked pages (PageLocks): Lock page and Unlock page from the page menus,
// several at once from the organiser, and the refusal everything else meets
// on a locked page — felt, and said with Unlock beside it.

import Foundation

extension DesignStore {

    /// Whether the page on screen is locked.
    var isPageLocked: Bool { PageLocks.isLocked(page) }

    /// Lock the page on screen, or unlock it, as one undo step.
    func setPageLocked(_ locked: Bool) {
        setPagesLocked([page.id], locked: locked)
    }

    /// Lock or unlock the pages `ids` in one undo step, as the organiser
    /// picks them; none when nothing changes. Locking the page on screen
    /// lets go of what was selected or typed on it first.
    func setPagesLocked(_ ids: Set<String>, locked: Bool) {
        guard design.pages.contains(where: { ids.contains($0.id) && PageLocks.isLocked($0) != locked }) else { return }
        if locked && ids.contains(page.id) {
            endTextEdit()
            finishCrop()
            selection.removeAll()
        }
        apply { d in
            for i in d.pages.indices where ids.contains(d.pages[i].id) {
                d.pages[i].locked = locked ? true : nil
            }
        }
        buzz(.confirm)
    }

    /// The toast's Unlock: page `id` unlocked, as one undo step.
    func unlockPage(_ id: String) {
        setPagesLocked([id], locked: false)
    }

    /// True when the page on screen is locked, which is then felt and said,
    /// with Unlock (announcementUnlocks), and whatever was asked of it is
    /// not done.
    @discardableResult
    func refusesLockedPage() -> Bool {
        refusesLockedPage(at: min(pageIndex, design.pages.count - 1))
    }

    /// The same for page `at`, which something is about to go onto.
    @discardableResult
    func refusesLockedPage(at: Int) -> Bool {
        guard design.pages.indices.contains(at), PageLocks.isLocked(design.pages[at]) else { return false }
        buzz(.reject)
        announce(PageLocks.lockedNote, undoable: false)
        announcementUnlocks = design.pages[at].id
        return true
    }

    /// Something about to be added: true when the page on screen takes it,
    /// or — when it is locked — the next unlocked page after it, brought up
    /// and said (PageLocks.landing); false — and asked to unlock — when every
    /// page from here on is locked. Android's words.
    func landsOnUnlockedPage() -> Bool {
        guard isPageLocked else { return true }
        guard let to = PageLocks.landing(from: pageIndex, in: design.pages) else {
            refusesLockedPage()
            return false
        }
        let locked = pageIndex + 1
        setPage(to)
        announce("Page \(locked) is locked, so this went on page \(to + 1)", undoable: false)
        return true
    }
}
