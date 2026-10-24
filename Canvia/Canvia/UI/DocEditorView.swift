// The Doc editor: the design's blocks as one list that scrolls and reflows
// to the phone — tap a block to type in it, '/' at the start of an empty
// one for the block menu, the handle to drag a block up or down (or its
// menu to move it, turn it into another type or delete it). Return makes
// the next block. Headings and words in the brand kit's heading and body
// faces. Export lays it out on pages for a PDF or a print, or writes it as
// a Word document; More has the page size, Turn into presentation and
// Convert to design. Typing in a block is one undo step, closed as the
// caret leaves it. The Android twin's DocEditor.

import PhotosUI
import SwiftUI

struct DocEditorView: View {
    @Bindable var store: DesignStore
    var onHome: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: String?
    /// The block whose '/' menu is open.
    @State private var slashFor: String?
    /// The block a photo being picked goes into.
    @State private var photoFor: String?
    @State private var picking = false
    @State private var photoItem: PhotosPickerItem?
    @State private var addingBlock = false
    /// The Doc laid out on its pages, for the Export sheet while it is up.
    @State private var exportStore: DesignStore?
    @State private var saveTask: Task<Void, Never>?
    @State private var note: String?
    /// The brand kit's heading and body faces, read once as it opens.
    @State fileprivate var styles = DocPages.styles()

    private var blocks: [DocBlock] { Docs.blocks(store.design) }
    private var setup: DocPage { Docs.pageSetup(store.design) }

