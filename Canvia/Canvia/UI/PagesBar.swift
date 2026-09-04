// Bottom pages bar: thumbnails, add/duplicate/move/delete.

import SwiftUI
import UIKit

struct PagesBar: View {
    @Bindable var store: DesignStore
    @State private var confirmingDelete = false
    @State private var editingNotes = false

    var body: some View {
        HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(store.design.pages.enumerated()), id: \.element.id) { index, page in
                        pageThumb(index: index, page: page)
                    }
                    Button { store.addPage() } label: {
                        Image(systemName: "plus")
                            .frame(width: 40, height: 56)
                            .background(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                .foregroundStyle(.secondary))
                    }
                    .accessibilityLabel("Add page")
                }
                .padding(.horizontal, 12)
            }

            HStack(spacing: 2) {
                Button { store.duplicatePage() } label: { Image(systemName: "plus.square.on.square") }
                Button { store.movePage(by: -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(store.pageIndex == 0)
                Button { store.movePage(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(store.pageIndex >= store.design.pages.count - 1)
                Button { editingNotes = true } label: {
                    Image(systemName: (store.page.notes?.isEmpty == false)
                          ? "note.text" : "note")
                }
                .accessibilityLabel("Page notes")
                Button(role: .destructive) {
                    // A page can hold an hour's work and the bin is next to
                    // the arrows. Undo covers it, but only if you notice
                    // before the next edit pushes it down the stack.
                    if store.page.elements.isEmpty {
                        store.deletePage()
                    } else {
                        confirmingDelete = true
                    }
                } label: { Image(systemName: "trash") }
                    .disabled(store.design.pages.count <= 1)
            }
            .font(.system(size: 15))
            .padding(.trailing, 12)
        }
        .frame(height: 72)
        .background(Theme.chrome)
        .overlay(alignment: .top) { Divider() }
        .confirmationDialog("Delete page \(store.pageIndex + 1)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete page", role: .destructive) { store.deletePage() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(store.page.elements.count == 1
                 ? "It has 1 element on it."
                 : "It has \(store.page.elements.count) elements on it.")
        }
        .sheet(isPresented: $editingNotes) {
            PageNotesSheet(store: store)
        }
    }

    private func pageThumb(index: Int, page: Page) -> some View {
        let aspect = store.design.width / store.design.height
        return Button {
            store.setPage(index)
        } label: {
            PageThumbnail(design: store.design, page: page)
                .frame(width: 56 * aspect, height: 56)
                .clipped()
                .overlay(alignment: .topLeading) {
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
                        .padding(2)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(index == store.pageIndex ? Theme.accent : Color(.systemGray4),
                            lineWidth: index == store.pageIndex ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

/// Notes about a page rather than on it: what to say over this slide, what
/// the client asked for, which photo still needs replacing. Never rendered,
/// so they cannot leak into an export.
private struct PageNotesSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: Binding(
                get: { store.page.notes ?? "" },
                set: { text in
                    store.applyToPage { $0.notes = text.isEmpty ? nil : text }
                }))
                .padding(8)
                .navigationTitle("Notes for page \(store.pageIndex + 1)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
        }
        .presentationDetents([.medium])
    }
}

/// A page rendered once into a bitmap rather than kept as a live element
/// tree. A ten-page design would otherwise hold every element of every page
/// in the hierarchy — each text element re-running CoreText layout — just to
/// fill a row of 56pt thumbnails.
///
/// `task(id: page)` re-renders exactly when the page's contents change,
/// because Page is Equatable, so the cache can never go stale — but "when
/// the contents change" includes every frame of a drag, so the render is
/// debounced below.
private struct PageThumbnail: View {
    let design: Design
    let page: Page
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Color.white
            }
        }
        .task(id: page) {
            // Debounced, because a drag rewrites the page on every frame.
            // Without the wait, each of those frames started a full
            // ImageRenderer pass over the whole page — rasterising every
            // element, re-running CoreText for every text run — to refresh a
            // 56pt thumbnail nobody is looking at mid-gesture.
            //
            // task(id:) cancels the in-flight task whenever the id changes, so
            // during continuous movement none of them survive the sleep and
            // exactly one render happens once the page stops changing. Pages
            // that are not being edited keep the same id throughout, so they
            // are never re-rendered at all.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            render()
        }
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: page))
        renderer.scale = max(0.02, 140 / max(design.width, 1))
        renderer.isOpaque = true
        if let ui = renderer.uiImage { image = ui }
    }
}
