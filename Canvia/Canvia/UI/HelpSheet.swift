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
                    List(topics) { topic in
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
