// Locked pages: a finished page in a long deck kept as it is. Nothing on a
// locked page — its background included — can be selected, moved, added to
// or deleted until it is unlocked; a tap there says so and offers Unlock.
// The flag is the page's own (`Page.locked`), under the key the Android
// twin keeps it by, written only when true. Locking changes nothing that is
// drawn: a locked page is shown, presented, exported and copied as before.

import Foundation

enum PageLocks {

    /// Said, with Unlock beside it, wherever something is refused on a
    /// locked page.
    static let lockedNote = "This page is locked"

    static func isLocked(_ page: Page) -> Bool { page.locked == true }

    /// Whether `before` may become `after`: always on an unlocked page; on a
    /// locked one only when its elements and its background are as they
    /// were — its title, notes, timing, hiding and the lock itself may still
    /// change. What every edit made to one page is held to.
    static func allows(_ before: Page, becoming after: Page) -> Bool {
        guard isLocked(before) else { return true }
        return after.elements == before.elements && after.background == before.background
    }

    /// Where something added while page `index` is on screen goes: that
    /// page when it is unlocked, else the first unlocked page after it —
    /// never one before, so a deck fills forwards. Nil when every page from
    /// `index` to the end is locked, when the editor asks to unlock instead.
    /// The Android twin's PageLocks.pageForAdding, row for row.
    static func landing(from index: Int, in pages: [Page]) -> Int? {
        guard index < pages.count else { return nil }
        return (max(index, 0)..<pages.count).first { !isLocked(pages[$0]) }
    }

    /// What deleting several pages from the organiser says, locked ones
    /// left where they are: "Deleted 2 pages, skipped 1 locked page";
    /// "Skipped 2 locked pages" when nothing went.
    static func deletedNote(deleted: Int, skipped: Int) -> String {
        let gone = deleted == 1 ? "Deleted 1 page" : "Deleted \(deleted) pages"
        let kept = skipped == 1 ? "1 locked page" : "\(skipped) locked pages"
        if skipped == 0 { return gone }
        if deleted == 0 { return "Skipped " + kept }
        return gone + ", skipped " + kept
    }

    /// What asking before a page is deleted says of it: how much is on it,
    /// and that it is locked when it is — a locked page always asks.
    static func deleteMessage(elements: Int, locked: Bool) -> String {
        let count = elements == 1 ? "1 element" : "\(elements) elements"
        return locked ? "It is locked, with \(count) on it." : "It has \(count) on it."
    }

    /// What VoiceOver adds for a locked page, after "hidden".
    static let spoken = "locked"
}
