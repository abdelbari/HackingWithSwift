// Type the numbers, get the chart; type the cells, get the table.

import SwiftUI

struct DataSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var kind = DataGraphics.ChartKind.column
    @State private var chartText = "Spring, 40\nSummer, 65\nAutumn, 30\nWinter, 20"
    @State private var tableText = "Item, Qty, Price\nCoffee, 2, 3.50\nBagel, 1, 2.25\nJuice, 3, 4.00"

    var body: some View {
        NavigationStack {
            Form {
                Picker("Kind", selection: $mode) {
                    Text("Chart").tag(0)
                    Text("Table").tag(1)
                }
                .pickerStyle(.segmented)
                if mode == 0 {
                    Section {
                        Picker("Chart", selection: $kind) {
                            ForEach(DataGraphics.ChartKind.allCases) { Text($0.name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        TextEditor(text: $chartText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 140)
                    } header: {
                        Text("One line per value: label, number")
                    } footer: {
                        let n = DataGraphics.parse(chartText).count
                        Text(n == 0 ? "No numbers found yet." : (n == 1 ? "1 value" : "\(n) values") + " — coloured from the document's palette.")
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
                        Text(rows.isEmpty ? "Nothing to tabulate yet." : "\(rows.count) rows × \(rows.map(\.count).max() ?? 0) columns; the first row is the header.")
                    }
                }
            }
            .navigationTitle(mode == 0 ? "Chart" : "Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add(); dismiss() }
                        .disabled(mode == 0 ? DataGraphics.parse(chartText).isEmpty : DataGraphics.parseTable(tableText).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func add() {
        let w = store.pageWidth, h = store.pageHeight
        let frame = CGRect(x: (w * 0.1).rounded(), y: (h * 0.2).rounded(), width: (w * 0.8).rounded(), height: (h * 0.6).rounded())
        let palette = ColorTools.documentColors(store.design, limit: 8)
        let colors = palette.count >= 2 ? palette : (ContentLibrary.palettes.first?.colors ?? ["#5a31f4"])
        let elements = mode == 0
            ? DataGraphics.chart(kind, series: DataGraphics.parse(chartText), in: frame, palette: colors)
            : DataGraphics.table(DataGraphics.parseTable(tableText), in: frame, accent: colors[0])
        guard !elements.isEmpty else { return }
        store.applyToPage { $0.elements.append(contentsOf: elements) }
        store.selection = Set(elements.map(\.id))
    }
}
