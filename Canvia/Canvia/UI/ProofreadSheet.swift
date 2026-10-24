// Every misspelling in the document, each with its suggestions, in the
// design's language, chosen at the top. A suggestion fixes the word as one
// undo step and the check runs again; Show takes you to its box; Ignore
// passes over the word in this design from now on (its Ignore list, one
// undo step), and Add to dictionary in every design on this phone — as the
// Android twin's sheet does. The pages' speaker notes are checked too,
// listed under Notes; Show opens a page's notes. A Doc is checked as its
// blocks and its tables' cells, each listed as "Doc, paragraph N".
//
// Below them, Writing: the writing rules' findings (Proofing) — a repeated
// word, extra spaces, a missing capital, straight quotes and the rest, the
// typographic ones only while Settings ▸ Proofing's Typography is on — each
// with Fix (one undo step), Ignore (for this check), and Fix all of its kind
// (one undo step for them all).

import SwiftUI

struct ProofreadSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var found: [Proofreader.Misspelling] = []
    /// The writing findings, and those Ignore has passed over this check.
    @State private var writing: [Proofreader.Misspelling] = []
    @State private var letBe: Set<String> = []
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

    /// The writing findings still to look at.
    private var writingShown: [Proofreader.Misspelling] {
        writing.filter { !letBe.contains($0.id) }
    }

    private var title: String {
        let count = shown.count + writingShown.count
        if count == 0 { return tr("Spelling") }
        return trn("%d possible mistake|%d possible mistakes", count)
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
        .sheet(isPresented: notesShown) { PageNotesSheet(store: store) }
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
        if !writingShown.isEmpty {
            List {
                spellingSections
                writingSection
            }
        } else if shown.isEmpty && !found.isEmpty {
            // Words were found, and every one has been let be.
            ContentUnavailableView("Nothing left to look at.",
                                   systemImage: "checkmark.seal",
                                   description: Text("Every word found has been ignored."))
        } else if shown.isEmpty {
            ContentUnavailableView("No spelling mistakes found",
                                   systemImage: "checkmark.seal",
                                   description: Text("Every word in the document is in the dictionary."))
        } else {
            List { spellingSections }
        }
    }

    /// The misspellings: in the boxes, or a Doc's blocks, then the notes.
    @ViewBuilder
    private var spellingSections: some View {
        let words = shown.filter { $0.kind != .notes }
        if !words.isEmpty {
            Section {
                ForEach(words) { row($0) }
            }
        }
        let notes = shown.filter { $0.kind == .notes }
        if !notes.isEmpty {
            Section("Notes") {
                ForEach(notes) { row($0) }
            }
        }
    }

    /// The writing findings, each with its kind and its fix.
    @ViewBuilder
    private var writingSection: some View {
        if !writingShown.isEmpty {
            Section("Writing") {
                ForEach(writingShown) { writingRow($0) }
            }
        }
    }

    private func writingRow(_ finding: Proofreader.Misspelling) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Proofing.ruleName(finding.rule ?? "")).font(.headline)
                Text(verbatim: "· " + place(finding)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Show") { show(finding) }
                    .font(.caption)
            }
            Text(verbatim: Self.change(finding))
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if let fix = finding.suggestions.first {
                    Button("Fix") { self.fix(finding, with: fix) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Ignore") { letBe.insert(finding.id) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                if finding.suggestions.first != nil {
                    Button("Fix all") { fixAll(finding.rule) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// What a writing fix does: the words found, an arrow and the words
    /// that take their place — quoted, so spaces show.
    static func change(_ finding: Proofreader.Misspelling) -> String {
        let found = "“" + finding.word + "”"
        guard let fix = finding.suggestions.first else { return found }
        return found + " → " + "“" + fix + "”"
    }

    /// Where a finding is: "page N", "Notes, page N" or "Doc, paragraph N".
    private func place(_ finding: Proofreader.Misspelling) -> String {
        switch finding.kind {
        case .doc: return FindReplaceSheet.docPlace(Proofreader.docPlace(store.design, blockId: finding.blockId))
        case .notes: return FindReplaceSheet.notesPlace(finding.pageIndex)
        case .element: return tr("page %d", finding.pageIndex + 1)
        }
    }

    /// A page's notes open while a misspelling in them is showing.
    private var notesShown: Binding<Bool> {
        Binding(get: { store.notesAsked != nil }, set: { if !$0 { store.notesAsked = nil } })
    }

    private func row(_ miss: Proofreader.Misspelling) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(miss.word).font(.headline)
                if miss.kind == .doc {
                    Text(verbatim: "· " + place(miss)).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("· page \(miss.pageIndex + 1)").font(.caption).foregroundStyle(.secondary)
                }
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
                                           range: miss.range, plain: miss.plain, preview: miss.word,
                                           kind: miss.kind, blockId: miss.blockId, row: miss.row, col: miss.col))
    }

    private func refresh() {
        found = Proofreader.misspellings(in: store.design, language: store.design.language,
                                         skip: Proofreader.skipped(store.design, dictionary: dictionary))
        writing = Proofreader.writing(in: store.design, language: store.design.language,
                                      typography: Proofing.typographyOn)
    }

    /// Every finding of `rule` showing fixed, as one undo step.
    private func fixAll(_ rule: String?) {
        if let next = Proofreader.fixedAll(store.design, writingShown.filter { $0.rule == rule }) {
            store.apply { $0 = next }
            fixes += 1
        }
        refresh()
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
