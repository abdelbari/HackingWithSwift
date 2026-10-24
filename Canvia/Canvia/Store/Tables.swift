// Tables edited as tables, each change one step: rows and columns added and
// taken away, cells recoloured, merged and parted, the header turned on and
// off, the borders and the column widths set, and the table set again from
// its words. The table worked on is the one the selection is in (see
// DataGraphics for what each change does to it), as the Android twin's
// editor works it.

import CoreGraphics
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

    /// Move row up and down, and Move column left and right, move the one
    /// row, or column, the selected cells are in, while there is one that
    /// way to change places with — and the header row stays at the top:
    /// neither it nor the row under it moves across the top.
    var canMoveRowUp: Bool { rows.count == 1 && (rows.first ?? 0) > 0 && !(header && rows.first == 1) }
    var canMoveRowDown: Bool { rows.count == 1 && (rows.first ?? 0) < rowCount - 1 && !(header && rows.first == 0) }
    var canMoveColumnLeft: Bool { columns.count == 1 && (columns.first ?? 0) > 0 }
    var canMoveColumnRight: Bool { columns.count == 1 && (columns.first ?? 0) < columnCount - 1 }

    /// Why a turned table, or one with a locked cell, is left as it is.
    static let turnedNote = tr("Turn the table back to level to change its rows and columns.")
    static let lockedNote = tr("A cell of this table is locked. Unlock it to change the table.")
    /// Why a row, or a column, a merged cell runs through stays where it is.
    static let unmergeRowNote = tr("Unmerge first to move this row")
    static let unmergeColumnNote = tr("Unmerge first to move this column")
    /// Why the header row, or the row under it, stays where it is.
    static let headerRowNote = tr("The header row stays at the top")

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
            // A caption box is not typed into: its words are its cues,
            // changed in Edit captions — as on the Android twin.
            return ShapeText.carriesWords(el) && !el.locked && el.captions == nil ? el : nil
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

    /// Where the row edges the canvas offers to drag are: the bottom edge
    /// of each of the selected table's rows, and the table's left, where
    /// their handles stand — while the table or a cell of it is selected,
    /// level and with no cell locked, as on the Android twin.
    var tableRowEdges: (ys: [Double], rows: [Int], left: Double)? {
        guard let table = tableSelection, !table.turned else { return nil }
        let members = DataGraphics.tableMembers(page.elements, id: table.id)
        guard !members.contains(where: \.locked),
              let left = members.filter({ $0.type == .shape }).map(\.x).min() else { return nil }
        let boxes = DataGraphics.tableRowBoxes(page.elements, id: table.id)
        let rows = boxes.keys.sorted()
        return (rows.compactMap { boxes[$0].map { $0.y + $0.h } }, rows, left)
    }

    /// The selected table's rows' heights, by row.
    var tableRowHeights: [Int: Double] {
        guard let table = tableSelection else { return [:] }
        return DataGraphics.tableRowBoxes(page.elements, id: table.id).mapValues(\.h)
    }

    /// The edge under row `row` of the selected table dragged `dy` from
    /// where it was in `start` — the page's elements when the drag began —
    /// while the drag goes on; letting go closes the step (commit).
    func dragTableRowTransient(from start: [Element], row: Int, by dy: Double) {
        guard let table = tableSelection, !table.turned,
              !DataGraphics.tableMembers(start, id: table.id).contains(where: \.locked) else { return }
        beginGesture()
        design.pages[pageIndex].elements = DataGraphics.withRowDragged(start, id: table.id, boundary: row, dy: dy,
                                                                       heightFor: measure) ?? start
    }

    /// The edge under the last row the selected cells cover made a step
    /// lower (taller) or higher (DataGraphics.withRowStepped), as one step:
    /// VoiceOver's Taller row and Shorter row. Whether it changed.
    @discardableResult
    func resizeTableRow(taller: Bool) -> Bool {
        let measure = self.measure
        return editTable { els, t in
            DataGraphics.withRowStepped(els, id: t.id, rows: t.rows, taller: taller, heightFor: measure)
        }
    }

    /// Distribute rows, as one step: the selected table's rows made one
    /// height (DataGraphics.evenRows). Whether they changed.
    @discardableResult
    func distributeTableRows() -> Bool {
        let measure = self.measure
        return editTable { els, t in DataGraphics.evenRows(els, id: t.id, heightFor: measure) }
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

    // MARK: moving rows and columns, spacing and alternating rows

    /// The selected cell's row moved up (`step` -1) or down (1), as one
    /// step; refused, and said, when the header would leave the top or a
    /// merged cell runs through either row.
    func moveTableRow(by step: Int) {
        let measure = self.measure
        var note: String?
        editTable { els, t in
            guard t.rows.count == 1, let row = t.rows.first, row + step >= 0, row + step < t.rowCount else { return nil }
            if DataGraphics.tableHeaderStays(els, id: t.id, row: row, by: step) {
                note = TableSelection.headerRowNote
                return nil
            }
            if DataGraphics.rowMoveSplitsMerge(els, id: t.id, row: row, by: step) {
                note = TableSelection.unmergeRowNote
                return nil
            }
            return DataGraphics.movedTableRow(els, id: t.id, row: row, by: step, heightFor: measure)
        }
        if let note { announce(note, undoable: false) }
    }

    /// The selected cell's column moved left (`step` -1) or right (1), as
    /// one step; refused, and said, when a merged cell runs across either.
    func moveTableColumn(by step: Int) {
        let measure = self.measure
        var merged = false
        editTable { els, t in
            guard t.columns.count == 1, let col = t.columns.first else { return nil }
            if DataGraphics.columnMoveSplitsMerge(els, id: t.id, col: col, by: step) {
                merged = true
                return nil
            }
            return DataGraphics.movedTableColumn(els, id: t.id, col: col, by: step, heightFor: measure)
        }
        if merged { announce(TableSelection.unmergeColumnNote, undoable: false) }
    }

    /// The selected table's cell spacing, as the slider shows it.
    var tablePadding: Double? {
        tableSelection.map { DataGraphics.tablePadding(page.elements, id: $0.id) }
    }

    /// The selected table's cell spacing set, as one step. Whether it changed.
    @discardableResult
    func setTablePadding(_ padding: Double) -> Bool {
        let measure = self.measure
        return editTable { els, t in
            let set = DataGraphics.withTablePadding(els, id: t.id, padding: padding, heightFor: measure)
            return set == els ? nil : set
        }
    }

    /// The same while the Cell spacing slider moves; letting go closes the
    /// step (commit).
    func setTablePaddingTransient(_ padding: Double) {
        guard let table = tableSelection, !table.turned,
              !DataGraphics.tableMembers(page.elements, id: table.id).contains(where: \.locked) else { return }
        beginGesture()
        design.pages[pageIndex].elements = DataGraphics.withTablePadding(
            design.pages[pageIndex].elements, id: table.id, padding: padding, heightFor: measure)
    }

    /// The selected table's alternating rows' colour, while it keeps them
    /// or is striped as a table is made (DataGraphics.tableBandsShown).
    var tableBands: String? {
        tableSelection.flatMap { DataGraphics.tableBandsShown(page.elements, id: $0.id) }
    }

    /// The selected table's alternating rows on, in `colour` — the colour
    /// they were, else the default band, when none is given — or off, as
    /// one step. Whether anything changed.
    @discardableResult
    func setTableBands(_ on: Bool, colour: String? = nil) -> Bool {
        let chosen = colour ?? tableBands ?? DataGraphics.tableBand
        return editTable { els, t in
            let set = DataGraphics.withTableBands(els, id: t.id, on: on, colour: chosen)
            return set == els ? nil : set
        }
    }

    // MARK: lines, alignment in cells and designs

    /// Which of the selected table's lines show (Tables.borderMode).
    var tableBorderMode: String? {
        tableSelection.map { Tables.borderMode(page.elements, id: $0.id) }
    }

    /// The selected table's lines shown as `mode` — all, outer, inner,
    /// horizontal, vertical or none (Tables.withBorderMode) — one step.
    /// Whether they changed.
    @discardableResult
    func setTableBorderMode(_ mode: String) -> Bool {
        editTable { els, t in Tables.withBorderMode(els, id: t.id, mode: mode) }
    }

    /// The cells Align in cell acts on: the selected ones, or every cell
    /// when the whole table is selected (nil).
    private func alignedCells(_ table: TableSelection) -> Set<[Int]>? {
        guard !table.whole else { return nil }
        return Set(selectedElements.compactMap(\.table).filter { $0.id == table.id }.map { [$0.row, $0.col] })
    }

    /// Where the words of the cells Align in cell acts on sit, when they
    /// share a place (Tables.cellAlignment).
    var tableCellAlignment: String? {
        tableSelection.flatMap { Tables.cellAlignment(page.elements, id: $0.id, cells: alignedCells($0)) }
    }

    /// Those cells' words set top, middle or bottom in their cells
    /// (Tables.aligned), one step. Whether they moved.
    @discardableResult
    func setTableCellAlignment(_ align: String) -> Bool {
        let measure = self.measure
        return editTable { els, t in
            Tables.aligned(els, id: t.id, cells: alignedCells(t), align: align, heightFor: measure)
        }
    }

    /// The colours a table design's "accent" and "accent2" stand for here:
    /// the brand kit's, else the design's own (TableDesigns.accents).
    var tableAccents: (String, String) {
        TableDesigns.accents(brand: BrandKit.load().colors, palette: DataGraphics.palette(for: design, page: page))
    }

    /// The design the selected table was last given, when it was.
    var tableDesignId: String? {
        tableSelection.flatMap { Tables.designOf(DataGraphics.tableMembers(page.elements, id: $0.id)) }
    }

    /// The selected table in `look` (Tables.withDesign): its words, merged
    /// cells, column widths and row heights kept — one step. Whether it
    /// changed.
    @discardableResult
    func setTableDesign(_ look: TableDesigns.TableDesign) -> Bool {
        let (accent, accent2) = tableAccents
        let measure = self.measure
        return editTable { els, t in
            Tables.withDesign(els, id: t.id, design: look, accent: accent, accent2: accent2, heightFor: measure)
        }
    }

    /// A new table of `rows` across the middle of the page on screen — the
    /// next unlocked one when this one is locked — its first row the header
    /// unless `header` is off, in `look` when one is given: one step,
    /// selected, and remembered in Add's Recently used. Whether it went on.
    @discardableResult
    func addTable(_ rows: [[String]], header: Bool = true, look: TableDesigns.TableDesign? = nil) -> Bool {
        endTextEdit()
        let cells = rows.map { row in row.map { $0.trimmingCharacters(in: .whitespaces) } }
        guard cells.contains(where: { row in row.contains { !$0.isEmpty } }) else { return false }
        guard landsOnUnlockedPage() else { return false }
        let made = newTable(cells, header: header, look: look)
        guard !made.isEmpty else { return false }
        applyToPage { $0.elements.append(contentsOf: made) }
        selection = Set(made.map(\.id))
        ElementSearch.remember(.table, look?.id ?? "table")
        buzz(.confirm)
        return true
    }

    /// A table of `rows` for the page on screen, across its middle, in the
    /// design's colours that show on it: header off when asked, and in
    /// `look` when given.
    func newTable(_ rows: [[String]], header: Bool, look: TableDesigns.TableDesign?,
                  frame given: CGRect? = nil) -> [Element] {
        let w = pageWidth, h = pageHeight
        let frame = given ?? CGRect(x: (w * 0.1).rounded(), y: (h * 0.2).rounded(), width: (w * 0.8).rounded(),
                                    height: (h * 0.6).rounded())
        let accent = DataGraphics.palette(for: design, page: page).first ?? "#5a31f4"
        let measure = self.measure
        var made = DataGraphics.table(rows, in: frame, accent: accent, heightFor: measure)
        guard let id = made.lazy.compactMap({ $0.table?.id }).first else { return made }
        if !header { made = DataGraphics.withTableHeader(made, id: id, on: false, accent: accent, heightFor: measure) }
        guard let look else { return made }
        let (a, b) = tableAccents
        return Tables.withDesign(made, id: id, design: look, accent: a, accent2: b, heightFor: measure) ?? made
    }

    // MARK: Tab between cells

    /// The cell typed in, in reading order: the text of the next cell —
    /// the one after it, or with `back` the one before it — in rows from
    /// the top, left to right; nil past either end.
    func neighbourCell(of id: String, back: Bool) -> Element? {
        guard let cell = element(id)?.table else { return nil }
        let texts = DataGraphics.tableMembers(page.elements, id: cell.id).filter { $0.type == .text }
            .sorted { a, b in (a.table?.row ?? 0, a.table?.col ?? 0) < (b.table?.row ?? 0, b.table?.col ?? 0) }
        guard let at = texts.firstIndex(where: { $0.id == id }) else { return nil }
        let next = back ? at - 1 : at + 1
        return texts.indices.contains(next) ? texts[next] : nil
    }

    /// Tab while typing in a cell — or the typing bar's arrow: the words
    /// kept as their own step, and typing goes on in the next cell, or with
    /// `back` (Shift-Tab) the one before. Tab in the last cell adds a row
    /// below, as a step of its own, and goes on in its first cell. With no
    /// cell to go to — Shift-Tab in the first, or a next one locked — it
    /// buzzes and typing stays where it is, as on Android. Whether typing
    /// moved.
    @discardableResult
    func typeInNextCell(back: Bool) -> Bool {
        guard let id = editingTextId, let cell = element(id)?.table else { return false }
        if let next = neighbourCell(of: id, back: back) {
            if next.locked {
                buzz(.reject)
                return false
            }
            endTextEdit()
            startTyping(next.id)
            return true
        }
        guard !back else {
            buzz(.reject)
            return false
        }
        endTextEdit()
        selection = [id]
        let lastRow = DataGraphics.tableRows(page.elements, id: cell.id).last ?? cell.row
        let before = Set(page.elements.map(\.id))
        let measure = self.measure
        let added = editTable { els, t in
            DataGraphics.addingTableRow(els, id: t.id, row: lastRow, below: true, heightFor: measure)
        }
        guard added else { return false }
        let fresh = page.elements.filter { !before.contains($0.id) && $0.type == .text && $0.table?.id == cell.id }
            .min { ($0.table?.col ?? 0) < ($1.table?.col ?? 0) }
        guard let fresh else { return false }
        startTyping(fresh.id)
        return true
    }
}
