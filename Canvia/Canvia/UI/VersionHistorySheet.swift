// Earlier versions of this design.
//
// Undo covers the last few minutes; this covers the last few days. A version
// is written at most every two minutes while editing and whenever the editor
// is left, and only when something actually changed — so the list is a set of
// moments, not a keystroke log.

import SwiftUI

struct VersionHistorySheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [DesignLibrary.Version] = []
    @State private var confirming: DesignLibrary.Version?

    var body: some View {
        NavigationStack {
            Group {
                if versions.isEmpty {
                    ContentUnavailableView(
                        "No earlier versions yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("A version is kept every couple of minutes while you "
                                          + "edit, and each time you leave the editor."))
                } else {
                    List(versions) { version in
                        Button {
                            confirming = version
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(version.savedAt, style: .relative) + Text(" ago")
                                    Text(summary(version))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.uturn.backward")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Version history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Restore this version?", isPresented: Binding(
                get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                                titleVisibility: .visible) {
                Button("Restore") {
                    if let version = confirming, let design = DesignLibrary.load(version: version) {
                        // Keep what is on screen now as a version first, so
                        // restoring is never a one-way door.
                        DesignLibrary.snapshot(store.design, force: true)
                        store.restore(design)
                    }
                    confirming = nil
                    dismiss()
                }
                Button("Cancel", role: .cancel) { confirming = nil }
            } message: {
                Text("Your current design is kept as a version too, and restoring can be undone.")
            }
        }
        .presentationDetents(sheetDetents)
        .onAppear { versions = DesignLibrary.versions(for: store.design.id) }
    }

    private func summary(_ v: DesignLibrary.Version) -> String {
        let pages = v.pages == 1 ? "1 page" : "\(v.pages) pages"
        let elements = v.elements == 1 ? "1 element" : "\(v.elements) elements"
        return "\(pages), \(elements)"
    }
}