    var body: some View {
        NavigationStack {
            blockList
                .navigationTitle(store.design.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .photosPicker(isPresented: $picking, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            if let item { placePhoto(item) }
        }
        // Typing in a block is one step, closed as the caret leaves it.
        .onChange(of: focused) { _, _ in store.commit() }
        .modifier(DocEditorSheets(editor: self))
        .onAppear { store.onCommit = { scheduleSave() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { saveDocument() }
        }
    }

    // MARK: the list

    private var blockList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                    row(block, index: index)
                }
                addButton
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func row(_ block: DocBlock, index: Int) -> some View {
        DocBlockRow(block: block, index: index, count: blocks.count, number: numberAt(index),
                    focus: $focused, editor: self)
    }

    private var addButton: some View {
        Button { addingBlock = true } label: {
            Label("Add a block", systemImage: "plus")
        }
        .padding(.top, 8)
        .confirmationDialog("Add a block", isPresented: $addingBlock, titleVisibility: .hidden) {
            ForEach(Docs.types, id: \.self) { type in
                Button(Self.typeName(type)) { appendBlock(type) }
            }
        }
    }

    /// A numbered item's number: it counts on through its run.
    private func numberAt(_ index: Int) -> Int {
        guard blocks[index].type == Docs.number else { return 0 }
        var n = 1
        var i = index - 1
        while i >= 0 && blocks[i].type == Docs.number {
            n += 1
            i -= 1
        }
        return n
    }

    // MARK: toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { closeDoc() } label: { Image(systemName: "chevron.backward") }
                .accessibilityLabel("Back")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .accessibilityLabel("Undo")
                .disabled(!(store.canUndo || store.hasPendingChanges))
            Button { store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .accessibilityLabel("Redo")
                .disabled(!store.canRedo)
            Button { openExport() } label: { Image(systemName: "square.and.arrow.up") }
                .accessibilityLabel("Export")
            moreMenu
        }
    }

    private var moreMenu: some View {
        Menu {
            Picker(selection: pageSize) {
                Text(verbatim: "A4").tag(Docs.a4)
                Text("US Letter").tag(Docs.letter)
            } label: { EmptyView() }
            .pickerStyle(.inline)
            Divider()
            Button("Turn into presentation") { makeDesign(presentation: true) }
            Button("Convert to design") { makeDesign(presentation: false) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    private var pageSize: Binding<String> {
        Binding(get: { setup.size }, set: { size in
            var changed = setup
            changed.size = size
            editDoc { Docs.withPageSetup($0, changed) }
        })
    }

    // MARK: editing

    /// A block type's name, as the '/' menu and Turn into say it.
    static func typeName(_ type: String) -> String {
        switch type {
        case Docs.h1: return tr("Heading 1")
        case Docs.h2: return tr("Heading 2")
        case Docs.h3: return tr("Heading 3")
        case Docs.p: return tr("Paragraph")
        case Docs.bullet: return tr("Bulleted list")
        case Docs.number: return tr("Numbered list")
        case Docs.checklist: return tr("Checklist")
        case Docs.quote: return tr("Quote")
        case Docs.divider: return tr("Divider")
        case Docs.image: return tr("Image")
        case Docs.table: return tr("Table")
        case Docs.chart: return tr("Chart")
        default: return tr("Page break")
        }
    }

    /// `block` made a `type`: its words kept where it has words, a table or
    /// a chart begun with something to change.
    static func turned(_ block: DocBlock, into type: String) -> DocBlock {
        var b = block
        b.type = type
        switch type {
        case Docs.table:
            b.text = ""
            if b.table == nil { b.table = DocTable(rows: [["", ""], ["", ""]], header: true) }
        case Docs.chart:
            b.text = ""
            if b.chart == nil {
                b.chart = ChartSpec(id: UID.make("chart"), kind: DataGraphics.ChartKind.column.rawValue,
                                    data: "A, 3\nB, 5\nC, 2")
            }
        case Docs.divider, Docs.pagebreak, Docs.image:
            b.text = ""
        default:
            if b.text.hasPrefix("/") { b.text.removeFirst() }
            b.checked = type == Docs.checklist ? (b.checked ?? false) : nil
        }
        return b
    }

    /// The design changed by `change`, as one step of its own: words being
    /// typed are closed as theirs first.
    func editDoc(_ change: (Design) -> Design) {
        store.commit()
        store.apply { $0 = change($0) }
    }

    /// The blocks changed by `change`, as one step.
    func editBlocks(_ change: ([DocBlock]) -> [DocBlock]) {
        editDoc { Docs.withBlocks($0, change(Docs.blocks($0))) }
    }

    /// The blocks changed as typing changes them: kept open as one step
    /// until the caret leaves the block, or a key makes another.
    func editLive(_ change: ([DocBlock]) -> [DocBlock]) {
        store.beginGesture()
        store.design = Docs.withBlocks(store.design, change(Docs.blocks(store.design)))
    }

    /// Block `id` changed by `change`, live or as a step.
    func updateBlock(_ id: String, live: Bool, _ change: (inout DocBlock) -> Void) {
        var list = blocks
        guard let i = list.firstIndex(where: { $0.id == id }) else { return }
        change(&list[i])
        let changed = list
        if live { editLive { _ in changed } } else { editBlocks { _ in changed } }
    }

    /// Block `id`'s words as they now stand.
    func wordsOf(_ id: String) -> String {
        blocks.first { $0.id == id }?.text ?? ""
    }

    /// Words typed into block `id`: '/' in an empty block opens the block
    /// menu, and Return makes the next block.
    func typeInto(_ new: String, in id: String) {
        let old = wordsOf(id)
        if new == "/" && old.isEmpty {
            updateBlock(id, live: true) { $0.text = new }
            slashFor = id
            return
        }
        if let cut = new.firstIndex(of: "\n"), !old.contains("\n") {
            splitBlock(id, before: String(new[..<cut]), after: String(new[new.index(after: cut)...]))
            return
        }
        updateBlock(id, live: true) { $0.text = new }
    }

    /// Return: a new block after this one — the same kind of list item,
    /// else a paragraph; an empty item ends the list instead.
    private func splitBlock(_ id: String, before: String, after: String) {
        guard let block = blocks.first(where: { $0.id == id }) else { return }
        let listed: Set<String> = [Docs.bullet, Docs.number, Docs.checklist]
        if before.isEmpty && listed.contains(block.type) {
            updateBlock(id, live: false) { b in
                b.type = Docs.p
                b.checked = nil
            }
            return
        }
        let nextType = listed.contains(block.type) ? block.type : Docs.p
        let made = DocBlock(type: nextType, text: after, checked: nextType == Docs.checklist ? false : nil)
        editBlocks { list in
            list.flatMap { b -> [DocBlock] in
                guard b.id == id else { return [b] }
                var kept = b
                kept.text = before
                return [kept, made]
            }
        }
        focusSoon(made.id)
    }

    /// Block `id` made a `type` — from '/' or Turn into — as one step. A
    /// divider or a page break leaves a paragraph after it to go on in.
    func turnBlock(_ id: String, into type: String) {
        slashFor = nil
        let fresh = DocBlock(type: Docs.p)
        let breaks = type == Docs.divider || type == Docs.pagebreak
        editBlocks { list in
            list.flatMap { b -> [DocBlock] in
                guard b.id == id else { return [b] }
                let made = Self.turned(b, into: type)
                return breaks ? [made, fresh] : [made]
            }
        }
        if breaks { focusSoon(fresh.id) }
        if type == Docs.image { pickPhoto(for: id) }
    }

    /// A block of `type` added at the end, as one step.
    private func appendBlock(_ type: String) {
        let made = Self.turned(DocBlock(type: Docs.p), into: type)
        editBlocks { $0 + [made] }
        if Docs.textTypes.contains(type) { focusSoon(made.id) }
        if type == Docs.image { pickPhoto(for: made.id) }
    }

    func moveBlock(_ index: Int, by step: Int) {
        let to = index + step
        guard blocks.indices.contains(index), blocks.indices.contains(to) else { return }
        editBlocks { list in
            var moved = list
            moved.insert(moved.remove(at: index), at: to)
            return moved
        }
    }

    func deleteBlock(_ id: String) {
        editBlocks { $0.filter { $0.id != id } }
    }

    private func focusSoon(_ id: String) {
        Task { @MainActor in focused = id }
    }

    // MARK: photos

    func pickPhoto(for id: String) {
        photoFor = id
        picking = true
    }

    /// The picked photo brought in as any photo is — scaled, stored, kept
    /// among your uploads — and given to its block, as one step.
    private func placePhoto(_ item: PhotosPickerItem) {
        let id = photoFor
        photoFor = nil
        photoItem = nil
        guard let id else { return }
        Task { @MainActor in
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                note = tr("Couldn't open that")
                return
            }
            let src = await Task.detached(priority: .userInitiated) { () -> String? in
                guard let prepared = ImageDownsampler.prepare(data),
                      let src = MediaStore.store(prepared) else { return nil }
                Uploads.record(source: src)
                return src
            }.value
            guard let src else {
                note = tr("Couldn't open that")
                return
            }
            updateBlock(id, live: false) { $0.src = src }
        }
    }

    // MARK: export, designs, saving

    private func openExport() {
        store.commit()
        exportStore = DesignStore(design: DocPages.drawn(store.design))
    }

    /// The Doc made into a new design of its own, saved and opened in its
    /// place — a presentation, a slide a first-level heading
    /// (Docs.presentation), or its pages (Convert to design). The Doc is
    /// left as it is.
    @MainActor
    private func makeDesign(presentation: Bool) {
        store.commit()
        saveNow()
        let doc = store.design
        var made = presentation ? Docs.presentation(doc) : DocPages.drawn(doc)
        let now = Date().timeIntervalSince1970 * 1000
        made.id = UID.make("doc")
        made.title = Titles.unique(doc.title, taken: DesignLibrary.recents().map(\.title))
        made.titleAuto = false
        made.folder = doc.folder
        made.plannedPosts = nil
        made.createdAt = now
        made.updatedAt = now
        guard DesignLibrary.save(made) else {
            note = tr("Couldn't make the design")
            return
        }
        DesignLibrary.writeThumbnail(for: made)
        LaunchRequest.set(.open(id: made.id))
        NotificationCenter.default.post(name: QuickActions.requested, object: nil)
    }

    @MainActor
    private func closeDoc() {
        focused = nil
        store.commit()
        saveNow()
        onHome()
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            saveDocument()
        }
    }

    @MainActor
    private func saveDocument() {
        saveTask?.cancel()
        saveTask = nil
        if !DesignLibrary.save(store.design) { note = EditorView.saveFailedMessage }
        _ = DesignLibrary.snapshot(store.design)
    }

    /// The Doc and its thumbnail — its first page laid out — on the way out.
    @MainActor
    private func saveNow() {
        saveDocument()
        _ = DesignLibrary.snapshot(store.design, force: true)
        DesignLibrary.writeThumbnail(for: store.design)
    }

    // MARK: sheets

    fileprivate var slashShown: Binding<Bool> {
        Binding(get: { slashFor != nil }, set: { if !$0 { slashFor = nil } })
    }

    fileprivate var exportShown: Binding<Bool> {
        Binding(get: { exportStore != nil }, set: { if !$0 { exportStore = nil } })
    }

    fileprivate var noteShown: Binding<Bool> {
        Binding(get: { note != nil }, set: { if !$0 { note = nil } })
    }

    fileprivate var slashChoices: some View {
        ForEach(Docs.types, id: \.self) { type in
            Button(Self.typeName(type)) {
                if let id = slashFor { turnBlock(id, into: type) }
            }
        }
    }

    @ViewBuilder
    fileprivate var exportSheet: some View {
        if let exportStore {
            ExportSheet(store: exportStore, readOnly: true, doc: store.design, docStore: store)
        }
    }

    fileprivate var noteText: String { note ?? "" }
}

/// The editor's sheets and dialogs, kept out of its body.
private struct DocEditorSheets: ViewModifier {
    let editor: DocEditorView

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Turn into", isPresented: editor.slashShown, titleVisibility: .hidden) {
                editor.slashChoices
            }
            .sheet(isPresented: editor.exportShown) { editor.exportSheet }
            .alert(editor.noteText, isPresented: editor.noteShown) {
                Button("OK", role: .cancel) {}
            }
    }
}

