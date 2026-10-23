// Tables that stay tables: rows and columns added and taken away, the header
// turned on and off, cells recoloured and merged, borders and column widths
// set, the table set again from its words, and every row as tall as its
// words.
//
// A table is still what table() makes — a rectangle and a text box per cell,
// grouped — and each of them carries its cell's place, the `table` key
// (TableCell): the table's id, the row and the column, and for a merged
// cell the rows and columns it spans. The cells' texts are the table's
// content, and its borders its rectangles' strokes, so nothing else is
// kept. Every change here is to a page's elements, the table's cells found
// among them by its id, and ends with relayout: rows as tall as their
// words, stacked from the table's top, the texts in their cells. The Android twin's Tables does the same, number
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

    /// Table `id`'s rows, top to bottom: every row a cell covers, merged
    /// down into or not.
    static func tableRows(_ elements: [Element], id: String) -> [Int] {
        Set(tableMembers(elements, id: id).compactMap(\.table).flatMap { Array($0.spannedRows) }).sorted()
    }

    /// Table `id`'s columns, left to right, as their rectangles cover them.
    static func tableColumns(_ elements: [Element], id: String) -> [Int] {
        Set(tableMembers(elements, id: id).filter { $0.type == .shape }.compactMap(\.table)
            .flatMap { Array($0.spannedCols) }).sorted()
    }

    /// What VoiceOver says of table `id`'s cell at `row`, `col` — the
    /// Android twin's Tables.spokenCell, word for word: "Row 2 of 5, Column
    /// 3 of 4, Price: 3.50", its place counted from 1 among the table's rows
    /// and columns, then its column's header (the words of row 0's cell over
    /// it) and its own words. The header row says its words alone, as does
    /// a cell under a blank header; a merged cell adds how far it spans,
    /// "spans 2 columns", "spans 3 rows". Its lines are read as one. Nil
    /// when the table has no such cell.
    static func spokenCell(_ elements: [Element], id: String, row: Int, col: Int) -> String? {
        let cells = tableMembers(elements, id: id).compactMap { el in el.table.map { (el: el, cell: $0) } }
        guard let cell = cells.first(where: { $0.cell.row == row && $0.cell.col == col })?.cell else { return nil }
        func words(_ r: Int, _ c: Int) -> String {
            let text = cells.first { $0.el.type == .text && $0.cell.row == r && $0.cell.spannedCols.contains(c) }?.el.text
            return RichText.strip(text ?? "").replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let place = tr("Row %d of %d, Column %d of %d", row + 1, tableRows(elements, id: id).count,
                       col + 1, tableColumns(elements, id: id).count)
        let own = words(row, col)
        let header = row == 0 ? "" : words(0, col)
        let said = header.isEmpty ? own : tr("%@: %@", header, own)
        var parts = [place, said]
        if cell.colSpan > 1 { parts.append(trn("spans %d column|spans %d columns", cell.colSpan)) }
        if cell.rowSpan > 1 { parts.append(trn("spans %d row|spans %d rows", cell.rowSpan)) }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Whether table `id` is turned — whose rows and columns are not
    /// edited, as a turned table's cells no longer stand in rows.
    static func tableIsTurned(_ elements: [Element], id: String) -> Bool {
        tableMembers(elements, id: id).contains { $0.rotation != 0 }
    }

    /// A table's cells put back in order after an edit. Each column keeps
    /// the x and width it has (columnBoxes); each text is fitted to the
    /// columns its cell spans, inset by `tablePad` times the type of the
    /// table's first cell, and measured by `heightFor`; each row is as tall
    /// as rowHeights makes it, the rows stacked down from the table's top;
    /// each rectangle spans its cell's columns and rows; and each text sits
    /// in its cell — rounded as table() rounds, so a table just made comes
    /// back unchanged. Elements that are not cells, and a turned table, come
    /// back as they were.
    static func relayout(_ table: [Element], heightFor: (Element) -> Double) -> [Element] {
        let cells: [(el: Element, cell: TableCell)] = table.compactMap { el in el.table.map { (el: el, cell: $0) } }
        let rects = cells.filter { $0.el.type == .shape }
        guard !rects.isEmpty, !cells.contains(where: { $0.el.rotation != 0 }) else { return table }
        let texts = cells.filter { $0.el.type == .text }
        let columns = columnBoxes(of: table)
        // The x a cell starts at and the width of all the columns it spans.
        func across(_ cell: TableCell) -> (x: Double, w: Double)? {
            guard let first = columns[cell.col] else { return nil }
            return (first.x, cell.spannedCols.compactMap { columns[$0]?.w }.reduce(0, +))
        }
        let first = texts.min { a, b in (a.cell.row, a.cell.col) < (b.cell.row, b.cell.col) }
        let size = first?.el.fontSize ?? 10
        // The table's own cell spacing, or the inset it was made with.
        let pad = first?.cell.pad ?? size * tablePad
        var fitted: [String: Element] = [:]
        for (t, cell) in texts {
            guard let span = across(cell) else { continue }
            var sized = t
            sized.w = max(span.w - 2 * pad, t.fontSize ?? size)
            sized.h = heightFor(sized)
            fitted[t.id] = sized
        }
        let heights = rowHeights(rects: rects, texts: texts, fitted: fitted, pad: pad)
        var tops: [Int: Double] = [:]
        var y = rects.map { $0.el.y }.min() ?? 0
        for row in heights.keys.sorted() {
            tops[row] = y
            y += heights[row] ?? 0
        }
        return table.map { el in
            guard let cell = el.table, let span = across(cell), let top = tops[cell.row] else { return el }
            switch el.type {
            case .shape:
                var out = el
                out.x = span.x.rounded()
                out.y = top.rounded()
                out.w = span.w
                out.h = cell.spannedRows.compactMap { heights[$0] }.reduce(0, +)
                return out
            case .text:
                guard var out = fitted[el.id] else { return el }
                out.x = (span.x + pad).rounded()
                out.y = (top + pad).rounded()
                return out
            default:
                return el
            }
        }
    }

    /// Each row's height, for relayout, by the Android twin's rule, number
    /// for number: as tall as the tallest words of a cell of its own — one
    /// row tall — and `pad` above and below, rounded; a row with no such
    /// words keeps its height, the tallest of its own rectangles. A row with
    /// none of its own — every cell in it merged with a row above or below —
    /// shares, evenly with the other rows like it, what the top-left merged
    /// rectangle over it leaves of its height once its other rows are taken
    /// away; a row still unknown is none tall. Then a merged text taller
    /// than its rows, inset, makes the last of them taller by what it
    /// lacks, merged cells from the top and left first.
    private static func rowHeights(rects: [(el: Element, cell: TableCell)], texts: [(el: Element, cell: TableCell)],
                                   fitted: [String: Element], pad: Double) -> [Int: Double] {
        let rows = Set((rects + texts).flatMap { Array($0.cell.spannedRows) }).sorted()
        var heights: [Int: Double] = [:]
        for row in rows {
            let tallest = texts.filter { $0.cell.row == row && $0.cell.rowSpan <= 1 }.compactMap { fitted[$0.el.id]?.h }.max()
            let own = rects.filter { $0.cell.row == row && $0.cell.rowSpan <= 1 }.map { $0.el.h }.max()
            if let h = tallest.map({ ($0 + 2 * pad).rounded() }) ?? own { heights[row] = h }
        }
        func merged(_ cells: [(el: Element, cell: TableCell)]) -> [(el: Element, cell: TableCell)] {
            cells.filter { $0.cell.rowSpan > 1 }.sorted { a, b in (a.cell.row, a.cell.col) < (b.cell.row, b.cell.col) }
        }
        for (rect, cell) in merged(rects) {
            let unknown = cell.spannedRows.filter { heights[$0] == nil }
            guard !unknown.isEmpty else { continue }
            let known = cell.spannedRows.compactMap { heights[$0] }.reduce(0, +)
            let share = max(0, rect.h - known) / Double(unknown.count)
            for r in unknown { heights[r] = share }
        }
        for row in rows where heights[row] == nil { heights[row] = 0 }
        for (t, cell) in merged(texts) {
            guard let h = fitted[t.id]?.h, let last = cell.spannedRows.last else { continue }
            let have = cell.spannedRows.compactMap { heights[$0] }.reduce(0, +)
            let need = (h + 2 * pad).rounded()
            if need > have { heights[last] = (heights[last] ?? 0) + need - have }
        }
        return heights
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
        let added = insertingRow(elements, id: id, source: row, at: below ? row + 1 : row)
        return relaidTable(restriped(added, id: id), id: id, heightFor: heightFor)
    }

    /// A column added left or right of `col` (right with `right`), copying
    /// that column's cells with no words. It is as wide as the columns were
    /// on average before it came, and the others are narrowed in proportion
    /// to make room, so the table is as wide as it was; the last column
    /// takes what rounding leaves over.
    static func addingTableColumn(_ elements: [Element], id: String, col: Int, right: Bool,
                                  heightFor: (Element) -> Double) -> [Element] {
        guard columnBoxes(elements, id: id)[col] != nil,
              let added = withColumn(elements, id: id, source: col, at: right ? col + 1 : col) else { return elements }
        return relaidTable(added, id: id, heightFor: heightFor)
    }

    /// Row `row` taken out, the rows below moved up; nil when it is the
    /// table's last row, which never goes.
    static func deletingTableRow(_ elements: [Element], id: String, row: Int,
                                 heightFor: (Element) -> Double) -> [Element]? {
        let rows = tableRows(elements, id: id)
        guard rows.contains(row), rows.count > 1 else { return nil }
        return relaidTable(restriped(removingRow(elements, id: id, row: row), id: id), id: id, heightFor: heightFor)
    }

    /// Column `col` taken out and the columns left widened in proportion,
    /// so the table keeps its width, as adding one keeps it, the last column
    /// taking what rounding leaves over; nil when it is the table's last
    /// column, which never goes.
    static func deletingTableColumn(_ elements: [Element], id: String, col: Int,
                                    heightFor: (Element) -> Double) -> [Element]? {
        let boxes = columnBoxes(elements, id: id)
        guard boxes[col] != nil, boxes.count > 1,
              let removed = withoutColumn(elements, id: id, col: col) else { return nil }
        return relaidTable(removed, id: id, heightFor: heightFor)
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
    /// row like the rest: regular, in the table's ink, and filled as row 0
    /// of the body is banded — in the table's alternating rows' colour as
    /// the sheet shows it (tableBandsShown), white when they are off — the
    /// other rows left as they are.
    static func withTableHeader(_ elements: [Element], id: String, on: Bool, accent: String,
                                heightFor: (Element) -> Double) -> [Element] {
        let band = tableBandsShown(elements, id: id)
        let styled = elements.map { el -> Element in
            guard let cell = el.table, cell.id == id, cell.row == 0 else { return el }
            var out = el
            switch el.type {
            case .shape:
                out.fill = .solid(on ? accent : band.map { tableBodyFill(0, band: $0) } ?? tableBody)
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

    // MARK: merged cells

    /// The block of rows and columns `cells` of table `id` make together,
    /// when they can be merged: two or more cells that cover every place of
    /// the rectangle round them and no place twice, no other cell of the
    /// table reaching into it. A merged cell among them counts with all it
    /// covers. Nil otherwise.
    static func mergeBlock(_ elements: [Element], id: String,
                           cells: Set<TableCell>) -> (rows: Range<Int>, cols: Range<Int>)? {
        let chosen = Set(cells.filter { $0.id == id }.map { [$0.row, $0.col] })
        let placed = tableMembers(elements, id: id).filter { $0.type == .shape }.compactMap(\.table)
        // A rectangle per cell.
        let picked = Dictionary(placed.filter { chosen.contains([$0.row, $0.col]) }.map { ([$0.row, $0.col], $0) },
                                uniquingKeysWith: { first, _ in first })
        let anchors = Array(picked.values)
        guard anchors.count >= 2,
              let top = anchors.map(\.row).min(), let left = anchors.map(\.col).min(),
              let bottom = anchors.map({ $0.row + $0.rowSpan }).max(),
              let right = anchors.map({ $0.col + $0.colSpan }).max() else { return nil }
        let rows = top..<bottom
        let cols = left..<right
        var covered = Set<[Int]>()
        for cell in anchors {
            for r in cell.spannedRows {
                for c in cell.spannedCols {
                    guard covered.insert([r, c]).inserted else { return nil }
                }
            }
        }
        guard covered.count == rows.count * cols.count else { return nil }
        for cell in placed where picked[[cell.row, cell.col]] == nil {
            if cell.spannedRows.overlaps(rows) && cell.spannedCols.overlaps(cols) { return nil }
        }
        return (rows, cols)
    }

    /// `cells` of table `id` merged into one, when they make a block
    /// (mergeBlock): the top-left cell's rectangle and text kept, spanning
    /// the block, its words those of each merged cell that has any, in
    /// reading order, a line each; the rectangle made the box the merged
    /// ones filled, so a row left with no cell of its own keeps its height;
    /// the other cells' rectangles and texts taken out; the table laid out
    /// again. Nil when they make no block.
    static func mergingTableCells(_ elements: [Element], id: String, cells: Set<TableCell>,
                                  heightFor: (Element) -> Double) -> [Element]? {
        guard let block = mergeBlock(elements, id: id, cells: cells) else { return nil }
        func inBlock(_ cell: TableCell) -> Bool {
            cell.id == id && block.rows.contains(cell.row) && block.cols.contains(cell.col)
        }
        func words(_ el: Element) -> String {
            RichText.strip(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let texts = tableMembers(elements, id: id).filter { $0.type == .text && $0.table.map(inBlock) == true }
            .sorted { a, b in (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0) }
        let joined = texts.map(words).filter { !$0.isEmpty }.joined(separator: "\n")
        let box = Geometry.union(tableMembers(elements, id: id)
            .filter { $0.type == .shape && $0.table.map(inBlock) == true }.map(\.frame))
        let look = tableMembers(elements, id: id).lazy.compactMap(\.table).first
        let merged = TableCell(id: id, row: block.rows.lowerBound, col: block.cols.lowerBound,
                               rowSpan: block.rows.count, colSpan: block.cols.count, pad: look?.pad, bands: look?.bands)
        let out = elements.compactMap { el -> Element? in
            guard let cell = el.table, inBlock(cell) else { return el }
            guard cell.row == merged.row && cell.col == merged.col else { return nil }
            var kept = el
            kept.table = merged
            if el.type == .text && words(el) != joined { kept.setText(joined) }
            if el.type == .shape {
                kept.x = Double(box.minX)
                kept.y = Double(box.minY)
                kept.w = Double(box.width)
                kept.h = Double(box.height)
            }
            return kept
        }
        return relaidTable(out, id: id, heightFor: heightFor)
    }

    /// The merged cells among `cells` of table `id` parted again: each one
    /// cell as it was before, its words and look kept, and a blank cell — a
    /// copy of its rectangle, and of its text with no words — in every
    /// other place it covered, each at its column's width; then the table
    /// laid out again. Nil when none of them is merged.
    static func unmergingTableCells(_ elements: [Element], id: String, cells: Set<TableCell>,
                                    heightFor: (Element) -> Double) -> [Element]? {
        let chosen = Set(cells.filter { $0.id == id }.map { [$0.row, $0.col] })
        func parting(_ cell: TableCell) -> Bool { cell.isMerged && chosen.contains([cell.row, cell.col]) }
        let members = tableMembers(elements, id: id)
        let merged = members.filter { $0.table.map(parting) == true }
        guard !merged.isEmpty else { return nil }
        let columns = columnBoxes(of: members)
        // A rectangle at its place's column and its share of the rows.
        func placed(_ el: Element, _ cell: TableCell, row: Int, col: Int) -> Element {
            guard el.type == .shape else { return el }
            var out = el
            out.h = el.h / Double(cell.rowSpan)
            out.y = el.y + out.h * Double(row - cell.row)
            if let box = columns[col] {
                out.x = box.x
                out.w = box.w
            }
            return out
        }
        var fresh: [Element] = []
        for el in merged {
            guard let cell = el.table else { continue }
            for r in cell.spannedRows {
                for c in cell.spannedCols where r != cell.row || c != cell.col {
                    fresh.append(placed(blank(el, row: r, col: c), cell, row: r, col: c))
                }
            }
        }
        let parted = elements.map { el -> Element in
            guard let cell = el.table, cell.id == id, parting(cell) else { return el }
            var out = placed(el, cell, row: cell.row, col: cell.col)
            out.table = TableCell(id: id, row: cell.row, col: cell.col, pad: cell.pad, bands: cell.bands)
            return out
        }
        return relaidTable(inserting(fresh, into: parted, id: id), id: id, heightFor: heightFor)
    }

    // MARK: borders

    /// The Borders choices — None, Thin (a new table's), Medium and Thick —
    /// and the width each sets every cell rectangle's stroke at, as the
    /// Android twin offers them. A table's border is no key of its own: it
    /// is the `stroke` and `strokeWidth` its rectangles already have.
    static let tableBorderWeights: [(name: String, width: Double)] = [
        (tr("None"), 0), (tr("Thin"), 1), (tr("Medium"), 2), (tr("Thick"), 4),
    ]
    /// The heaviest border a table takes; the Border width slider runs from
    /// none to it.
    static let tableBorderMax = 12.0
    /// A new table's border colour, a faint hairline.
    static let tableHairline = "#00000022"

    /// The width every rectangle of table `id` has its stroke at, one with
    /// none being 0; nil when they differ.
    static func tableBorderWidth(_ elements: [Element], id: String) -> Double? {
        let widths = Set(tableMembers(elements, id: id).filter { $0.type == .shape }.map { $0.strokeWidth ?? 0 })
        return widths.count == 1 ? widths.first : nil
    }

    /// The colour every rectangle of table `id` strokes in; nil when they
    /// differ or have none.
    static func tableBorderColour(_ elements: [Element], id: String) -> String? {
        let colours = Set(tableMembers(elements, id: id).filter { $0.type == .shape }.map(\.stroke))
        return colours.count == 1 ? colours.first ?? nil : nil
    }

    /// Every rectangle of table `id` stroked `width` wide, held to
    /// 0...tableBorderMax, when given, and in `color` when given. The rows
    /// stay as they are: a border takes no room.
    static func borderingTable(_ elements: [Element], id: String, width: Double?, color: String?) -> [Element] {
        elements.map { el in
            guard el.type == .shape, el.table?.id == id else { return el }
            var out = el
            if let width { out.strokeWidth = min(max(width, 0), tableBorderMax) }
            if let color { out.stroke = color }
            return out
        }
    }

    // MARK: column widths

    /// The narrowest a column is dragged.
    static let minColumnWidth = 24.0

    /// Table `id`'s column widths, left to right (columnBoxes).
    static func tableColumnWidths(_ elements: [Element], id: String) -> [Double] {
        let boxes = columnBoxes(elements, id: id)
        return boxes.keys.sorted().compactMap { boxes[$0]?.w }
    }

    /// Table `id`'s inner column edges, left to right: where each column
    /// but the last ends.
    static func tableColumnEdges(_ elements: [Element], id: String) -> [Double] {
        let boxes = columnBoxes(elements, id: id)
        return boxes.keys.sorted().dropLast().compactMap { boxes[$0].map { $0.x + $0.w } }
    }

    /// `widths` (columns left to right) with the edge between column
    /// `edge` and the next dragged by `dx`: the column left of it the whole
    /// number nearest its width and `dx`, the one right of it what that
    /// leaves of the two together, so the table keeps its width; each at
    /// least minColumnWidth. Two together narrower than twice that stay as
    /// they are. Nil when there is no such edge. The Android twin's rule,
    /// row for row in the tests.
    static func draggedColumns(_ widths: [Double], edge: Int, by dx: Double) -> [Double]? {
        guard edge >= 0, edge + 1 < widths.count else { return nil }
        let both = widths[edge] + widths[edge + 1]
        guard both >= 2 * minColumnWidth else { return widths }
        let left = min(max((widths[edge] + dx).rounded(), minColumnWidth), both - minColumnWidth)
        var out = widths
        out[edge] = left
        out[edge + 1] = both - left
        return out
    }

    /// `count` columns sharing `total` evenly, each the whole number
    /// nearest its share and the last what is left, as Distribute columns
    /// shares out a table's width.
    static func evenColumns(total: Double, count: Int) -> [Double] {
        guard count > 0 else { return [] }
        let share = (total / Double(count)).rounded()
        var out = Array(repeating: share, count: count)
        out[count - 1] = total - share * Double(count - 1)
        return out
    }

    /// Table `id`'s columns made `widths` wide, left to right from the
    /// table's left edge, and the table laid out again to them — the words
    /// fitted, each row as tall as they then need. `elements` themselves
    /// when `widths` are not one per column.
    static func placingTableColumns(_ elements: [Element], id: String, widths: [Double],
                                    heightFor: (Element) -> Double) -> [Element] {
        let boxes = columnBoxes(elements, id: id)
        let columns = boxes.keys.sorted()
        guard columns.count == widths.count, let left = boxes.values.map({ $0.x }).min() else { return elements }
        let byColumn = Dictionary(uniqueKeysWithValues: zip(columns, widths))
        return relaidTable(placingColumns(elements, id: id, left: left, widths: byColumn), id: id, heightFor: heightFor)
    }

    // MARK: moving rows and columns

    /// Whether moving row `row` of table `id` by `step` would part a merged
    /// cell: one running down through either of the two rows that change
    /// places. Moving it is refused then (Unmerge first).
    static func rowMoveSplitsMerge(_ elements: [Element], id: String, row: Int, by step: Int) -> Bool {
        tableMembers(elements, id: id).compactMap(\.table).contains { cell in
            cell.rowSpan > 1 && (cell.spannedRows.contains(row) || cell.spannedRows.contains(row + step))
        }
    }

    /// Whether moving column `col` by `step` would part a merged cell: one
    /// running across either of the two columns that change places.
    static func columnMoveSplitsMerge(_ elements: [Element], id: String, col: Int, by step: Int) -> Bool {
        tableMembers(elements, id: id).compactMap(\.table).contains { cell in
            cell.colSpan > 1 && (cell.spannedCols.contains(col) || cell.spannedCols.contains(col + step))
        }
    }

    /// Whether moving row `row` of table `id` `step` rows would take its
    /// header off the top, or put another row there: refused, as the
    /// Android twin's Tables.keepsHeader refuses it, with "The header row
    /// stays at the top" — striped again, the old header would be a body
    /// row, its light bold words on white.
    static func tableHeaderStays(_ elements: [Element], id: String, row: Int, by step: Int) -> Bool {
        tableHasHeader(elements, id: id) && (row == 0 || row + step == 0)
    }

    /// Row `row` of table `id` and the row `step` (±1) from it changed
    /// places — their cells, words and colours with them — the alternating
    /// rows striped again (restriped) and the table laid out again. Nil when
    /// there is no row there, when the header would leave the top
    /// (tableHeaderStays), or when a merged cell would be parted
    /// (rowMoveSplitsMerge).
    static func movedTableRow(_ elements: [Element], id: String, row: Int, by step: Int,
                              heightFor: (Element) -> Double) -> [Element]? {
        let rows = tableRows(elements, id: id)
        let other = row + step
        guard step != 0, rows.contains(row), rows.contains(other),
              !tableHeaderStays(elements, id: id, row: row, by: step),
              !rowMoveSplitsMerge(elements, id: id, row: row, by: step) else { return nil }
        let swapped = elements.map { el -> Element in
            guard var cell = el.table, cell.id == id, cell.row == row || cell.row == other else { return el }
            cell.row = cell.row == row ? other : row
            var out = el
            out.table = cell
            return out
        }
        return relaidTable(restriped(swapped, id: id), id: id, heightFor: heightFor)
    }

    /// Column `col` of table `id` and the column `step` (±1) from it changed
    /// places — each keeping its width — and the table laid out again. Nil
    /// when there is no column there, or when a merged cell would be parted
    /// (columnMoveSplitsMerge).
    static func movedTableColumn(_ elements: [Element], id: String, col: Int, by step: Int,
                                 heightFor: (Element) -> Double) -> [Element]? {
        let boxes = columnBoxes(elements, id: id)
        let other = col + step
        guard step != 0, let mine = boxes[col], let theirs = boxes[other],
              let left = boxes.values.map({ $0.x }).min(),
              !columnMoveSplitsMerge(elements, id: id, col: col, by: step) else { return nil }
        var widths = boxes.mapValues { $0.w }
        widths[col] = theirs.w
        widths[other] = mine.w
        let swapped = elements.map { el -> Element in
            guard var cell = el.table, cell.id == id, cell.col == col || cell.col == other else { return el }
            cell.col = cell.col == col ? other : col
            var out = el
            out.table = cell
            return out
        }
        return relaidTable(placingColumns(swapped, id: id, left: left, widths: widths), id: id, heightFor: heightFor)
    }

    // MARK: cell spacing

    /// The most the Cell spacing slider sets, in page units.
    static let tablePadMax = 40.0

    /// The inset table `id` was made with: tablePad times the type of its
    /// first cell's words.
    static func defaultTablePadding(_ elements: [Element], id: String) -> Double {
        let texts = tableMembers(elements, id: id).filter { $0.type == .text }
        let first = texts.min { a, b in
            (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0)
        }
        return (first?.fontSize ?? 10) * tablePad
    }

    /// Table `id`'s cell spacing: its own, or the inset it was made with.
    static func tablePadding(_ elements: [Element], id: String) -> Double {
        tableMembers(elements, id: id).lazy.compactMap { $0.table?.pad }.first
            ?? defaultTablePadding(elements, id: id)
    }

    /// Table `id` with its words inset `padding` (held to 0…tablePadMax)
    /// from its cells' edges: kept as `pad` on every cell, and none when it
    /// is the inset the table was made with, then the table laid out again,
    /// its rows as tall as their words and the new spacing need.
    static func withTablePadding(_ elements: [Element], id: String, padding: Double,
                                 heightFor: (Element) -> Double) -> [Element] {
        guard padding.isFinite else { return elements }
        let held = min(max(padding, 0), tablePadMax)
        let pad: Double? = abs(held - defaultTablePadding(elements, id: id)) < 1e-9 ? nil : held
        let set = elements.map { el -> Element in
            guard var cell = el.table, cell.id == id else { return el }
            cell.pad = pad
            var out = el
            out.table = cell
            return out
        }
        return relaidTable(set, id: id, heightFor: heightFor)
    }

    // MARK: alternating rows

    /// Table `id`'s alternating rows' colour, while they are kept; nil when
    /// they are not.
    static func tableBands(_ elements: [Element], id: String) -> String? {
        tableMembers(elements, id: id).lazy.compactMap { $0.table?.bands }.first
    }

    /// Table `id`'s alternating rows as the Table sheet shows them: the
    /// colour kept (tableBands), or — with none kept — the default band
    /// while the body is striped as a table is made (every body rectangle
    /// in tableBodyFill of its row, and at least one row in the band), so
    /// a table just made, or made before `bands` was kept, reads On; nil
    /// otherwise. The Android twin's Tables.bandsShown, rule for rule.
    static func tableBandsShown(_ elements: [Element], id: String) -> String? {
        if let kept = tableBands(elements, id: id) { return kept }
        let header = tableHasHeader(elements, id: id)
        let body = tableMembers(elements, id: id).filter { el in
            guard el.type == .shape, let cell = el.table else { return false }
            return !(header && cell.row == 0)
        }
        guard body.contains(where: { ($0.table?.row ?? 1) % 2 == 0 }) else { return nil }
        let striped = body.allSatisfy { el in
            el.fill?.kind == "solid" && el.fill?.color?.lowercased() == tableBodyFill(el.table?.row ?? 0)
        }
        return striped ? tableBand : nil
    }

    /// Table `id` with alternating rows in `colour` (`on`), kept as `bands`
    /// on every cell and striped again whenever a row is added, deleted or
    /// moved — or with none, every body row plain white (striped).
    static func withTableBands(_ elements: [Element], id: String, on: Bool, colour: String) -> [Element] {
        let bands: String? = on ? colour.lowercased() : nil
        let set = elements.map { el -> Element in
            guard var cell = el.table, cell.id == id else { return el }
            cell.bands = bands
            var out = el
            out.table = cell
            return out
        }
        return striped(set, id: id, band: bands)
    }

    /// Table `id` striped again in its kept alternating rows' colour, if it
    /// keeps one (withTableBands); as it is otherwise.
    static func restriped(_ elements: [Element], id: String) -> [Element] {
        guard let band = tableBands(elements, id: id) else { return elements }
        return striped(elements, id: id, band: band)
    }

    /// Table `id`'s body rows striped as a table is made, the simplest rule
    /// and the Android twin's: below a header (every row, with none), each
    /// rectangle of an even row filled `band` and of an odd one white — a
    /// merged cell by its top row, and whatever colour it had — or every one
    /// white for nil. The header keeps its own.
    private static func striped(_ elements: [Element], id: String, band: String?) -> [Element] {
        let header = tableHasHeader(elements, id: id)
        return elements.map { el -> Element in
            guard el.type == .shape, let cell = el.table, cell.id == id, !(header && cell.row == 0) else { return el }
            let fill = band.map { tableBodyFill(cell.row, band: $0) } ?? tableBody
            if el.fill?.kind == "solid" && el.fill?.color?.lowercased() == fill { return el }
            var out = el
            out.fill = .solid(fill)
            return out
        }
    }

    // MARK: as text

    /// Table `id`'s words as rows of cells, for the editor tables are typed
    /// in (parseTable reads them back, a line at a time): commas between
    /// cells, or tabs between them in every row once any cell's words hold
    /// a comma, so the rows read alike (tableTextTabbed); each cell's plain
    /// words, its line breaks and tabs spaces.
    static func tableText(_ elements: [Element], id: String) -> String {
        DataGrid.tableText(tableGrid(elements, id: id))
    }

    /// Whether tableText puts tabs between table `id`'s cells, so that the
    /// lines it wrote are read back split on tabs alone (parseEditedTable): a
    /// one-column table's words with a comma in them are still one cell.
    static func tableTextTabbed(_ elements: [Element], id: String) -> Bool {
        DataGrid.tabbed(tableGrid(elements, id: id))
    }

    /// The places, as [row, column] by their order in tableGrid, that a
    /// merged cell of table `id` covers past its own — those whose words
    /// the grid cannot set.
    static func tableCovered(_ elements: [Element], id: String) -> Set<[Int]> {
        let rowAt = Dictionary(uniqueKeysWithValues: tableRows(elements, id: id).enumerated().map { ($0.element, $0.offset) })
        let colAt = Dictionary(uniqueKeysWithValues: tableColumns(elements, id: id).enumerated().map { ($0.element, $0.offset) })
        var out = Set<[Int]>()
        for cell in tableMembers(elements, id: id).filter({ $0.type == .shape }).compactMap(\.table) where cell.isMerged {
            for r in cell.spannedRows {
                for c in cell.spannedCols where r != cell.row || c != cell.col {
                    if let row = rowAt[r], let col = colAt[c] { out.insert([row, col]) }
                }
            }
        }
        return out
    }

    /// Table `id`'s words as rows of cells, as the data grid shows them and
    /// tableText writes them: each cell's plain words, its line breaks and
    /// tabs spaces; the places a merged cell covers past its own blank.
    static func tableGrid(_ elements: [Element], id: String) -> [[String]] {
        var words: [[Int]: String] = [:]
        for el in tableMembers(elements, id: id) where el.type == .text {
            if let cell = el.table { words[[cell.row, cell.col]] = el.text ?? "" }
        }
        let columns = tableColumns(elements, id: id)
        return tableRows(elements, id: id).map { row in
            columns.map { col in words[[row, col]].map(plainWords) ?? "" }
        }
    }

    /// Table `id` made `rows` of cells (parseTable's): rows and columns
    /// added at the end or taken off it until there are as many, every
    /// column it keeps keeping its width and a new one the width they then
    /// average, rounded, so the table grows or shrinks on the right; then
    /// each cell's words set, a cell whose words did not change keeping its
    /// own styles. A new row copies the row two above it, keeping the bands,
    /// or the last row when there are fewer than three: a copy of a header
    /// alone is made a body row, so a table of a header alone grows body
    /// rows, and a copy of the one body row keeps its fonts and colours,
    /// only a cell in that row's own band taking the next band
    /// (bandedRow). A merged cell stays where it is, and words at a place
    /// it covers join its own (cellWords). Nil when `rows` has no cell.
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
            if have.count == 1 && tableHasHeader(out, id: id) {
                out = asBodyRow(out, id: id, row: last + 1)
            } else if have.count <= 2 {
                out = bandedRow(out, id: id, from: source, row: last + 1)
            }
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
                  let r = rowAt[cell.row], r < rows.count, colAt[cell.col] != nil else { return el }
            let words = cellWords(rows, cell, rowAt: rowAt, colAt: colAt)
            if plainWords(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == words { return el }
            var set = el
            set.setText(words)
            return set
        }
        return relaidTable(restriped(out, id: id), id: id, heightFor: heightFor)
    }

    /// The words `rows` give `cell`: its own place's, and — a merged
    /// cell's — any a place it covers holds too (the grid's words shifted or
    /// pasted onto one), each trimmed, joined after its own by line breaks
    /// in rows from the top and left to right, as merging joins them, so no
    /// word is lost; its own as they are when the places it covers are
    /// blank.
    private static func cellWords(_ rows: [[String]], _ cell: TableCell,
                                  rowAt: [Int: Int], colAt: [Int: Int]) -> String {
        func at(_ row: Int, _ col: Int) -> String {
            guard let r = rowAt[row], let c = colAt[col], r < rows.count, c < rows[r].count else { return "" }
            return rows[r][c]
        }
        let own = at(cell.row, cell.col)
        var covered: [String] = []
        for row in cell.spannedRows {
            for col in cell.spannedCols where row != cell.row || col != cell.col {
                let words = at(row, col).trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { covered.append(words) }
            }
        }
        guard !covered.isEmpty else { return own }
        let mine = own.trimmingCharacters(in: .whitespacesAndNewlines)
        return ([mine] + covered).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Table `id`'s row `row`, a copy of row `from`, banded as its place
    /// has it: each cell still in `from`'s own band takes `row`'s, and a
    /// cell given a colour of its own keeps it.
    private static func bandedRow(_ elements: [Element], id: String, from: Int, row: Int) -> [Element] {
        elements.map { el -> Element in
            guard el.type == .shape, let cell = el.table, cell.id == id, cell.row == row,
                  let fill = el.fill, fill.kind == "solid",
                  fill.color?.lowercased() == tableBodyFill(from) else { return el }
            var out = el
            out.fill = .solid(tableBodyFill(cell.row))
            return out
        }
    }

    /// Table `id`'s row `row` styled as a body row, as withTableHeader
    /// styles row 0 when it is off: banded, regular, in the table's ink.
    private static func asBodyRow(_ elements: [Element], id: String, row: Int) -> [Element] {
        elements.map { el -> Element in
            guard let cell = el.table, cell.id == id, cell.row == row else { return el }
            var out = el
            switch el.type {
            case .shape:
                out.fill = .solid(tableBodyFill(row))
            case .text:
                out.fontWeight = 400
                out.color = tableInk
            default:
                break
            }
            return out
        }
    }

    // MARK: after a step

    /// `after` with each table whose words changed since `before` laid out
    /// again — a cell typed in, its type changed in the Text controls, words
    /// replaced — so a row grows with its words in the same step that grew
    /// them. Moving cells about is not a change of words, and tables
    /// nothing was typed in are left where they are: a copy's cells are new,
    /// not typed in, so a copy stays as its original stands, and a table with
    /// a locked cell is never moved, as no change to a table moves one.
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
                guard let cell = el.table, !edited.contains(cell.id),
                      let w = was[el.id], wordsDiffer(w, el) else { continue }
                edited.append(cell.id)
            }
            edited.removeAll { id in tableMembers(page.elements, id: id).contains(where: \.locked) }
            guard !edited.isEmpty else { continue }
            var elements = page.elements
            for id in edited { elements = relaidTable(elements, id: id, heightFor: heightFor) }
            if elements != page.elements { out.pages[p].elements = elements }
        }
        return out
    }

    // MARK: rows and columns, before the relayout

    /// Column `source` copied, without words, in as column `at`, as wide
    /// as the columns averaged, the others narrowed in proportion to make
    /// room and the last given what rounding leaves of the table's width;
    /// nil when the table has no width to share.
    private static func withColumn(_ elements: [Element], id: String, source: Int, at: Int) -> [Element]? {
        let boxes = columnBoxes(elements, id: id)
        let total = boxes.values.map { $0.w }.reduce(0, +)
        guard let left = boxes.values.map({ $0.x }).min(), total > 0 else { return nil }
        let average = total / Double(boxes.count)
        var widths: [Int: Double] = [:]
        for (c, box) in boxes { widths[c >= at ? c + 1 : c] = box.w * (total - average) / total }
        widths[at] = average
        let added = insertingColumn(elements, id: id, source: source, at: at)
        return placingColumns(added, id: id, left: left, widths: roundedWidths(widths, total: total))
    }

    /// Column `col` taken out, the columns left widened in proportion to
    /// fill the table's width and the last given what rounding leaves over;
    /// nil when nothing would be left to widen.
    private static func withoutColumn(_ elements: [Element], id: String, col: Int) -> [Element]? {
        let boxes = columnBoxes(elements, id: id)
        guard let box = boxes[col], boxes.count > 1, let left = boxes.values.map({ $0.x }).min() else { return nil }
        let total = boxes.values.map { $0.w }.reduce(0, +)
        let rest = total - box.w
        guard rest > 0 else { return nil }
        var widths: [Int: Double] = [:]
        for (c, b) in boxes where c != col { widths[c > col ? c - 1 : c] = b.w * total / rest }
        let removed = removingColumn(elements, id: id, col: col)
        return placingColumns(removed, id: id, left: left, widths: roundedWidths(widths, total: total))
    }

    /// Row `source` copied, without words, in as row `at`; rows from `at`
    /// on moved down one. A cell merged down across where the row comes in
    /// grows a row to cover it; every other place in the new row is a blank
    /// copy of the cell over that column in row `source`, one cell wide.
    private static func insertingRow(_ elements: [Element], id: String, source: Int, at: Int) -> [Element] {
        let members = tableMembers(elements, id: id)
        let crossed = Set(members.compactMap(\.table).filter { $0.row < at && $0.row + $0.rowSpan > at }
            .flatMap { Array($0.spannedCols) })
        var copies: [Element] = []
        for col in tableColumns(elements, id: id) where !crossed.contains(col) {
            copies += members.filter { $0.table?.covers(row: source, col: col) == true }.map { blank($0, row: at, col: col) }
        }
        let shifted = elements.map { el -> Element in
            guard var cell = el.table, cell.id == id else { return el }
            if cell.row >= at {
                cell.row += 1
            } else if cell.row + cell.rowSpan > at {
                cell.rowSpan += 1
            } else {
                return el
            }
            var out = el
            out.table = cell
            return out
        }
        return inserting(copies, into: shifted, id: id)
    }

    /// Column `source` copied, without words, in as column `at`; columns
    /// from `at` on moved right one. A cell merged across where the column
    /// comes in grows a column to cover it; every other place in the new
    /// column is a blank copy of the cell over that row in column `source`,
    /// one cell tall.
    private static func insertingColumn(_ elements: [Element], id: String, source: Int, at: Int) -> [Element] {
        let members = tableMembers(elements, id: id)
        let crossed = Set(members.compactMap(\.table).filter { $0.col < at && $0.col + $0.colSpan > at }
            .flatMap { Array($0.spannedRows) })
        var copies: [Element] = []
        for row in tableRows(elements, id: id) where !crossed.contains(row) {
            copies += members.filter { $0.table?.covers(row: row, col: source) == true }.map { blank($0, row: row, col: at) }
        }
        let shifted = elements.map { el -> Element in
            guard var cell = el.table, cell.id == id else { return el }
            if cell.col >= at {
                cell.col += 1
            } else if cell.col + cell.colSpan > at {
                cell.colSpan += 1
            } else {
                return el
            }
            var out = el
            out.table = cell
            return out
        }
        return inserting(copies, into: shifted, id: id)
    }

    /// Table `id`'s rectangles each as wide as the columns it spans in
    /// `widths` (by column), the columns side by side from `left`; the
    /// relayout then fits the words to them.
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
                  let cx = xs[cell.col], widths[cell.col] != nil else { return el }
            var out = el
            out.x = cx
            out.w = cell.spannedCols.compactMap { widths[$0] }.reduce(0, +)
            return out
        }
    }

    /// Row `row` gone, the rows below numbered up one, the table's top kept
    /// where it was. A cell merged down through the row stays, a row
    /// shorter, with its words.
    private static func removingRow(_ elements: [Element], id: String, row: Int) -> [Element] {
        guard let top = tableMembers(elements, id: id).filter({ $0.type == .shape }).map(\.y).min() else { return elements }
        let kept = elements.compactMap { el -> Element? in
            guard var cell = el.table, cell.id == id else { return el }
            if cell.row > row {
                cell.row -= 1
            } else if cell.row + cell.rowSpan > row {
                guard cell.rowSpan > 1 else { return nil }
                cell.rowSpan -= 1
            } else {
                return el
            }
            var out = el
            out.table = cell
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

    /// Column `col` gone, the columns right of it numbered down one. A cell
    /// merged across the column stays, a column narrower, with its words.
    private static func removingColumn(_ elements: [Element], id: String, col: Int) -> [Element] {
        elements.compactMap { el -> Element? in
            guard var cell = el.table, cell.id == id else { return el }
            if cell.col > col {
                cell.col -= 1
            } else if cell.col + cell.colSpan > col {
                guard cell.colSpan > 1 else { return nil }
                cell.colSpan -= 1
            } else {
                return el
            }
            var out = el
            out.table = cell
            return out
        }
    }

    /// A cell's copy for a new row or column: a new element, no words, and
    /// no name of its own — the layers list gives it the generated one.
    private static func blank(_ el: Element, row: Int, col: Int) -> Element {
        var copy = el
        copy.id = UID.make()
        copy.layerName = nil
        if el.type == .text { copy.setText("") }
        if let cell = el.table { copy.table = TableCell(id: cell.id, row: row, col: col, pad: cell.pad, bands: cell.bands) }
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

    /// Table `id`'s columns' x and width (columnBoxes(of:)).
    private static func columnBoxes(_ elements: [Element], id: String) -> [Int: (x: Double, w: Double)] {
        columnBoxes(of: tableMembers(elements, id: id))
    }

    /// Each column's x and width among a table's `members`, as the top
    /// rectangle one column wide in it has them. A column with no rectangle
    /// of its own anywhere — every one in it merged with another column —
    /// shares what the top-left merged rectangle over it leaves of its
    /// width once the columns it covers that are known are taken away,
    /// evenly with the other columns of it unknown, side by side from its
    /// left. The Android twin's rule, number for number.
    private static func columnBoxes(of members: [Element]) -> [Int: (x: Double, w: Double)] {
        var boxes: [Int: (x: Double, w: Double)] = [:]
        var topRow: [Int: Int] = [:]
        for el in members where el.type == .shape {
            guard let cell = el.table, cell.colSpan <= 1, topRow[cell.col].map({ cell.row < $0 }) ?? true else { continue }
            topRow[cell.col] = cell.row
            boxes[cell.col] = (el.x, el.w)
        }
        let merged = members.filter { $0.type == .shape && ($0.table?.colSpan ?? 1) > 1 }
            .sorted { a, b in (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0) }
        for el in merged {
            guard let cell = el.table else { continue }
            let unknown = cell.spannedCols.filter { boxes[$0] == nil }
            guard !unknown.isEmpty else { continue }
            let known = cell.spannedCols.compactMap { boxes[$0]?.w }.reduce(0, +)
            let share = max(0, el.w - known) / Double(unknown.count)
            var x = el.x
            for c in cell.spannedCols {
                if boxes[c] == nil { boxes[c] = (x, share) }
                x += boxes[c]?.w ?? 0
            }
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
    /// take, changed. The settings the Android twin keeps among an
    /// element's extras — case, lists, indent, paragraph spacing, drop cap,
    /// the way the words run and how they fit their box — count too, as
    /// they count there.
    private static func wordsDiffer(_ a: Element, _ b: Element) -> Bool {
        let face = a.text != b.text || a.fontSize != b.fontSize || a.fontFamily != b.fontFamily
            || a.fontWeight != b.fontWeight || a.italic != b.italic || a.lineHeight != b.lineHeight
            || a.letterSpacing != b.letterSpacing
        let marks = a.spans != b.spans || a.spansText != b.spansText || a.table != b.table
        let lines = a.uppercase != b.uppercase || a.listStyle != b.listStyle || a.indent != b.indent
            || a.paragraphs != b.paragraphs || a.paragraphSpacing != b.paragraphSpacing || a.dropCap != b.dropCap
        let run = a.vertical != b.vertical || a.curve != b.curve || a.textPath != b.textPath
            || a.fitText != b.fitText || a.vAlign != b.vAlign
        return face || marks || lines || run
    }
}
