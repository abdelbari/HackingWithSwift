// Tables edited as tables, each change one step: rows and columns added and
// taken away, cells recoloured, merged and parted, the header turned on and
// off, the borders and the column widths set, and the table set again from
// its words. The table worked on is the one the selection is in (see
// DataGraphics for what each change does to it), as the Android twin's
// editor works it.

import Foundation

/// The table the selection is in, as the Table sheet reads it: its id, the
/// rows and columns its selected cells cover, how many rows and columns it
/// has, whether it has a header row, whether it is turned, whether the
/// whole of it is selected, and whether the selected cells can be merged
/// or any of them parted.
struct TableSelection: Equatable {
    var id: String
    var rows: [Int]
    var columns: [Int]
    var rowCount: Int
    var columnCount: Int
    var header: Bool
    var turned: Bool
    var whole: Bool
    var canMerge = false
    var canUnmerge = false

    /// Delete row and Delete column act on one row, or one column, and never
    /// on a table's last.
    var canDeleteRow: Bool { rows.count == 1 && rowCount > 1 }
    var canDeleteColumn: Bool { columns.count == 1 && columnCount > 1 }

    /// Why a turned table, or one with a locked cell, is left as it is.
    static let turnedNote = tr("Turn the table back to level to change its rows and columns.")
    static let lockedNote = tr("A cell of this table is locked. Unlock it to change the table.")

    /// Why Delete row or Delete column waits, when either does.
    var deleteNote: String? {
        guard !canDeleteRow || !canDeleteColumn else { return nil }
        if rowCount <= 1 && columnCount <= 1 { return tr("A table keeps at least one row and one column.") }
        if rows.count > 1 || columns.count > 1 { return tr("Select one cell to delete its row or column.") }
        return rowCount <= 1 ? tr("A table keeps at least one row.") : tr("A table keeps at least one column.")
    }
}

extension DesignStore {

    /// The table any selected cell belongs to — the first, in page order —
    /// or none when nothing selected is a table's cell.
    var tableSelection: TableSelection? {
        let selected = selectedElements
        guard let id = selected.lazy.compactMap({ $0.table?.id }).first else { return nil }
        let els = page.elements
        let chosen = selected.compactMap(\.table).filter { $0.id == id }
        let members = DataGraphics.tableMembers(els, id: id)
        return TableSelection(
            id: id,
            rows: Set(chosen.flatMap { Array($0.spannedRows) }).sorted(),
            columns: Set(chosen.flatMap { Array($0.spannedCols) }).sorted(),
            rowCount: DataGraphics.tableRows(els, id: id).count,
            columnCount: DataGraphics.tableColumns(els, id: id).count,
            header: DataGraphics.tableHasHeader(els, id: id),
            turned: DataGraphics.tableIsTurned(els, id: id),
            whole: members.allSatisfy { selection.contains($0.id) },
            canMerge: DataGraphics.mergeBlock(els, id: id, cells: Set(chosen)) != nil,
            canUnmerge: chosen.contains(where: \.isMerged))
    }

