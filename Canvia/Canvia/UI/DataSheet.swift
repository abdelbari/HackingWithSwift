// Fill in the cells, get the chart; fill in the cells, get the table. Edit
// chart opens it again on the selected chart, filled in, to Update it in
// place. Opened from a table's Edit as text, it shows that table's cells and
// Update sets the table again from them, its column widths kept.
//
// The data is edited in a grid of cells (DataGridEditor), or with Text as
// the lines it is kept in — a chart's `data` and a table's words, read and
// written as they always were (DataGrid), so the file does not change. A
// chart's grid left as it opened keeps its text exactly as it was typed.
//
// A chart's Text section sets its labels' font, colour and size, and for a
// kind drawn against a scale Smooth line and the Axis range — all kept in
// its spec, so Update keeps them. Import CSV reads a CSV, TSV or text file
// of up to 1 MB into the grid to look over before Add or Update (DataGrid
// .fromCsv), saying what it left out, as the Android twin's does.

import SwiftUI
import UniformTypeIdentifiers

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
    /// The chart's text look and scale (chartLook), kept for Update: the
    /// labels' font and ink (nil for the defaults), their size as a share,
    /// smooth lines, and the axis's ends as typed ("" for the data's own).
    @State private var font: String?
    @State private var ink: String?
    @State private var textScale: Double
    @State private var smooth: Bool
    @State private var axisMin: String
    @State private var axisMax: String
    @State private var choosingFont = false
    @State private var choosingInk = false
    /// Import CSV's file picker, and what the last import left out — or why
    /// it brought nothing in.
    @State private var importingCsv = false
    @State private var imported: String?
    @State private var importRefused = false

    private static let sampleTable = "Item, Qty, Price\nCoffee, 2, 3.50\nBagel, 1, 2.25\nJuice, 3, 4.00"

    /// `start`, for a new one, is what Add's search found it by: a chart's
    /// kind ("pie"), or "table".
    init(store: DesignStore, editing: ChartSpec? = nil, editingTable: Bool = false, start: String? = nil) {
        self.store = store
        self.editing = editing
        self.editingTable = editingTable
        let text = editing?.data ?? "Spring, 40\nSummer, 65\nAutumn, 30\nWinter, 20"
        let started = editing == nil ? start.flatMap { DataGraphics.ChartKind(rawValue: $0) } : nil
        _kind = State(initialValue: editing.flatMap { DataGraphics.ChartKind(rawValue: $0.kind) } ?? started ?? .column)
        _mode = State(initialValue: editing == nil && !editingTable && start == "table" ? 1 : 0)
        _chartText = State(initialValue: text)
        _chartGrid = State(initialValue: DataGrid.cells(text))
        _chartGridOpened = State(initialValue: DataGrid.cells(text))
        _legend = State(initialValue: editing?.legend ?? false)
        _values = State(initialValue: editing?.values ?? false)
        _gridlines = State(initialValue: editing?.gridlines ?? false)
        _font = State(initialValue: editing?.font)
        _ink = State(initialValue: editing?.ink)
        _textScale = State(initialValue: editing.map(DataGraphics.textScale(of:)) ?? 1)
        _smooth = State(initialValue: editing?.smooth ?? false)
        _axisMin = State(initialValue: Self.axisText(editing?.axisMin))
        _axisMax = State(initialValue: Self.axisText(editing?.axisMax))
    }

    /// An axis end as typed: a number, a comma for its point too; nil when
    /// blank or not a number — as the Android twin reads the field.
    static func axisNumber(_ typed: String) -> Double? {
        let text = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// An axis end as its field shows it.
    static func axisText(_ value: Double?) -> String {
        value.map(DataGraphics.valueText) ?? ""
    }

    /// `spec` with the look set in the Text section and the axis's ends.
    private func look(_ spec: ChartSpec) -> ChartSpec {
        var out = spec
        out.font = font
        out.ink = ink
        out.textScale = textScale == 1 ? nil : textScale
        out.smooth = smooth
        out.axisMin = Self.axisNumber(axisMin)
        out.axisMax = Self.axisNumber(axisMax)
        return out
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
        .modifier(DataSheetPickers(store: store, choosingFont: $choosingFont, choosingInk: $choosingInk,
                                   importingCsv: $importingCsv, font: $font, ink: $ink,
                                   inkShown: ink ?? DataGraphics.ink(for: store.page), onImport: importCsv))
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
            importRow
        } header: {
            Text("One \"Label, value\" per line, or a header row for series")
        } footer: {
            chartFooter
        }
        chartLook
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
            importRow
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

    /// The chart's Text section — its labels' font, colour and size, 50 to
    /// 200% — and, for a kind drawn against a scale, Smooth line (a line's
    /// or an area's, the other kinds having none to smooth) and the Axis
    /// range's two ends, either left blank for the data's own: the Android
    /// twin's ChartLookRows.
    @ViewBuilder
    private var chartLook: some View {
        Section("Text") {
            Button { choosingFont = true } label: {
                LabeledContent("Font", value: font.map { FontStore.displayName($0, in: store.design) } ?? "Default")
            }
            .foregroundStyle(.primary)
            Button { choosingInk = true } label: {
                HStack {
                    Text("Colour")
                    Spacer()
                    Circle()
                        .fill(Color(hex: ink ?? DataGraphics.ink(for: store.page)))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                }
            }
            .foregroundStyle(.primary)
            .accessibilityLabel("Text colour")
            .accessibilityValue(ElementNames.spokenColour(ink ?? DataGraphics.ink(for: store.page)))
            textSizeSlider
        }
        if kind.hasScale {
            Section {
                Toggle("Smooth line", isOn: $smooth)
                    .disabled(kind != .line && kind != .area)
                HStack(spacing: 12) {
                    axisField("Min", text: $axisMin)
                    axisField("Max", text: $axisMax)
                }
            } header: {
                Text("Axis range")
            } footer: {
                if let low = Self.axisNumber(axisMin), let high = Self.axisNumber(axisMax), low >= high {
                    Text("The minimum is not below the maximum, so the data's own range is used.")
                }
            }
        }
    }

    /// The labels' size, 50 to 200% of their usual one, in whole percent.
    private var textSizeSlider: some View {
        let readout = "\(Int((textScale * 100).rounded()))%"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Size")
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(get: { textScale * 100 }, set: { textScale = ($0.rounded()) / 100 }),
                   in: DataGraphics.textScales.lowerBound * 100...DataGraphics.textScales.upperBound * 100)
                .accessibilityLabel("Text size")
                .accessibilityValue(readout)
        }
    }

    /// One end of the axis: a number, or blank for the data's own.
    private func axisField(_ title: String, text: Binding<String>) -> some View {
        let wrong = !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty && Self.axisNumber(text.wrappedValue) == nil
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(wrong ? Color(.systemRed) : .secondary)
            TextField("Auto", text: text)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Axis \(title.lowercased())")
        }
    }

    /// Import CSV, and under it what the last import left out, if anything.
    private var importRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { importingCsv = true } label: {
                Label("Import CSV", systemImage: "square.and.arrow.down")
            }
            if let imported {
                Text(imported)
                    .font(.footnote)
                    .foregroundStyle(importRefused ? Color(.systemRed) : .secondary)
            }
        }
    }

    /// A file's rows into the grid — the chart's or the table's — to look
    /// over before Add or Update, the grid shown rather than the text; or
    /// why not, under the button.
    private func importCsv(_ url: URL) {
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { DataGrid.read(csvAt: url) }.value
            switch outcome {
            case .rows(let read):
                if mode == 0 {
                    chartGrid = read.cells
                    chartText = DataGrid.chartText(read.cells)
                    chartGridOpened = chartGrid
                } else {
                    tableGrid = read.cells
                    tableText = DataGrid.tableText(read.cells)
                }
                asText = false
                imported = read.note
                importRefused = false
                store.buzz(.confirm)
            case .refused(let why):
                imported = why
                importRefused = true
                store.buzz(.reject)
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
        let spec = look(ChartSpec(id: editing?.id ?? UID.make("chart"), kind: kind.rawValue, data: chartData,
                                  legend: legend, values: values, gridlines: gridlines))
        // Drawn again where it was, as one step, keeping its colours.
        if mode == 0, editing != nil { return store.updateChart(spec) }
        // A new one goes onto the next unlocked page when this one is locked.
        guard store.landsOnUnlockedPage() else { return false }
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
        // Add's Recently used: the kind of chart, or the table.
        if mode == 0 { ElementSearch.remember(.chart, kind.rawValue) } else { ElementSearch.remember(.table, "table") }
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

/// The data sheet's font and colour pickers and Import CSV's file picker,
/// apart from its body so the type checker takes each chain in reasonable
/// time.
private struct DataSheetPickers: ViewModifier {
    let store: DesignStore
    @Binding var choosingFont: Bool
    @Binding var choosingInk: Bool
    @Binding var importingCsv: Bool
    @Binding var font: String?
    @Binding var ink: String?
    let inkShown: String
    let onImport: (URL) -> Void

    func body(content: Content) -> some View {
        content
            // None is the chart's default face.
            .sheet(isPresented: $choosingFont) {
                FontSheet(store: store, choice: FontSheet.Choice(
                    title: "Chart font", current: font, onPick: { key in font = key }))
            }
            .sheet(isPresented: $choosingInk) {
                ColorPickerSheet(store: store, title: "Text colour", current: inkShown,
                                 onPick: { hex in ink = hex.lowercased() })
            }
            .fileImporter(isPresented: $importingCsv,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                guard case .success(let url) = result else { return }
                onImport(url)
            }
    }
}
