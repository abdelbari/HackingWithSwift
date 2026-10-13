// A table's rows, columns, cells and header, from the Table button.
//
// Shown for any selected cell of a table made here: a row added above or
// below the selected cells, a column left or right, the selected cell's row
// or column deleted (never the last), the selected cells merged or parted,
// their colour, the header row off and on, the table's borders, its
// columns made even, and the whole table in the data grid it is typed in.
// Each change is one undo step, and the rows then stand as tall as their
// words. The Android twin's TablePanel offers the same, in the same words.

import SwiftUI

struct TableSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingColour = false
    @State private var choosingBorderColour = false
    @State private var editingText = false

    var body: some View {
        NavigationStack {
            Form {
                if let table = store.tableSelection {
                    rowsAndColumns
                    deleting(table)
                    merging(table)
                    look(table)
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
                ColorPickerSheet(store: store, title: "Cell colour",
                                 current: store.tableCellColour,
                                 onPick: { c in store.setTableCellColour(c) },
                                 onPickTransient: { c in store.setTableCellColourTransient(c) })
            }
            .sheet(isPresented: $choosingBorderColour) {
                ColorPickerSheet(store: store, title: "Border colour",
                                 current: store.tableBorderColour,
                                 onPick: { c in store.setTableBorderColour(c) },
                                 onPickTransient: { c in store.setTableBorderTransient(width: nil, color: c) })
            }
            .sheet(isPresented: $editingText) {
                DataSheet(store: store, editingTable: true)
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private var rowsAndColumns: some View {
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
        }
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
            Button { choosingColour = true } label: {
                swatchRow("Cell colour", colour: store.tableCellColour ?? DataGraphics.tableBody)
            }
            .accessibilityLabel("Cell colour")
            .accessibilityValue(ElementNames.spokenColour(store.tableCellColour))
            Button { editingText = true } label: {
                Label("Edit as text", systemImage: "tablecells")
            }
        }
    }

    /// Distribute columns, and where the edges between them are dragged.
    private func columns(_ table: TableSelection) -> some View {
        Section {
            Button { store.distributeTableColumns() } label: {
                Label("Distribute columns", systemImage: "rectangle.split.3x1")
            }
            .disabled(table.columnCount < 2)
        } footer: {
            Text("Select the whole table to drag the edges between its columns.")
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
            borderSlider(width ?? 0)
            Button { choosingBorderColour = true } label: {
                swatchRow("Border colour", colour: store.tableBorderColour ?? DataGraphics.tableHairline)
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
