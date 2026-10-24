// The data grid Edit chart and Edit as text open: a chart's data or a
// table's words in rows and columns of cells, scrolled across and down, the
// header row in bold. A row's number and a column's letter each open a menu
// to add one before or after it or delete it (never the last); + Row and
// + Column add one at the end; and text pasted — with Paste, or into a
// cell, when it holds tabs or lines — splits into cells from the cell
// worked last (ClipboardTable, else DataGrid.pasting), as from a
// spreadsheet. A place a merged
// cell covers past its own waits, greyed: words pasted onto one join the
// merged cell's on Update (DataGraphics.rebuiltTable). While a table has a
// merged cell, the menus add and delete nothing, as the covered places
// would no longer line up with the words; + Row and + Column, at the end,
// still work. The Android twin's grid offers the same, its menus beside
// each row and over each column.

import SwiftUI

struct DataGridEditor: View {
    @Binding var cells: [[String]]
    /// Whether the first row is the header, drawn in bold.
    var header: Bool
    /// The places, as [row, column], a merged cell covers past its own.
    var covered: Set<[Int]> = []

    /// A cell's place.
    private struct Spot: Hashable {
        var row: Int
        var col: Int
    }
    @FocusState private var focus: Spot?
    /// The cell worked last, where Paste puts what it pastes.
    @State private var last = Spot(row: 0, col: 0)

    /// The cells as the grid shows them: every row as wide as the widest,
    /// and one blank cell when there are none.
    private var shown: [[String]] {
        let rows = DataGrid.padded(cells)
        return rows.isEmpty ? [[""]] : rows
    }

    private var width: Int { max(1, DataGrid.width(shown)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Rows made as they scroll into view, as the Android twin's:
            // Bulk create's may be 500 rows of 50 cells. Every place is a
            // fixed width, so the columns still line up.
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 2) {
                        Color.clear.frame(width: 30, height: 24)
                        ForEach(0..<width, id: \.self) { c in columnMenu(c) }
                    }
                    ForEach(0..<shown.count, id: \.self) { r in
                        HStack(spacing: 2) {
                            rowMenu(r)
                            ForEach(0..<width, id: \.self) { c in cell(r, c) }
                        }
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 160, maxHeight: 300)
            controls
        }
        .onChange(of: focus) { _, spot in
            if let spot { last = spot }
        }
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button { cells = DataGrid.addingRow(shown, at: shown.count) } label: {
                Label("Row", systemImage: "plus")
            }
            Button { cells = DataGrid.addingColumn(shown, at: width) } label: {
                Label("Column", systemImage: "plus")
            }
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                let text = strings.joined(separator: "\n")
                DispatchQueue.main.async { paste(text, at: last) }
            }
            .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
    }

    private func cell(_ r: Int, _ c: Int) -> some View {
        let free = !covered.contains([r, c])
        return TextField("", text: words(r, c))
            .disabled(!free)
            .font(r == 0 && header ? .body.bold() : .body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .padding(.horizontal, 6)
            .frame(width: 104, height: 34)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color(.secondarySystemBackground)))
            .focused($focus, equals: Spot(row: r, col: c))
            .accessibilityLabel("Row \(r + 1), column \(DataGrid.columnName(c))")
    }

    /// A cell's words. Text with a tab or a line break in it — a paste from
    /// a spreadsheet — fills the cells from this one on.
    private func words(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(
            get: { r < shown.count && c < shown[r].count ? shown[r][c] : "" },
            set: { new in
                if new.contains("\t") || new.contains(where: \.isNewline) {
                    paste(new, at: Spot(row: r, col: c))
                } else {
                    cells = DataGrid.settingCell(shown, row: r, col: c, to: new)
                }
            })
    }

    /// `text` laid over the grid from `spot`: a spreadsheet's range as it
    /// copies one (ClipboardTable, a quoted cell's line breaks kept in it),
    /// else rows of tab- or comma-separated cells (DataGrid.pasting).
    private func paste(_ text: String, at spot: Spot) {
        let row = min(spot.row, shown.count - 1), col = min(spot.col, width - 1)
        if let block = ClipboardTable.parse(text: text, html: nil) {
            cells = ClipboardTable.pastedInto(shown, row: row, col: col, block: block)
        } else {
            cells = DataGrid.pasting(text, into: shown, row: row, col: col)
        }
    }

    private func rowMenu(_ r: Int) -> some View {
        Menu {
            Button("Add row above") { cells = DataGrid.addingRow(shown, at: r) }
                .disabled(!covered.isEmpty)
            Button("Add row below") { cells = DataGrid.addingRow(shown, at: r + 1) }
                .disabled(!covered.isEmpty)
            Button("Delete row", role: .destructive) { cells = DataGrid.removingRow(shown, at: r) }
                .disabled(shown.count <= 1 || !covered.isEmpty)
        } label: {
            Text("\(r + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 34)
        }
        .accessibilityLabel("Row \(r + 1)")
    }

    private func columnMenu(_ c: Int) -> some View {
        Menu {
            Button("Add column left") { cells = DataGrid.addingColumn(shown, at: c) }
                .disabled(!covered.isEmpty)
            Button("Add column right") { cells = DataGrid.addingColumn(shown, at: c + 1) }
                .disabled(!covered.isEmpty)
            Button("Delete column", role: .destructive) { cells = DataGrid.removingColumn(shown, at: c) }
                .disabled(width <= 1 || !covered.isEmpty)
        } label: {
            Text(DataGrid.columnName(c))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 104, height: 24)
        }
        .accessibilityLabel("Column \(DataGrid.columnName(c))")
    }
}
