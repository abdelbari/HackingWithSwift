// A table's rows, columns, cells and header, from the Table button.
//
// Shown for any selected cell of a table made here: a row added above or
// below the selected cells, a column left or right, the selected cell's row
// or column deleted (never the last), the selected cells' colour, the header
// row off and on, and the whole table as text in the editor it was first
// typed in. Each change is one undo step, and the rows then stand as tall as
// their words. The Android twin's TablePanel offers the same, in the same
// words.

import SwiftUI

struct TableSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosingColour = false
    @State private var editingText = false

    var body: some View {
        NavigationStack {
            Form {
                if let table = store.tableSelection {
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
                    Section {
                        Toggle("Header row", isOn: Binding(get: { table.header },
                                                           set: { on in store.setTableHeader(on) }))
                        Button { choosingColour = true } label: {
                            HStack {
                                Text("Cell colour").foregroundStyle(.primary)
                                Spacer()
                                Circle()
                                    .fill(Color(hex: store.tableCellColour ?? DataGraphics.tableBody))
                                    .frame(width: 26, height: 26)
                                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                            }
                        }
                        .accessibilityLabel("Cell colour")
                        .accessibilityValue(ElementNames.spokenColour(store.tableCellColour))
                        Button { editingText = true } label: {
                            Label("Edit as text", systemImage: "text.alignleft")
                        }
                    }
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
            .sheet(isPresented: $editingText) {
                DataSheet(store: store, editingTable: true)
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
}
