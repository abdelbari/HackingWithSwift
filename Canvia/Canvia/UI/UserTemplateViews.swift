// Your own templates where they are used: their pictures, and the editor's
// Templates panel (first, under "Your templates", after the brand kit's in
// a "From <kit name>" row), where one of several pages opens the same
// strip a built-in set does (TemplateSetSheet).

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

/// The editor's Templates panel's first run: the brand kit's templates in a
/// row headed "From <kit name>", then your own, found by name or category,
/// every size fitted to this page. A tap applies one — a
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
    /// A template whose Send… was tapped.
    @State private var sending: UserTemplate?
    @State private var kit = BrandKit()

    private var shown: [UserTemplate] { UserTemplates.matching(entries, query: search) }

    /// Those shown that are not the brand kit's: those lead in its row.
    private var others: [UserTemplate] { kit.otherEntries(shown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            BrandTemplatesRow(kit: kit, entries: shown, tileWidth: 120) { tile($0) }
            if !others.isEmpty {
                Text(UserTemplates.sectionTitle)
                    .font(.subheadline.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                    ForEach(others) { entry in tile(entry) }
                }
            }
        }
        .onAppear {
            entries = UserTemplates.all()
            kit = BrandKit.load()
        }
        .sheet(item: $choice) { shown in
            TemplateSetSheet(name: shown.name, design: shown.design,
                             note: TemplateSetSheet.editorNote(empty: DesignStore.isEmptyForTemplates(store.design)),
                             applyAll: { applyAll(shown) }, usePage: { usePage($0, of: shown) },
                             addPage: { addPage($0, of: shown) })
        }
        .modifier(UserTemplateDialogs(renaming: $renaming, renameText: $renameText, deleting: $deleting) {
            entries = UserTemplates.all()
            kit = BrandKit.load()
        })
        .modifier(SendTemplate(sending: $sending))
    }

    private func tile(_ entry: UserTemplate) -> some View {
        Button {
            use(entry)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                UserTemplateThumb(entry: entry)
                Text(entry.name).font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel(entry.pageCount == 1 ? entry.name : entry.name + ", " + trn("%d page|%d pages", entry.pageCount))
        .contextMenu {
            // Both, whatever a tap would do; one of several gives its first
            // page, as on the Android twin.
            Button { useEntryPage(0, of: entry) } label: {
                Label("Use on this page", systemImage: "arrow.triangle.2.circlepath")
            }
            Button { addEntryPage(0, of: entry) } label: {
                Label("Add as new page", systemImage: "plus.rectangle.on.rectangle")
            }
            Button { renameText = entry.name; renaming = entry } label: { Label("Rename", systemImage: "pencil") }
            Button { sending = entry } label: { Label("Send…", systemImage: "square.and.arrow.up") }
            Button {
                update(entry)
            } label: { Label("Update from this design", systemImage: "arrow.triangle.2.circlepath") }
            Button(role: .destructive) { deleting = entry } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// One page goes as a built-in template's does — on a new page after
    /// this one when this page has something on it, else in its place
    /// (DesignStore.useTemplatePage); several show their strip first.
    private func use(_ entry: UserTemplate) {
        guard let shown = loaded(entry) else { return }
        if shown.design.pages.count > 1 {
            choice = shown
        } else {
            let pages = UserTemplates.pages(of: shown.design, width: store.pageWidth, height: store.pageHeight)
            guard let page = pages.first else { return }
            store.useTemplatePage(page, name: shown.name)
            onApplied()
        }
    }

    /// The template of your own as saved, or said when it cannot be read.
    private func loaded(_ entry: UserTemplate) -> TemplateChoice? {
        guard let design = UserTemplates.load(id: entry.id) else {
            store.announce(tr("Couldn't open that template"), undoable: false)
            return nil
        }
        return TemplateChoice(id: entry.id, name: entry.name, design: design)
    }

    /// Page `index` of a template of your own from a hold: in place of this
    /// page.
    private func useEntryPage(_ index: Int, of entry: UserTemplate) {
        if let shown = loaded(entry) { usePage(index, of: shown) }
    }

    /// Page `index` of a template of your own from a hold: on a new page.
    private func addEntryPage(_ index: Int, of entry: UserTemplate) {
        if let shown = loaded(entry) { addPage(index, of: shown) }
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

    /// "Add as new page": page `index` alone, fitted to this page, on a new
    /// page after it.
    private func addPage(_ index: Int, of shown: TemplateChoice) {
        let pages = UserTemplates.pages(of: shown.design, width: store.pageWidth, height: store.pageHeight)
        guard pages.indices.contains(index) else { return }
        store.addTemplatePage(pages[index], name: shown.name)
        onApplied()
    }

    /// The template made again from the design open, every page.
    private func update(_ entry: UserTemplate) {
        guard let updated = UserTemplates.update(entry.id, from: store.design) else {
            store.announce(tr("Couldn't update that template"), undoable: false)
            return
        }
        if let design = UserTemplates.load(id: updated.id) { UserTemplates.writeThumbnail(for: design) }
        entries = UserTemplates.all()
        store.announce(tr("Updated \u{201C}%@\u{201D}", updated.name), undoable: false)
    }
}

/// The brand kit's templates, leading Home's and the Templates panel's: a
/// row headed "From <kit name>" that scrolls, of those of `entries` the kit
/// lists, in its order — nothing when it lists none of them.
struct BrandTemplatesRow<Tile: View>: View {
    let kit: BrandKit
    let entries: [UserTemplate]
    var tileWidth: CGFloat
    /// How the heading is set, as the run below it heads its own.
    var titleFont: Font = .subheadline.weight(.semibold)
    /// The margin the heading and the row's ends keep from the edges.
    var inset: CGFloat = 0
    @ViewBuilder var tile: (UserTemplate) -> Tile

    var body: some View {
        let mine = kit.templateEntries(entries)
        if !mine.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(kit.templatesTitle)
                    .font(titleFont)
                    .padding(.horizontal, inset)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(mine) { entry in
                            tile(entry).frame(width: tileWidth)
                        }
                    }
                    .padding(.horizontal, inset)
                    .padding(.vertical, 4)
                }
            }
        }
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
                TextField("Category (\(UserTemplates.shownCategory(UserTemplates.defaultCategory)))", text: $typedCategory)
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
            onSaved(tr("Couldn't save the template"))
            return
        }
        if let kept = UserTemplates.load(id: saved.id) { UserTemplates.writeThumbnail(for: kept) }
        store.buzz(.confirm)
        onSaved(tr("Saved \u{201C}%@\u{201D} to your templates", saved.name))
    }
}

