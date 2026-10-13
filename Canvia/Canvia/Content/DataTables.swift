// Tables that stay tables: rows and columns added and taken away, the header
// turned on and off, cells recoloured, the table set again from its words,
// and every row as tall as its words.
//
// A table is still what table() makes — a rectangle and a text box per cell,
// grouped — and each of them carries its cell's place, the `table` key
// (TableCell): the table's id, the row and the column. The cells' texts are
// the table's content, so nothing else is kept. Every change here is to a
// page's elements, the table's cells found among them by its id, and ends
// with relayout: rows as tall as their words, stacked from the table's top,
// the texts in their cells. The Android twin's Tables does the same, number
// for number, over the same test table.

import Foundation

extension DataGraphics {

    /// The ink, banded fill and plain fill a table's body is drawn in.
    static let tableInk = "#1f2430"
    static let tableBand = "#f3f4f6"
    static let tableBody = "#ffffff"

    /// A cell's inset from its rectangle, as a share of the table's type.
    static let tablePad = 0.6

    /// Row `row`'s fill as a body row: banded every other row.
    static func tableBodyFill(_ row: Int, band: String = tableBand) -> String {
        row % 2 == 0 ? band : tableBody
    }

    /// Table `id`'s cells among `elements`, in their order.
    static func tableMembers(_ elements: [Element], id: String) -> [Element] {
        elements.filter { $0.table?.id == id }
    }

    /// Table `id`'s rows, top to bottom.
    static func tableRows(_ elements: [Element], id: String) -> [Int] {
        Set(tableMembers(elements, id: id).compactMap { $0.table?.row }).sorted()
    }

    /// Table `id`'s columns, left to right, as their rectangles have them.
    static func tableColumns(_ elements: [Element], id: String) -> [Int] {
        Set(tableMembers(elements, id: id).filter { $0.type == .shape }.compactMap { $0.table?.col }).sorted()
    }

    /// Whether table `id` is turned — whose rows and columns are not
    /// edited, as a turned table's cells no longer stand in rows.
    static func tableIsTurned(_ elements: [Element], id: String) -> Bool {
        tableMembers(elements, id: id).contains { $0.rotation != 0 }
    }

    /// A table's cells put back in order after an edit. Each column keeps
    /// the x and width of its top cell's rectangle; each text is fitted to
    /// its column, inset by `tablePad` times the type of the table's first
    /// cell, and measured by `heightFor`; each row is as tall as its tallest
    /// text and that inset above and below, the rows stacked down from the
    /// table's top; and each text sits in its cell — rounded as table()
    /// rounds, so a table just made comes back unchanged. Elements that are
    /// not cells, and a turned table, come back as they were.
    static func relayout(_ table: [Element], heightFor: (Element) -> Double) -> [Element] {
        let cells: [(el: Element, cell: TableCell)] = table.compactMap { el in el.table.map { (el: el, cell: $0) } }
        let rects = cells.filter { $0.el.type == .shape }
        guard !rects.isEmpty, !cells.contains(where: { $0.el.rotation != 0 }) else { return table }
        let texts = cells.filter { $0.el.type == .text }
        // Each column where its top cell is.
        var columns: [Int: (x: Double, w: Double)] = [:]
        var topRow: [Int: Int] = [:]
        for (el, cell) in rects where topRow[cell.col].map({ cell.row < $0 }) ?? true {
            topRow[cell.col] = cell.row
            columns[cell.col] = (el.x, el.w)
        }
        let first = texts.min { a, b in (a.cell.row, a.cell.col) < (b.cell.row, b.cell.col) }
        let size = first?.el.fontSize ?? 10
        let pad = size * tablePad
        var fitted: [String: Element] = [:]
        for (t, cell) in texts {
            guard let column = columns[cell.col] else { continue }
            var sized = t
            sized.w = max(column.w - 2 * pad, t.fontSize ?? size)
            sized.h = heightFor(sized)
            fitted[t.id] = sized
        }
        var tops: [Int: Double] = [:]
        var heights: [Int: Double] = [:]
        var y = rects.map { $0.el.y }.min() ?? 0
        for row in Set(cells.map { $0.cell.row }).sorted() {
            let tallest = texts.filter { $0.cell.row == row }.compactMap { fitted[$0.el.id]?.h }.max()
            // A row with no text left in it keeps its height.
            let h = tallest.map { ($0 + 2 * pad).rounded() }
                ?? rects.filter { $0.cell.row == row }.map { $0.el.h }.max() ?? 0
            tops[row] = y
            heights[row] = h
            y += h
        }
        return table.map { el in
            guard let cell = el.table, let column = columns[cell.col], let top = tops[cell.row] else { return el }
            switch el.type {
            case .shape:
                var out = el
                out.x = column.x.rounded()
                out.y = top.rounded()
                out.w = column.w
                out.h = heights[cell.row] ?? el.h
                return out
            case .text:
                guard var out = fitted[el.id] else { return el }
                out.x = (column.x + pad).rounded()
                out.y = (top + pad).rounded()
                return out
            default:
                return el
            }
        }
    }

