// Hidden pages: a backup slide, an old version kept for reference, the
// answer to a question that may not come up. A hidden page stays in the
// design — edited, saved, numbered and drawn as a master like any other —
// but Present steps over it and "All pages" in an export leaves it out.
// The flag is the page's own (`Page.hidden`), under the key the Android
// twin keeps it by (core/content/PageExtras.kt).

import Foundation

enum PageVisibility {

    /// Said where Present, or an export of every page, has nothing to show.
    static let everyPageHidden = "Every page is hidden"

    /// The first shown page after page `index`, among `visible` (the
    /// design's visiblePageIndices); nil when there is none.
    static func next(after index: Int, in visible: [Int]) -> Int? {
        visible.first { $0 > index }
    }

    /// The last shown page before page `index`; nil when there is none.
    static func previous(before index: Int, in visible: [Int]) -> Int? {
        visible.last { $0 < index }
    }

    /// Where Present starts when asked to start on page `index`: there, or —
    /// when that page is hidden — the next page shown, else the one before
    /// it; nil when every page is hidden.
    static func start(at index: Int, in visible: [Int]) -> Int? {
        if visible.contains(index) { return index }
        return next(after: index, in: visible) ?? previous(before: index, in: visible)
    }

    /// What an export of every page says it covers: "All 5 pages", or
    /// "All 5 pages, 2 hidden left out" when some are hidden. `total` counts
    /// every page, hidden or not.
    static func allPages(total: Int, hidden: Int) -> String {
        hidden > 0 ? "All \(total) pages, \(hidden) hidden left out" : "All \(total) pages"
    }
}
