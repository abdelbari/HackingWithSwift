// Tables edited as tables, each change one step: rows and columns added and
// taken away, cells recoloured, the header turned on and off, and the table
// set again from its words. The table worked on is the one the selection is
// in (see DataGraphics for what each change does to it), as the Android
// twin's editor works it.

import Foundation

/// The table the selection is in, as the Table sheet reads it: its id, the
/// rows and columns of its cells that are selected, how many rows and
/// columns it has, whether it has a header row, whether it is turned, and
/// whether the whole of it is selected.
struct TableSelection: Equatable {
    var id: String
    var rows: [Int]
    var columns: [Int]
    var rowCount: Int
    var columnCount: Int
    var header: Bool
    var turned: Bool
    var whole: Bool

    /// Delete row and Delete column act on one row, or one column, and never
    /// on a table's last.
    var canDeleteRow: Bool { rows.count == 1 && rowCount > 1 }
    var canDeleteColumn: Bool { columns.count == 1 && columnCount > 1 }

    /// Why Delete row or Delete column waits, when either does.
    var deleteNote: String? {
        guard !canDeleteRow || !canDeleteColumn else { return nil }
        if rowCount <= 1 && columnCount <= 1 { return "A table keeps at least one row and one column." }
        if rows.count > 1 || columns.count > 1 { return "Select one cell to delete its row or column." }
        return rowCount <= 1 ? "A table keeps at least one row." : "A table keeps at least one column."
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
            rows: Set(chosen.map(\.row)).sorted(),
            columns: Set(chosen.map(\.col)).sorted(),
            rowCount: DataGraphics.tableRows(els, id: id).count,
            columnCount: DataGraphics.tableColumns(els, id: id).count,
            header: DataGraphics.tableHasHeader(els, id: id),
            turned: DataGraphics.tableIsTurned(els, id: id),
            whole: members.allSatisfy { selection.contains($0.id) })
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
        guard let cell = el.table, el.type == .shape else {
            return ShapeText.carriesWords(el) && !el.locked ? el : nil
        }
        guard let words = page.elements.first(where: { $0.type == .text && $0.table == cell }),
              !words.locked else { return nil }
        return words
    }

    /// One edit to the selected table, as one undo step: `change` given the
    /// page's elements, the table and the selection in it; nil is nothing to
    /// do. A turned table's rows no longer stand in rows, and a locked cell
    /// stays where it is, so neither is changed. The whole table stays
    /// selected when it was, new cells and all; a cell taken away hands the
    /// selection to the cell now in its place. Whether it changed.
    @discardableResult
    private func editTable(_ change: ([Element], TableSelection) -> [Element]?) -> Bool {
        endTextEdit()
        guard let table = tableSelection else { return false }
        if table.turned {
            buzz(.reject)
            announce("Turn the table back to level to change its rows and columns.", undoable: false)
            return false
        }
        let els = page.elements
        guard !DataGraphics.tableMembers(els, id: table.id).contains(where: \.locked),
              let changed = change(els, table) else {
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
            let cell = TableCell(id: table.id, row: row, col: col)
            selection = Set(members.filter { $0.type == .text && $0.table == cell }.map(\.id))
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

    /// The selected table's words, as the table editor shows them.
    var tableText: String {
        tableSelection.map { DataGraphics.tableText(page.elements, id: $0.id) } ?? ""
    }

    /// The selected table made the rows typed in `text`, its column widths
    /// kept, as one step. False when the text holds no rows.
    @discardableResult
    func rebuildTable(from text: String) -> Bool {
        let rows = DataGraphics.parseTable(text)
        guard !rows.isEmpty else { return false }
        let measure = self.measure
        return editTable { els, t in
            DataGraphics.rebuiltTable(els, id: t.id, rows: rows, heightFor: measure)
        }
    }
}
