// One search across everything Add puts on a page that has a name — the
// Android twin's ElementSearch, rule for rule, with the same test rows: the
// shapes, the icons (their names, tags and categories), the stickers (by
// their words), the photo frames, the grids, the lines, the charts and the
// table, the QR code and the stock art.
//
// A hit is ranked by how it matches the query — its spaces trimmed and run
// together, case aside:
// 0. its name is the query;
// 1. its name starts with it;
// 2. a word of its name, or one of its words (tags, a sticker's words, a
//    grid's "two photos"), starts with it — or a word the query is a
//    synonym of does (`synonyms`, one table on both phones);
// 3. a word of its category starts with it ("Arrows", "Stickers", "Grids"),
//    or with a synonym of it.
// Hits of one rank keep the library's order, kind by kind in HitKind order.
//
// Add's search shows the hits in sections (`sections`), in Shelf order,
// and Recently used shows the last `recentLimit` things put on a page from
// Add (`remembered`), kept on the phone under `recentElements` as a JSON
// array of {kind, id} (`encode`) and never in a design.

import Foundation

enum ElementSearch {

    /// The sections the hits are shown in, in this order.
    enum Shelf: String, CaseIterable, Identifiable {
        case shapes = "Shapes"
        case icons = "Icons"
        case stickers = "Stickers"
        case frames = "Frames"
        case grids = "Grids"
        case lines = "Lines"
        case charts = "Charts and tables"
        case artwork = "Artwork"

        var id: String { rawValue }
        var title: String { tr(rawValue) }
    }

    /// What a hit is, by the key Recently used keeps it under. The QR code
    /// is shown with the charts and tables, the other things made from what
    /// you type.
    enum HitKind: String, CaseIterable {
        case shape, icon, sticker, photoFrame, grid, line, chart, table, qr, stockArt

        var section: Shelf {
            switch self {
            case .shape: return .shapes
            case .icon: return .icons
            case .sticker: return .stickers
            case .photoFrame: return .frames
            case .grid: return .grids
            case .line: return .lines
            case .chart, .table, .qr: return .charts
            case .stockArt: return .artwork
            }
        }
    }

    /// One thing to put on a page: its kind and id — a shape's or an icon's
    /// id, a sticker's glyph, a frame's, grid's or stock picture's id, a
    /// line's name, a chart's kind ("column"), "table" or "qr" — and the
    /// name it is shown by.
    struct Hit: Equatable, Hashable {
        var kind: HitKind
        var id: String
        var name: String

        /// Told apart from every other hit, whatever its kind.
        var key: String { "\(kind.rawValue):\(id)" }
    }

    /// A hit's place in the search: what it is, and what it is found by.
    private struct Entry {
        var hit: Hit
        var words: [String]
        var category: String
    }

    /// How many hits a section shows before See all.
    static let sectionLimit = 8

    /// How many things Recently used keeps.
    static let recentLimit = 24

    /// Add's four lines, in its order, by the name each is found and kept
    /// by: plain, an arrow at the end it points to, an arrow at each end, a
    /// dot at each end — the Android twin's LineEnds.presets.
    struct LinePreset {
        var name: String
        var symbol: String
        var start: String?
        var end: String?
    }

    static let linePresets: [LinePreset] = [
        LinePreset(name: "Line", symbol: "line.diagonal", start: nil, end: nil),
        LinePreset(name: "Arrow", symbol: "arrow.right", start: nil, end: "arrow"),
        LinePreset(name: "Double arrow", symbol: "arrow.left.and.right", start: "arrow", end: "arrow"),
        LinePreset(name: "Dot ends", symbol: "ellipsis", start: "dot", end: "dot"),
    ]

