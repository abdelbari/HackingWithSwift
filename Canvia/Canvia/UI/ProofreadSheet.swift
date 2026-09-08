// Every misspelling in the document, each with its suggestions.

import SwiftUI

struct ProofreadSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var found: [Proofreader.Misspelling] = []
    @State private var ignored: Set<String> = []

    private var shown: [Proofreader.Misspelling] { found.filter { !ignored.contains($0.word.lowercased()) } }

    var body: some View {
        NavigationStack {
            Group {
                if shown.isEmpty {
                    ContentUnavailableView("No spelling mistakes found",
                                           systemImage: "checkmark.seal",
                                           description: Text("Every word in the document is in the dictionary."))
                } else {
                    List(shown) { miss in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(miss.word).font(.headline)
                                Text("· page \(miss.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button("Show") { store.reveal(.init(pageIndex: miss.pageIndex,
                                                                     elementId: miss.elementId,
                                                                     range: miss.range, preview: miss.word)) }
                                    .font(.caption)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(miss.suggestions, id: \.self) { suggestion in
                                        Button(suggestion) { fix(miss, with: suggestion) }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                    Button("Ignore") { ignored.insert(miss.word.lowercased()) }
                                        .buttonStyle(.borderless)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(shown.isEmpty ? "Spelling" : (shown.count == 1 ? "1 possible mistake" : "\(shown.count) possible mistakes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .onAppear { refresh() }
    }

    private func refresh() {
        found = Proofreader.misspellings(in: store.design)
    }

    /// Replace the word and re-run: the ranges after it have moved.
    private func fix(_ miss: Proofreader.Misspelling, with replacement: String) {
        store.apply { design in
            guard design.pages.indices.contains(miss.pageIndex),
                  let i = design.pages[miss.pageIndex].elements.firstIndex(where: { $0.id == miss.elementId }),
                  let text = design.pages[miss.pageIndex].elements[i].text else { return }
            design.pages[miss.pageIndex].elements[i].text =
                Proofreader.replacing(miss.range, in: text, with: replacement)
            design.pages[miss.pageIndex].elements[i].h =
                FontLibrary.layoutHeight(for: design.pages[miss.pageIndex].elements[i])
        }
        refresh()
    }
}
