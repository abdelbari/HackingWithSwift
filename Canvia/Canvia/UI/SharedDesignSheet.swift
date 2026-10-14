// "New design from shared": what to make of photos, videos, PDFs or SVGs
// opened in Canvia from another app (SharedInbox). A design the size of the
// first photo, one of the four design types nearest its shape, or the pages
// added to a design already made — each item on a page of its own.

import SwiftUI

struct SharedDesignSheet: View {
    let box: SharedInbox.Box
    /// The design open in the editor, offered first under "Add to an open
    /// design…".
    var open: DesignStore?
    /// What came of it, once the items are in.
    var onDone: (Outcome) -> Void
    @Environment(\.dismiss) private var dismiss
    /// The first item's size in pixels, once read; nil for an SVG or one
    /// that does not read.
    @State private var firstSize: CGSize?
    @State private var measured = false
    @State private var recents: [RecentDesign] = []
    @State private var working = false

    /// What the sheet made of the share; each carries what to say of the
    /// items that could not be opened.
    enum Outcome {
        /// A design to open in the editor: new, or one from the shelf added to.
        case open(Design, note: String?)
        /// The design open in the editor took the pages.
        case added(note: String?)
        /// No item could be opened, so nothing was made.
        case nothing(note: String?)
    }

    /// A design sized to its photo when the photo's size is unknown.
    private static let fallbackSize = CGSize(width: 1080, height: 1080)

