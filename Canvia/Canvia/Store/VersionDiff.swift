// What a kept version has that the design open now does not, page by page
// — the badges in Version history's preview — and one page of it brought
// back into the design ("Bring back this page"), the version left as it is.
// The Android twin's VersionDiff (core/content/VersionDiff.kt), with the
// shared fixture Fixtures/versions/diff.json.

import Foundation

enum VersionDiff {

    /// A version's page against the design now: the same, changed, or only
    /// in the version — deleted since. The raw value is its name in the
    /// shared fixture.
    enum PageChange: String, Equatable, Sendable {
        case same
        case changed
        case onlyInVersion
    }

    struct PageState: Equatable, Sendable {
        var pageId: String
        var state: PageChange
    }

    /// Each of `version`'s pages, in its order, against `current`: matched
    /// by page id, the same when their JSON is, once written canonically —
    /// keys sorted at every level, thumbnails and caches left out
    /// (`ignored`) — changed when it is not, and only in the version when
    /// `current` has no page with its id.
    static func pages(_ version: Design, _ current: Design) -> [PageState] {
        var now: [String: Page] = [:]
        for page in current.pages where now[page.id] == nil { now[page.id] = page }
        return version.pages.map { page in
            guard let there = now[page.id] else { return PageState(pageId: page.id, state: .onlyInVersion) }
            return PageState(pageId: page.id, state: canonical(there) == canonical(page) ? .same : .changed)
        }
    }

    /// The keys a page's comparison leaves out, at any level: pictures and
    /// measurements kept to save drawing them again.
    static let ignored: Set<String> = ["thumbnail", "thumb", "cache", "cached"]

    /// `page` written as JSON with its keys sorted at every level and the
    /// `ignored` ones left out; nil when it does not write.
    static func canonical(_ page: Page) -> Data? {
        guard let data = try? JSONEncoder().encode(page),
              let tree = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return try? JSONSerialization.data(withJSONObject: stripped(tree), options: [.sortedKeys])
    }

    private static func stripped(_ value: Any) -> Any {
        if let object = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, inner) in object where !ignored.contains(key) { out[key] = stripped(inner) }
            return out
        }
        if let array = value as? [Any] { return array.map(stripped) }
        return value
    }

    /// Where a page brought back went, and the design with it there.
    struct Brought {
        var design: Design
        var index: Int
    }

    /// `version`'s page `pageId` brought back into `current`, whose page
    /// `currentIndex` is showing, copied as a page is pasted
    /// (PageClipboard.fitted): fresh page and element ids, arrows joined to
    /// the copies of what they joined, photos, clips and fonts shared by
    /// reference, and the records of the fonts of your own it uses adopted.
    /// A page that keeps its own size comes as it was; any other is fitted
    /// to `current`'s size, as a pasted page is.
    ///
    /// Where it goes, the simplest rule: a page only in the version goes
    /// back to its old index, clamped to the pages there are now; any other
    /// goes after the current page — or, `replace`, in place of the page
    /// with its id, which keeps nothing of its own. Nil when the version
    /// has no such page, or when the page to replace is locked (PageLocks).
    static func bringBack(_ version: Design, into current: Design, pageId: String, currentIndex: Int,
                          replace: Bool) -> Brought? {
        guard let from = version.pages.firstIndex(where: { $0.id == pageId }) else { return nil }
        let page = version.pages[from]
        let copy: Page
        if page.width != nil || page.height != nil {
            copy = Copies.of(page)
        } else {
            copy = PageClipboard.fitted(PageClipboard.Payload(page: page, width: version.width, height: version.height),
                                        width: current.width, height: current.height)
        }
        let fonts = CustomFonts.carried(page.elements, from: version)
        var pages = current.pages
        let index: Int
        if let there = pages.firstIndex(where: { $0.id == pageId }) {
            if replace {
                guard !PageLocks.isLocked(pages[there]) else { return nil }
                pages[there] = copy
                index = there
            } else {
                index = min(max(currentIndex + 1, 0), pages.count)
                pages.insert(copy, at: index)
            }
        } else {
            index = min(max(from, 0), pages.count)
            pages.insert(copy, at: index)
        }
        var design = current
        design.pages = pages
        return Brought(design: CustomFonts.adopting(fonts, into: design), index: index)
    }
}

extension DesignStore {

    /// Page `pageId` of `version` brought back into the design as one undo
    /// step, "Bring back page" (VersionDiff.bringBack): back where it was
    /// when it has been deleted since, else after this page — or,
    /// `replace`, in place of the page with its id, unless that page is
    /// locked, which is said with Unlock beside it. The version stays as it
    /// is. Whether it came.
    @discardableResult
    func bringBackPage(from version: Design, pageId: String, replace: Bool) -> Bool {
        finishCrop()
        endTextEdit()
        guard let brought = VersionDiff.bringBack(version, into: design, pageId: pageId,
                                                  currentIndex: pageIndex, replace: replace) else {
            if let at = design.pages.firstIndex(where: { $0.id == pageId }) { refusesLockedPage(at: at) }
            return false
        }
        // Typing and a crop are closed above, so the step this names is
        // the one apply records.
        namedStep = tr("Bring back page")
        apply { $0 = brought.design }
        pageIndex = brought.index
        selection.removeAll()
        buzz(.confirm)
        announce(tr("Brought back page %d", brought.index + 1))
        return true
    }
}
