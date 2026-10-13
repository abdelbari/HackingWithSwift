// Fill in the cells, get the chart; fill in the cells, get the table. Edit
// chart opens it again on the selected chart, filled in, to Update it in
// place. Opened from a table's Edit as text, it shows that table's cells and
// Update sets the table again from them, its column widths kept.
//
// The data is edited in a grid of cells (DataGridEditor), or with Text as
// the lines it is kept in — a chart's `data` and a table's words, read and
// written as they always were (DataGrid), so the file does not change. A
// chart's grid left as it opened keeps its text exactly as it was typed.

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
    /// The chart's data as text: as typed, or as the grid was when Text was
    /// last turned on or off.
    @State private var chartText: String
    @State private var chartGrid: [[String]]
    /// The grid as chartText makes it: while it is so, chartText is kept.
    @State private var chartGridOpened: [[String]]
    @State private var legend: Bool
    @State private var values: Bool
    @State private var gridlines: Bool
    @State private var tableGrid = DataGrid.cells(DataSheet.sampleTable)
    @State private var tableText = DataSheet.sampleTable
    /// Whether the table's text, when Text was turned on, put tabs between
    /// its cells, so a comma in its words stays in its cell.
    @State private var tableTabs = false
    /// The table's text as Text showed it, whose lines with no tab are read
    /// as they were written.
    @State private var tableOpened = ""
    /// Whether the table has a header row.
    @State private var tableHeader = true
    /// The places of the table being edited that a merged cell covers.
    @State private var tableCovered: Set<[Int]> = []
    /// The lines rather than the grid.
    @State private var asText = false
    /// Why the last Add drew nothing, until the data or the kind changes.
    @State private var refusal: String?

    private static let sampleTable = "Item, Qty, Price\nCoffee, 2, 3.50\nBagel, 1, 2.25\nJuice, 3, 4.00"

    init(store: DesignStore, editing: ChartSpec? = nil, editingTable: Bool = false) {
        self.store = store
        self.editing = editing
        self.editingTable = editingTable
        let text = editing?.data ?? "Spring, 40\nSummer, 65\nAutumn, 30\nWinter, 20"
        _kind = State(initialValue: editing.flatMap { DataGraphics.ChartKind(rawValue: $0.kind) } ?? .column)
        _chartText = State(initialValue: text)
        _chartGrid = State(initialValue: DataGrid.cells(text))
        _chartGridOpened = State(initialValue: DataGrid.cells(text))
        _legend = State(initialValue: editing?.legend ?? false)
        _values = State(initialValue: editing?.values ?? false)
        _gridlines = State(initialValue: editing?.gridlines ?? false)
    }

    /// The chart's data as it will be kept: the text, or the grid's lines.
    private var chartData: String {
        if asText || chartGrid == chartGridOpened { return chartText }
        return DataGrid.chartText(chartGrid)
    }

    /// The rows typed for the table: the grid's — a new table's without its
    /// blank rows, as on the Android twin — or with Text the lines as Edit
    /// as text reads its own words back when a table is being edited, else
    /// as a new table's.
    private var tableRows: [[String]] {
        if asText {
            return editingTable
                ? DataGraphics.parseEditedTable(tableText, opened: tableOpened, tabs: tableTabs)
                : DataGraphics.parseTable(tableText)
        }
        if editingTable { return tableGrid }
        return tableGrid.filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
            .map { row in row.map { $0.trimmingCharacters(in: .whitespaces) } }
    }

    /// Edit chart on a chart with a locked part: nothing to update until it
    /// is unlocked.
    private var locked: Bool { editing.map { store.chartIsLocked($0.id) } ?? false }

    private var nothingToAdd: Bool {
        mode == 0 ? DataGraphics.chartData(chartData, kind: kind).rows.isEmpty : tableRows.isEmpty
    }

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
                    if mode == 0 { chartSections } else { tableSection }
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
                    .disabled(locked || nothingToAdd)
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: chartText) { refusal = nil }
        .onChange(of: chartGrid) { refusal = nil }
        .onChange(of: tableText) { refusal = nil }
        .onChange(of: tableGrid) { refusal = nil }
        .onChange(of: kind) { refusal = nil }
        .onChange(of: mode) { refusal = nil }
        .onAppear {
            guard editingTable else { return }
            mode = 1
            tableGrid = store.tableGrid
            tableCovered = store.tableCovered
            tableHeader = store.tableSelection?.header ?? true
        }
    }

    /// Grid or Text, carrying what was typed across: the grid as lines, or
    /// the lines as cells.
    private var showsText: Binding<Bool> {
        Binding(get: { asText }, set: { on in
            guard on != asText else { return }
            if on {
                chartText = chartData
                tableText = DataGrid.tableText(tableGrid)
                tableOpened = tableText
                tableTabs = DataGrid.tabbed(tableGrid)
            } else {
                chartGrid = DataGrid.cells(chartText)
                chartGridOpened = chartGrid
                tableGrid = DataGrid.padded(tableRows)
            }
            asText = on
        })
    }

    /// The lines in place of the grid, as the Android twin's Text chip.
    private var editAs: some View {
        Toggle("Text", isOn: showsText)
    }

    /// The chart's header row: a first row of names, one per series.
    private var chartHeader: Binding<Bool> {
        Binding(get: { DataGrid.chartHasHeader(chartGrid) },
                set: { on in chartGrid = DataGrid.withChartHeader(chartGrid, on: on) })
    }

    @ViewBuilder
    private var chartSections: some View {
        Section {
            // Eleven kinds: a menu, where a segmented row would not fit.
            Picker("Chart", selection: $kind) {
                ForEach(DataGraphics.ChartKind.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.menu)
            editAs
            if asText {
                TextEditor(text: $chartText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
            } else {
                Toggle("Header row", isOn: chartHeader)
                DataGridEditor(cells: $chartGrid, header: DataGrid.chartHasHeader(chartGrid))
            }
        } header: {
            Text("One \"Label, value\" per line, or a header row for series")
        } footer: {
            chartFooter
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
    }

    @ViewBuilder
    private var chartFooter: some View {
        let data = DataGraphics.chartData(chartData, kind: kind)
        if let refusal {
            Text(refusal).foregroundStyle(Color(.systemRed))
        } else if kind.isProgress || data.rows.isEmpty {
            Text(DataGraphics.chartSummary(data, kind: kind))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(DataGraphics.chartSummary(data, kind: kind))
                Text(kind == .scatter ? DataGraphics.scatterHint : DataGraphics.seriesHint)
            }
        }
    }

    private var tableSection: some View {
        Section {
            editAs
            if asText {
                TextEditor(text: $tableText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 140)
            } else {
                Toggle("Header row", isOn: $tableHeader)
                DataGridEditor(cells: $tableGrid, header: tableHeader, covered: tableCovered)
            }
        } header: {
            Text(asText ? "One row per line, cells separated by commas or tabs"
                        : "A row of cells per row, or paste rows from a spreadsheet")
        } footer: {
            if let refusal {
                Text(refusal).foregroundStyle(Color(.systemRed))
            } else {
                Text(DataGraphics.tableSummary(tableRows))
            }
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
        if !editingTable || tableRows.isEmpty {
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
        if editingTable { return store.rebuildTable(rows: tableRows, header: tableHeader) }
        let spec = ChartSpec(id: editing?.id ?? UID.make("chart"), kind: kind.rawValue, data: chartData,
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
            : newTable(in: frame, accent: colors[0])
        guard !elements.isEmpty else { return false }
        store.applyToPage { $0.elements.append(contentsOf: elements) }
        store.selection = Set(elements.map(\.id))
        return true
    }

    /// A new table of the rows typed, its header row off when it was turned
    /// off in the grid.
    private func newTable(in frame: CGRect, accent: String) -> [Element] {
        let made = DataGraphics.table(tableRows, in: frame, accent: accent)
        guard !tableHeader, let id = made.lazy.compactMap({ $0.table?.id }).first else { return made }
        return DataGraphics.withTableHeader(made, id: id, on: false, accent: accent, heightFor: store.measure)
    }
}
