// Type the numbers, get the chart; type the cells, get the table. Edit chart
// opens it again on the selected chart, filled in, to Update it in place.
// Opened from a table's Edit as text, it shows that table's cells and Update
// sets the table again from them, its column widths kept.

import SwiftUI

struct DataSheet: View {
    @Bindable var store: DesignStore
    /// The chart Edit chart opened the sheet on: its kind, data and switches
    /// filled in, and Update in place of Add. Nil for a new chart or table.
    let editing: ChartSpec?
    /// Editing the selected table's cells rather than adding a new one.
    let editingTable: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var kind: DataGraphics.ChartKind
    @State private var chartText: String
    @State private var legend: Bool
    @State private var values: Bool
    @State private var gridlines: Bool
    @State private var tableText = "Item, Qty, Price\nCoffee, 2, 3.50\nBagel, 1, 2.25\nJuice, 3, 4.00"
    /// Why the last Add drew nothing, until the data or the kind changes.
    @State private var refusal: String?

    init(store: DesignStore, editing: ChartSpec? = nil, editingTable: Bool = false) {
        self.store = store
        self.editing = editing
        self.editingTable = editingTable
        _kind = State(initialValue: editing.flatMap { DataGraphics.ChartKind(rawValue: $0.kind) } ?? .column)
        _chartText = State(initialValue: editing?.data ?? "Spring, 40\nSummer, 65\nAutumn, 30\nWinter, 20")
        _legend = State(initialValue: editing?.legend ?? false)
        _values = State(initialValue: editing?.values ?? false)
        _gridlines = State(initialValue: editing?.gridlines ?? false)
    }

    /// Edit chart on a chart with a locked part: nothing to update until it
    /// is unlocked.
    private var locked: Bool { editing.map { store.chartIsLocked($0.id) } ?? false }

    var body: some View {
        NavigationStack {
            Form {
                // A locked chart is only told how to unlock, as on the Android twin.
                if locked {
                    Label("This chart is locked. Tap Unlock to edit it.", systemImage: "lock")
                        .foregroundStyle(.secondary)
                } else {
                    // A chart being edited stays a chart, and a table a table.
                    if editing == nil && !editingTable {
                        Picker("Kind", selection: $mode) {
                            Text("Chart").tag(0)
                            Text("Table").tag(1)
                        }
                        .pickerStyle(.segmented)
                    }
                    if mode == 0 {
                        Section {
                            // Ten kinds: a menu, where a segmented row would not fit.
                            Picker("Chart", selection: $kind) {
                                ForEach(DataGraphics.ChartKind.allCases) { Text($0.name).tag($0) }
                            }
                            .pickerStyle(.menu)
                            TextEditor(text: $chartText)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 140)
                        } header: {
                            Text("One \"Label, value\" per line, or a header row for series")
                        } footer: {
                            let data = DataGraphics.parseChart(chartText)
                            if let refusal {
                                Text(refusal).foregroundStyle(Color(.systemRed))
                            } else if kind.isProgress || data.rows.isEmpty {
                                Text(DataGraphics.chartSummary(data, kind: kind))
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(DataGraphics.chartSummary(data, kind: kind))
                                    Text(DataGraphics.seriesHint)
                                }
                            }
                        }
                        Section {
                            // A progress kind writes its own value and has no
                            // legend; only kinds with a scale have lines to
                            // draw across it.
                            Toggle("Legend", isOn: $legend)
                                .disabled(kind.isProgress)
                            Toggle("Values", isOn: $values)
                                .disabled(kind.isProgress)
                            Toggle("Gridlines", isOn: $gridlines)
                                .disabled(!kind.hasScale)
                        }
                    } else {
                        Section {
                            TextEditor(text: $tableText)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 140)
                        } header: {
                            Text("One row per line, cells separated by commas or tabs")
                        } footer: {
                            let rows = DataGraphics.parseTable(tableText)
                            if let refusal {
                                Text(refusal).foregroundStyle(Color(.systemRed))
                            } else {
                                Text(DataGraphics.tableSummary(rows))
                            }
                        }
                    }
                }
            }
            .navigationTitle(editing != nil ? "Edit chart" : (mode == 0 ? "Chart" : "Table"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // Kept open with a word when there turns out to be
                    // nothing to draw — a pie of zeros — as on the Android twin.
                    Button(editing != nil || editingTable ? "Update" : "Add") {
                        if add() { dismiss() } else { refusal = whyNot() }
                    }
                        .disabled(locked || (mode == 0 ? DataGraphics.parseChart(chartText).rows.isEmpty : DataGraphics.parseTable(tableText).isEmpty))
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: chartText) { refusal = nil }
        .onChange(of: tableText) { refusal = nil }
        .onChange(of: kind) { refusal = nil }
        .onChange(of: mode) { refusal = nil }
        .onAppear {
            guard editingTable else { return }
            mode = 1
            tableText = store.tableText
        }
    }

    /// Why Add or Update did nothing. Rows typed for a table being edited
    /// were fine, so the table itself refused them — turned, or with a
    /// locked cell — and the store has already buzzed and said why; the
    /// sheet says it too, in the same words.
    private func whyNot() -> String? {
        if mode == 0 {
            store.buzz(.reject)
            return "Nothing to draw: type some values, or values above zero."
        }
        if !editingTable || DataGraphics.parseTable(tableText).isEmpty {
            store.buzz(.reject)
            return "Nothing to set: type some rows."
        }
        guard let table = store.tableSelection else { return nil }
        if table.turned { return TableSelection.turnedNote }
        if DataGraphics.tableMembers(store.page.elements, id: table.id).contains(where: \.locked) {
            return TableSelection.lockedNote
        }
        return nil
    }

    @discardableResult
    private func add() -> Bool {
        if editingTable { return store.rebuildTable(from: tableText) }
        let spec = ChartSpec(id: editing?.id ?? UID.make("chart"), kind: kind.rawValue, data: chartText,
                             legend: legend, values: values, gridlines: gridlines)
        // Drawn again where it was, as one step, keeping its colours.
        if mode == 0, editing != nil { return store.updateChart(spec) }
        let w = store.pageWidth, h = store.pageHeight
        let frame = CGRect(x: (w * 0.1).rounded(), y: (h * 0.2).rounded(), width: (w * 0.8).rounded(), height: (h * 0.6).rounded())
        // The design's colours that show on this page, and labels in an ink
        // that reads on it — as the Android twin chooses them.
        let colors = DataGraphics.palette(for: store.design, page: store.page)
        let elements = mode == 0
            ? DataGraphics.chart(spec, in: frame, palette: colors, ink: DataGraphics.ink(for: store.page))
            : DataGraphics.table(DataGraphics.parseTable(tableText), in: frame, accent: colors[0])
        guard !elements.isEmpty else { return false }
        store.applyToPage { $0.elements.append(contentsOf: elements) }
        store.selection = Set(elements.map(\.id))
        return true
    }
}