/// A template of your own's Send…: its file made — the design package,
/// photos and all, under its name and category (DesignPackage.templateFile)
/// — then the share sheet, as the Android twin sends one.
struct SendTemplate: ViewModifier {
    @Binding var sending: UserTemplate?
    @State private var shared: ShareURL?
    @State private var failed = false

    func body(content: Content) -> some View {
        content
            .onChange(of: sending?.id) { _, id in
                guard id != nil, let template = sending else { return }
                sending = nil
                Task { @MainActor in
                    do {
                        shared = ShareURL(url: try await DesignPackage.templateFile(template))
                    } catch {
                        failed = true
                    }
                }
            }
            .sheet(item: $shared) { ShareSheet(urls: [$0.url]) }
            .alert("Couldn't make the template file", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
    }
}

/// A design file just opened: what to make of it. A template sent from
/// either phone ("asTemplate") is added to Your templates unless opened as
/// a design; a plain design file is opened as one unless added as a
/// template — the choice first in each case is the one that leads, as on
/// the Android twin.
struct OpenedFileQuestion: ViewModifier {
    @Binding var opened: DesignPackage.OpenedFile?
    var onDesign: (Design) -> Void
    /// Added to Your templates, or nil when it could not be written.
    var onTemplate: (UserTemplate?) -> Void

    func body(content: Content) -> some View {
        content.alert(opened.map { $0.asTemplate?.name ?? $0.design.title } ?? "",
                      isPresented: Binding(get: { opened != nil }, set: { if !$0 { opened = nil } }),
                      presenting: opened) { file in
            if file.asTemplate != nil {
                Button("Add to Your templates") { addTemplate(file) }
                Button("Open as a design") { openDesign(file) }
            } else {
                Button("Open as a design") { openDesign(file) }
                Button("Add to Your templates") { addTemplate(file) }
            }
            Button("Cancel", role: .cancel) { opened = nil }
        } message: { file in
            if file.asTemplate != nil {
                Text("This file is a template. Add it to Your templates to start designs from it, or open it as a design.")
            } else {
                Text("Open this file as a design, or add it to Your templates to start designs from it.")
            }
        }
    }

    private func openDesign(_ file: DesignPackage.OpenedFile) {
        opened = nil
        onDesign(file.design)
    }

    private func addTemplate(_ file: DesignPackage.OpenedFile) {
        opened = nil
        let entry = DesignPackage.addAsTemplate(file)
        NotificationCenter.default.post(name: UserTemplates.didAdd, object: nil)
        onTemplate(entry)
    }
}

/// Home's template files: a design file opened asks what to make of it
/// (OpenedFileQuestion), a template's Send… shares its file (SendTemplate),
/// and one added from outside — opened in Files — is listed (`onAdded`).
struct TemplateFiles: ViewModifier {
    @Binding var opened: DesignPackage.OpenedFile?
    @Binding var sending: UserTemplate?
    var onDesign: (Design) -> Void
    var onTemplate: (UserTemplate?) -> Void
    var onAdded: () -> Void

    func body(content: Content) -> some View {
        content
            .modifier(OpenedFileQuestion(opened: $opened, onDesign: onDesign, onTemplate: onTemplate))
            .modifier(SendTemplate(sending: $sending))
            .onReceive(NotificationCenter.default.publisher(for: UserTemplates.didAdd)) { _ in onAdded() }
    }
}