// MARK: - a block

/// One block's row: its handle — dragged, the block moves a place for each
/// step of the drag; tapped, its menu — and the block itself.
private struct DocBlockRow: View {
    let block: DocBlock
    let index: Int
    let count: Int
    let number: Int
    var focus: FocusState<String?>.Binding
    let editor: DocEditorView
    /// Places moved by the drag under way.
    @State private var moved = 0

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            handle
            content
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var handle: some View {
        Menu { handleMenu } label: {
            Image(systemName: "line.3.horizontal")
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .foregroundStyle(.secondary)
        .simultaneousGesture(drag)
        .accessibilityLabel(tr("%@ block", DocEditorView.typeName(block.type)))
        .modifier(DocMoveActions(index: index, count: count, editor: editor, id: block.id))
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { g in
                let steps = Int((g.translation.height / 48).rounded(.towardZero))
                guard steps != moved else { return }
                editor.moveBlock(index, by: steps - moved)
                moved = steps
            }
            .onEnded { _ in moved = 0 }
    }

    @ViewBuilder
    private var handleMenu: some View {
        if index > 0 { Button("Move up") { editor.moveBlock(index, by: -1) } }
        if index < count - 1 { Button("Move down") { editor.moveBlock(index, by: 1) } }
        Section("Turn into") {
            ForEach(Docs.types.filter { Docs.textTypes.contains($0) && $0 != block.type }, id: \.self) { type in
                Button(DocEditorView.typeName(type)) { editor.turnBlock(block.id, into: type) }
            }
        }
        Button("Delete", role: .destructive) { editor.deleteBlock(block.id) }
    }

    @ViewBuilder
    private var content: some View {
        switch block.type {
        case Docs.divider:
            Divider().padding(.vertical, 12)
        case Docs.pagebreak:
            Text(verbatim: "— " + tr("Page break") + " —")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        case Docs.image:
            DocImageBlock(block: block, editor: editor)
        case Docs.table:
            DocTableBlock(block: block, editor: editor)
        case Docs.chart:
            DocChartBlock(block: block, editor: editor)
        default:
            DocTextBlock(block: block, number: number, focus: focus, editor: editor)
        }
    }
}

/// Move up, Move down and Delete for VoiceOver, as the handle's menu has.
private struct DocMoveActions: ViewModifier {
    let index: Int
    let count: Int
    let editor: DocEditorView
    let id: String

