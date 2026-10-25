// Edit the brand kits: which one is in use, its named palettes, a face for
// each text role, its logos, photos and graphics, and its templates. A kit
// can be shared as a file and one brought in from another phone. Opened
// from Home or Settings it has no design attached: what would take from a
// design is not offered, and a logo comes from the photo library instead.

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct BrandKitSheet: View {
    @Bindable var store: DesignStore
    /// Whether `store` is a design being edited, which colours, pictures
    /// and logos can be taken from; false from Home and Settings.
    var withDesign = true
    /// Make brand guidelines: the kit as a new design, to open in the
    /// editor (BrandGuidelines).
    var onGuidelines: ((Design) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var kits = BrandKits.load()
    @State private var newColor = Color.blue
    /// The logos there when the sheet opened, or the kit was switched to,
    /// listed even once switched off.
    @State private var openedWithLogos = BrandKit.load().logos
    /// The role whose face is being chosen in the font picker.
    @State private var choosingRole: BrandFonts.Role?
    /// What a name is being typed for, and the name.
    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var deletingKit = false
    /// The kit's file, while the share sheet is up.
    @State private var sharedURL: URL?
    @State private var importing = false
    /// What the file picker is open for: a kit's file, or an SVG graphic.
    @State private var importKind = ImportKind.kit
    @State private var problem: String?
    /// Photos picked for the kit's photos, and for its graphics.
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var pickedGraphics: [PhotosPickerItem] = []
    /// Photos picked as logos, with no design to take one from.
    @State private var pickedLogos: [PhotosPickerItem] = []
    /// Your own templates, read as the sheet opens.
    @State private var ownTemplates: [UserTemplate] = []

    private enum ImportKind {
        case kit, svg
    }

    /// The kit's lists of pictures with a section each.
    private enum AssetList {
        case photos, graphics

        var keyPath: WritableKeyPath<BrandKit, [String]> {
            self == .photos ? \BrandKit.photos : \BrandKit.graphics
        }

        var title: String { self == .photos ? tr("Photos") : tr("Graphics") }

        /// What VoiceOver calls one: "Brand photo 2 of 5".
        func label(_ index: Int, of count: Int) -> String {
            self == .photos ? tr("Brand photo %d of %d", index + 1, count)
                : tr("Brand graphic %d of %d", index + 1, count)
        }
    }

    /// What the name field names.
    private enum Naming: Equatable {
        case kit
        case newPalette
        case palette(Int)
        /// A colour of a palette: the palette and the colour.
        case colour(Int, String)
    }

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
    private let assetColumns = [GridItem(.adaptive(minimum: 64), spacing: 10)]

    /// The kit in use.
    private var kit: BrandKit { kits.active }

    /// A change to the kit in use.
    private func editKit(_ change: (inout BrandKit) -> Void) {
        var changed = kits.active
        change(&changed)
        kits.update(changed)
    }

    var body: some View {
        withAlerts(withSheets(form))
            // Every change kept as it is made, as on the Android twin, so
            // the sheet can be swiped away as well as closed with Done.
            .onChange(of: kits) { _, changed in changed.save() }
            .onChange(of: kits.activeId) { openedWithLogos = kits.active.logos }
            .onChange(of: pickedPhotos) { _, items in bringIn(items, to: .photos) }
            .onChange(of: pickedGraphics) { _, items in bringIn(items, to: .graphics) }
            .onChange(of: pickedLogos) { _, items in
                guard !items.isEmpty else { return }
                pickedLogos = []
                keep(items, in: \.logos)
            }
            .onAppear { ownTemplates = UserTemplates.all() }
    }

    private var form: some View {
        NavigationStack {
            Form {
                kitSection
                if kit.palettes.isEmpty {
                    paletteSection(nil)
                } else {
                    ForEach(Array(kit.palettes.indices), id: \.self) { index in
                        paletteSection(index)
                    }
                }
                Section {
                    Button("Add a palette") {
                        nameText = ""
                        naming = .newPalette
                    }
                } footer: {
                    Text("The kit's palettes are offered first in every colour picker, each by name. Press and hold a swatch to remove it.")
                }
                typeSection
                logosSection
                assetSection(.photos)
                assetSection(.graphics)
                templatesSection
            }
            .navigationTitle("Brand kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: kits

    /// The kit switcher, at the top, and what can be done with the kit.
    private var kitSection: some View {
        Section {
            Picker("Brand kit", selection: Binding(get: { kit.id }, set: { kits.activeId = $0 })) {
                ForEach(kits.kits) { Text($0.name).tag($0.id) }
            }
            Button("New brand kit") { _ = kits.addKit() }
            Button("Rename this kit…") {
                nameText = kit.name
                naming = .kit
            }
            Button("Share this kit…") { share() }
            if let onGuidelines {
                Button("Make brand guidelines") {
                    let made = BrandGuidelines.design(kit, now: Date().timeIntervalSince1970 * 1000)
                    dismiss()
                    onGuidelines(made)
                }
            }
            Button("Import a kit…") {
                importKind = .kit
                importing = true
            }
            if kits.kits.count > 1 {
                Button("Delete this kit", role: .destructive) { deletingKit = true }
            }
        } footer: {
            Text("The kit in use is the one every design is offered: its colours, its fonts in Add text and Document theme, and its logos.")
        }
    }

    /// The kit's file, written for the share sheet: its logos inside.
    private func share() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(DesignExporter.fileBaseName(kit.name)).\(BrandKitFile.ext)")
        do {
            try BrandKitFile.export(kit).write(to: url, options: .atomic)
            sharedURL = url
        } catch {
            problem = tr("Couldn't make the brand kit file.")
        }
    }

    /// A kit's file, read in as a kit of its own and put in use.
    private func importKit(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            var next = kits
            try BrandKitFile.import(data, into: &next)
            kits = next
        } catch {
            // As the Android twin says it, whatever went wrong.
            problem = BrandKitFile.KitFileError.notAKit.localizedDescription
        }
    }

    // MARK: palettes

    /// One palette: its colours, a way to add one, and its name in the
    /// header with a menu to rename or remove it. Nil is the kit with no
    /// palette yet, whose first colour starts "Colours".
    private func paletteSection(_ index: Int?) -> some View {
        let palette = index.flatMap { kit.palettes.indices.contains($0) ? kit.palettes[$0] : nil }
        let colors = palette?.colors ?? []
        return Section {
            if !colors.isEmpty {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(colors, id: \.self) { hex in
                        swatch(hex, palette: index ?? 0)
                    }
                }
            }
            ColorPicker("Add a colour", selection: $newColor, supportsOpacity: false)
            Button("Add") { editKit { $0.addColor(UIColor(newColor).hexString, palette: index ?? 0) } }
            if withDesign && !ColorTools.documentColors(store.design).isEmpty {
                Button("Add this design's colours") {
                    editKit { kit in
                        for hex in ColorTools.documentColors(store.design, limit: 6).reversed() {
                            kit.addColor(hex, palette: index ?? 0)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(palette?.name ?? BrandKit.firstPaletteName)
                Spacer()
                if let index { paletteMenu(index) }
            }
        }
    }

    private func paletteMenu(_ index: Int) -> some View {
        Menu {
            Button("Rename palette…") {
                nameText = kit.palettes.indices.contains(index) ? kit.palettes[index].name : ""
                naming = .palette(index)
            }
            Button("Delete palette", role: .destructive) {
                editKit { kit in if kit.palettes.indices.contains(index) { kit.palettes.remove(at: index) } }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Palette options")
    }

    private func swatch(_ hex: String, palette index: Int) -> some View {
        let remove = {
            editKit { kit in
                if kit.palettes.indices.contains(index) { kit.palettes[index].colors.removeAll { $0 == hex } }
            }
        }
        let rename = {
            nameText = kit.palettes.indices.contains(index) ? kit.palettes[index].name(of: hex) ?? "" : ""
            naming = .colour(index, hex)
        }
        let name = kit.palettes.indices.contains(index) ? kit.palettes[index].name(of: hex) : nil
        return RoundedRectangle(cornerRadius: 9)
            .fill(Color(hex: hex))
            .frame(height: 40)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
            .help(name ?? "")
            .contextMenu {
                Button("Rename colour…") { rename() }
                Button("Remove", role: .destructive) { remove() }
            }
            .accessibilityLabel(kit.brandColourLabel(hex))
            .accessibilityAction(named: "Rename colour…") { rename() }
            .accessibilityAction(named: "Remove") { remove() }
    }

    /// The name typed, applied to what is being named; an empty one changes
    /// nothing.
    private func applyName() {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { naming = nil }
        // A colour's name may be cleared: a blank takes it away.
        if case .colour(let index, let hex) = naming {
            editKit { kit in if kit.palettes.indices.contains(index) { kit.palettes[index].setName(name, of: hex) } }
            return
        }
        guard !name.isEmpty, let naming else { return }
        switch naming {
        case .kit:
            editKit { $0.name = name }
        case .newPalette:
            editKit { $0.palettes.append(BrandPalette(name: name, colors: [])) }
        case .palette(let index):
            editKit { kit in if kit.palettes.indices.contains(index) { kit.palettes[index].name = name } }
        case .colour:
            break
        }
    }

    // MARK: type

    private var typeSection: some View {
        Section {
            ForEach(BrandFonts.Role.allCases) { role in
                roleRow(role)
                if kit.fonts[role] != nil {
                    BrandRoleMore(face: faceBinding(role), palettes: kit.palettes)
                }
            }
        } header: {
            Text("Type")
        } footer: {
            Text("Add text offers each role in its face. Document theme gives the largest text the first face set, the next size the next, and so on.")
        }
    }

    /// A role's face, its name drawn in itself at the kit's weight for it,
    /// or None; a tap opens the font picker. One of your own not on this
    /// phone says so.
    private func roleRow(_ role: BrandFonts.Role) -> some View {
        let face = kit.fonts[role]
        let name = face.map { FontStore.displayName($0.family, in: store.design) } ?? tr("None")
        let missing = face.flatMap { FontStore.missingNote($0.family, in: store.design) }
        return Button { choosingRole = role } label: {
            HStack {
                Text(role.label).foregroundStyle(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(name)
                        .font(face.map { FontLibrary.font(family: $0.family, size: 17, weight: $0.weight, italic: false) } ?? .body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let missing {
                        Text(missing).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .accessibilityLabel("\(role.label) font")
        .accessibilityValue(missing ?? name)
    }

    /// A face picked for a role keeps the role's weight, size and the rest
    /// of its type; None clears it.
    private func pick(_ key: String?, for role: BrandFonts.Role) {
        editKit { kit in
            guard let key else { kit.fonts[role] = nil; return }
            var face = kit.fonts[role] ?? BrandFont(family: key, weight: role.defaultWeight)
            face.family = key
            kit.fonts[role] = face
        }
    }

    /// A role's face as its More rows change it, written back to the kit.
    private func faceBinding(_ role: BrandFonts.Role) -> Binding<BrandFont> {
        Binding(get: { kit.fonts[role] ?? BrandFont(family: "sans", weight: role.defaultWeight) },
                set: { face in editKit { $0.fonts[role] = face } })
    }

    // MARK: logos

    private var logosSection: some View {
        Section {
            let candidates = BrandKit.logoCandidates(openedWith: openedWithLogos, current: kit.logos,
                                                     design: store.design)
            if !withDesign {
                PhotosPicker(selection: $pickedLogos, maxSelectionCount: 10, matching: .images) {
                    Text("Add logo from photos…")
                }
            } else if candidates.isEmpty {
                Text("Add a picture to the design, then mark it here as a logo.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(candidates.enumerated()), id: \.element) { index, src in
                logoRow(src, index: index, count: candidates.count)
            }
        } header: {
            Text("Logos")
        } footer: {
            Text("Logos appear in the Photos tab of Add, in every design.")
        }
    }

    /// One switch per picture, told apart by its place in the list — the
    /// picture is all that differs, and VoiceOver cannot see it.
    private func logoRow(_ src: String, index: Int, count: Int) -> some View {
        HStack {
            if let ui = PhotoLibrary.resolve(src) {
                Image(uiImage: PhotoLibrary.preview(ui, key: src))
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            Toggle("Picture \(index + 1)", isOn: Binding(
                get: { kit.logos.contains(src) },
                set: { on in
                    editKit { kit in
                        if on { if !kit.logos.contains(src) { kit.logos.append(src) } }
                        else { kit.logos.removeAll { $0 == src } }
                    }
                }))
            .accessibilityLabel("Picture \(index + 1) of \(count), a brand logo")
        }
    }

    // MARK: photos and graphics

    /// The kit's photos or graphics: a tile each, held to remove; the
    /// picture selected added from this design; pictures from the photo
    /// library; and, for graphics, an SVG file, placed as a recolourable
    /// graphic. The Brand tab of Add offers them.
    private func assetSection(_ list: AssetList) -> some View {
        let sources = kit[keyPath: list.keyPath]
        // The one picture selected, not yet in the list; nothing with
        // several selected, as on the Android twin.
        let only = store.selectedElements.count == 1 ? store.selectedElements.first : nil
        let picked = only.flatMap { BrandKit.picture(of: $0) }
        let selected: String? = picked.flatMap { src -> String? in sources.contains(src) ? nil : src }
        return Section {
            if !sources.isEmpty {
                LazyVGrid(columns: assetColumns, spacing: 10) {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, src in
                        assetTile(src, list: list, label: list.label(index, of: sources.count))
                    }
                }
            }
            if withDesign {
                Button("Add from this design") {
                    if let selected { editKit { $0.add(selected, to: list.keyPath) } }
                }
                .disabled(selected == nil)
            }
            PhotosPicker(selection: list == .photos ? $pickedPhotos : $pickedGraphics,
                         maxSelectionCount: 10, matching: .images) {
                Text("Add from photos")
            }
            if list == .graphics {
                Button("Add an SVG file") {
                    importKind = .svg
                    importing = true
                }
            }
        } header: {
            Text(list.title)
        } footer: {
            if list == .graphics {
                Text("Photos and graphics appear in the Brand tab of Add, in every design. Press and hold one to remove it.")
            }
        }
    }

    private func assetTile(_ src: String, list: AssetList, label: String) -> some View {
        let remove = { editKit { kit in kit[keyPath: list.keyPath].removeAll { $0 == src } } }
        return assetThumb(src)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(.systemGray6)))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contextMenu {
                Button("Remove", role: .destructive) { remove() }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAction(named: "Remove") { remove() }
    }

    /// A picture as itself; an SVG graphic as the uploads show one.
    @ViewBuilder
    private func assetThumb(_ src: String) -> some View {
        if BrandKit.svgID(src) != nil {
            VStack(spacing: 2) {
                Image(systemName: "square.on.circle")
                Text("SVG").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)
        } else if let ui = PhotoLibrary.resolve(src) {
            Image(uiImage: PhotoLibrary.preview(ui, key: src))
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color(.systemGray5)
        }
    }

    /// The photos picked, each stored as a photo brought in is — scaled
    /// and kept among your uploads, off the main thread — and added to the
    /// list in the order picked; one that does not read is said.
    private func bringIn(_ items: [PhotosPickerItem], to list: AssetList) {
        guard !items.isEmpty else { return }
        if list == .photos { pickedPhotos = [] } else { pickedGraphics = [] }
        keep(items, in: list.keyPath)
    }

    /// The photos picked, stored as above, added to one of the kit's
    /// lists — its photos, graphics or logos.
    private func keep(_ items: [PhotosPickerItem], in keyPath: WritableKeyPath<BrandKit, [String]>) {
        Task { @MainActor in
            var added: [String] = []
            for item in items {
                guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                let src = await Task.detached(priority: .userInitiated) { () -> String? in
                    guard let prepared = ImageDownsampler.prepare(data),
                          let src = MediaStore.store(prepared) else { return nil }
                    Uploads.record(source: src)
                    return src
                }.value
                if let src { added.append(src) }
            }
            if added.count < items.count { problem = tr("Couldn't add every photo picked.") }
            editKit { kit in
                for src in added { kit.add(src, to: keyPath) }
            }
        }
    }

    /// An SVG file kept among your uploads, as Add keeps one, and added to
    /// the kit's graphics — refused, in Add's words, when it draws nothing.
    private func addSVG(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task { @MainActor in
            let id = await Task.detached(priority: .userInitiated) { () -> String? in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), data.count <= SvgImport.maxBytes,
                      let text = String(data: data, encoding: .utf8),
                      SvgImport.graphic(text, pageWidth: 1080, pageHeight: 1080) != nil,
                      let id = MediaStore.storeGraphic(data) else { return nil }
                Uploads.record(id, kind: .image)
                return id
            }.value
            guard let id else {
                problem = tr("No shape to take from that file")
                return
            }
            editKit { $0.add(BrandKit.svgSource(id), to: \.graphics) }
        }
    }

    // MARK: templates

    /// The kit's templates, from your own, held to take out; they lead
    /// Home's templates and the Templates panel's, in a row of their own.
    private var templatesSection: some View {
        let entries = kit.templateEntries(ownTemplates)
        let addable = ownTemplates.filter { !kit.templates.contains($0.id) }
        return Section {
            ForEach(entries) { entry in
                templateRow(entry)
            }
            Menu("Add a template of yours") {
                ForEach(addable) { entry in
                    Button(entry.name) { editKit { $0.add(entry.id, to: \.templates) } }
                }
            }
            .disabled(addable.isEmpty)
        } header: {
            Text("Templates")
        } footer: {
            Text(ownTemplates.isEmpty
                 ? tr("Save a design as a template from More, then add it here.")
                 : tr("They come first, under the kit's name, on Home and in Templates."))
        }
    }

    private func templateRow(_ entry: UserTemplate) -> some View {
        let remove = { editKit { kit in kit.templates.removeAll { $0 == entry.id } } }
        return HStack(spacing: 12) {
            UserTemplateThumb(entry: entry)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            Text(entry.name)
            Spacer()
        }
        .contextMenu {
            Button("Remove", role: .destructive) { remove() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Remove") { remove() }
    }

    // MARK: dialogs

    /// The sheet's sheets and file picker, apart from its body so the type
    /// checker takes each chain in reasonable time.
    private func withSheets<V: View>(_ content: V) -> some View {
        content
            // The font picker, None first, every font and your own, as for
            // a text — as the Android twin chooses a brand face.
            .sheet(item: $choosingRole) { role in
                FontSheet(store: store, choice: FontSheet.Choice(
                    title: tr("%@ font", role.label),
                    current: kit.fonts[role]?.family,
                    onPick: { key in pick(key, for: role) }))
            }
            .sheet(item: Binding(
                get: { sharedURL.map(ShareURL.init) },
                set: { if $0 == nil { sharedURL = nil } })) { item in
                ShareSheet(urls: [item.url])
            }
            // One file picker for both, as two on one view do not both open.
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: importKind == .svg ? [UTType.svg] : [UTType.json, .data]) { result in
                if importKind == .svg { addSVG(result) } else { importKit(result) }
            }
    }

    private func withAlerts<V: View>(_ content: V) -> some View {
        content
            .alert(namingTitle, isPresented: Binding(
                get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Name", text: $nameText)
                Button("Save") { applyName() }
                Button("Cancel", role: .cancel) { naming = nil }
            }
            .confirmationDialog("Delete \u{201C}\(kit.name)\u{201D}?", isPresented: $deletingKit,
                                titleVisibility: .visible) {
                Button("Delete kit", role: .destructive) { kits.removeKit(kit.id) }
            } message: {
                Text("Its colours, fonts, and lists of logos, photos, graphics and templates go. Designs that use them keep them.")
            }
            .alert("Couldn't do that", isPresented: Binding(
                get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK") { problem = nil }
            } message: {
                Text(problem ?? "")
            }
    }

    private var namingTitle: String {
        switch naming {
        case .kit: return tr("Rename brand kit")
        case .newPalette: return tr("New palette")
        case .palette: return tr("Rename palette")
        case .colour: return tr("Rename colour")
        case nil: return ""
        }
    }
}

/// The kit sheet with no design attached, as Home and Settings open it.
struct StandaloneBrandKitSheet: View {
    /// Make brand guidelines, from Home; none offers it.
    var onGuidelines: ((Design) -> Void)? = nil
    /// A blank page, for the font picker to measure against.
    @State private var blank = DesignStore(design: Design(title: "", width: 1080, height: 1080))

    var body: some View {
        BrandKitSheet(store: blank, withDesign: false, onGuidelines: onGuidelines)
    }
}
