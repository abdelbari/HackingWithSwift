// Finding one thing in a long deck: Layers' search box, its kind chips and
// its This page / All pages scope. The Android twin's core LayerSearch, rule
// for rule, with the same rows (layer-search.json):
//
// - The query, trimmed, is looked for anywhere in one of: what the element
//   is called — its own name from Rename…, else the one ElementNames makes
//   — all of its words, a text's or a shape's (not only the start the name
//   quotes), or one of the English words for its kind ("text", "photo",
//   "video", "shape", "line", "sticker", "chart", "table", "icon",
//   "graphic", "group"), as the name is in the app's language already.
//   Case and accents aside; an empty query matches everything.
// - The chips each pick a kind (`KindChip`): a chart's parts, a library
//   icon or graphic and a sticker are Graphics, not Text or Shapes and
//   lines; Locked is either lock. With none picked every element passes;
//   with several, an element passes when it is any one of them — the
//   simplest rule, the same on both phones.
// - What is typed and picked lasts while the app runs (`session`) and is
//   never part of a design.

import Foundation

enum LayerSearch {

    /// The chips under the search box, in this order.
    enum KindChip: String, CaseIterable, Identifiable {
        case text = "Text"
        case media = "Photos and videos"
        case shapes = "Shapes and lines"
        case graphics = "Graphics"
        case groups = "Groups"
        case hidden = "Hidden"
        case locked = "Locked"

        var id: String { rawValue }
        var title: String { tr(rawValue) }
    }

    /// What Layers is asked for: the words typed, the chips picked and
    /// whether every page is searched.
    struct Query: Equatable {
        var text = ""
        var kinds: Set<KindChip> = []
        var allPages = false

        /// Whether the query narrows the list at all.
        var narrows: Bool {
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !kinds.isEmpty
        }
    }

    /// The query as it was left, while the app runs; never saved.
    static var session = Query()

    /// How many elements a design has, past which matching runs off the
    /// main thread.
    static let offMainOver = 500

    /// How long typing rests before the list is matched again, in
    /// milliseconds.
    static let debounceMilliseconds = 150

    /// Whether `el` is one of `kind`.
    static func isKind(_ el: Element, _ kind: KindChip) -> Bool {
        switch kind {
        case .text: return el.type == .text && !isGraphic(el)
        case .media: return el.type == .image
        case .shapes: return (el.type == .shape || el.type == .line) && !isGraphic(el)
        case .graphics: return isGraphic(el)
        case .groups: return el.group != nil
        case .hidden: return el.isHidden
        case .locked: return ElementLock.mode(of: el) != .unlocked
        }
    }

    /// A sticker, a part of a chart, or an icon or illustrated graphic from
    /// Add.
    private static func isGraphic(_ el: Element) -> Bool {
        el.type == .sticker || el.chartPart != nil
            || IconLibrary.icon(of: el) != nil || GraphicsLibrary.graphic(of: el) != nil
    }

    /// Whether `el` matches `query` and passes `kinds` (see the top).
    static func matches(_ el: Element, query: String, kinds: Set<KindChip>) -> Bool {
        if !kinds.isEmpty && !kinds.contains(where: { isKind(el, $0) }) { return false }
        let needle = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        return words(of: el).contains { folded($0).contains(needle) }
    }

    /// Everything an element is looked for in, each on its own: its name,
    /// all its words and its kind's words.
    static func words(of el: Element) -> [String] {
        var out = [ElementNames.name(of: el)]
        if let text = el.text { out.append(RichText.strip(text)) }
        return out + kindWords(el)
    }

    /// The English words for what `el` is: a clip is a photo and a video,
    /// a sticker a graphic too.
    static func kindWords(_ el: Element) -> [String] {
        var out: [String] = []
        switch el.type {
        case .text: out.append("text")
        case .image:
            out.append("photo")
            if VideoStore.isVideo(el.src) { out.append("video") }
        case .shape: out.append("shape")
        case .line: out.append("line")
        case .sticker: out.append("sticker")
        }
        if el.chartPart != nil { out.append("chart") }
        if el.table != nil { out.append("table") }
        if IconLibrary.icon(of: el) != nil { out.append("icon") }
        if GraphicsLibrary.graphic(of: el) != nil || el.type == .sticker { out.append("graphic") }
        if el.group != nil { out.append("group") }
        return out
    }

    /// `text` with case and accents taken away.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// One page's hits: its index and the ids of what matched, back to
    /// front as the page holds them.
    struct PageHits: Equatable, Identifiable {
        var page: Int
        var ids: [String]
        var id: Int { page }
    }

    /// The hits for `query` on `pages` — every page with a hit, in order,
    /// or only `current` when the scope is This page (with or without
    /// hits, so its section is always there). `only`, when given, keeps a
    /// page's list to those ids (Overlapping).
    static func hits(_ pages: [Page], current: Int, query: Query, only: Set<String>?) -> [PageHits] {
        var out: [PageHits] = []
        for (index, page) in pages.enumerated() where query.allPages || index == current {
            let ids = page.elements.filter { el in
                (only?.contains(el.id) ?? true) && matches(el, query: query.text, kinds: query.kinds)
            }.map(\.id)
            if !ids.isEmpty || !query.allPages { out.append(PageHits(page: index, ids: ids)) }
        }
        return out
    }

    /// What VoiceOver says of the hits, on this page or all of them: "12
    /// layers found on 4 pages", or "No layers found" — the Android twin's
    /// words.
    static func spokenCount(_ hits: [PageHits]) -> String {
        let count = hits.reduce(0) { $0 + $1.ids.count }
        guard count > 0 else { return tr("No layers found") }
        let pages = hits.filter { !$0.ids.isEmpty }.count
        return trn("%d layer found on %@|%d layers found on %@", count, trn("%d page|%d pages", pages))
    }

    /// A section's heading: "Page 3", or "Page 3 - Intro" for a page with a
    /// title, as the Android twin heads it.
    static func heading(_ page: Page, number: Int) -> String {
        guard let title = page.title.flatMap(PageTitles.kept) else { return tr("Page %d", number) }
        return tr("Page %d - %@", number, title)
    }

    /// The note Select gets when a tick would join things on two pages: a
    /// selection stays on one page, as in Canva.
    static var onePageNote: String { tr("Things on different pages can't be selected together") }
}