    /// The selected cells' fill, when they share one.
    var tableCellColour: String? {
        guard let id = tableSelection?.id else { return nil }
        let cells = Set(selectedElements.compactMap(\.table))
        let fills = DataGraphics.tableMembers(page.elements, id: id)
            .filter { $0.type == .shape && $0.table.map(cells.contains) == true }
            .map { $0.fill?.color }
        guard let first = fills.first, fills.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// What a double tap on `el` types into: `el` itself, or for a table
    /// cell's rectangle the cell's words — the padding round them is the
    /// cell too. Nil when it takes no typing.
    func typedIn(_ el: Element) -> Element? {
        typedIn(el, among: page.elements)
    }

    /// What a double tap on `el` types into among `elements`, the page it
    /// is on — another page of the column, too, before it is the one worked.
    func typedIn(_ el: Element, among elements: [Element]) -> Element? {
        guard let cell = el.table, el.type == .shape else {
            return ShapeText.carriesWords(el) && !el.locked ? el : nil
        }
        guard let words = elements.first(where: { $0.type == .text && $0.table == cell }),
              !words.locked else { return nil }
        return words
    }

    /// One edit to the selected table, as one undo step: `change` given the
    /// page's elements, the table and the selection in it; nil is nothing to
    /// do. A turned table's rows no longer stand in rows, and a locked cell
    /// stays as it is, so neither table is changed, and each says why, as
    /// the Android twin says it. The whole table stays selected when it
    /// was, new cells and all; a cell taken away hands the selection to the
    /// cell now in its place. Whether it changed.
    @discardableResult
    private func editTable(_ change: ([Element], TableSelection) -> [Element]?) -> Bool {
        endTextEdit()
        guard let table = tableSelection else { return false }
        if table.turned {
            buzz(.reject)
            announce(TableSelection.turnedNote, undoable: false)
            return false
        }
        let els = page.elements
        if DataGraphics.tableMembers(els, id: table.id).contains(where: \.locked) {
            buzz(.reject)
            announce(TableSelection.lockedNote, undoable: false)
            return false
        }
        guard let changed = change(els, table) else {
            buzz(.reject)
            return false
        }
        let first = selectedElements.lazy.compactMap(\.table).first { $0.id == table.id }
        let before = selection
        applyToPage { $0.elements = changed }
        let members = DataGraphics.tableMembers(page.elements, id: table.id)
        let kept = before.intersection(members.map(\.id))
        if table.whole {
            selection = Set(members.map(\.id))
        } else if !kept.isEmpty {
            selection = kept
        } else if let first {
            // The cell where the selected one was, or the last before it.
            let rows = DataGraphics.tableRows(page.elements, id: table.id)
            let cols = DataGraphics.tableColumns(page.elements, id: table.id)
            let row = rows.last(where: { $0 <= first.row }) ?? rows.first ?? 0
            let col = cols.last(where: { $0 <= first.col }) ?? cols.first ?? 0
            selection = Set(members.filter { $0.type == .text && $0.table?.covers(row: row, col: col) == true }.map(\.id))
        }
        buzz(.confirm)
        return true
    }

    /// A row above the selected cells' top row, or below their bottom one.
    func addTableRow(below: Bool) {
        let measure = self.measure
        editTable { els, t in
            guard let row = below ? t.rows.last : t.rows.first else { return nil }
            return DataGraphics.addingTableRow(els, id: t.id, row: row, below: below, heightFor: measure)
        }
    }

    /// A column left of the selected cells' first column, or right of their
    /// last.
    func addTableColumn(right: Bool) {
        let measure = self.measure
        editTable { els, t in
            guard let col = right ? t.columns.last : t.columns.first else { return nil }
            return DataGraphics.addingTableColumn(els, id: t.id, col: col, right: right, heightFor: measure)
        }
    }

    /// The selected cell's row taken out; never the last one.
    func deleteTableRow() {
        let measure = self.measure
        editTable { els, t in
            guard t.canDeleteRow, let row = t.rows.first else { return nil }
            return DataGraphics.deletingTableRow(els, id: t.id, row: row, heightFor: measure)
        }
    }

    /// The selected cell's column taken out; never the last one.
    func deleteTableColumn() {
        let measure = self.measure
        editTable { els, t in
            guard t.canDeleteColumn, let col = t.columns.first else { return nil }
            return DataGraphics.deletingTableColumn(els, id: t.id, col: col, heightFor: measure)
        }
    }

    /// The selected cells filled with `color`. Whether any changed.
    @discardableResult
    func setTableCellColour(_ color: String) -> Bool {
        let cells = Set(selectedElements.compactMap(\.table))
        return editTable { els, t in
            let coloured = DataGraphics.colouringTableCells(els, id: t.id, cells: cells, color: color)
            return coloured == els ? nil : coloured
        }
    }

    /// The same while the colour wheel is dragged; the colour sheet closes
    /// the step.
    func setTableCellColourTransient(_ color: String) {
        guard let table = tableSelection, !table.turned,
              !DataGraphics.tableMembers(page.elements, id: table.id).contains(where: \.locked) else { return }
        let cells = Set(selectedElements.compactMap(\.table))
        beginGesture()
        design.pages[pageIndex].elements = DataGraphics.colouringTableCells(
            design.pages[pageIndex].elements, id: table.id, cells: cells, color: color)
    }

    /// The header row on, in the page's first colour as a new table's is,
    /// or off.
    func setTableHeader(_ on: Bool) {
        let accent = DataGraphics.palette(for: design, page: page).first ?? "#5a31f4"
        let measure = self.measure
        editTable { els, t in
            let styled = DataGraphics.withTableHeader(els, id: t.id, on: on, accent: accent, heightFor: measure)
            return styled == els ? nil : styled
        }
    }

    /// The selected cells merged into one (DataGraphics.mergingTableCells).
    /// Whether they were.
    @discardableResult
    func mergeTableCells() -> Bool {
        let cells = Set(selectedElements.compactMap(\.table))
        let measure = self.measure
        return editTable { els, t in
            DataGraphics.mergingTableCells(els, id: t.id, cells: cells, heightFor: measure)
        }
    }

    /// The selected merged cells parted again into blank cells round their
    /// words (DataGraphics.unmergingTableCells). Whether any were.
    @discardableResult
    func unmergeTableCells() -> Bool {
        let cells = Set(selectedElements.compactMap(\.table))
        let measure = self.measure
        return editTable { els, t in
            DataGraphics.unmergingTableCells(els, id: t.id, cells: cells, heightFor: measure)
        }
    }

    /// The width every cell of the selected table has its border at, or
    /// nil when they differ.
    var tableBorderWidth: Double? {
        tableSelection.flatMap { DataGraphics.tableBorderWidth(page.elements, id: $0.id) }
    }

    /// The colour every cell of the selected table has its border in, or
    /// nil when they differ or have none.
    var tableBorderColour: String? {
        tableSelection.flatMap { DataGraphics.tableBorderColour(page.elements, id: $0.id) }
    }

    /// The selected table's borders made `width` wide, keeping their
    /// colour, as one step. Whether they changed.
    @discardableResult
    func setTableBorderWidth(_ width: Double) -> Bool {
        editTable { els, t in
            let set = DataGraphics.borderingTable(els, id: t.id, width: width, color: nil)
            return set == els ? nil : set
        }
    }

    /// The selected table's borders made `color`, as wide as they are, as
    /// one step. Whether they changed.
    @discardableResult
    func setTableBorderColour(_ color: String) -> Bool {
        editTable { els, t in
            let set = DataGraphics.borderingTable(els, id: t.id, width: nil, color: color)
            return set == els ? nil : set
        }
    }

    /// The selected table's borders while the Border width slider moves, or
    /// the colour wheel is dragged: redrawn, and recorded as one step when
    /// the slider or the colour sheet closes it (commit).
    func setTableBorderTransient(width: Double?, color: String?) {
        guard let table = tableSelection, !table.turned,
              !DataGraphics.tableMembers(page.elements, id: table.id).contains(where: \.locked) else { return }
        beginGesture()
        design.pages[pageIndex].elements = DataGraphics.borderingTable(
            design.pages[pageIndex].elements, id: table.id, width: width, color: color)
    }

    /// The selected table's column widths, left to right.
    var tableColumnWidths: [Double] {
        tableSelection.map { DataGraphics.tableColumnWidths(page.elements, id: $0.id) } ?? []
    }

    /// Where the column edges the canvas offers to drag are: the selected
    /// table's inner column edges, its top and its foot, where their
    /// handles stand, as on the Android twin — when the whole table, and
    /// nothing else, is selected, level and with no cell locked.
    var tableColumnEdges: (xs: [Double], top: Double, bottom: Double)? {
        guard let table = tableSelection, table.whole, !table.turned, table.columnCount > 1 else { return nil }
        let members = DataGraphics.tableMembers(page.elements, id: table.id)
        guard selection.count == members.count, !members.contains(where: \.locked) else { return nil }
        let rects = members.filter { $0.type == .shape }
        guard let top = rects.map(\.y).min(), let bottom = rects.map({ $0.y + $0.h }).max() else { return nil }
        return (DataGraphics.tableColumnEdges(page.elements, id: table.id), top, bottom)
    }

    /// The selected table's columns made `widths` wide as one step, the
    /// rows as tall as their words then need. Whether they changed.
    @discardableResult
    func setTableColumnWidths(_ widths: [Double]) -> Bool {
        let measure = self.measure
        return editTable { els, t in
            let placed = DataGraphics.placingTableColumns(els, id: t.id, widths: widths, heightFor: measure)
            return placed == els ? nil : placed
        }
    }

    /// The same while a column edge is dragged on the canvas; letting go
    /// closes the step (commit).
    func setTableColumnWidthsTransient(_ widths: [Double]) {
        guard let table = tableSelection, !table.turned,
              !DataGraphics.tableMembers(page.elements, id: table.id).contains(where: \.locked) else { return }
        beginGesture()
        design.pages[pageIndex].elements = DataGraphics.placingTableColumns(
            design.pages[pageIndex].elements, id: table.id, widths: widths, heightFor: measure)
    }

    /// The selected table's columns made even, as one step: its width shared
    /// alike (DataGraphics.evenColumns). Whether they changed.
    @discardableResult
    func distributeTableColumns() -> Bool {
        let widths = tableColumnWidths
        return setTableColumnWidths(DataGraphics.evenColumns(total: widths.reduce(0, +), count: widths.count))
    }

    /// The selected table's words as the data grid shows them.
    var tableGrid: [[String]] {
        tableSelection.map { DataGraphics.tableGrid(page.elements, id: $0.id) } ?? []
    }

    /// The places in tableGrid a merged cell covers past its own.
    var tableCovered: Set<[Int]> {
        tableSelection.map { DataGraphics.tableCovered(page.elements, id: $0.id) } ?? []
    }

    /// The selected table's words, as the table editor shows them.
    var tableText: String {
        tableSelection.map { DataGraphics.tableText(page.elements, id: $0.id) } ?? ""
    }

    /// Whether tableText puts tabs between the selected table's cells.
    var tableTextTabbed: Bool {
        tableSelection.map { DataGraphics.tableTextTabbed(page.elements, id: $0.id) } ?? false
    }

    /// The selected table made the rows typed in `text` (read as
    /// DataGraphics.parseEditedTable reads them, against the `opened` text
    /// and with `tabs`), its column widths kept, as one step. False when
    /// the text holds no rows.
    @discardableResult
    func rebuildTable(from text: String, opened: String = "", tabs: Bool = false) -> Bool {
        rebuildTable(rows: DataGraphics.parseEditedTable(text, opened: opened, tabs: tabs), header: nil)
    }

    /// The selected table made `rows` of cells — the data grid's, each
    /// cell's spaces trimmed — as one step, its column widths kept, and with
    /// `header` given, its header row turned on or off in the same step when
    /// it is not so already. A place a merged cell covers past its own has
    /// no words of its own (tableCovered). False when there are no rows.
    @discardableResult
    func rebuildTable(rows typed: [[String]], header: Bool? = nil) -> Bool {
        let rows = typed.map { row in row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        guard !rows.isEmpty, !rows.allSatisfy(\.isEmpty) else { return false }
        let accent = DataGraphics.palette(for: design, page: page).first ?? "#5a31f4"
        let measure = self.measure
        return editTable { els, t in
            guard let rebuilt = DataGraphics.rebuiltTable(els, id: t.id, rows: rows, heightFor: measure) else { return nil }
            guard let header, header != DataGraphics.tableHasHeader(rebuilt, id: t.id) else { return rebuilt }
            return DataGraphics.withTableHeader(rebuilt, id: t.id, on: header, accent: accent, heightFor: measure)
        }
    }
}
