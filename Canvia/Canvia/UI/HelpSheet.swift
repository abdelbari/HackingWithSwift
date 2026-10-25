// "What is this?" — searchable, offline, and every topic a door.

import SwiftUI

struct HelpSheet: View {
    var onOpen: (HelpTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            let topics = HelpTopics.search(query)
            Group {
                if topics.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    topicList(topics)
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

    /// The tools the search names, then the topics found.
    private func topicList(_ topics: [HelpTopic]) -> some View {
        List {
            HelpToolsSection(tools: HelpTopics.tools(query)) { target in
                dismiss()
                onOpen(target)
            }
            ForEach(topics) { topic in
                VStack(alignment: .leading, spacing: 6) {
                    Text(topic.title).font(.headline)
                    Text(topic.body).font(.subheadline).foregroundStyle(.secondary)
                    if let target = topic.opens {
                        Button("Show me") {
                            dismiss()
                            onOpen(target)
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

/// The Tools section: a row for each tool a search names
/// (HelpTopics.tools), a tap opening it there and then — in help, and above
/// what Add's search finds. Nothing at all when there are none.
struct HelpToolsSection: View {
    var tools: [HelpTopic]
    var onOpen: (HelpTarget) -> Void

    var body: some View {
        if !tools.isEmpty {
            Section("Tools") {
                ForEach(tools) { tool in
                    if let target = tool.opens {
                        Button {
                            onOpen(target)
                        } label: {
                            Label(tool.title, systemImage: "wrench.and.screwdriver")
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

/// The Tools section outside a list: Add's search shows it above the
/// elements it finds, under the same heading.
struct HelpToolsList: View {
    var tools: [HelpTopic]
    var onOpen: (HelpTarget) -> Void

    var body: some View {
        if !tools.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tools")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(tools) { tool in
                    if let target = tool.opens {
                        Button {
                            onOpen(target)
                        } label: {
                            Label(tool.title, systemImage: "wrench.and.screwdriver")
                                .lineLimit(1)
                                .frame(minHeight: 44)
                        }
                        .tint(Theme.accent)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top])
        }
    }
}

/// Every editor tip may be said again, once each. One tap, then it says it
/// is done rather than offering to do it twice — as on the Android twin.
struct TipsAgainButton: View {
    @State private var reset = false

    var body: some View {
        Button(reset ? tr("Tips will show again in the editor") : tr("Show the editor's tips again")) {
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
        tr("Pick what you are making — a post, a poster, a card. Most sizes come with ready-made designs."),
        tr("Change the words and the colours. Tap anything on the page to select it; drag it to move it. Double-tap text to type in it where it sits, and a photo to crop it."),
        tr("Share it. Export the page as an image, the whole thing as a PDF, or the design itself to open on another phone — Android or iPhone."),
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
