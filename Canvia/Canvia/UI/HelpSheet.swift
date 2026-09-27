// "What is this?" — searchable, offline, and every topic a door.

import SwiftUI

struct HelpSheet: View {
    var onOpen: (EditorSheet) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let topics = HelpTopics.search(query)
            Group {
                if topics.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(topics) { topic in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(topic.title).font(.headline)
                                Text(topic.body).font(.subheadline).foregroundStyle(.secondary)
                                if let sheet = topic.opens {
                                    Button("Show me") {
                                        dismiss()
                                        onOpen(sheet)
                                    }
                                    .font(.subheadline.weight(.semibold))
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        Section {
                            TipsAgainButton()
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search help")
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }
}

/// Every editor tip may be said again, once each. One tap, then it says it
/// is done rather than offering to do it twice — as on the Android twin.
struct TipsAgainButton: View {
    @State private var reset = false

    var body: some View {
        Button(reset ? "Tips will show again in the editor" : "Show the editor's tips again") {
            TipEngine.shared.reset()
            reset = true
        }
        .disabled(reset)
    }
}

/// "How Canvia works", from Home: three steps, the tips and the tour again,
/// and what happens to your work — reachable before the first design, not
/// only from inside one.
struct HowCanviaWorksSheet: View {
    /// Close the sheet and show the welcome tour again.
    var onReplayTour: () -> Void
    @Environment(\.dismiss) private var dismiss

    static let steps: [String] = [
        "Pick what you are making — a post, a poster, a card. Most sizes come with ready-made designs.",
        "Change the words and the colours. Tap anything on the page to select it; drag it to move it. Double-tap text to type in it where it sits, and a photo to crop it.",
        "Share it. Export the page as an image, the whole thing as a PDF, or the design itself to open on another phone — Android or iPhone.",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .font(.headline)
                                .foregroundStyle(Theme.accent)
                                .frame(minWidth: 36, minHeight: 36)
                                .background(Theme.accentSubtle, in: RoundedRectangle(cornerRadius: 8))
                            Text(step)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    TipsAgainButton()
                        .padding(.top, 4)
                    Button("Show the welcome tour again") { onReplayTour() }
                    Text("Everything stays on your phone. No account, no internet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .navigationTitle("How Canvia works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
