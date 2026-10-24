// Bulk create: one page filled in from each row of a table — certificates,
// name badges, product cards — as Canva's Bulk create makes them, and the
// Android twin's BulkCreate, rule for rule (the shared rows in
// Tests/Fixtures/bulk-create.json give the same columns, rows and pages on
// both phones).
//
//   • the rows are a CSV file's (DataGrid.fromCsv) or typed in the grid; the
//     first is the columns' names, each trimmed, a blank one "Column N" and
//     a repeat "Name 2", as many as the widest row has up to maxColumns. A
//     row with no words is left out, a short one is filled out with empty
//     cells, and no more than maxRows are kept — the rows made, as the
//     design keeps them
//   • words — a text's, or a shape's — with a "{{Column}}" of a known
//     column in them have each such placeholder become that column's cell
//     (the name as the column has it, spaces inside the braces aside),
//     whether or not they are connected to a column too ("bulkField");
//     words with none, connected to a column, become its cell whole. Either
//     way the words come in as typed, any *, _ or ~ in them kept as itself
//     (RichText.escapeLiteral)
//   • a photo or frame (not a clip) connected to a column takes the photo
//     upload its cell names — its id, with or without "media:" and a file
//     extension, else its file name where uploads.json keeps one, letter
//     case aside — in place of its picture (Crop.replaced); a cell that
//     names none leaves it as it was
//   • each page is a copy of the page made from (Copies.of(page)), so its
//     ids are fresh, appended after the design's last page in row order
//   • connected words that no longer fit their box — taller laid out than
//     the box by more than half a unit, a box that fits its words to itself
//     aside — are said: "Row 7: Name is too long", rows counted from 1
//     under the names

import Foundation

/// The rows Bulk create last made pages from, as a design keeps them:
/// {"columns": [...], "rows": [[...]]}.
struct BulkData: Codable, Equatable {
    var columns: [String]
    var rows: [[String]]

    private enum CodingKeys: String, CodingKey { case columns, rows }

    init(columns: [String], rows: [[String]]) {
        self.columns = columns
        self.rows = rows
    }

    /// Leniently: a cell that is not words is an empty one, and rows that
    /// are not a list of lists are none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        columns = (try? c.decode([LenientCell].self, forKey: .columns))?.map(\.text) ?? []
        rows = (try? c.decode([[LenientCell]].self, forKey: .rows))?.map { $0.map(\.text) } ?? []
    }

    private struct LenientCell: Decodable {
        var text: String

        init(from decoder: Decoder) throws {
            text = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        }
    }
}

enum BulkCreate {

    /// The most rows made at once.
    static let maxRows = 500

    /// The most columns the rows keep.
    static let maxColumns = 50

    /// An upload a photo cell can name: its id, its file name where
    /// uploads.json keeps one, and the source a design names it by.
    struct Picture: Equatable {
        var id: String
        var name: String?
        var src: String
    }

    private static func trimmed(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `cells` — the first row the columns' names — as Bulk create keeps
    /// them: names trimmed, a blank one "Column N" and a repeat "Name 2",
    /// as many as the widest row has (maxColumns at most); rows with no
    /// words left out, each as wide as the names, at most maxRows of them.
    static func data(from cells: [[String]]) -> BulkData {
        let width = min(maxColumns, cells.map(\.count).max() ?? 0)
        guard let head = cells.first, width > 0 else { return BulkData(columns: [], rows: []) }
        var seen = Set<String>()
        var columns: [String] = []
        for c in 0..<width {
            let named = c < head.count ? trimmed(head[c]) : ""
            let base = named.isEmpty ? tr("Column %d", c + 1) : named
            var name = base
            var n = 2
            while !seen.insert(name).inserted {
                name = "\(base) \(n)"
                n += 1
            }
            columns.append(name)
        }
        let rows = cells.dropFirst()
            .map { row in (0..<width).map { $0 < row.count ? trimmed(row[$0]) : "" } }
            .filter { row in row.contains { !$0.isEmpty } }
            .prefix(maxRows)
        return BulkData(columns: columns, rows: Array(rows))
    }

    /// How many rows `cells` has under its names, empty ones aside.
    static func rowCount(_ cells: [[String]]) -> Int {
        cells.dropFirst().filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }.count
    }

