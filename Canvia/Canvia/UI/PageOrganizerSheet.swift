// Every page at once: drag to reorder, select several to duplicate, hide or
// delete, tap one to go there.
//
// The bottom bar shows a strip of thumbnails and moves a page one step at a
// time. That is fine for four pages; for a twenty-page deck, moving the
// closing slide to the front is nineteen taps. A list with drag handles is
// one.

import SwiftUI

struct PageOrganizerSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var editMode = EditMode.active
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            List(selection: $selected) {
                ForEach(Array(store.design.pages.enumerated()), id: \.element.id) { index, page in
                    row(index: index, page: page)
                        .tag(page.id)
                }
                .onMove { source, destination in
                    store.movePages(from: source, to: destination)
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(store.design.pages.count == 1 ? "1 page" : "\(store.design.pages.count) pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        store.duplicatePages(selected)
                        selected = []
                    } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Button {
                        if let id = selected.first, selected.count == 1,
                           let i = store.design.pages.firstIndex(where: { $0.id == id }) {
                            store.setPage(i)
                            dismiss()
                        }
                    } label: { Label("Go to page", systemImage: "arrow.right.circle") }
                        .disabled(selected.count != 1)
                    Spacer()
                    // Show when every page picked is hidden; otherwise Hide,
                    // which hides the rest of them too.
                    Button {
                        store.setPagesHidden(selected, hidden: !selectionHidden)
                        selected = []
                    } label: {
                        Label(selectionHidden ? "Show" : "Hide", systemImage: selectionHidden ? "eye" : "eye.slash")
                    }
                        .disabled(selected.isEmpty)
                    Spacer()
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: { Label("Delete", systemImage: "trash") }
                        .disabled(selected.isEmpty || selected.count >= store.design.pages.count)
                }
            }
            .confirmationDialog(selected.count == 1 ? "Delete this page?" : "Delete \(selected.count) pages?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deletePages(selected)
                    selected = []
                }
                Button("Cancel", role: .cancel) {}
            }
        }
        .presentationDetents([.large])
    }

    /// Whether every page picked is hidden, so the bar offers Show.
    private var selectionHidden: Bool {
        let picked = store.design.pages.filter { selected.contains($0.id) }
        return !picked.isEmpty && picked.allSatisfy { $0.hidden == true }
    }

    private func row(index: Int, page: Page) -> some View {
        let pageSize = store.design.size(for: page)
        let aspect = pageSize.width / max(pageSize.height, 1)
        return HStack(spacing: 14) {
            PageThumbnail(design: store.design, page: page)
                .frame(width: 72 * min(aspect, 1.8), height: 72)
                // Faded with the eye struck through when hidden, as in the
                // pages bar.
                .opacity(page.hidden == true ? 0.4 : 1)
                .overlay(alignment: .topLeading) {
                    if page.hidden == true {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                            .padding(3)
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(index == store.pageIndex ? Theme.accent : Color(.systemGray4),
                            lineWidth: index == store.pageIndex ? 2 : 1))
            VStack(alignment: .leading, spacing: 3) {
                Text("Page \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                Text(page.elements.count == 1 ? "1 element" : "\(page.elements.count) elements")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = page.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        // The whole row, as it reads to the eye: which page, whether it is
        // the one on screen, how much is on it and its notes. A label of
        // "Page 3, current" alone replaced the rest.
        .accessibilityLabel(Self.spokenRow(number: index + 1, current: index == store.pageIndex,
                                           hidden: page.hidden == true,
                                           elements: page.elements.count, notes: page.notes))
    }

    /// What VoiceOver says for a page's row, as the Android twin's reads.
    static func spokenRow(number: Int, current: Bool, hidden: Bool = false,
                          elements: Int, notes: String?) -> String {
        var label = "Page \(number)"
        if current { label += ", current" }
        if hidden { label += ", hidden" }
        label += elements == 1 ? ", 1 element" : ", \(elements) elements"
        if let notes, !notes.isEmpty { label += ", " + notes }
        return label
    }
}
