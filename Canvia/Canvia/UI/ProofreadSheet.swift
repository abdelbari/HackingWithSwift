// Every misspelling in the document, each with its suggestions, in the
// design's language, chosen at the top. A suggestion fixes the word as one
// undo step and the check runs again; Show takes you to its box; Ignore
// passes over the word in this design from now on (its Ignore list, one
// undo step), and Add to dictionary in every design on this phone — as the
// Android twin's sheet does.

import SwiftUI

struct ProofreadSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var found: [Proofreader.Misspelling] = []
    /// This phone's dictionary, as last read or added to.
    @State private var dictionary: [String] = []
    /// Fixes made, so each is felt.
    @State private var fixes = 0

    /// The words found less those ignored in the design or added to the
    /// dictionary since the check, passed over at once.
    private var shown: [Proofreader.Misspelling] {
        let skip = Proofreader.skipped(store.design, dictionary: dictionary)
        return found.filter { !skip.contains($0.word.lowercased()) }
    }

    private var title: String {
        if shown.isEmpty { return "Spelling" }
        return shown.count == 1 ? "1 possible mistake" : "\(shown.count) possible mistakes"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                languageRow
                Divider()
                results
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .onAppear {
            dictionary = SpellingDictionary.load()
            refresh()
        }
        .feel(.success, trigger: fixes)
    }

    /// The language the design is checked — and read aloud and dictated —
    /// in: the phone's own, or one of Proofreader.languages.
    private var languageRow: some View {
        HStack {
            Text("Language").font(.subheadline.weight(.semibold))
            Spacer()
            Menu {
                Button(Proofreader.phoneLanguage) { setLanguage(nil) }
                ForEach(Proofreader.languages, id: \.tag) { language in
                    Button(language.name) { setLanguage(language.tag) }
                }
            } label: {
                Text(Proofreader.languageName(store.design.language))
            }
            .accessibilityLabel("Language")
            .accessibilityValue(Proofreader.languageName(store.design.language))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var results: some View {
        if shown.isEmpty && !found.isEmpty {
            // Words were found, and every one has been let be.
            ContentUnavailableView("Nothing left to look at.",
                                   systemImage: "checkmark.seal",
                                   description: Text("Every word found has been ignored."))
        } else if shown.isEmpty {
            ContentUnavailableView("No spelling mistakes found",
                                   systemImage: "checkmark.seal",
                                   description: Text("Every word in the document is in the dictionary."))
        } else {
            List(shown) { miss in
                row(miss)
            }
        }
    }

    private func row(_ miss: Proofreader.Misspelling) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(miss.word).font(.headline)
                Text("· page \(miss.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show") { show(miss) }
                    .font(.caption)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if miss.suggestions.isEmpty {
                        Text("No suggestions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(miss.suggestions, id: \.self) { suggestion in
                        Button(suggestion) { fix(miss, with: suggestion) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button("Ignore") { store.ignoreSpelling(miss.word) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    Button("Add to dictionary") { addToDictionary(miss.word) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Jump to the word and mark it there, as Find and replace does.
    private func show(_ miss: Proofreader.Misspelling) {
        store.reveal(DesignStore.TextMatch(pageIndex: miss.pageIndex, elementId: miss.elementId,
                                           range: miss.range, plain: miss.plain, preview: miss.word))
    }

    private func refresh() {
        found = Proofreader.misspellings(in: store.design, language: store.design.language,
                                         skip: Proofreader.skipped(store.design, dictionary: dictionary))
    }

    /// The design in `language`, as one step, and the check run again in it.
    private func setLanguage(_ language: String?) {
        store.setLanguage(language)
        refresh()
    }

    /// `word` passed over in every design on this phone from now on.
    private func addToDictionary(_ word: String) {
        SpellingDictionary.add([word])
        dictionary = SpellingDictionary.load()
    }

    /// Replace the word, style marks kept, and re-run: the ranges after it
    /// have moved. A row gone stale — the word edited meanwhile — changes
    /// nothing and is simply read again.
    private func fix(_ miss: Proofreader.Misspelling, with replacement: String) {
        if let next = Proofreader.fixed(store.design, miss, with: replacement) {
            store.apply { $0 = next }
            fixes += 1
        }
        refresh()
    }
}