    /// `elements` with table `id` laid out again (relayout).
    static func relaidTable(_ elements: [Element], id: String, heightFor: (Element) -> Double) -> [Element] {
        let laid = relayout(tableMembers(elements, id: id), heightFor: heightFor)
        let byId = Dictionary(laid.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return elements.map { byId[$0.id] ?? $0 }
    }

    // MARK: rows and columns

    /// A row added above or below `row` (below with `below`): a copy of that
    /// row's cells — their fills and their text's style — with no words,
    /// the rows after it moved down one.
    static func addingTableRow(_ elements: [Element], id: String, row: Int, below: Bool,
                               heightFor: (Element) -> Double) -> [Element] {
        guard tableRows(elements, id: id).contains(row) else { return elements }
        return relaidTable(insertingRow(elements, id: id, source: row, at: below ? row + 1 : row),
                           id: id, heightFor: heightFor)
    }

    /// A column added left or right of `col` (right with `right`), copying
    /// that column's cells with no words. It is as wide as the columns were
    /// on average, and the others are narrowed in proportion to make room,
    /// so the table is as wide as it was; the last column takes what
    /// rounding leaves over.
    static func addingTableColumn(_ elements: [Element], id: String, col: Int, right: Bool,
                                  heightFor: (Element) -> Double) -> [Element] {
        let boxes = columnBoxes(elements, id: id)
        let total = boxes.values.map { $0.w }.reduce(0, +)
        guard let left = boxes.values.map({ $0.x }).min(), boxes[col] != nil, total > 0 else { return elements }
        let average = total / Double(boxes.count)
        let at = right ? col + 1 : col
        var widths: [Int: Double] = [:]
        for (c, box) in boxes { widths[c >= at ? c + 1 : c] = box.w * (total - average) / total }
        widths[at] = average
        let added = insertingColumn(elements, id: id, source: col, at: at)
        return relaidTable(placingColumns(added, id: id, left: left, widths: roundedWidths(widths, total: total)),
                           id: id, heightFor: heightFor)
    }

    /// Row `row` taken out, the rows below moved up; nil when it is the
    /// table's last row, which never goes.
    static func deletingTableRow(_ elements: [Element], id: String, row: Int,
                                 heightFor: (Element) -> Double) -> [Element]? {
        let rows = tableRows(elements, id: id)
        guard rows.contains(row), rows.count > 1 else { return nil }
        return relaidTable(removingRow(elements, id: id, row: row), id: id, heightFor: heightFor)
    }

    /// Column `col` taken out and the columns left widened in proportion,
    /// so the table keeps its width, as adding one keeps it, the last column
    /// taking what rounding leaves over; nil when it is the table's last
    /// column, which never goes.
    static func deletingTableColumn(_ elements: [Element], id: String, col: Int,
                                    heightFor: (Element) -> Double) -> [Element]? {
        let boxes = columnBoxes(elements, id: id)
        guard let box = boxes[col], boxes.count > 1, let left = boxes.values.map({ $0.x }).min() else { return nil }
        let total = boxes.values.map { $0.w }.reduce(0, +)
        let rest = total - box.w
        guard rest > 0 else { return nil }
        var widths: [Int: Double] = [:]
        for (c, b) in boxes where c != col { widths[c > col ? c - 1 : c] = b.w * total / rest }
        let removed = removingColumn(elements, id: id, col: col)
        return relaidTable(placingColumns(removed, id: id, left: left, widths: roundedWidths(widths, total: total)),
                           id: id, heightFor: heightFor)
    }

    // MARK: look

    /// The rectangles of table `id`'s `cells` filled with `color`; their
    /// words keep their colour.
    static func colouringTableCells(_ elements: [Element], id: String, cells: Set<TableCell>,
                                    color: String) -> [Element] {
        elements.map { el in
            guard el.type == .shape, let cell = el.table, cell.id == id, cells.contains(cell) else { return el }
            var out = el
            out.fill = .solid(color)
            return out
        }
    }

    /// Whether table `id` has a header row: every word in row 0 bold.
    static func tableHasHeader(_ elements: [Element], id: String) -> Bool {
        let heads = tableMembers(elements, id: id).filter { $0.type == .text && $0.table?.row == 0 }
        return !heads.isEmpty && heads.allSatisfy { ($0.fontWeight ?? 400) >= 700 }
    }

    /// Row 0 made the header, as table() makes one — filled with `accent`,
    /// its words bold in ink that reads on it — or, with `on` false, a body
    /// row like the rest: banded, regular, in the table's ink.
    static func withTableHeader(_ elements: [Element], id: String, on: Bool, accent: String,
                                heightFor: (Element) -> Double) -> [Element] {
        let styled = elements.map { el -> Element in
            guard let cell = el.table, cell.id == id, cell.row == 0 else { return el }
            var out = el
            switch el.type {
            case .shape:
                out.fill = .solid(on ? accent : tableBodyFill(0))
            case .text:
                out.fontWeight = on ? 700 : 400
                out.color = on ? ColorTheory.readableInk(on: accent) : tableInk
            default:
                break
            }
            return out
        }
        return relaidTable(styled, id: id, heightFor: heightFor)
    }

    // MARK: as text

    /// Table `id`'s words as rows of cells, for the editor tables are typed
    /// in (parseTable reads them back, a line at a time): commas between
    /// cells, or tabs in a row whose words hold a comma; each cell's plain
    /// words, its line breaks and tabs spaces.
    static func tableText(_ elements: [Element], id: String) -> String {
        var words: [TableCell: String] = [:]
        for el in tableMembers(elements, id: id) where el.type == .text {
            if let cell = el.table { words[cell] = el.text ?? "" }
        }
        let columns = tableColumns(elements, id: id)
        return tableRows(elements, id: id).map { row in
            let cells = columns.map { col in words[TableCell(id: id, row: row, col: col)].map(plainWords) ?? "" }
            return cells.joined(separator: cells.contains { $0.contains(",") } ? "\t" : ", ")
        }.joined(separator: "\n")
    }

    /// Table `id` made `rows` of cells (parseTable's): rows and columns
    /// added at the end or taken off it until there are as many, every
    /// column it had keeping its width and a new one the width they
    /// averaged, so the table grows to the right; then each cell's words
    /// set, a cell whose words did not change keeping its own styles. A new
    /// row copies the row two above it, keeping the bands, or the last row
    /// when that would be the header. Nil when `rows` has no cell.
    static func rebuiltTable(_ elements: [Element], id: String, rows: [[String]],
                             heightFor: (Element) -> Double) -> [Element]? {
        guard let wanted = rows.map(\.count).max(), wanted > 0,
              !columnBoxes(elements, id: id).isEmpty else { return nil }
        var out = elements
        while true {
            let have = tableRows(out, id: id)
            guard have.count < rows.count, let last = have.last else { break }
            let source = have.count >= 3 ? have[have.count - 2] : last
            out = insertingRow(out, id: id, source: source, at: last + 1)
        }
        while tableRows(out, id: id).count > rows.count, let last = tableRows(out, id: id).last {
            out = removingRow(out, id: id, row: last)
        }
        while true {
            let boxes = columnBoxes(out, id: id)
            guard boxes.count < wanted, let last = boxes.keys.max(),
                  let left = boxes.values.map({ $0.x }).min() else { break }
            var widths = boxes.mapValues { $0.w }
            widths[last + 1] = (boxes.values.map { $0.w }.reduce(0, +) / Double(boxes.count)).rounded()
            out = placingColumns(insertingColumn(out, id: id, source: last, at: last + 1), id: id, left: left, widths: widths)
        }
        while true {
            let boxes = columnBoxes(out, id: id)
            guard boxes.count > wanted, let last = boxes.keys.max() else { break }
            out = removingColumn(out, id: id, col: last)
        }
        let rowAt = Dictionary(uniqueKeysWithValues: tableRows(out, id: id).enumerated().map { ($0.element, $0.offset) })
        let colAt = Dictionary(uniqueKeysWithValues: tableColumns(out, id: id).enumerated().map { ($0.element, $0.offset) })
        out = out.map { el in
            guard el.type == .text, let cell = el.table, cell.id == id,
                  let r = rowAt[cell.row], let c = colAt[cell.col], r < rows.count else { return el }
            let words = c < rows[r].count ? rows[r][c] : ""
            if plainWords(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == words { return el }
            var set = el
            set.setText(words)
            return set
        }
        return relaidTable(out, id: id, heightFor: heightFor)
    }

    // MARK: after a step

    /// `after` with each table whose words changed since `before` laid out
    /// again — a cell typed in, its type changed in the Text controls, words
    /// replaced — so a row grows with its words in the same step that grew
    /// them. Moving cells about is not a change of words, and tables
    /// nothing was typed in are left where they are.
    static func settlingTables(_ after: Design, since before: Design, heightFor: (Element) -> Double) -> Design {
        var out = after
        for p in out.pages.indices {
            let page = out.pages[p]
            let old = before.pages.first { $0.id == page.id }
            if let old, old.elements == page.elements { continue }
            var was: [String: Element] = [:]
            for el in old?.elements ?? [] where el.type == .text && el.table != nil { was[el.id] = el }
            var edited: [String] = []
            for el in page.elements where el.type == .text {
                guard let cell = el.table, !edited.contains(cell.id) else { continue }
                if let w = was[el.id], !wordsDiffer(w, el) { continue }
                edited.append(cell.id)
            }
            guard !edited.isEmpty else { continue }
            var elements = page.elements
            for id in edited { elements = relaidTable(elements, id: id, heightFor: heightFor) }
            if elements != page.elements { out.pages[p].elements = elements }
        }
        return out
    }

    // MARK: rows and columns, before the relayout

    /// Row `source` copied, without words, in as row `at`; rows from `at`
    /// on moved down one.
    private static func insertingRow(_ elements: [Element], id: String, source: Int, at: Int) -> [Element] {
        let copies = tableMembers(elements, id: id).filter { $0.table?.row == source }
        let shifted = elements.map { el -> Element in
            guard let cell = el.table, cell.id == id, cell.row >= at else { return el }
            var out = el
            out.table = TableCell(id: id, row: cell.row + 1, col: cell.col)
            return out
        }
        return inserting(copies.map { blank($0, row: at, col: $0.table?.col ?? 0) }, into: shifted, id: id)
    }

    /// Column `source` copied, without words, in as column `at`; columns
    /// from `at` on moved right one.
    private static func insertingColumn(_ elements: [Element], id: String, source: Int, at: Int) -> [Element] {
        let copies = tableMembers(elements, id: id).filter { $0.table?.col == source }
        let shifted = elements.map { el -> Element in
            guard let cell = el.table, cell.id == id, cell.col >= at else { return el }
            var out = el
            out.table = TableCell(id: id, row: cell.row, col: cell.col + 1)
            return out
        }
        return inserting(copies.map { blank($0, row: $0.table?.row ?? 0, col: at) }, into: shifted, id: id)
    }

    /// Table `id`'s rectangles each at its column's width in `widths` (by
    /// column), the columns side by side from `left`; the relayout then
    /// fits the words to them.
    private static func placingColumns(_ elements: [Element], id: String, left: Double,
                                       widths: [Int: Double]) -> [Element] {
        var xs: [Int: Double] = [:]
        var x = left
        for c in widths.keys.sorted() {
            xs[c] = x
            x += widths[c] ?? 0
        }
        return elements.map { el in
            guard el.type == .shape, let cell = el.table, cell.id == id,
                  let cx = xs[cell.col], let w = widths[cell.col] else { return el }
            var out = el
            out.x = cx
            out.w = w
            return out
        }
    }

    /// Row `row` gone, the rows below numbered up one, the table's top kept
    /// where it was.
    private static func removingRow(_ elements: [Element], id: String, row: Int) -> [Element] {
        guard let top = tableMembers(elements, id: id).filter({ $0.type == .shape }).map(\.y).min() else { return elements }
        let kept = elements.filter { !($0.table?.id == id && $0.table?.row == row) }.map { el -> Element in
            guard let cell = el.table, cell.id == id, cell.row > row else { return el }
            var out = el
            out.table = TableCell(id: id, row: cell.row - 1, col: cell.col)
            return out
        }
        // Restacked from the top, so the new first row starts where the old one did.
        guard let first = tableRows(kept, id: id).first else { return kept }
        return kept.map { el in
            guard el.type == .shape, el.table?.id == id, el.table?.row == first else { return el }
            var out = el
            out.y = top
            return out
        }
    }

    /// Column `col` gone, the columns right of it numbered down one.
    private static func removingColumn(_ elements: [Element], id: String, col: Int) -> [Element] {
        elements.filter { !($0.table?.id == id && $0.table?.col == col) }.map { el in
            guard let cell = el.table, cell.id == id, cell.col > col else { return el }
            var out = el
            out.table = TableCell(id: id, row: cell.row, col: cell.col - 1)
            return out
        }
    }

    /// A cell's copy for a new row or column: a new element, no words.
    private static func blank(_ el: Element, row: Int, col: Int) -> Element {
        var copy = el
        copy.id = UID.make()
        if el.type == .text { copy.setText("") }
        if let cell = el.table { copy.table = TableCell(id: cell.id, row: row, col: col) }
        return copy
    }

    /// `fresh` cells put in just above table `id`'s last element, so they
    /// are in its layer — rectangles first, under the words.
    private static func inserting(_ fresh: [Element], into elements: [Element], id: String) -> [Element] {
        let after = (elements.lastIndex { $0.table?.id == id } ?? -1) + 1
        let ordered = fresh.filter { $0.type != .text } + fresh.filter { $0.type == .text }
        var out = elements
        out.insert(contentsOf: ordered, at: after)
        return out
    }

    /// `widths` (by column) each rounded, the last column given what is
    /// left of `total`, so they add up to it exactly.
    private static func roundedWidths(_ widths: [Int: Double], total: Double) -> [Int: Double] {
        var out = widths.mapValues { $0.rounded() }
        guard let last = out.keys.max(), let own = out[last] else { return out }
        out[last] = total - (out.values.reduce(0, +) - own)
        return out
    }

    /// Each column's x and width, as its top cell's rectangle has them.
    private static func columnBoxes(_ elements: [Element], id: String) -> [Int: (x: Double, w: Double)] {
        var boxes: [Int: (x: Double, w: Double)] = [:]
        var topRow: [Int: Int] = [:]
        for el in tableMembers(elements, id: id) where el.type == .shape {
            guard let cell = el.table, topRow[cell.col].map({ cell.row < $0 }) ?? true else { continue }
            topRow[cell.col] = cell.row
            boxes[cell.col] = (el.x, el.w)
        }
        return boxes
    }

    /// A cell's words as they are typed in the table editor: no style
    /// marks, line breaks and tabs as spaces, so each reads back in its own
    /// cell.
    private static func plainWords(_ text: String) -> String {
        RichText.strip(text).components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "\t")))
            .joined(separator: " ")
    }

    /// Whether a cell's words, or anything that sets how much room they
    /// take, changed.
    private static func wordsDiffer(_ a: Element, _ b: Element) -> Bool {
        a.text != b.text || a.fontSize != b.fontSize || a.fontFamily != b.fontFamily
            || a.fontWeight != b.fontWeight || a.italic != b.italic || a.lineHeight != b.lineHeight
            || a.letterSpacing != b.letterSpacing || a.spans != b.spans || a.spansText != b.spansText
            || a.table != b.table
    }
}