    /// What is said when there are more than maxRows rows: only the first
    /// are made. Nil for maxRows or fewer.
    static func capNote(rows: Int) -> String? {
        rows > maxRows ? tr("Only the first %d of %d rows will be made.", maxRows, rows) : nil
    }

    /// "{{Column}}": two braces, a name with no brace in it, two braces —
    /// the Android twin's pattern.
    private static let placeholder = try! NSRegularExpression(pattern: "\\{\\{([^{}]+)\\}\\}")

    /// A "{{Column}}" found: where it is, and the name in it trimmed.
    private typealias Match = (range: Range<String.Index>, name: String)

    /// Each "{{Column}}" in `text`, in order.
    private static func matches(in text: String) -> [Match] {
        placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m -> Match? in
            guard let whole = Range(m.range, in: text), let inner = Range(m.range(at: 1), in: text) else { return nil }
            return (range: whole, name: trimmed(String(text[inner])))
        }
    }

    /// The columns named in `text` as "{{Column}}" that `columns` has, in
    /// the order first met.
    static func placeholders(in text: String, columns: [String]) -> [String] {
        var found: [String] = []
        for m in matches(in: text) where columns.contains(m.name) && !found.contains(m.name) {
            found.append(m.name)
        }
        return found
    }

    /// Whether `el` has words to fill: a text, or a shape with words.
    static func hasWords(_ el: Element) -> Bool {
        el.type == .text || ShapeText.words(of: el) != nil
    }

    /// Whether `el` can show a picture from a cell: a photo or a frame.
    static func takesPhoto(_ el: Element) -> Bool {
        el.type == .image && !VideoStore.isVideo(el.src)
    }

    /// The columns element `el` takes its cells from: its own, then those
    /// its words name. Only columns `columns` has.
    static func fields(of el: Element, columns: [String]) -> [String] {
        var out: [String] = []
        if let field = el.bulkField, columns.contains(field) { out.append(field) }
        if hasWords(el), let text = el.text {
            for name in placeholders(in: RichText.strip(text), columns: columns) where !out.contains(name) {
                out.append(name)
            }
        }
        return out
    }

    /// Whether anything on `page` takes a cell from `columns`.
    static func connects(_ page: Page, columns: [String]) -> Bool {
        page.elements.contains { !fields(of: $0, columns: columns).isEmpty }
    }

    /// `text` with each "{{Column}}" of `columns` its cell in `row`, as typed.
    static func filled(_ text: String, columns: [String], row: [String]) -> String {
        var out = ""
        var at = text.startIndex
        for m in matches(in: text) {
            out += text[at..<m.range.lowerBound]
            if let c = columns.firstIndex(of: m.name) {
                out += RichText.escapeLiteral(c < row.count ? row[c] : "")
            } else {
                out += text[m.range]
            }
            at = m.range.upperBound
        }
        return out + text[at...]
    }

    /// `name` without its file extension: up to its last dot, unless the
    /// dot is its first letter.
    static func bare(_ name: String) -> String {
        guard let dot = name.lastIndex(of: "."), dot > name.startIndex else { return name }
        return String(name[..<dot])
    }

    /// The source of the photo upload `cell` names among `pictures`: the
    /// cell's words trimmed, a "media:" before them aside, are its id, else
    /// its id with a file extension, else its file name, letter case aside.
    /// Nil for none.
    static func picture(_ cell: String, pictures: [Picture]) -> String? {
        let words = trimmed(cell)
        let key = words.hasPrefix("media:") ? String(words.dropFirst("media:".count)) : words
        let stem = bare(key)
        let lower = words.lowercased()
        let hit = pictures.first { $0.id == key }
            ?? pictures.first { $0.id == stem }
            ?? pictures.first { $0.name.map { trimmed($0).lowercased() } == lower }
        return hit?.src
    }

    /// `el` filled in from `row`. Placeholders come before the column it is
    /// connected to: "Hello {{Name}}" connected to Name too reads "Hello
    /// Ada".
    static func filled(_ el: Element, columns: [String], row: [String], pictures: [Picture]) -> Element {
        let cell: String? = el.bulkField.flatMap { field in
            columns.firstIndex(of: field).map { $0 < row.count ? row[$0] : "" }
        }
        if hasWords(el) {
            var out = el
            let text = el.text ?? ""
            if !placeholders(in: RichText.strip(text), columns: columns).isEmpty {
                let next = filled(text, columns: columns, row: row)
                if next != text { out.setText(next) }
            } else if let cell {
                out.setText(RichText.escapeLiteral(cell))
            }
            return out
        }
        if takesPhoto(el), let cell, let src = picture(cell, pictures: pictures) {
            return Crop.replaced(el, src: src)
        }
        return el
    }

    /// One copy of page `pageId` for each row of `data`, filled in, with
    /// fresh ids; none when there is no such page.
    static func pages(_ design: Design, pageId: String, data: BulkData,
                      pictures: [Picture] = []) -> [Page] {
        guard let page = design.pages.first(where: { $0.id == pageId }) else { return [] }
        return data.rows.map { row -> Page in
            var copy = Copies.of(page)
            copy.elements = copy.elements.map { filled($0, columns: data.columns, row: row, pictures: pictures) }
            return copy
        }
    }

    /// What the pages made say of words that no longer fit: "Row 7: Name is
    /// too long", for each connected text of each page — `pages` made from
    /// `data`'s rows in order, from `template` — taller laid out
    /// (`heightFor`) than its box, by more than half a unit.
    static func overflows(_ pages: [Page], template: Page, data: BulkData,
                          heightFor: (Element) -> Double) -> [String] {
        var out: [String] = []
        for (r, page) in pages.enumerated() {
            for (i, el) in page.elements.enumerated() where hasWords(el) && el.fitText != true {
                guard i < template.elements.count,
                      let field = fields(of: template.elements[i], columns: data.columns).first,
                      heightFor(el) > el.h + 0.5 else { continue }
                out.append(tr("Row %d: %@ is too long", r + 1, field))
            }
        }
        return out
    }

    /// The title of the design made from `row` when each row is a design of
    /// its own: its first cell, or the design's own title when that is
    /// empty.
    static func title(of row: [String], fallback: String) -> String {
        let first = row.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return first.isEmpty ? fallback : first
    }

    /// The titles of the designs made from `rows`, a design each: each
    /// row's title(of:), made unique (Titles.unique) among `taken` — the
    /// titles on Home — `fallback`, the design's own, and the ones before
    /// it, as Android's BulkCreate.designs titles them.
    static func titles(of rows: [[String]], fallback: String, taken: [String]) -> [String] {
        var used = taken + [fallback]
        return rows.map { row -> String in
            let made = Titles.unique(title(of: row, fallback: fallback), taken: used)
            used.append(made)
            return made
        }
    }

    /// The design made from `page` alone, a new one titled `title`: the
    /// design's size and settings, that one page, and nothing that named
    /// its other pages.
    static func separate(_ design: Design, page: Page, title: String, now: Double) -> Design {
        var out = design
        out.id = UID.make("doc")
        out.title = title
        out.titleAuto = false
        out.pages = [page]
        out.masterPageId = nil
        out.recordings = nil
        out.beatSyncRestore = nil
        out.bulk = nil
        out.starred = nil
        out.createdAt = now
        out.updatedAt = now
        return out
    }
}
