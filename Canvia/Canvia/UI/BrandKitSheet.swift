// Edit the brand kits: which one is in use, its named palettes, a face for
// each text role, and its logos. A kit can be shared as a file and one
// brought in from another phone.

import SwiftUI
import UniformTypeIdentifiers

struct BrandKitSheet: View {
    @Bindable var store: DesignStore
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
    @State private var problem: String?

    /// What the name field names.
    private enum Naming: Equatable {
        case kit
        case newPalette
        case palette(Int)
    }

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

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
            Button("Import a kit…") { importing = true }
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
            problem = "Couldn't make the kit's file."
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
            problem = error.localizedDescription
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
            if !ColorTools.documentColors(store.design).isEmpty {
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
        return RoundedRectangle(cornerRadius: 9)
            .fill(Color(hex: hex))
            .frame(height: 40)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
            .contextMenu {
                Button("Remove", role: .destructive) { remove() }
            }
            .accessibilityLabel("\(ElementNames.spokenColour(hex)), brand colour")
            .accessibilityAction(named: "Remove") { remove() }
    }

    /// The name typed, applied to what is being named; an empty one changes
    /// nothing.
    private func applyName() {
        let name = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { naming = nil }
        guard !name.isEmpty, let naming else { return }
        switch naming {
        case .kit:
            editKit { $0.name = name }
        case .newPalette:
            editKit { $0.palettes.append(BrandPalette(name: name, colors: [])) }
        case .palette(let index):
            editKit { kit in if kit.palettes.indices.contains(index) { kit.palettes[index].name = name } }
        }
    }

    // MARK: type

    private var typeSection: some View {
        Section {
            ForEach(BrandFonts.Role.allCases) { role in
                roleRow(role)
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
        let name = face.map { FontStore.displayName($0.family, in: store.design) } ?? "None"
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

    /// A face picked for a role keeps the role's weight and size; None
    /// clears it.
    private func pick(_ key: String?, for role: BrandFonts.Role) {
        editKit { kit in
            guard let key else { kit.fonts[role] = nil; return }
            let old = kit.fonts[role]
            kit.fonts[role] = BrandFont(family: key, weight: old?.weight ?? role.defaultWeight, size: old?.size)
        }
    }

    // MARK: logos

    private var logosSection: some View {
        Section {
            let candidates = BrandKit.logoCandidates(openedWith: openedWithLogos, current: kit.logos,
                                                     design: store.design)
            if candidates.isEmpty {
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

    // MARK: dialogs

    /// The sheet's sheets and file picker, apart from its body so the type
    /// checker takes each chain in reasonable time.
    private func withSheets<V: View>(_ content: V) -> some View {
        content
            // The font picker, None first, every font and your own, as for
            // a text — as the Android twin chooses a brand face.
            .sheet(item: $choosingRole) { role in
                FontSheet(store: store, choice: FontSheet.Choice(
                    title: "\(role.label) font",
                    current: kit.fonts[role]?.family,
                    onPick: { key in pick(key, for: role) }))
            }
            .sheet(item: Binding(
                get: { sharedURL.map(ShareURL.init) },
                set: { if $0 == nil { sharedURL = nil } })) { item in
                ShareSheet(urls: [item.url])
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, .data]) { result in
                importKit(result)
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
                Text("Its colours, fonts and logo list go. Designs that use them keep them.")
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
        case .kit: return "Rename brand kit"
        case .newPalette: return "New palette"
        case .palette: return "Rename palette"
        case nil: return ""
        }
    }
}
