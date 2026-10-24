// Find and replace, across every page.
//
// A single-page design does not need this; a ten-page deck with a client's
// name in it does, and retyping that by hand is exactly the kind of chore
// that makes people go back to a desktop tool.
//
// The search is non-mutating and runs on every keystroke, so the count is
// live. Previous and Next step through the matches — "3 of 12" between them
// — each switching to its page and selecting its box, its letters marked
// there, with the sheet at half height so the canvas shows; Replace changes
// the one match showing and moves on to the next. The words are searched as
// they read, whatever their styles (FindReplace.matches). Replace all is one undo step: forty separate steps
// to undo a mistaken replace would be worse than no undo at all. Match case
// and Whole words narrow the search (FindReplace), as on the Android twin.
// The pages' speaker notes are searched too, after each page's boxes: a
// match there is listed as "Notes, page N", and showing it opens the
// page's notes.

import SwiftUI

struct FindReplaceSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    @State private var needle = ""
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var wholeWord = false
    @State private var replacedCount: Int?
    /// Which match Previous, Next and Replace are at.
    @State private var current = 0
    @State private var detent: PresentationDetent = .medium
    @FocusState private var needleFocused: Bool

    private var matches: [DesignStore.TextMatch] {
        store.matches(for: needle, caseSensitive: caseSensitive, wholeWord: wholeWord)
    }

    var body: some View {
        // One search a render, the count and the list both from it.
        let found = matches
        let said = Self.summary(needle: needle, matches: found, replaced: replacedCount)
        return NavigationStack {
            Form {
                Section {
                    TextField("Find", text: $needle)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($needleFocused)
                    TextField("Replace with", text: $replacement)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Toggle("Match case", isOn: $caseSensitive)
                    Toggle("Whole words", isOn: $wholeWord)
                } footer: {
                    Text(said)
                }
                if !found.isEmpty { stepping(found) }
                replaceSection(found)
                if !found.isEmpty { matchList(found) }
            }
            .navigationTitle("Find and replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { needleFocused = true }
            // The letters marked stay only while their match is showing.
            .onDisappear { store.findHighlight = nil }
            .onChange(of: needle) { replacedCount = nil; searchChanged() }
            .onChange(of: caseSensitive) { searchChanged() }
            .onChange(of: wholeWord) { searchChanged() }
            // The count spoken as it changes, once typing pauses, so a
            // VoiceOver user hears what the footer shows.
            .task(id: said) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, !needle.isEmpty else { return }
                AccessibilityNotification.Announcement(said).post()
            }
            .feel(trigger: replacedCount) { _, count in count != nil ? .success : nil }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .sheet(isPresented: notesShown) { PageNotesSheet(store: store) }
    }

    /// The page's notes open while a match in them is showing.
    private var notesShown: Binding<Bool> {
        Binding(get: { store.notesAsked != nil }, set: { if !$0 { store.notesAsked = nil } })
    }

    /// Previous, "k of N" and Next.
    private func stepping(_ found: [DesignStore.TextMatch]) -> some View {
        Section {
            HStack {
                Button { step(-1, in: found) } label: {
                    Label("Previous", systemImage: "chevron.up").labelStyle(.iconOnly)
                }
                Spacer()
                Text(FindReplace.position(current, of: found.count))
                    .monospacedDigit()
                    .accessibilityLabel("Match \(FindReplace.position(current, of: found.count))")
                Spacer()
                Button { step(1, in: found) } label: {
                    Label("Next", systemImage: "chevron.down").labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.borderless)
        }
    }

    /// Replace, for the match showing, and Replace all.
    private func replaceSection(_ found: [DesignStore.TextMatch]) -> some View {
        Section {
            Button("Replace") { replaceCurrent(in: found) }
                .disabled(needle.isEmpty || found.isEmpty)
            // How many it will change, on the button that changes them, as
            // on the Android twin.
            // Only the matches it can change: a chart's value labels and
            // axis numbers are found, never replaced.
            let count = found.filter { DesignStore.replaceable(store.design, $0) }.count
            Button(count == 0 ? tr("Replace all") : tr("Replace all %d", count)) {
                replacedCount = store.replaceAll(needle, with: replacement,
                                                 caseSensitive: caseSensitive, wholeWord: wholeWord)
                current = 0
            }
            .disabled(needle.isEmpty || count == 0)
        }
    }

    private func matchList(_ found: [DesignStore.TextMatch]) -> some View {
        Section("Matches") {
            // Capped: a search for "e" in a long document would otherwise
            // build a list of thousands of rows on every keystroke. The count
            // above always tells the truth. A tap makes the match the one
            // showing, as Previous and Next do.
            ForEach(Array(found.prefix(50).enumerated()), id: \.element.id) { entry in
                Button { show(entry.offset, in: found) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.element.preview)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        Text(whereFound(entry.element))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if found.count > 50 {
                Text("…and \(found.count - 50) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A new search starts at its first match, nothing marked until one is
    /// shown.
    private func searchChanged() {
        current = 0
        store.findHighlight = nil
    }

    /// Previous or Next: the match before or after, round at either end.
    private func step(_ delta: Int, in found: [DesignStore.TextMatch]) {
        show(FindReplace.step(from: current, by: delta, count: found.count), in: found)
    }

    /// Match `index` showing: its page, its box selected under the sheet
    /// and its letters marked, kept at half height so the canvas shows.
    private func show(_ index: Int, in found: [DesignStore.TextMatch]) {
        guard found.indices.contains(index) else { return }
        current = index
        replacedCount = nil
        detent = .medium
        needleFocused = false
        store.reveal(found[index])
    }

    /// Replace: the match showing changed, as one step, and the next one
    /// shown.
    private func replaceCurrent(in found: [DesignStore.TextMatch]) {
        guard !found.isEmpty else { return }
        let at = min(max(current, 0), found.count - 1)
        guard store.replaceOne(found[at], with: replacement) else {
            // A match Replace never changes is passed on from.
            if !DesignStore.replaceable(store.design, found[at]) {
                show(FindReplace.step(from: at, by: 1, count: found.count), in: found)
            }
            return
        }
        replacedCount = nil
        let now = matches
        let next = DesignStore.matchAfter(replacing: found[at], at: at,
                                          length: (replacement as NSString).length, in: now)
        if now.isEmpty {
            current = 0
            store.findHighlight = nil
        } else {
            show(next, in: now)
        }
    }

    /// Where a match is: its page, by title, or "Notes, page N".
    private func whereFound(_ match: DesignStore.TextMatch) -> String {
        if match.kind == .notes { return Self.notesPlace(match.pageIndex) }
        return PageTitles.named(match.pageIndex + 1, title: pageTitle(match.pageIndex))
    }

    /// "Notes, page 3", for a match in page 3's notes.
    static func notesPlace(_ pageIndex: Int) -> String {
        tr("Notes, page %d", pageIndex + 1)
    }

    /// The title of page `index`, to name a match's page by.
    private func pageTitle(_ index: Int) -> String? {
        store.design.pages.indices.contains(index) ? store.design.pages[index].title : nil
    }

    /// "12 found on 3 pages", in the Android twin's words; what was replaced
    /// once it has been.
    static func summary(needle: String, matches: [DesignStore.TextMatch], replaced: Int?) -> String {
        if let replaced {
            return trn("Replaced %d occurrence.|Replaced %d occurrences.", replaced)
        }
        if needle.isEmpty { return tr("Searches the text on every page.") }
        if matches.isEmpty { return tr("Not found in this design.") }
        let pages = Set(matches.map(\.pageIndex)).count
        return tr("%d found on %@", matches.count, trn("%d page|%d pages", pages))
    }
}
