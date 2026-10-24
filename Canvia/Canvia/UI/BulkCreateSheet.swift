// More ▸ Bulk create…: the rows — a CSV or TSV file brought in, or typed in
// the grid, the first row the columns' names — then each text and photo on
// the page connected to a column ("{{Column}}" in a text's words connects it
// too), then one page made from the page on screen for every row, as one
// Undo, or a design of its own for every row. What no longer fits is said
// row by row (BulkCreate), and the sheet stays open to say it. As the
// Android twin's Bulk create sheet, in the same words.

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
    /// What the last Generate said of words that no longer fit; nil before
    /// one, or once the rows change.
    @State private var overflows: [String]?
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

    /// The words, photos and frames on the page on screen, which a column
    /// can fill.
    private var fillable: [Element] {
        store.page.elements.filter { BulkCreate.hasWords($0) || BulkCreate.takesPhoto($0) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Make a page for each row of your data: certificates, name badges, product cards.")
                        .foregroundStyle(.secondary)
                }
                dataSection
                fieldsSection
                makeSection
            }
            .navigationTitle("Bulk create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]) { result in
                guard case .success(let url) = result else { return }
                importFile(url)
            }
        }
        .presentationDetents([.large])
        .onChange(of: cells) { overflows = nil }
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
            if let note = BulkCreate.capNote(rows: max(BulkCreate.rowCount(cells), fileRows)) {
                Text(note).font(.footnote).foregroundStyle(Color(.systemRed))
            }
        } header: {
            Text("1. Add data")
        } footer: {
            Text("The first row names the columns.")
        }
    }

    /// Step 2: each text and photo, and the column it takes.
    private var fieldsSection: some View {
        Section {
            if fillable.isEmpty {
                Text("This page has no text or photos to fill.")
            }
            ForEach(fillable) { el in
                fieldRow(el)
            }
        } header: {
            Text("2. Connect data")
        } footer: {
            Text("Pick a column for each text or photo, or type {{Column}} in a text.")
        }
    }

    private func fieldRow(_ el: Element) -> some View {
        let columns = data.columns
        // The columns its words name of their own, as Android lists them.
        let own = BulkCreate.fields(of: el, columns: columns).filter { $0 != el.bulkField }
        return VStack(alignment: .leading, spacing: 2) {
            Picker(ElementNames.shortName(of: el), selection: Binding(
                get: { el.bulkField ?? "" },
                set: { store.setBulkField(el.id, column: $0.isEmpty ? nil : $0) })) {
                Text("Not connected").tag("")
                ForEach(columns, id: \.self) { Text($0).tag($0) }
            }
            .disabled(el.locked || store.isPageLocked)
            if !own.isEmpty {
                Text(tr("Connected by %@", own.map { "{{\($0)}}" }.joined(separator: ", ")))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Step 3: the pages, or the designs, and what did not fit.
    private var makeSection: some View {
        let count = data.rows.count
        let connected = BulkCreate.connects(store.page, columns: data.columns)
        return Section {
            Toggle("As separate designs", isOn: $separate)
            Button(separate ? trn("Make %d design|Make %d designs", count)
                   : trn("Generate %d page|Generate %d pages", count)) { generate() }
                .disabled(count == 0 || !connected)
            if count > 0 && !connected {
                Text("Connect a column to something on the page first.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let overflows {
                report(overflows)
            }
        } header: {
            Text("3. Generate")
        }
    }

    /// What the last Generate found: everything fits, or each text too long
    /// for its box, row by row.
    @ViewBuilder
    private func report(_ found: [String]) -> some View {
        if found.isEmpty {
            Text("Everything fits.")
        } else {
            Text(trn("%d text is too long for its box|%d texts are too long for their boxes", found.count))
                .foregroundStyle(Color(.systemRed))
            ForEach(found, id: \.self) { line in
                Label(line, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func importFile(_ url: URL) {
        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                DataGrid.read(csvAt: url, maxRows: BulkCreate.maxRows + 1, maxColumns: BulkCreate.maxColumns)
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
        let found: [String]
        if separate {
            let outcome = store.bulkCreateDesigns(rows)
            found = outcome.overflows
            onDesigns(outcome.designs)
        } else {
            let outcome = store.bulkCreatePages(rows)
            found = outcome.overflows
            if outcome.made > 0 {
                store.announce(trn("Added %d page|Added %d pages", outcome.made))
            }
        }
        overflows = found
    }
}