    /// Words that find one another, one row a set: a query that is one of a
    /// row's words (or starts one) finds what the others find too, ranked
    /// as a word match at best.
    static let synonyms: [[String]] = [
        ["heart", "love", "valentine"],
        ["arrow", "pointer", "direction"],
        ["star", "favourite", "favorite", "rating"],
        ["circle", "round", "oval", "ring"],
        ["square", "rectangle", "box"],
        ["speech", "bubble", "chat", "talk", "callout"],
        ["photo", "picture", "image"],
        ["collage", "grid", "layout"],
        ["line", "divider", "rule"],
        ["chart", "graph", "plot"],
        ["table", "spreadsheet"],
        ["qr", "code", "barcode"],
        ["smile", "happy", "smiley"],
        ["party", "celebrate", "celebration"],
        ["flower", "blossom", "floral"],
        ["sun", "sunny", "summer"],
        ["check", "tick", "done"],
        ["phone", "mobile"],
        ["laptop", "computer"],
        ["frame", "border", "mockup"],
        ["background", "wallpaper", "art"],
    ]

    private static let counted = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]

    /// Every glyph of the sticker groups, once each, in their order — the
    /// order the Android twin's table of sticker words has.
    private static var stickerGlyphs: [String] {
        var out: [String] = []
        for group in ContentLibrary.stickerGroups {
            for glyph in group.emoji where !out.contains(glyph) { out.append(glyph) }
        }
        return out
    }

    private static let index: [Entry] = {
        var out: [Entry] = []
        for shape in ContentLibrary.shapes {
            out.append(Entry(hit: Hit(kind: .shape, id: shape.id, name: shape.name), words: ["shape"],
                             category: ContentLibrary.shapeGroupName(shape.category)))
        }
        for icon in IconLibrary.icons {
            out.append(Entry(hit: Hit(kind: .icon, id: icon.id, name: icon.name), words: icon.tags + ["icon"],
                             category: icon.category))
        }
        for glyph in stickerGlyphs {
            let words = Stickers.words(for: glyph)
            guard let first = words.first else { continue }
            let name = first.prefix(1).uppercased() + first.dropFirst()
            out.append(Entry(hit: Hit(kind: .sticker, id: glyph, name: name), words: words + ["sticker", "emoji"],
                             category: "Stickers"))
        }
        for frame in DecorativeFrames.presets {
            out.append(Entry(hit: Hit(kind: .photoFrame, id: frame.id, name: tr(frame.name)), words: ["photo frame"],
                             category: "Frames"))
        }
        for layout in PhotoGrids.layouts {
            let n = layout.cells.count
            var photos = ["\(n) photos"]
            if n >= 1 && n <= counted.count { photos.append("\(counted[n - 1]) photos") }
            out.append(Entry(hit: Hit(kind: .grid, id: layout.id, name: tr(layout.name)),
                             words: photos + ["collage", "photo grid"], category: "Grids"))
        }
        for line in linePresets {
            out.append(Entry(hit: Hit(kind: .line, id: line.name, name: tr(line.name)), words: ["line"], category: "Lines"))
        }
        for kind in DataGraphics.ChartKind.allCases {
            out.append(Entry(hit: Hit(kind: .chart, id: kind.rawValue, name: tr("%@ chart", kind.name)),
                             words: ["chart", "graph"], category: "Charts"))
        }
        out.append(Entry(hit: Hit(kind: .table, id: "table", name: tr("Table")), words: ["table", "data"], category: "Tables"))
        out.append(Entry(hit: Hit(kind: .qr, id: "qr", name: tr("QR code")), words: ["qr", "code", "link"], category: "Codes"))
        for art in PhotoLibrary.photos {
            out.append(Entry(hit: Hit(kind: .stockArt, id: art.id, name: art.name), words: ["artwork", "background"],
                             category: art.category))
        }
        return out
    }()

    private static let byKey: [String: Hit] = Dictionary(
        index.map { ($0.hit.key, $0.hit) }, uniquingKeysWith: { first, _ in first })

    /// The query as it is matched: case aside, spaces trimmed and run
    /// together.
    static func normalised(_ query: String) -> String {
        query.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Every hit for `query`, best first (see the ranks above); none for a
    /// blank query.
    static func results(_ query: String) -> [Hit] {
        let q = normalised(query)
        guard !q.isEmpty else { return [] }
        var also: [String] = []
        for row in synonyms where row.contains(where: { $0 == q || (q.count >= 3 && $0.hasPrefix(q)) }) {
            for word in row where word != q && !also.contains(word) { also.append(word) }
        }
        var ranked: [(rank: Int, order: Int, hit: Hit)] = []
        for (order, entry) in index.enumerated() {
            if let r = rank(entry, q, also) { ranked.append((r, order, entry.hit)) }
        }
        ranked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.order < $1.order }
        return ranked.map(\.hit)
    }

    /// `hits` by section, in Shelf order, each keeping its order; a
    /// section with none drops out.
    static func sections(_ hits: [Hit]) -> [(section: Shelf, hits: [Hit])] {
        let grouped = Dictionary(grouping: hits, by: { $0.kind.section })
        return Shelf.allCases.compactMap { s in grouped[s].map { (section: s, hits: $0) } }
    }

    /// What the search says when it finds nothing.
    static func nothingFound(_ query: String) -> String {
        tr("Nothing called \"%@\". Try a shorter word.", query.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func rank(_ entry: Entry, _ q: String, _ also: [String]) -> Int? {
        let name = entry.hit.name.lowercased()
        let words = entry.words.map { $0.lowercased() }
        let category = entry.category.lowercased()
        if name == q { return 0 }
        if name.hasPrefix(q) { return 1 }
        if startsAWord(name, q) || words.contains(where: { startsAWord($0, q) }) { return 2 }
        if also.contains(where: { s in startsAWord(name, s) || words.contains { startsAWord($0, s) } }) { return 2 }
        if startsAWord(category, q) || also.contains(where: { startsAWord(category, $0) }) { return 3 }
        return nil
    }

    /// Whether `needle` starts a word of `text`: at its start, or after a
    /// character that is no letter or digit.
    private static func startsAWord(_ text: String, _ needle: String) -> Bool {
        var from = text.startIndex
        while let found = text.range(of: needle, range: from..<text.endIndex) {
            if found.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: found.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            from = text.index(after: found.lowerBound)
        }
        return false
    }

    // MARK: Recently used

    /// The UserDefaults key Recently used is kept under, as on the Android
    /// twin's Prefs.
    static let recentKey = "recentElements"

    /// The hit `kind` and `id` name, when this build has it.
    static func hit(_ kind: HitKind, _ id: String) -> Hit? {
        byKey["\(kind.rawValue):\(id)"]
    }

    /// `recent` with `hit` first, once, and no more than recentLimit.
    static func remembered(_ recent: [Hit], _ hit: Hit) -> [Hit] {
        Array(([hit] + recent.filter { $0.kind != hit.kind || $0.id != hit.id }).prefix(recentLimit))
    }

    /// Recently used as kept: a JSON array of {kind, id}, written key by key
    /// so it reads as the Android twin writes it.
    static func encode(_ recent: [Hit]) -> String {
        let items = recent.map { "{\"kind\":\(quoted($0.kind.rawValue)),\"id\":\(quoted($0.id))}" }
        return "[" + items.joined(separator: ",") + "]"
    }

    /// `text` as a JSON string.
    private static func quoted(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(text), let out = String(data: data, encoding: .utf8) else { return "\"\"" }
        return out
    }

    /// Recently used read back: what this build no longer has, or cannot
    /// read, is left out.
    static func decode(_ text: String?) -> [Hit] {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let array = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [Any] else { return [] }
        var out: [Hit] = []
        for item in array {
            guard let object = item as? [String: Any],
                  let kind = (object["kind"] as? String).flatMap({ HitKind(rawValue: $0) }),
                  let id = object["id"] as? String, let found = hit(kind, id),
                  !out.contains(where: { $0.kind == found.kind && $0.id == found.id }) else { continue }
            out.append(found)
        }
        return Array(out.prefix(recentLimit))
    }

    /// Recently used, as this phone keeps it.
    static func recent(in defaults: UserDefaults = .standard) -> [Hit] {
        decode(defaults.string(forKey: recentKey))
    }

    /// `kind` and `id` put on a page from Add: first in Recently used.
    static func remember(_ kind: HitKind, _ id: String, in defaults: UserDefaults = .standard) {
        guard let found = hit(kind, id) else { return }
        defaults.set(encode(remembered(recent(in: defaults), found)), forKey: recentKey)
    }
}
