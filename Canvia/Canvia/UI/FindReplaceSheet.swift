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
            Button(found.isEmpty ? "Replace all" : "Replace all \(found.count)") {
                replacedCount = store.replaceAll(needle, with: replacement,
                                                 caseSensitive: caseSensitive, wholeWord: wholeWord)
                current = 0
            }
            .disabled(needle.isEmpty || found.isEmpty)
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
                        Text(PageTitles.named(entry.element.pageIndex + 1, title: pageTitle(entry.element.pageIndex)))
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
        guard store.replaceOne(found[at], with: replacement) else { return }
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

    /// The title of page `index`, to name a match's page by.
    private func pageTitle(_ index: Int) -> String? {
        store.design.pages.indices.contains(index) ? store.design.pages[index].title : nil
    }

    /// "12 found on 3 pages", in the Android twin's words; what was replaced
    /// once it has been.
    static func summary(needle: String, matches: [DesignStore.TextMatch], replaced: Int?) -> String {
        if let replaced {
            return replaced == 1 ? "Replaced 1 occurrence." : "Replaced \(replaced) occurrences."
        }
        if needle.isEmpty { return "Searches the text on every page." }
        if matches.isEmpty { return "Not found in this design." }
        let pages = Set(matches.map(\.pageIndex)).count
        return "\(matches.count) found on \(pages == 1 ? "1 page" : "\(pages) pages")"
    }
}