    func body(content: Content) -> some View {
        content
            .accessibilityAction(named: Text("Move up")) { if index > 0 { editor.moveBlock(index, by: -1) } }
            .accessibilityAction(named: Text("Move down")) { if index < count - 1 { editor.moveBlock(index, by: 1) } }
            .accessibilityAction(named: Text("Delete")) { editor.deleteBlock(id) }
    }
}

/// A block of words: a heading, a paragraph, a list item or a quote, in
/// the brand kit's faces at the Doc's sizes.
private struct DocTextBlock: View {
    let block: DocBlock
    let number: Int
    var focus: FocusState<String?>.Binding
    let editor: DocEditorView

    private var heading: Bool { [Docs.h1, Docs.h2, Docs.h3].contains(block.type) }

    private var font: Font {
        let styles = editor.styles
        let face = heading ? (styles.heading ?? styles.body) : (styles.body ?? styles.heading)
        return FontLibrary.font(family: face?.family, size: Docs.fontSize(block.type),
                                weight: heading ? max(face?.weight ?? 700, 600) : (face?.weight ?? 400),
                                italic: block.type == Docs.quote)
    }

    private var words: Binding<String> {
        let id = block.id
        return Binding(get: { editor.wordsOf(id) }, set: { editor.typeInto($0, in: id) })
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker
            TextField(placeholder, text: words, axis: .vertical)
                .font(font)
                .focused(focus, equals: block.id)
                .accessibilityLabel(DocEditorView.typeName(block.type))
                .accessibilityAddTraits(heading ? .isHeader : [])
        }
    }

