// Finding one thing in a long deck: Layers' search box, its kind chips and
// its This page / All pages scope. The Android twin's core LayerSearch, rule
// for rule, with the same rows (layer-search.json):
//
// - The query, trimmed, is looked for anywhere in what the element is
//   called — its own name from Rename…, else the one ElementNames makes —
//   in all of a text's words (not only the start the name quotes), and in
//   the words for its kind ("text", "photo", "video", "shape", "line",
//   "chart", "table", "icon", "graphic", "sticker", "group") — in English,
//   as the name is in the app's language already. Case and accents aside;
//   an empty query matches everything.
// - The chips each pick a kind (`KindChip`). With none picked every element
//   passes; with several, an element passes when it is any one of them —
//   the simplest rule, the same on both phones.
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
        case .text: return el.type == .text
        case .media: return el.type == .image
        case .shapes: return (el.type == .shape && !isGraphic(el)) || el.type == .line
        case .graphics: return el.type == .sticker || isGraphic(el)
        case .groups: return el.group != nil
        case .hidden: return el.isHidden
        case .locked: return ElementLock.mode(of: el) != .unlocked
        }
    }

    /// An icon or an illustrated graphic from Add, which are shapes drawn.
    private static func isGraphic(_ el: Element) -> Bool {
        el.type == .shape && (IconLibrary.icon(of: el) != nil || GraphicsLibrary.graphic(of: el) != nil)
    }

    /// Whether `el` matches `query` and passes `kinds` (see the top).
    static func matches(_ el: Element, query: String, kinds: Set<KindChip>) -> Bool {
        if !kinds.isEmpty && !kinds.contains(where: { isKind(el, $0) }) { return false }
        let needle = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return true }
        return words(of: el).contains { folded($0).contains(needle) }
    }

    /// Everything an element is looked for in.
    static func words(of el: Element) -> [String] {
        var out = [ElementNames.name(of: el)]
        if let text = el.text { out.append(RichText.strip(text)) }
        if let text = ShapeText.words(of: el) { out.append(RichText.strip(text)) }
        return out + kindWords(el)
    }

    /// The English words for what `el` is.
    private static func kindWords(_ el: Element) -> [String] {
        var out: [String] = []
        switch el.type {
        case .text: out.append("text")
        case .image:
            out.append("photo")
            if VideoStore.isVideo(el.src) { out.append("video") }
        case .shape:
            out.append("shape")
            if IconLibrary.icon(of: el) != nil { out.append("icon") }
            if GraphicsLibrary.graphic(of: el) != nil { out.append("graphic") }
        case .sticker: out.append("sticker")
        case .line: out.append("line")
        }
        if el.chart != nil { out.append("chart") }
        if el.table != nil { out.append("table") }
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

    /// What VoiceOver says of the hits: "12 layers found on 4 pages", or
    /// "3 layers found" on this page alone.
    static func spokenCount(_ hits: [PageHits], allPages: Bool) -> String {
        let count = hits.reduce(0) { $0 + $1.ids.count }
        let layers = trn("%d layer|%d layers", count)
        guard allPages else { return tr("%@ found", layers) }
        let pages = hits.filter { !$0.ids.isEmpty }.count
        return tr("%@ found on %@", layers, trn("%d page|%d pages", pages))
    }

    /// The note Select gets when a tick would reach another page: a
    /// selection stays on one page, as in Canva.
    static var onePageNote: String { tr("Select several on one page at a time") }
}
