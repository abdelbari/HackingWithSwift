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
                    Button("Replace all") {
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
                                    Text("Page \(match.pageIndex + 1)")
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
        }
        .presentationDetents([.medium, .large])
    }

    private var summary: String {
        if let replacedCount {
            return replacedCount == 1 ? "Replaced 1 occurrence." : "Replaced \(replacedCount) occurrences."
        }
        if needle.isEmpty { return "Searches the text on every page." }
        switch matches.count {
        case 0: return "No matches."
        case 1: return "1 match."
        default: return "\(matches.count) matches."
        }
    }
}
