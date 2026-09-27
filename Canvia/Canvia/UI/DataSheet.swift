// Type the numbers, get the chart; type the cells, get the table.

import SwiftUI

struct DataSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode = 0
    @State private var kind = DataGraphics.ChartKind.column
    @State private var chartText = "Spring, 40\nSummer, 65\nAutumn, 30\nWinter, 20"
    @State private var tableText = "Item, Qty, Price\nCoffee, 2, 3.50\nBagel, 1, 2.25\nJuice, 3, 4.00"
    /// Why the last Add drew nothing, until the data or the kind changes.
    @State private var refusal: String?

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
                        if let refusal {
                            Text(refusal).foregroundStyle(Color(.systemRed))
                        } else {
                            Text(n == 0 ? "No numbers found yet." : (n == 1 ? "1 value" : "\(n) values") + " — coloured from the document's palette.")
                        }
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
            .navigationTitle(mode == 0 ? "Chart" : "Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // Kept open with a word when there turns out to be
                    // nothing to draw — a pie of zeros — as on the Android twin.
                    Button("Add") {
                        if add() { dismiss() } else {
                            store.buzz(.reject)
                            refusal = mode == 0 ? "Nothing to draw: type some values, or values above zero."
                                : "Nothing to set: type some rows."
                        }
                    }
                        .disabled(mode == 0 ? DataGraphics.parse(chartText).isEmpty : DataGraphics.parseTable(tableText).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .onChange(of: chartText) { refusal = nil }
        .onChange(of: tableText) { refusal = nil }
        .onChange(of: kind) { refusal = nil }
        .onChange(of: mode) { refusal = nil }
    }

    @discardableResult
    private func add() -> Bool {
        let w = store.pageWidth, h = store.pageHeight
        let frame = CGRect(x: (w * 0.1).rounded(), y: (h * 0.2).rounded(), width: (w * 0.8).rounded(), height: (h * 0.6).rounded())
        // The design's colours that show on this page, and labels in an ink
        // that reads on it — as the Android twin chooses them.
        let colors = DataGraphics.palette(for: store.design, page: store.page)
        let elements = mode == 0
            ? DataGraphics.chart(kind, series: DataGraphics.parse(chartText), in: frame, palette: colors,
                                 ink: DataGraphics.ink(for: store.page))
            : DataGraphics.table(DataGraphics.parseTable(tableText), in: frame, accent: colors[0])
        guard !elements.isEmpty else { return false }
        store.applyToPage { $0.elements.append(contentsOf: elements) }
        store.selection = Set(elements.map(\.id))
        return true
    }
}