    var body: some View {
        NavigationStack {
            List {
                Section {
                    fitRow
                    ForEach(SharedInbox.suggestions(for: firstSize ?? Self.fallbackSize)) { preset in
                        presetRow(preset)
                    }
                } header: {
                    Text(itemsText)
                }
                Section {
                    NavigationLink {
                        targetList
                    } label: {
                        Label("Add to an open design…", systemImage: "rectangle.stack.badge.plus")
                    }
                }
            }
            .disabled(working)
            .overlay { if working { OpeningDesignCard() } }
            .navigationTitle("New design from shared")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(working)
                }
            }
        }
        // Put aside, or brought in: the folder goes either way.
        .onDisappear { SharedInbox.remove(box.id) }
        .presentationDetents(sheetDetents)
        .interactiveDismissDisabled(working)
        .task {
            if let first = box.manifest.items.first {
                firstSize = await SharedInbox.pixelSize(of: first, in: box)
            }
            measured = true
            recents = await Task.detached(priority: .userInitiated) { DesignLibrary.recents() }.value
        }
    }

    /// "3 items", or what the one item is.
    private var itemsText: String {
        let items = box.manifest.items
        guard items.count == 1, let only = items.first else { return "\(items.count) items" }
        switch only.kind {
        case .image, .anim: return "1 photo"
        case .video: return "1 video"
        case .pdf: return "1 PDF"
        case .svg: return "1 SVG"
        }
    }

    private var fitRow: some View {
        let size = SharedInbox.fitSize(firstSize ?? Self.fallbackSize)
        return Button {
            make(Design(title: newTitle("Untitled design"), width: size.width, height: size.height))
        } label: {
            row("Fit to the photo", detail: measured ? "\(Int(size.width)) × \(Int(size.height))" : "…",
                systemImage: "photo")
        }
        .disabled(!measured)
    }

    private func presetRow(_ preset: SizePreset) -> some View {
        Button {
            make(preset.makeDesign(title: newTitle(preset.name)))
        } label: {
            row(preset.name, detail: preset.dimensions, systemImage: preset.icon)
        }
        .disabled(!measured)
    }

    private func row(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 28)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The design open in the editor, then the shelf's, most recent first.
    private var targetList: some View {
        List {
            if let open {
                Section("Open now") {
                    Button { addToOpen(open) } label: {
                        row(open.design.title, detail: RelativeTime.pages(open.design.pages.count),
                            systemImage: "pencil.and.outline")
                    }
                }
            }
            Section("Recent designs") {
                ForEach(recents.filter { $0.id != open?.design.id }) { recent in
                    Button { addTo(recent) } label: {
                        HStack(spacing: 12) {
                            ShelfThumbnail(id: recent.id, stamp: recent.thumbnailStamp)
                                .frame(width: 56, height: 42)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recent.title).foregroundStyle(.primary).lineLimit(1)
                                Text(recent.sizeText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .disabled(working)
        .overlay { if working { OpeningDesignCard() } }
        .navigationTitle("Add to an open design")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Never a name already on the shelf.
    private func newTitle(_ base: String) -> String {
        Titles.unique(base, taken: recents.map(\.title))
    }

    /// The items brought in at `size`, away from the main actor.
    private func bringIn(at size: CGSize) async -> SharedInbox.Brought {
        let box = self.box
        return await Task.detached(priority: .userInitiated) {
            SharedInbox.bringIn(box, pageSize: size)
        }.value
    }

    /// A new design of the items, saved and opened.
    private func make(_ blank: Design) {
        working = true
        Task { @MainActor in
            let brought = await bringIn(at: CGSize(width: blank.width, height: blank.height))
            var design = blank
            if !brought.pages.isEmpty { design.pages = brought.pages }
            design.updatedAt = Date().timeIntervalSince1970 * 1000
            finish(brought, design: design)
        }
    }

    /// The items as pages after the last of a design on the shelf, which
    /// then opens.
    private func addTo(_ recent: RecentDesign) {
        working = true
        Task { @MainActor in
            guard var design = DesignLibrary.load(id: recent.id) else {
                working = false
                return
            }
            let brought = await bringIn(at: CGSize(width: design.width, height: design.height))
            design.pages += brought.pages
            design.updatedAt = Date().timeIntervalSince1970 * 1000
            finish(brought, design: design)
        }
    }

    /// The items as pages after the last of the design in the editor, as
    /// one Undo, the first of them shown.
    private func addToOpen(_ store: DesignStore) {
        working = true
        Task { @MainActor in
            let brought = await bringIn(at: CGSize(width: store.design.width, height: store.design.height))
            if !brought.pages.isEmpty {
                let first = store.design.pages.count
                store.apply { $0.pages += brought.pages }
                store.setPage(first)
            }
            finish(brought, design: nil)
        }
    }

    /// Done: the inbox folder gone, the design saved when one is to open,
    /// and what could not be opened said. With nothing brought in at all,
    /// nothing is made.
    private func finish(_ brought: SharedInbox.Brought, design: Design?) {
        SharedInbox.remove(box.id)
        let note = SharedInbox.failureText(failed: brought.failed, total: brought.total)
        working = false
        if brought.pages.isEmpty {
            onDone(.nothing(note: note))
        } else if let design {
            DesignLibrary.save(design)
            onDone(.open(design, note: note))
        } else {
            onDone(.added(note: note))
        }
        dismiss()
    }
}

extension View {
    /// The "New design from shared" sheet for a share that has landed, at
    /// the app's root: a design made or added to opens in the editor, and
    /// items that could not be opened are said there — or, with none
    /// opened, in `failure`.
    func sharedDesignSheet(_ box: Binding<SharedInbox.Box?>, editing: Binding<DesignStore?>,
                           failure: Binding<String?>) -> some View {
        modifier(SharedDesignHost(box: box, editing: editing, failure: failure))
    }
}

private struct SharedDesignHost: ViewModifier {
    @Binding var box: SharedInbox.Box?
    @Binding var editing: DesignStore?
    @Binding var failure: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: $box) { shown in
                SharedDesignSheet(box: shown, open: editing) { outcome in done(outcome) }
            }
    }

    private func done(_ outcome: SharedDesignSheet.Outcome) {
        switch outcome {
        case .open(let design, let note):
            let store = DesignStore(design: design)
            withAnimation(.snappy(duration: 0.28)) { editing = store }
            if let note { say(note, on: store) }
        case .added(let note):
            if let note, let store = editing { say(note, on: store) }
        case .nothing(let note):
            failure = note ?? "Couldn't open that file"
        }
    }

    /// Said in the editor's toast once the sheet has gone and the editor
    /// is up to show it.
    private func say(_ note: String, on store: DesignStore) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            store.announce(note, undoable: false)
        }
    }
}
