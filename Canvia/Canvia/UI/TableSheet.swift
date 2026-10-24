// A table's rows, columns, cells and header, from the Table button.
//
// Shown for any selected cell of a table made here: a row added above or
// below the selected cells, a column left or right, the selected cell's row
// moved up or down and its column left or right, its row or column deleted
// (never the last), the selected cells merged or parted, their colour, the
// header row off and on, alternating rows in a colour, the cell spacing,
// the table's borders and which of its lines show, its words top, middle
// or bottom in their cells, a design from the gallery (TableDesigns), its
// columns made even, and the whole table in the data grid it is typed in.
// Each change is one undo step, and the rows then stand as tall as their
// words. The Android twin's TablePanel offers the same, in the same words.

import SwiftUI

struct TableSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingColour = false
    @State private var choosingBorderColour = false
    @State private var choosingBands = false
    @State private var editingText = false

    var body: some View {
        NavigationStack {
            Form {
                if let table = store.tableSelection {
                    rowsAndColumns(table)
                    deleting(table)
                    merging(table)
                    look(table)
                    design
                    aligning
                    spacing
                    columns(table)
                    borders
                } else {
                    Text("Select a table's cell to change its rows and columns.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $choosingColour) {
                ColorPickerSheet(store: store, title: tr("Cell colour"),
                                 current: store.tableCellColour,
                                 onPick: { c in store.setTableCellColour(c) },
                                 onPickTransient: { c in store.setTableCellColourTransient(c) })
            }
            .sheet(isPresented: $choosingBorderColour) {
                ColorPickerSheet(store: store, title: tr("Border colour"),
                                 current: store.tableBorderColour,
                                 onPick: { c in store.setTableBorderColour(c) },
                                 onPickTransient: { c in store.setTableBorderTransient(width: nil, color: c) })
            }
            .sheet(isPresented: $choosingBands) {
                ColorPickerSheet(store: store, title: tr("Alternating row colour"),
                                 current: store.tableBands,
                                 onPick: { c in store.setTableBands(true, colour: c) })
            }
            .sheet(isPresented: $editingText) {
                DataSheet(store: store, editingTable: true)
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private func rowsAndColumns(_ table: TableSelection) -> some View {
        Section {
            Button { store.addTableRow(below: false) } label: {
                Label("Add row above", systemImage: "arrow.up.to.line")
            }
            Button { store.addTableRow(below: true) } label: {
                Label("Add row below", systemImage: "arrow.down.to.line")
            }
            Button { store.addTableColumn(right: false) } label: {
                Label("Add column left", systemImage: "arrow.left.to.line")
            }
            Button { store.addTableColumn(right: true) } label: {
                Label("Add column right", systemImage: "arrow.right.to.line")
            }
            moving(table)
        }
    }

    /// Move row up and down, and Move column left and right: the one row,
    /// or column, the selected cells are in, each a step.
    private func moving(_ table: TableSelection) -> some View {
        HStack(spacing: 18) {
            Text("Move")
            Spacer(minLength: 0)
            moveButton("arrow.up", tr("Move row up"), enabled: table.canMoveRowUp) { store.moveTableRow(by: -1) }
            moveButton("arrow.down", tr("Move row down"), enabled: table.canMoveRowDown) { store.moveTableRow(by: 1) }
            moveButton("arrow.left", tr("Move column left"), enabled: table.canMoveColumnLeft) {
                store.moveTableColumn(by: -1)
            }
            moveButton("arrow.right", tr("Move column right"), enabled: table.canMoveColumnRight) {
                store.moveTableColumn(by: 1)
            }
        }
    }

    private func moveButton(_ symbol: String, _ name: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 30, height: 30)
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
        .accessibilityLabel(name)
    }

    private func deleting(_ table: TableSelection) -> some View {
        Section {
            Button(role: .destructive) { store.deleteTableRow() } label: {
                Label("Delete row", systemImage: "minus.rectangle")
            }
            .disabled(!table.canDeleteRow)
            Button(role: .destructive) { store.deleteTableColumn() } label: {
                Label("Delete column", systemImage: "minus.rectangle.portrait")
            }
            .disabled(!table.canDeleteColumn)
        } footer: {
            // Waiting, not hidden, with the reason, as on the
            // Android twin.
            if let note = table.deleteNote { Text(note) }
        }
    }

    /// Merge cells and Unmerge, each waiting until the selection gives it
    /// something to do.
    private func merging(_ table: TableSelection) -> some View {
        Section {
            Button { store.mergeTableCells() } label: {
                Label("Merge cells", systemImage: "rectangle.compress.vertical")
            }
            .disabled(!table.canMerge)
            Button { store.unmergeTableCells() } label: {
                Label("Unmerge", systemImage: "rectangle.split.2x2")
            }
            .disabled(!table.canUnmerge)
        }
    }

    private func look(_ table: TableSelection) -> some View {
        Section {
            Toggle("Header row", isOn: Binding(get: { table.header },
                                               set: { on in store.setTableHeader(on) }))
            Toggle("Alternating rows", isOn: Binding(get: { store.tableBands != nil },
                                                     set: { on in store.setTableBands(on, colour: nil) }))
            if let bands = store.tableBands {
                Button { choosingBands = true } label: {
                    swatchRow(tr("Alternating row colour"), colour: bands)
                }
                .accessibilityLabel("Alternating row colour")
                .accessibilityValue(ElementNames.spokenColour(bands))
            }
            Button { choosingColour = true } label: {
                swatchRow(tr("Cell colour"), colour: store.tableCellColour ?? DataGraphics.tableBody)
            }
            .accessibilityLabel("Cell colour")
            .accessibilityValue(ElementNames.spokenColour(store.tableCellColour))
            Button { editingText = true } label: {
                Label("Edit as text", systemImage: "tablecells")
            }
        }
    }

    /// Cell spacing: how far every cell's words sit from its edges, 0 to 40
    /// px in whole px, one step for each drag; the rows grow or shrink to it.
    private var spacing: some View {
        let pad = store.tablePadding ?? 0
        let readout = "\(Int(pad.rounded())) px"
        return Section {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Cell spacing").font(.subheadline)
                    Spacer()
                    Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
                Slider(value: Binding(
                    get: { pad },
                    set: { v in store.setTablePaddingTransient(v.rounded()) }
                ), in: 0...DataGraphics.tablePadMax, onEditingChanged: { editing in
                    if !editing { store.commit() }
                })
                .accessibilityLabel("Cell spacing")
                .accessibilityValue(readout)
            }
        }
    }

    /// Distribute columns and rows, and where the edges between them are
    /// dragged.
    private func columns(_ table: TableSelection) -> some View {
        Section {
            Button { store.distributeTableColumns() } label: {
                Label("Distribute columns", systemImage: "rectangle.split.3x1")
            }
            .disabled(table.columnCount < 2)
            Button { store.distributeTableRows() } label: {
                Label("Distribute rows", systemImage: "rectangle.split.1x2")
            }
            .disabled(table.rowCount < 2)
        } footer: {
            Text(tr("Select the whole table to drag the edges between its columns.") + " "
                 + tr("Drag the handle at the left of a row's lower edge to make it taller."))
        }
    }

    /// Borders: None, Thin, Medium or Thick round every cell, or any width
    /// from none to 12 px on the slider, and their colour, as the Android
    /// twin's Table panel sets them. Cells whose borders differ show no
    /// weight picked.
    private var borders: some View {
        let weights = DataGraphics.tableBorderWeights
        let width = store.tableBorderWidth
        let picked = Binding<Int>(
            get: { weights.firstIndex { $0.width == width } ?? -1 },
            set: { i in if weights.indices.contains(i) { store.setTableBorderWidth(weights[i].width) } })
        return Section("Borders") {
            Picker("Borders", selection: picked) {
                ForEach(weights.indices, id: \.self) { i in Text(weights[i].name).tag(i) }
            }
            .pickerStyle(.segmented)
            // Which lines show: every one, the outside, the inside, the
            // rows', the columns', or none — kept with the table, so a row
            // added keeps it.
            chips(Self.borderModes, selected: store.tableBorderMode) { mode in store.setTableBorderMode(mode) }
            borderSlider(width ?? 0)
            Button { choosingBorderColour = true } label: {
                swatchRow(tr("Border colour"), colour: store.tableBorderColour ?? DataGraphics.tableHairline)
            }
            .accessibilityLabel("Border colour")
            .accessibilityValue(ElementNames.spokenColour(store.tableBorderColour))
        }
    }

    /// Border width, 0 to 12 px in whole px, one step for each drag.
    private func borderSlider(_ width: Double) -> some View {
        let readout = "\(Int(width.rounded())) px"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Border width").font(.subheadline)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            // Named and read out on the slider itself, not beside it.
            .accessibilityHidden(true)
            Slider(value: Binding(
                get: { width },
                set: { v in store.setTableBorderTransient(width: v.rounded(), color: nil) }
            ), in: 0...DataGraphics.tableBorderMax, onEditingChanged: { editing in
                if !editing { store.commit() }
            })
            .accessibilityLabel("Border width")
            .accessibilityValue(readout)
        }
    }

    /// Design: a look from the gallery, the table's words and shape kept.
    private var design: some View {
        Section("Design") {
            TableDesignRow(accents: store.tableAccents, selected: store.tableDesignId) { look in
                store.setTableDesign(look)
            }
        }
    }

    /// Align in cell: the words of the selected cells — every cell's, when
    /// the whole table is selected — at the top, the middle or the bottom
    /// of their cells, which shows where a row is taller than its words.
    private var aligning: some View {
        Section("Align in cell") {
            chips(Self.cellAlignments, selected: store.tableCellAlignment) { align in
                store.setTableCellAlignment(align)
            }
        }
    }

    /// The border modes' chips (Tables.borderModes): each key, its words and
    /// its symbol.
    private static let borderModes: [(key: String, label: String, symbol: String)] = [
        ("all", tr("All"), "square.grid.3x3"),
        ("outer", tr("Outer"), "square"),
        ("inner", tr("Inner"), "plus"),
        ("horizontal", tr("Horizontal"), "line.3.horizontal"),
        ("vertical", tr("Vertical"), "rectangle.split.3x1"),
        ("none", tr("None"), "square.dashed"),
    ]

    private static let cellAlignments: [(key: String, label: String, symbol: String)] = [
        ("top", tr("Top"), "align.vertical.top"),
        ("middle", tr("Middle"), "align.vertical.center"),
        ("bottom", tr("Bottom"), "align.vertical.bottom"),
    ]

    /// A row of chips, the `selected` one filled, swiped along when it is
    /// wider than the sheet.
    private func chips(_ items: [(key: String, label: String, symbol: String)], selected: String?,
                       pick: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items.indices, id: \.self) { i in
                    chip(items[i].label, symbol: items[i].symbol, on: selected == items[i].key) { pick(items[i].key) }
                }
            }
        }
    }

    private func chip(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(on ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func swatchRow(_ title: String, colour: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer()
            Circle()
                .fill(Color(hex: colour))
                .frame(width: 26, height: 26)
                .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
    }
}
