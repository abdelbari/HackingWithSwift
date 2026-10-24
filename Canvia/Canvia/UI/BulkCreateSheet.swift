// More ▸ Bulk create…: the rows — a CSV or TSV file brought in, or typed in
// the grid, the first row the columns' names — then each text and photo on
// the page connected to a column ("{{Column}}" in a text's words connects it
// too), then one page made from the page on screen for every row, as one
// Undo, or a design of its own for every row. What no longer fits is said
// row by row (BulkCreate). As the Android twin's Bulk create sheet.

import SwiftUI
import UniformTypeIdentifiers

struct BulkCreateSheet: View {
    @Bindable var store: DesignStore
    /// The designs made when each row was a design of its own.
    var onDesigns: ([Design]) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    /// The rows, the first the columns' names.
    @State private var cells: [[String]]
    @State private var separate = false
    @State private var importing = false
    /// Why the file brought nothing in.
    @State private var refusal: String?
    /// What the last Generate said of words that no longer fit.
    @State private var overflows: [String] = []
    /// How many rows the file brought in had under its names, past what
    /// the grid holds.
    @State private var fileRows = 0

    init(store: DesignStore, onDesigns: @escaping ([Design]) -> Void = { _ in }) {
        self.store = store
        self.onDesigns = onDesigns
        let kept = store.design.bulk.map { [$0.columns] + $0.rows } ?? []
        _cells = State(initialValue: kept.isEmpty ? [[tr("Name"), ""], ["", ""]] : kept)
    }

    private var data: BulkData { BulkCreate.data(from: cells) }

    /// The texts and photos on the page on screen, which a column can fill.
    private var fillable: [Element] {
        store.page.elements.filter { $0.type == .text || $0.type == .image }
    }

    var body: some View {
        NavigationStack {
            Form {
                dataSection
                fieldsSection
                makeSection
            }
            .navigationTitle("Bulk create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                guard case .success(let url) = result else { return }
                importFile(url)
            }
        }
        .presentationDetents([.large])
    }

    /// Step 1: the rows.
    private var dataSection: some View {
        Section {
            DataGridEditor(cells: $cells, header: true)
            Button { importing = true } label: {
                Label("Import CSV", systemImage: "square.and.arrow.down")
            }
            if let refusal {
                Text(refusal).font(.footnote).foregroundStyle(Color(.systemRed))
            }
        } header: {
            Text("1. Data")
        } footer: {
            Text("The first row is the column names.")
        }
    }

    /// Step 2: each text and photo, and the column it takes.
    private var fieldsSection: some View {
        Section {
            ForEach(fillable) { el in
                fieldRow(el)
            }
        } header: {
            Text("2. Connect fields")
        } footer: {
            Text("Pick a column for a text or photo, or type {{Column}} in a text. A photo takes the upload its cell names.")
        }
    }

    private func fieldRow(_ el: Element) -> some View {
        let columns = data.columns.filter { !$0.isEmpty }
        let words = el.type == .text ? BulkCreate.placeholders(in: el.text ?? "", columns: columns) : []
        return VStack(alignment: .leading, spacing: 2) {
            Picker(ElementNames.shortName(of: el), selection: Binding(
                get: { el.bulkField ?? "" },
                set: { store.setBulkField(el.id, column: $0.isEmpty ? nil : $0) })) {
                Text("None").tag("")
                ForEach(columns, id: \.self) { Text($0).tag($0) }
            }
            .disabled(el.locked || store.isPageLocked)
            if !words.isEmpty {
                Text(tr("Its words name %@", words.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Step 3: the pages, or the designs, and what did not fit.
    private var makeSection: some View {
        let count = data.rows.count
        let total = max(BulkCreate.rowCount(cells), fileRows)
        return Section {
            Toggle("As separate designs", isOn: $separate)
            Button(separate ? trn("Make %d design|Make %d designs", count)
                   : trn("Generate %d page|Generate %d pages", count)) { generate() }
                .disabled(count == 0 || !BulkCreate.connects(store.page, columns: data.columns))
            ForEach(overflows, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("3. Generate")
        } footer: {
            if let note = BulkCreate.capNote(rows: total) { Text(note) }
        }
    }

    private func importFile(_ url: URL) {
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                DataGrid.read(csvAt: url, maxRows: BulkCreate.maxRows + 1, maxColumns: XlsxReader.maxColumns)
            }.value
            switch outcome {
            case .rows(let read):
                cells = read.cells
                fileRows = max(read.rows - 1, 0)
                refusal = nil
                store.buzz(.confirm)
            case .refused(let why):
                refusal = why
                store.buzz(.reject)
            }
        }
    }

    private func generate() {
        let rows = data
        if separate {
            let outcome = store.bulkCreateDesigns(rows)
            overflows = outcome.overflows
            onDesigns(outcome.designs)
        } else {
            let outcome = store.bulkCreatePages(rows)
            overflows = outcome.overflows
            if outcome.made > 0 {
                store.announce(trn("Added %d page|Added %d pages", outcome.made))
            }
        }
        if overflows.isEmpty { dismiss() }
    }
}
