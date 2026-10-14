// Your own templates where they are used: their pictures, and the editor's
// Templates panel (first, under "Your templates"), where one of several
// pages opens the same strip a built-in set does (TemplateSetSheet).

import SwiftUI

/// The picture of a template of your own, written when it was saved.
struct UserTemplateThumb: View {
    let entry: UserTemplate
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.systemGray6))
                    .aspectRatio(entry.width / max(entry.height, 1), contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) { PageCountBadge(count: entry.pageCount) }
        .task(id: "\(entry.id)-\(entry.updatedAt)") {
            let id = entry.id
            image = await Task.detached(priority: .userInitiated) { UserTemplates.thumbnail(for: id) }.value
        }
    }
}

/// A template of your own with several pages, while its strip asks what to
/// do with it: its name and its design at its own size, every page.
struct TemplateChoice: Identifiable {
    var id: String
    var name: String
    var design: Design
}

/// The editor's Templates panel's first run: your own, found by name or
/// category, every size fitted to this page. A tap applies one — a
/// template of several pages shows its strip, as a built-in set does — and
/// a long press offers Rename, Update from this design and Delete.
struct EditorYourTemplates: View {
    @Bindable var store: DesignStore
    var search: String
    var onApplied: () -> Void
    @State private var entries: [UserTemplate] = []
    @State private var choice: TemplateChoice?
    @State private var renaming: UserTemplate?
    @State private var renameText = ""
    @State private var deleting: UserTemplate?

    private var shown: [UserTemplate] { UserTemplates.matching(entries, query: search) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !shown.isEmpty {
                Text(UserTemplates.sectionTitle)
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(shown) { entry in tile(entry) }
                }
            }
        }
        .onAppear { entries = UserTemplates.all() }
        .sheet(item: $choice) { shown in
            TemplateSetSheet(name: shown.name, design: shown.design,
                             note: TemplateSetSheet.editorNote(empty: DesignStore.isEmptyForTemplates(store.design)),
                             applyAll: { applyAll(shown) }, usePage: { usePage($0, of: shown) })
        }
        .modifier(UserTemplateDialogs(renaming: $renaming, renameText: $renameText, deleting: $deleting) {
            entries = UserTemplates.all()
        })
    }

    private func tile(_ entry: UserTemplate) -> some View {
        Button {
            use(entry)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                UserTemplateThumb(entry: entry)
                Text(entry.name).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(entry.pageCount == 1 ? entry.name : "\(entry.name), \(entry.pageCount) pages")
        .contextMenu {
            Button { renameText = entry.name; renaming = entry } label: { Label("Rename", systemImage: "pencil") }
            Button {
                update(entry)
            } label: { Label("Update from this design", systemImage: "arrow.triangle.2.circlepath") }
            Button(role: .destructive) { deleting = entry } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// One page replaces this page, as a built-in template does; several
    /// show their strip first.
    private func use(_ entry: UserTemplate) {
        guard let design = UserTemplates.load(id: entry.id) else {
            store.announce("Couldn't open that template", undoable: false)
            return
        }
        if design.pages.count > 1 {
            choice = TemplateChoice(id: entry.id, name: entry.name, design: design)
        } else {
            usePage(0, of: TemplateChoice(id: entry.id, name: entry.name, design: design))
        }
    }

    /// "Apply all N pages": every page fitted to this one, by the rule a
    /// built-in set keeps (DesignStore.appliedTemplateSet) — in place of a
    /// design with nothing on it, else after this page — showing the first
    /// of them, as one Undo.
    private func applyAll(_ shown: TemplateChoice) {
        store.applyTemplateSet(UserTemplates.pages(of: shown.design, width: store.pageWidth, height: store.pageHeight),
                               name: shown.name)
        onApplied()
    }

    /// "Use this page": page `index` alone, fitted to this page, in its
    /// place.
    private func usePage(_ index: Int, of shown: TemplateChoice) {
        let pages = UserTemplates.pages(of: shown.design, width: store.pageWidth, height: store.pageHeight)
        guard pages.indices.contains(index) else { return }
        store.applyTemplatePage(pages[index], name: shown.name)
        onApplied()
    }

    /// The template made again from the design open, every page.
    private func update(_ entry: UserTemplate) {
        guard let updated = UserTemplates.update(entry.id, from: store.design) else {
            store.announce("Couldn't update that template", undoable: false)
            return
        }
        if let design = UserTemplates.load(id: updated.id) { UserTemplates.writeThumbnail(for: design) }
        entries = UserTemplates.all()
        store.announce("Updated \u{201C}\(updated.name)\u{201D}", undoable: false)
    }
}

/// Rename and Delete for a template of your own, on Home and in the editor.
struct UserTemplateDialogs: ViewModifier {
    @Binding var renaming: UserTemplate?
    @Binding var renameText: String
    @Binding var deleting: UserTemplate?
    /// Called once the list has changed.
    var onChange: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Rename template", isPresented: Binding(
                get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let target = renaming { UserTemplates.rename(target.id, to: renameText) }
                    renaming = nil
                    onChange()
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?", isPresented: Binding(
                get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("Delete template", role: .destructive) {
                    if let target = deleting { UserTemplates.delete(target.id) }
                    deleting = nil
                    onChange()
                }
            } message: {
                Text("Designs made from it stay as they are. \(DesignLibrary.cannotBeUndone)")
            }
    }
}

extension View {
    /// More's "Save as template…": a name — the design's title to start
    /// with — and a category, every page kept. `onSaved` is told what to
    /// say.
    func saveTemplateAlert(isPresented: Binding<Bool>, store: DesignStore,
                           onSaved: @escaping (String) -> Void) -> some View {
        modifier(SaveTemplateAlert(isPresented: isPresented, store: store, onSaved: onSaved))
    }
}

private struct SaveTemplateAlert: ViewModifier {
    @Binding var isPresented: Bool
    let store: DesignStore
    var onSaved: (String) -> Void
    @State private var typedName = ""
    @State private var typedCategory = ""

    func body(content: Content) -> some View {
        content
            .alert("Save as template", isPresented: $isPresented) {
                TextField("Name", text: $typedName)
                TextField("Category (\(UserTemplates.defaultCategory))", text: $typedCategory)
                Button("Save") { save() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every page is kept. Your templates come first under Templates, on Home and here.")
            }
            .onChange(of: isPresented) { _, open in
                guard open else { return }
                typedName = store.design.title
                typedCategory = ""
            }
    }

    private func save() {
        let design = store.design
        let title = UserTemplates.name(typedName, design: design)
        guard let saved = UserTemplates.save(design, name: title, category: UserTemplates.category(typedCategory)) else {
            store.buzz(.reject)
            onSaved("Couldn't save the template")
            return
        }
        if let kept = UserTemplates.load(id: saved.id) { UserTemplates.writeThumbnail(for: kept) }
        store.buzz(.confirm)
        onSaved("Saved \u{201C}\(saved.name)\u{201D} to your templates")
    }
}
