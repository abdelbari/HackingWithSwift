// Turn into a Doc, asked first: whether the pages' speaker notes come too
// ("Include speaker notes", off to begin with), then the act on its button
// — from the editor's More menu and a design's card on Home, as the Android
// twin's TurnIntoDocDialog asks it.

import SwiftUI

struct TurnIntoDocSheet: View {
    /// What is done, with whether the notes come too.
    var onTurn: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var notes = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A new Doc of this design's headings, words, tables, charts and pictures. The design stays as it is.")
                        .foregroundStyle(.secondary)
                    Toggle("Include speaker notes", isOn: $notes)
                }
            }
            .navigationTitle("Turn into a Doc")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Turn into a Doc") {
                        dismiss()
                        onTurn(notes)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