    private var placeholder: String {
        heading ? DocEditorView.typeName(block.type) : tr("Type '/' for blocks")
    }

    @ViewBuilder
    private var marker: some View {
        switch block.type {
        case Docs.bullet:
            Text(verbatim: "•").font(font)
        case Docs.number:
            Text(verbatim: "\(number).").font(font)
        case Docs.checklist:
            Button {
                editor.updateBlock(block.id, live: false) { $0.checked = !($0.checked ?? false) }
            } label: {
                Image(systemName: block.checked == true ? "checkmark.square.fill" : "square")
            }
            .accessibilityLabel("Checklist")
            .accessibilityAddTraits(block.checked == true ? .isSelected : [])
        case Docs.quote:
            Rectangle().fill(.secondary).frame(width: 3, height: 24)
        default:
            EmptyView()
        }
    }
}

/// A picture block: the photo, Choose or Replace, and its alt text.
private struct DocImageBlock: View {
    let block: DocBlock
    let editor: DocEditorView

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = PhotoLibrary.resolve(block.src) {
                Color.clear
                    .aspectRatio(CGFloat(1 / Docs.pictureRatio), contentMode: .fit)
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipped()
                    .accessibilityElement()
                    .accessibilityLabel(block.alt ?? "")
                    .accessibilityAddTraits(.isImage)
            }
            Button(block.src == nil ? tr("Choose a photo") : tr("Replace photo")) { editor.pickPhoto(for: block.id) }
                .buttonStyle(.bordered)
            DocAltField(block: block, editor: editor)
        }
    }
}

