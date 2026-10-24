// Bulk create: one page filled in from each row of a table — certificates,
// name badges, product cards — as Canva's Bulk create makes them, and the
// Android twin's BulkCreate, rule for rule (the shared rows in
// Tests/Fixtures/bulk-create.json give the same pages on both phones).
//
//   • the rows are a CSV file's (DataGrid.fromCsv) or typed in the grid; the
//     first is the columns' names, each trimmed. A row with no words is left
//     out, a short one is filled out with empty cells, and no more than
//     maxRows are made
//   • a text takes its column's cell whole when it is connected to one
//     ("bulkField"), and every "{{Column}}" in its words — the name as the
//     column has it, spaces inside the braces aside — is that column's
//     cell; the words come in as typed, any *, _ or ~ in them kept as
//     itself (RichText.escapeLiteral)
//   • a photo or frame connected to a column takes the upload its cell
//     names — an upload's id, with or without "media:" or "video:" and a
//     file extension — in place of its picture (Crop.replaced); a cell
//     that names none leaves it as it was
//   • each page is a copy of the page made from (Copies.of(page)), so its
//     ids are fresh, appended after the design's last page in row order
//   • a connected text whose words no longer fit its box — taller laid out
//     than the box, a box that fits its words to itself aside — is said:
//     "Row 7: Name is too long", rows counted from 1 under the names

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

    /// `cells` — the first row the columns' names — as Bulk create keeps
    /// them: names trimmed, rows with no words left out, each row as wide as
    /// the names, at most maxRows of them.
    static func data(from cells: [[String]]) -> BulkData {
        guard let head = cells.first else { return BulkData(columns: [], rows: []) }
        let columns = head.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rows = cells.dropFirst()
            .filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
            .prefix(maxRows)
            .map { row in (0..<columns.count).map { $0 < row.count ? row[$0].trimmingCharacters(in: .whitespacesAndNewlines) : "" } }
        return BulkData(columns: columns, rows: Array(rows))
    }

    /// How many rows `cells` has under its names, empty ones aside.
    static func rowCount(_ cells: [[String]]) -> Int {
        cells.dropFirst().filter { row in row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }.count
    }

    /// What is said when there are more than maxRows rows: only the first
    /// are made. Nil for maxRows or fewer.
    static func capNote(rows: Int) -> String? {
        rows > maxRows ? tr("Only the first %d of %d rows will be made", maxRows, rows) : nil
    }

    /// The columns named in `text` as "{{Column}}" that `columns` has, in
    /// the order first met.
    static func placeholders(in text: String, columns: [String]) -> [String] {
        var found: [String] = []
        var rest = text[...]
        while let open = rest.range(of: "{{") {
            guard let close = rest[open.upperBound...].range(of: "}}") else { break }
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            if columns.contains(name), !found.contains(name) { found.append(name) }
            rest = rest[close.upperBound...]
        }
        return found
    }

    /// The columns element `el` takes its cells from: its own, then those
    /// its words name. Only columns `columns` has.
    static func fields(of el: Element, columns: [String]) -> [String] {
        var out: [String] = []
        if let field = el.bulkField, columns.contains(field) { out.append(field) }
        if el.type == .text, let text = el.text {
            for name in placeholders(in: text, columns: columns) where !out.contains(name) { out.append(name) }
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
        var rest = text[...]
        while let open = rest.range(of: "{{") {
            guard let close = rest[open.upperBound...].range(of: "}}") else { break }
            let name = rest[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespaces)
            out += rest[..<open.lowerBound]
            if let c = columns.firstIndex(of: name) {
                out += RichText.escapeLiteral(c < row.count ? row[c] : "")
            } else {
                out += rest[open.lowerBound..<close.upperBound]
            }
            rest = rest[close.upperBound...]
        }
        return out + rest
    }

    /// The source of the upload `cell` names among `pictures` (an upload's
    /// id to its "media:" or "video:" source): by its id, with or without
    /// its source's prefix and a file extension. Nil for none.
    static func picture(_ cell: String, pictures: [String: String]) -> String? {
        var key = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["media:", VideoStore.prefix] where key.hasPrefix(prefix) { key = String(key.dropFirst(prefix.count)) }
        if let hit = pictures[key] { return hit }
        let bare = (key as NSString).deletingPathExtension
        return pictures[bare]
    }

    /// `el` filled in from `row`.
    static func filled(_ el: Element, columns: [String], row: [String], pictures: [String: String]) -> Element {
        var out = el
        let cell: String? = el.bulkField.flatMap { field in
            columns.firstIndex(of: field).map { $0 < row.count ? row[$0] : "" }
        }
        if el.type == .text {
            if let cell {
                out.setText(RichText.escapeLiteral(cell))
            } else if let text = el.text, text.contains("{{") {
                let next = filled(text, columns: columns, row: row)
                if next != text { out.setText(next) }
            }
        } else if el.type == .image, let cell, let src = picture(cell, pictures: pictures) {
            out = Crop.replaced(el, src: src)
        }
        return out
    }

    /// One copy of page `pageId` for each row of `data`, filled in, with
    /// fresh ids; none when there is no such page.
    static func pages(_ design: Design, pageId: String, data: BulkData,
                      pictures: [String: String] = [:]) -> [Page] {
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
            for (i, el) in page.elements.enumerated() where el.type == .text && el.fitText != true {
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
