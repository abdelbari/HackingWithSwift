// Find and replace, across every page.
//
// A single-page design does not need this; a ten-page deck with a client's
// name in it does, and retyping that by hand is exactly the kind of chore
// that makes people go back to a desktop tool.
//
// The search is non-mutating and runs on every keystroke, so the count is
// live. Replace-all is one undo step: forty separate steps to undo a mistaken
// replace would be worse than no undo at all.

import SwiftUI

struct FindReplaceSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    @State private var needle = ""
    @State private var replacement = ""
    @State private var caseSensitive = false
    @State private var replacedCount: Int?
    @FocusState private var needleFocused: Bool

    private var matches: [DesignStore.TextMatch] {
        store.matches(for: needle, caseSensitive: caseSensitive)
    }

    var body: some View {
        NavigationStack {
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
                } footer: {
                    Text(summary)
                }

                Section {
                    // How many it will change, on the button that changes
                    // them, as on the Android twin.
                    Button(matches.isEmpty ? "Replace all" : "Replace all \(matches.count)") {
                        replacedCount = store.replaceAll(needle, with: replacement,
                                                         caseSensitive: caseSensitive)
                    }
                    .disabled(needle.isEmpty || matches.isEmpty)
                }

                if !matches.isEmpty {
                    Section("Matches") {
                        // Capped: a search for "e" in a long document would
                        // otherwise build a list of thousands of rows on every
                        // keystroke. The count above always tells the truth.
                        ForEach(matches.prefix(50)) { match in
                            Button {
                                store.reveal(match)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.preview)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(PageTitles.named(match.pageIndex + 1, title: pageTitle(match.pageIndex)))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if matches.count > 50 {
                            Text("…and \(matches.count - 50) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Find and replace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { needleFocused = true }
            .onChange(of: needle) { replacedCount = nil }
            // The count spoken as it changes, once typing pauses, so a
            // VoiceOver user hears what the footer shows.
            .task(id: summary) {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, !needle.isEmpty else { return }
                AccessibilityNotification.Announcement(summary).post()
            }
            .feel(trigger: replacedCount) { _, count in count != nil ? .success : nil }
        }
        .presentationDetents([.medium, .large])
    }

    private var summary: String {
        Self.summary(needle: needle, matches: matches, replaced: replacedCount)
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