/// A picture's or a chart's alt text.
private struct DocAltField: View {
    let block: DocBlock
    let editor: DocEditorView

    private var alt: Binding<String> {
        let id = block.id
        return Binding(get: { block.alt ?? "" }, set: { text in
            editor.updateBlock(id, live: true) { $0.alt = text }
        })
    }

    var body: some View {
        TextField("Alt text", text: alt, axis: .vertical)
            .textFieldStyle(.roundedBorder)
    }
}

/// A table block: its cells to type in, rows and columns to add, and its
/// header row on or off.
private struct DocTableBlock: View {
    let block: DocBlock
    let editor: DocEditorView

    private var rows: [[String]] { Docs.tableRows(block).rows }
    private var header: Bool { Docs.tableRows(block).header }
    private var columns: Int { rows.map(\.count).max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<columns, id: \.self) { c in cell(r, c) }
                }
            }
            HStack(spacing: 8) {
                Button("Add row") { set(rows + [Array(repeating: "", count: columns)], header: header, live: false) }
                Button("Add column") { set(rows.map { $0 + [""] }, header: header, live: false) }
                Button(header ? tr("No header row") : tr("Header row")) { set(rows, header: !header, live: false) }
            }
            .font(.footnote)
        }
    }

    private func cell(_ r: Int, _ c: Int) -> some View {
        TextField("", text: binding(r, c))
            .font(.system(size: 15, weight: header && r == 0 ? .bold : .regular))
            .padding(6)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 1))
            .accessibilityLabel(tr("Row %d, column %d", r + 1, c + 1))
    }

    private func binding(_ r: Int, _ c: Int) -> Binding<String> {
        Binding(get: {
            rows.indices.contains(r) && rows[r].indices.contains(c) ? rows[r][c] : ""
        }, set: { text in
            let width = columns
            let changed = rows.enumerated().map { i, row -> [String] in
                guard i == r else { return row }
                return (0..<width).map { k in
                    k == c ? text.replacingOccurrences(of: "\n", with: " ") : (row.indices.contains(k) ? row[k] : "")
                }
            }
            set(changed, header: header, live: true)
        })
    }

    private func set(_ rows: [[String]], header: Bool, live: Bool) {
        editor.updateBlock(block.id, live: live) { $0.table = DocTable(rows: rows, header: header) }
    }
}

/// A chart block: the chart as the Doc lays it out, its data to change,
/// and its alt text.
private struct DocChartBlock: View {
    let block: DocBlock
    let editor: DocEditorView

    private var data: Binding<String> {
        let id = block.id
        return Binding(get: { block.chart?.data ?? "" }, set: { text in
            editor.updateBlock(id, live: true) { $0.chart?.data = text }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let sheet = DocPages.sheet(editor.store.design, block) {
                DocSheetView(sheet: sheet)
                    .accessibilityElement()
                    .accessibilityLabel(Docs.altOf(block) ?? "")
            }
            if block.chart != nil {
                TextField("Data", text: data, axis: .vertical)
                    .lineLimit(3...)
                    .textFieldStyle(.roundedBorder)
            }
            DocAltField(block: block, editor: editor)
        }
    }
}

/// A sheet of the Doc's — one block laid out — drawn to the column's width.
private struct DocSheetView: View {
    let sheet: Design

    var body: some View {
        GeometryReader { geo in
            PageRenderView(design: sheet, page: sheet.pages[0])
                .frame(width: CGFloat(sheet.width), height: CGFloat(sheet.height))
                .scaleEffect(geo.size.width / CGFloat(max(sheet.width, 1)), anchor: .topLeading)
                .designDirection()
        }
        .aspectRatio(CGFloat(sheet.width / max(sheet.height, 1)), contentMode: .fit)
        .background(Color.white)
    }
}
