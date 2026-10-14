// Insert sheet: templates, shapes, lines, icons, text presets & font
// combinations, photos, stickers, and photo-library uploads.

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

struct InsertSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Templates"
    @State private var search = ""
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var importingPDF = false
    @State private var scanning = false
    /// Bumped when a favourite is toggled, so the tab re-reads the set.
    @State private var favoritesVersion = 0
    @State private var qrPayload = ""
    /// Every template, fitted to this page, rather than only those made for
    /// its size.
    @State private var everySizeTemplates = false
    /// A template of several pages, while what to do with it is asked.
    @State private var templateChoice: TemplateChoice?
    /// The component whose deletion is being asked about.
    @State private var removingComponent: Component?
    /// The words typed for a code are more than a code holds.
    @State private var qrTooLong = false
    @FocusState private var qrFocused: Bool

    // Six at most: a segmented control gives each the same width, and a
    // seventh cuts the longer names short on a small phone. Icons are a
    // section of Elements for that reason.
    private let tabs = ["Templates", "Elements", "Text", "Photos", "Stickers", "Background"]

    private var isReplacing: Bool { store.replaceTargetId != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $tab) {
                    ForEach(tabs, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    Color.clear.frame(height: 0).id(favoritesVersion)
                    if nothingMatches {
                        ContentUnavailableView.search(text: search)
                            .padding(.top, 40)
                    } else {
                        switch tab {
                        case "Templates": templatesGrid
                        case "Elements": elementsGrid
                        case "Text": textList
                        case "Photos": photosGrid
                        case "Stickers": stickersGrid
                        default: backgroundNote
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: searchPrompt)
            .navigationTitle(isReplacing ? "Replace image" : "Add to design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear {
            // Replacing? Go straight to the picture sources.
            if isReplacing { tab = "Photos" }
        }
        .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            importPDF(url)
        }
        .onDisappear {
            // Abandoning the sheet must not leave a replace pending.
            store.replaceTargetId = nil
        }
        .onChange(of: pickedItems) {
            let items = pickedItems
            guard !items.isEmpty else { return }
            pickedItems = []
            bringIn(items)
        }
    }

    /// Photos and clips from the library: into the frame being replaced, into
    /// the selection's empty frames — a grid's cells in reading order — or
    /// onto the page, whatever the frames do not take. A clip takes a while
    /// to copy, so that is said first; what could not be read is counted and
    /// said at the end, as the Android twin says it, rather than the sheet
    /// just staying open.
    private func bringIn(_ items: [PhotosPickerItem]) {
        // Capture the replace target and the frames now: loading is async,
        // and the sheet (and with it store.replaceTargetId) may be gone by
        // the time it finishes — the pick should still go where it was
        // meant to, not insert a stray.
        let target = store.replaceTargetId
        let emptyFrames = target == nil ? store.framesToFill : []
        let store = self.store
        if items.contains(where: { item in item.supportedContentTypes.contains { $0.conforms(to: .movie) } }) {
            store.announce("Bringing them in…", undoable: false)
        }
        Task {
            // Those the frames do not take land as a cascade, each a step
            // down and right from the last, so ten photos are ten visible
            // photos and not one photo ten deep.
            var frames = emptyFrames
            var placed = 0
            var added = 0
            for item in items {
                guard let stored = await load(item) else { continue }
                placed += 1
                if placed == 1, let target {
                    insertImage(stored.src, natural: stored.natural, replacing: target)
                    continue
                }
                if !frames.isEmpty, store.replacePicture(frames.removeFirst(), with: stored.src) { continue }
                insertImage(stored.src, natural: stored.natural, cascade: added)
                added += 1
            }
            let missed = items.count - placed
            if placed == 0 {
                store.buzz(.reject)
                store.announce(target != nil ? "Couldn't open that photo"
                               : items.count == 1 ? "Couldn't open that" : "Couldn't open those",
                               undoable: false)
            } else if missed > 0 {
                store.buzz(.reject)
                store.announce(missed == 1 ? "One couldn't be opened" : "\(missed) couldn't be opened",
                               undoable: false)
            } else if target == nil {
                store.buzz(.confirm)
            }
            // Out of the way either way, so what was said is seen.
            dismiss()
        }
    }

    /// What the camera took, kept among your uploads and placed as a
    /// picked photo or clip is: into the frame being replaced, else into
    /// the selection's first empty frame, else onto the page.
    private func bringInCaptured(_ outcome: CameraCapture.Outcome) {
        let target = store.replaceTargetId
        let store = self.store
        if case .cancelled = outcome {
            store.announce(CameraCapture.cancelledNote, undoable: false)
            return
        }
        Task {
            guard let stored = await CameraCapture.store(outcome) else {
                store.buzz(.reject)
                store.announce(CameraCapture.failedNote, undoable: false)
                return
            }
            if let target {
                insertImage(stored.src, natural: stored.natural, replacing: target)
            } else {
                place(stored.src, natural: stored.natural)
                store.buzz(.confirm)
            }
            dismiss()
        }
    }

    /// One picked item stored: a clip whole, shown by its poster frame, an
    /// animated GIF or WebP whole, shown by its first frame, or a picture
    /// decoded, scaled and re-encoded — all off the main actor, where a
    /// full-resolution camera photo's decode belongs. A clip or a photo is
    /// kept among your uploads, to use again; an animated picture lives
    /// with the designs that show it.
    private func load(_ item: PhotosPickerItem) async -> (src: String, natural: CGSize, isVideo: Bool)? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        if let movie = item.supportedContentTypes.first(where: { $0.conforms(to: .movie) }) {
            let ext = movie.preferredFilenameExtension ?? "mov"
            return await Task.detached(priority: .userInitiated) { () -> (src: String, natural: CGSize, isVideo: Bool)? in
                guard let id = VideoStore.store(data, ext: ext), let poster = VideoStore.poster(id) else { return nil }
                Uploads.record(id, kind: .video)
                return (VideoStore.src(id, at: nil), poster.size, true)
            }.value
        }
        return await Task.detached(priority: .userInitiated) { () -> (src: String, natural: CGSize, isVideo: Bool)? in
            // An animated GIF or WebP is kept as it came, to play; a still
            // one is a photo like any other.
            if let animated = AnimStore.bringIn(data) { return (animated.src, animated.natural, false) }
            guard let prepared = ImageDownsampler.prepare(data),
                  let src = MediaStore.store(prepared) else { return nil }
            Uploads.record(source: src)
            return (src, prepared.natural, false)
        }.value
    }

    /// What the search field says on the tabs whose search is their own.
    private var searchPrompt: Text? {
        switch tab {
        case "Elements": return Text("Search shapes and icons")
        case "Text": return Text("Search font combinations")
        default: return nil
        }
    }

    /// A search that finds nothing on this tab says so, rather than showing
    /// a blank scroll view that looks like a load that never finished. The
    /// Text tab says it in its own words, under the combinations' search.
    private var nothingMatches: Bool {
        guard !search.isEmpty else { return false }
        switch tab {
        // Nothing of any size: those of other sizes are a chip away, so
        // only a search nothing at all answers is said to be empty.
        case "Templates":
            return ContentLibrary.editorTemplates(width: store.pageWidth, height: store.pageHeight,
                                                  everySize: true, matching: search).isEmpty
                && UserTemplates.matching(UserTemplates.all(), query: search).isEmpty
        case "Elements":
            return !ContentLibrary.shapes.contains { ContentLibrary.shape($0, matches: search) }
                && IconLibrary.search(search).isEmpty
        case "Photos": return filteredPhotos.isEmpty
        case "Stickers":
            return filteredStickerGroups.allSatisfy { $0.emoji.isEmpty } && Stickers.searchAnimated(search).isEmpty
        default: return false
        }
    }

    // MARK: templates

    /// Those made for this page's size lead; the rest, fitted to it, are a
    /// chip away. A tap starts the page over from the template, as one Undo.
    private var templatesGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Your own first, every size, fitted to this page.
            EditorYourTemplates(store: store, search: search) { dismiss() }
            if !exactTemplates.isEmpty {
                Toggle("Every size, fitted to this page", isOn: $everySizeTemplates)
                    .toggleStyle(.button)
                    .tint(Theme.accent)
                    .font(.subheadline)
            }
            Text(filteredTemplates.isEmpty
                 ? "No template is called that, or is of that kind."
                 : ContentLibrary.editorTemplatesNote(exactCount: exactTemplates.count))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(favoritesFirst(filteredTemplates, kind: "template", id: \.id)) { template in
                    templateTile(template)
                }
            }
        }
        .padding()
        .templatePageChoice($templateChoice, store: store) { dismiss() }
    }

    private func templateTile(_ template: Template) -> some View {
        let starred = Favorites.isFavorite("template", template.id)
        return Button {
            startOver(from: template)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                TemplateThumb(template: template)
                    .overlay(alignment: .topTrailing) { if starred { starBadge } }
                Text(template.name).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityLabel(starred ? "\(template.name), favourite" : template.name)
        .contextMenu { favoriteButton("template", template.id) }
    }

    /// The page's background and every element give way to the template's,
    /// fitted to this page's own size — which in a design of mixed sizes
    /// need not be the document's — as one step the toast can take back.
    private func startOver(from template: Template) {
        // One of several pages asks first: all of them, or one.
        guard template.pageCount == 1 else {
            templateChoice = TemplateChoice(id: template.id, name: template.name, design: template.instantiate())
            return
        }
        let page = template.makePage(width: store.pageWidth, height: store.pageHeight)
        store.applyToPage { current in
            current.background = page.background
            current.elements = page.elements
        }
        store.selection.removeAll()
        store.buzz(.confirm)
        store.announce("Started over from \u{201C}\(template.name)\u{201D}")
        dismiss()
    }

    /// Templates made for exactly this page's size.
    private var exactTemplates: [Template] {
        ContentLibrary.sizedTemplates(width: store.pageWidth, height: store.pageHeight, category: nil)
    }

    private var filteredTemplates: [Template] {
        ContentLibrary.editorTemplates(width: store.pageWidth, height: store.pageHeight,
                                       everySize: everySizeTemplates, matching: search)
    }

    // MARK: shapes + lines

    private var elementsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("QR code")
            qrRow
            sectionHeader("Lines")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                lineTile("Line", "line.diagonal", nil, nil)
                lineTile("Arrow", "arrow.right", nil, "arrow")
                lineTile("Double arrow", "arrow.left.and.right", "arrow", "arrow")
                lineTile("Dot ends", "ellipsis", "dot", "dot")
            }
            dataRow
            svgImportRow
            componentsSection
            let starred = search.isEmpty ? Favorites.ids(of: "shape").compactMap { ContentLibrary.shapeMap[$0] } : []
            ForEach(["Favourites"] + ContentLibrary.shapeCategories, id: \.self) { category in
                let shapes = category == "Favourites" ? starred : ContentLibrary.shapes.filter {
                    $0.category == category && ContentLibrary.shape($0, matches: search)
                }
                if !shapes.isEmpty {
                    sectionHeader(category == "Favourites" ? category : ContentLibrary.shapeGroupName(category))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                        ForEach(shapes) { shape in shapeTile(shape) }
                    }
                }
            }
            iconsSection
        }
        .padding()
    }

    private func shapeTile(_ shape: ShapeDef) -> some View {
        let starred = Favorites.isFavorite("shape", shape.id)
        return Button {
            // From this page's size — a page may have its own.
            let size = min(store.pageWidth, store.pageHeight) * 0.28
            store.add(.shape(shape.id, w: size, h: size))
            dismiss()
        } label: {
            LibraryShape(definition: shape, cornerRadius: 0)
                .fill(Color(hex: "#545d6b"))
                .padding(8)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .overlay(alignment: .topTrailing) { if starred { starBadge } }
        }
        .accessibilityLabel(starred ? "\(shape.name), favourite" : shape.name)
        .contextMenu { favoriteButton("shape", shape.id) }
    }

    /// A code is generated from its payload every time it is drawn, so the
    /// element's source is the payload itself and there is nothing to store.
    private var qrRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "qrcode")
                    .font(.title2)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))

                TextField("Link or text", text: $qrPayload)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($qrFocused)
                    .onSubmit { addQRCode() }
                    .onChange(of: qrPayload) { qrTooLong = false }

                Button("Add", action: addQRCode)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(trimmedQRPayload.isEmpty || qrTooLong)
            }
            if qrTooLong {
                Text(Self.qrTooLongMessage)
                    .font(.footnote)
                    .foregroundStyle(Color(.systemRed))
            }
        }
    }

    static let qrTooLongMessage = "That is too long for a QR code."

    private var trimmedQRPayload: String {
        qrPayload.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// More than a code holds is refused, as the Android twin refuses it,
    /// with the words kept to shorten — never a blank code on the page.
    private func addQRCode() {
        let payload = trimmedQRPayload
        guard !payload.isEmpty else { return }
        guard CodeGenerator.modules(for: payload) != nil else {
            qrTooLong = true
            store.buzz(.reject)
            return
        }
        qrFocused = false
        // Square, because a QR code that is not square has been stretched and
        // no longer scans.
        // From this page's size — a page may have its own — as the Android
        // twin sizes a code.
        let size = min(store.pageWidth, store.pageHeight) * 0.3
        store.add(.image(CodeGenerator.source(for: payload), w: size.rounded(), h: size.rounded()))
        qrPayload = ""
        dismiss()
    }

    /// A line with its ends, named under the tile as the Android twin's
    /// line presets are, so it can be told apart by eye and by VoiceOver.
    private func lineTile(_ name: String, _ icon: String, _ start: String?, _ end: String?) -> some View {
        Button {
            var el = Element.line(w: store.pageWidth * 0.3)
            el.startCap = start ?? "none"
            el.endCap = end ?? "none"
            store.add(el)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 64, height: 52)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isButton)
    }

    // MARK: icons

    /// Below the shapes, a heading and one row a category, as the Android
    /// twin lays them out. Headed as icons, since the shapes have an Arrows
    /// and a Symbols of their own.
    private var iconsSection: some View {
        ForEach(iconGroups) { group in
            sectionHeader(group.category)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(group.icons) { icon in iconTile(icon) }
                }
            }
        }
    }

    /// Those the search finds, by category; while nothing is searched,
    /// starred icons lead in a row of their own.
    private var iconGroups: [IconGroup] {
        var groups = IconLibrary.grouped(search).map {
            IconGroup(category: "Icons \u{00B7} \($0.category)", icons: $0.icons)
        }
        let starred = Favorites.ids(of: "icon").compactMap { IconLibrary.icon($0) }
        if search.trimmingCharacters(in: .whitespaces).isEmpty && !starred.isEmpty {
            groups.insert(IconGroup(category: "Favourite icons", icons: starred), at: 0)
        }
        return groups
    }

    /// An icon drawn from its own path, read by its name, and starred as the
    /// shapes are.
    private func iconTile(_ icon: IconDef) -> some View {
        let starred = Favorites.isFavorite("icon", icon.id)
        return Button {
            addIcon(icon)
        } label: {
            LibraryShape(definition: icon.shape, cornerRadius: 0)
                .fill(Color(hex: "#545d6b"))
                .padding(14)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .overlay(alignment: .topTrailing) { if starred { starBadge } }
        }
        .accessibilityLabel(starred ? "\(icon.name), favourite" : icon.name)
        .contextMenu { favoriteButton("icon", icon.id) }
    }

    /// In the middle of this page — a page may have a size of its own — in
    /// the brand kit's first colour, or ink that reads on the page, and
    /// selected: one Undo, as on the Android twin.
    private func addIcon(_ icon: IconDef) {
        let fill = IconLibrary.fill(for: store.page, brandColours: BrandKit.load().colors)
        store.add(IconLibrary.element(icon, pageWidth: store.pageWidth, pageHeight: store.pageHeight, fill: fill))
        dismiss()
    }

    // MARK: text

    /// The role inserts and a page number, then the font combinations two
    /// to a row, the six pairings first. A search keeps the combinations
    /// whose name or a tag has it, and only them — as on the Android twin.
    private var textList: some View {
        // In the active brand kit's faces, role by role.
        let fonts = BrandKit.load().fonts
        let searching = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            if !searching {
                ForEach(fonts.addTextRoles) { role in
                    roleInsert(role, face: fonts[role])
                }
                textInsert("Page {page} of {pages}", size: 0.022, weight: 500)
            }
            comboGrid(TextCombos.search(search))
        }
        .padding()
    }

    /// "Font combinations", each a tile drawn as it goes on a page, its name
    /// under it; or, when a search finds none, that said.
    @ViewBuilder
    private func comboGrid(_ combos: [TextCombos.Combo]) -> some View {
        if combos.isEmpty {
            Text(TextCombos.noneFound(search))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        } else {
            sectionHeader("Font combinations")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(combos) { combo in comboTile(combo) }
            }
        }
    }

    /// A tap puts the combination on this page, centred and selected, as
    /// one Undo (DesignStore.addTextCombo).
    private func comboTile(_ combo: TextCombos.Combo) -> some View {
        Button {
            store.addTextCombo(combo)
            dismiss()
        } label: {
            VStack(spacing: 4) {
                ComboThumb(combo: combo)
                Text(combo.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(combo.name) font combination")
        .accessibilityAddTraits(.isButton)
    }

    private func textInsert(_ label: String, size: Double, weight: Int) -> some View {
        Button {
            // Sized from this page, which may have a size of its own.
            var el = Element.text(label, fontSize: (store.pageWidth * size).rounded(),
                                  w: (store.pageWidth * 0.72).rounded())
            el.fontWeight = weight
            el.h = FontLibrary.layoutHeight(for: el)
            store.addText(el)
            dismiss()
        } label: {
            Text(label)
                .font(.system(size: 12 + size * 160, weight: weight >= 700 ? .bold : weight >= 600 ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }

    /// A text in a brand role, sized from this page, which may have a size
    /// of its own; its button drawn in the role's face.
    private func roleInsert(_ role: BrandFonts.Role, face: BrandFont?) -> some View {
        let size = 12 + role.widthFraction * 160
        let weight = face?.weight ?? role.defaultWeight
        return Button {
            store.addText(BrandFonts.element(role, face: face, pageWidth: store.pageWidth))
            dismiss()
        } label: {
            Text(role.addLabel)
                .font(FontLibrary.font(family: face?.family ?? "sans", size: size, weight: weight, italic: false))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
    }

    // MARK: uploads

    /// Which of your uploads shows: photos, videos or music.
    @State private var uploadKind = Uploads.Kind.image
    /// The upload whose deletion is being asked about, with what deleting
    /// it would mean.
    @State private var deletingUpload: UploadDeletion?

    private struct UploadDeletion {
        var id: String
        var kind: Uploads.Kind
        var use: DesignLibrary.UploadUse
    }

    /// Everything brought in — photos, videos and music — newest first,
    /// starred first, to use again or let go: the pile that used to be
    /// invisible. Replacing a picture, the photos only; a clip or a song
    /// cannot go in its frame.
    @ViewBuilder
    private var uploadsSection: some View {
        let kind = isReplacing ? Uploads.Kind.image : uploadKind
        let entries = Uploads.all()
        // A graphic cannot fill a photo's frame, so a replace leaves them out.
        let shown = favoritesFirst(entries.filter { $0.kind == kind }.map(\.id), kind: "upload", id: { $0 })
            .filter { !isReplacing || !MediaStore.isGraphic($0) }
        let offered = isReplacing ? !shown.isEmpty : !entries.isEmpty
        if offered {
            sectionHeader("Your uploads")
            if !isReplacing { uploadKindPicker }
            if shown.isEmpty {
                Text(Self.noUploadsNote(kind))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if kind == .audio {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element) { index, id in
                        musicRow(id, index: index, count: shown.count)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(Array(shown.enumerated()), id: \.element) { index, id in
                        if kind == .video {
                            videoTile(id, index: index, count: shown.count)
                        } else if MediaStore.isGraphic(id) {
                            graphicTile(id, index: index, count: shown.count)
                        } else {
                            uploadTile(id, index: index, count: shown.count)
                        }
                    }
                }
            }
        }
    }

    private var uploadKindPicker: some View {
        Picker("Uploads", selection: $uploadKind) {
            Text("Photos").tag(Uploads.Kind.image)
            Text("Videos").tag(Uploads.Kind.video)
            Text("Music").tag(Uploads.Kind.audio)
        }
        .pickerStyle(.segmented)
    }

    private static func noUploadsNote(_ kind: Uploads.Kind) -> String {
        switch kind {
        case .image: return "Photos you add show here."
        case .video: return "Videos you add show here."
        case .audio: return "Music and voice-overs you add show here."
        }
    }

    private func uploadTile(_ id: String, index: Int, count: Int) -> some View {
        let src = "media:\(id)"
        let starred = Favorites.isFavorite("upload", id)
        let inFrame = src == replaceSource
        return Button {
            pickLibraryPicture(src, natural: MediaStore.load(id)?.size ?? CGSize(width: 4, height: 3))
        } label: {
            Group {
                if let ui = MediaStore.load(id) {
                    Image(uiImage: PhotoLibrary.preview(ui, key: src))
                        .resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay { if inFrame { currentRing(cornerRadius: 10) } }
            .overlay(alignment: .topTrailing) { if starred { starBadge } }
        }
        .accessibilityLabel(AddSheetNames.picture(AddSheetNames.upload(index, of: count),
                                              starred: starred, inFrame: inFrame))
        .contextMenu {
            favoriteButton("upload", id)
            deleteUploadButton(id, kind: .image)
        }
    }

    /// An SVG brought in as a graphic, kept to place again: a tap puts the
    /// whole graphic on the page once more.
    private func graphicTile(_ id: String, index: Int, count: Int) -> some View {
        let starred = Favorites.isFavorite("upload", id)
        return Button {
            placeGraphic(id)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "square.on.circle").font(.title2)
                Text("SVG").font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) { if starred { starBadge } }
        }
        .accessibilityLabel(AddSheetNames.picture(AddSheetNames.uploadedGraphic(index, of: count),
                                                  starred: starred, inFrame: false))
        .contextMenu {
            favoriteButton("upload", id)
            deleteUploadButton(id, kind: .image)
        }
    }

    /// A clip brought in, shown by its first frame. A tap puts it on the
    /// page as a clip, as bringing it in did.
    private func videoTile(_ id: String, index: Int, count: Int) -> some View {
        let starred = Favorites.isFavorite("upload", id)
        return Button {
            insertClip(id)
        } label: {
            ClipPoster(id: id)
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .overlay(alignment: .topTrailing) { if starred { starBadge } }
        }
        .accessibilityLabel(AddSheetNames.picture(AddSheetNames.uploadedVideo(index, of: count),
                                                  starred: starred, inFrame: false))
        .contextMenu {
            favoriteButton("upload", id)
            deleteUploadButton(id, kind: .video)
        }
    }

    /// A clip from your uploads onto the page, half the page wide at its
    /// own shape, as importing it put it there.
    private func insertClip(_ id: String) {
        let store = self.store
        Task {
            let natural = await Task.detached(priority: .userInitiated) { VideoStore.poster(id)?.size }.value
            guard let natural else {
                store.buzz(.reject)
                store.announce("Couldn't open that", undoable: false)
                return
            }
            insertImage(VideoStore.src(id, at: nil), natural: natural)
            store.buzz(.confirm)
            dismiss()
        }
    }

    /// A song brought in, by its own name. A tap adds it as another of the
    /// design's audio tracks, from the film's start; one the design plays
    /// already is ticked.
    private func musicRow(_ id: String, index: Int, count: Int) -> some View {
        let starred = Favorites.isFavorite("upload", id)
        let playing = store.design.audioTracks.contains { $0.audioId == id }
        let name = AudioStore.label(for: id)
        return Button {
            addTrack(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentSubtle))
                Text(name)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if starred {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                }
                if playing {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AddSheetNames.music(name, index, of: count, starred: starred, playing: playing))
        .contextMenu {
            favoriteButton("upload", id)
            deleteUploadButton(id, kind: .audio)
        }
    }

    /// The song as a new audio track, as one Undo, said, and the sheet out
    /// of the way.
    private func addTrack(_ id: String) {
        store.addAudioTrack(id)
        store.buzz(.confirm)
        store.announce("Added \(AudioStore.label(for: id))")
        dismiss()
    }

    private func deleteUploadButton(_ id: String, kind: Uploads.Kind) -> some View {
        Button(role: .destructive) {
            askToDelete(id, kind: kind)
        } label: { Label("Delete upload", systemImage: "trash") }
    }

    /// Asked first, saying how many designs use it: found before the
    /// question is put, off the main thread, as every design is read for it.
    private func askToDelete(_ id: String, kind: Uploads.Kind) {
        let editing = store.statesInHistory
        Task {
            let use = await Task.detached(priority: .userInitiated) {
                DesignLibrary.use(ofUpload: id, kind: kind, editing: editing)
            }.value
            deletingUpload = UploadDeletion(id: id, kind: kind, use: use)
        }
    }

    /// Off the list, and unstarred. The file stays in the designs that show
    /// it, and the launch sweep takes it once nothing does, as on the
    /// Android twin: another window may hold it in a step Undo can go back
    /// to, or in a change not yet saved, which nothing here can see.
    private func deleteUpload(_ deletion: UploadDeletion) {
        Uploads.remove(deletion.id)
        // The sweep keeps whatever is starred, list or not.
        if Favorites.isFavorite("upload", deletion.id) { Favorites.toggle("upload", deletion.id) }
        favoritesVersion += 1
    }

    /// The picture in the frame being replaced, if Replace opened the sheet.
    private var replaceSource: String? {
        store.replaceTargetId.flatMap { store.element($0) }?.src
    }

    /// A tile from the library, uploads or logos: put on the page, or into
    /// the frame being replaced — where the picture already there changes
    /// nothing, so the sheet just closes.
    private func pickLibraryPicture(_ src: String, natural: CGSize) {
        if src == replaceSource {
            store.replaceTargetId = nil
            dismiss()
            return
        }
        place(src, natural: natural)
        dismiss()
    }

    /// The ring round the picture already in the frame being replaced.
    private func currentRing(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius).stroke(Theme.accent, lineWidth: 3)
    }

    /// A small star on a starred tile, so what was starred shows and not
    /// only leads the order.
    private var starBadge: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.yellow)
            .padding(4)
            .background(Circle().fill(Color.black.opacity(0.55)))
            .padding(4)
            .accessibilityHidden(true)
    }

    // MARK: svg

    @State private var importingSVG = false
    /// Whether the file picked comes in whole, as a graphic, or as its
    /// first path, as a custom shape.
    @State private var svgWhole = true

    /// A whole SVG as a recolourable graphic, and its first path alone as
    /// a custom shape. One file importer serves both.
    private var svgImportRow: some View {
        VStack(spacing: 8) {
            svgButton("Graphic from an SVG file", symbol: "square.on.circle", whole: true)
            svgButton("Custom shape from an SVG file", symbol: "scribble.variable", whole: false)
        }
        .fileImporter(isPresented: $importingSVG, allowedContentTypes: [.svg]) { result in
            guard case .success(let url) = result else { return }
            if svgWhole {
                importGraphic(from: url)
            } else {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                importFirstPath(from: url)
            }
        }
    }

    private func svgButton(_ title: String, symbol: String, whole: Bool) -> some View {
        Button {
            svgWhole = whole
            importingSVG = true
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
        }
    }

    private func importFirstPath(from url: URL) {
        guard let d = SVGPath.importFirstPath(fromFileAt: url) else {
            // Said, and out of the way, as the Android twin refuses it.
            refuseSVG()
            return
        }
        let size = min(store.pageWidth, store.pageHeight) * 0.4
        var el = Element.shape("rect", w: size.rounded(), h: size.rounded())
        el.pathData = d
        el.radius = 0
        store.add(el)
        store.buzz(.confirm)
        dismiss()
    }

    /// The whole file as a graphic, and the file kept among your uploads to
    /// place again. Read, parsed and kept off the main thread, so a large
    /// illustration does not hold the editor up.
    private func importGraphic(from url: URL) {
        let width = store.pageWidth, height = store.pageHeight
        Task {
            let read = await Task.detached(priority: .userInitiated) { () -> GraphicRead in
                // The picker's permission held while the file is read.
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return GraphicRead.of(url, keep: true, pageWidth: width, pageHeight: height)
            }.value
            finishGraphic(read)
        }
    }

    /// An SVG from your uploads placed again.
    private func placeGraphic(_ id: String) {
        let width = store.pageWidth, height = store.pageHeight
        let url = MediaStore.graphicURL(id)
        Task {
            let read = await Task.detached(priority: .userInitiated) {
                GraphicRead.of(url, keep: false, pageWidth: width, pageHeight: height)
            }.value
            finishGraphic(read)
        }
    }

    /// What reading an SVG came to: the graphic, or what to say instead.
    private enum GraphicRead {
        case graphic(SvgImport.Graphic)
        case refused(String)

        /// An SVG file read and made a graphic, and kept among the uploads
        /// when `keep` — or refused in the Android twin's words: one past
        /// 2 MB, one that cannot be read, and one with nothing to draw.
        static func of(_ url: URL, keep: Bool, pageWidth: Double, pageHeight: Double) -> GraphicRead {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard size <= SvgImport.maxBytes else { return .refused("That SVG is larger than 2 MB") }
            guard let data = try? Data(contentsOf: url) else { return .refused("Couldn't open that") }
            guard data.count <= SvgImport.maxBytes else { return .refused("That SVG is larger than 2 MB") }
            guard let text = String(data: data, encoding: .utf8),
                  let graphic = SvgImport.graphic(text, pageWidth: pageWidth, pageHeight: pageHeight) else {
                return .refused("No shape to take from that file")
            }
            if keep, let id = MediaStore.storeGraphic(data) { Uploads.record(id, kind: .image) }
            return .graphic(graphic)
        }
    }

    private func finishGraphic(_ read: GraphicRead) {
        switch read {
        case .graphic(let graphic):
            store.addGraphic(graphic)
            dismiss()
        case .refused(let note):
            refuseSVG(note)
        }
    }

    private func refuseSVG(_ note: String = "No shape to take from that file") {
        store.buzz(.reject)
        store.announce(note, undoable: false)
        dismiss()
    }

    // MARK: layouts

    /// Grid layouts: empty frames in one tap, filled by photos dragged onto
    /// them, picked while the grid is selected, or with Replace.
    private var layoutsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Photo grids")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhotoGrids.layouts) { layout in
                        Button {
                            // Laid out across this page, which may be a size
                            // of its own, not the document's.
                            let width = store.pageWidth, height = store.pageHeight
                            let margin = PhotoGrids.margin(forWidth: width)
                            let frames = PhotoGrids.elements(for: layout, width: width, height: height,
                                                             margin: margin, gutter: PhotoGrids.gutter(margin: margin))
                            store.applyToPage { $0.elements.append(contentsOf: frames) }
                            store.selection = Set(frames.map(\.id))
                            dismiss()
                        } label: {
                            VStack(spacing: 4) {
                                layoutThumb(layout)
                                Text(layout.name).font(.caption2)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(layout.name) photo grid")
                    }
                }
            }
        }
    }

    private func layoutThumb(_ layout: PhotoGrids.Layout) -> some View {
        Canvas { context, size in
            for cell in layout.cells {
                let r = CGRect(x: cell.minX * size.width + 1.5, y: cell.minY * size.height + 1.5,
                               width: cell.width * size.width - 3, height: cell.height * size.height - 3)
                context.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(Color(hex: "#9aa4b2")))
            }
        }
        .frame(width: 64, height: 48)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
    }

    // MARK: decorative frames

    /// Photo frames: a polaroid, a phone, a film strip… each a group of
    /// shapes round one empty frame, put in the middle of the page with all
    /// of it selected, so photos picked next go straight into its window.
    private var decorativeFramesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Photo frames")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DecorativeFrames.presets) { preset in
                        Button {
                            insertDecorativeFrame(preset)
                        } label: {
                            VStack(spacing: 4) {
                                decorativeFrameThumb(preset)
                                Text(preset.name).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(preset.name) photo frame")
                    }
                }
            }
        }
    }

    /// Laid out on this page, which may be a size of its own, as one step.
    private func insertDecorativeFrame(_ preset: FrameDef) {
        let made = DecorativeFrames.elements(preset, page: CGSize(width: store.pageWidth, height: store.pageHeight))
        guard !made.isEmpty else { return }
        store.applyToPage { $0.elements.append(contentsOf: made) }
        store.selection = Set(made.map(\.id))
        dismiss()
    }

    /// The frame drawn by the page renderer at its own size, scaled down.
    private func decorativeFrameThumb(_ preset: FrameDef) -> some View {
        var design = Design(title: preset.name, width: preset.width, height: preset.height)
        design.pages[0] = Page(background: .color("#eef0f3"),
                               elements: preset.parts.compactMap { DecorativeFrames.element($0, scale: 1) })
        let scale = min(56 / preset.width, 44 / preset.height)
        return PageRenderView(design: design, page: design.pages[0])
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: preset.width * scale, height: preset.height * scale)
            .frame(width: 64, height: 48)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: pdf

    /// One page becomes a picture on this page; several become pages of
    /// their own after it, each picture fitted to the page. It says what
    /// happened either way: locked, unreadable, or how many pages came in.
    private func importPDF(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }
        let target = store.replaceTargetId
        let store = self.store
        // Out of the way first, so what it says next is seen rather than
        // hidden behind the sheet.
        dismiss()
        guard let data else {
            store.buzz(.reject)
            store.announce("Couldn't open that PDF", undoable: false)
            return
        }
        store.announce("Opening the PDF…", undoable: false)
        // A replace has one slot, so one page is all that is drawn.
        let limit = target == nil ? PDFImporter.maxPages : 1
        Task {
            // Each page stored as it is rendered, so only one is in memory.
            let (stored, outcome) = await Task.detached(priority: .userInitiated) { () -> ([(src: String, natural: CGSize)], PDFImporter.Outcome) in
                var stored: [(src: String, natural: CGSize)] = []
                let outcome = PDFImporter.forEachPage(of: data, limit: limit) { image in
                    if let src = MediaStore.storeOpaque(image) { stored.append((src, image.size)) }
                }
                return (stored, outcome)
            }.value
            switch outcome {
            case .locked:
                store.buzz(.reject)
                store.announce("That PDF is locked with a password", undoable: false)
            case .unreadable:
                store.buzz(.reject)
                store.announce("Couldn't open that PDF", undoable: false)
            case .pages(_, let total):
                guard !stored.isEmpty else {
                    store.buzz(.reject)
                    store.announce("Couldn't open that PDF", undoable: false)
                    return
                }
                insertPictures(stored, replacing: target)
                store.buzz(.confirm)
                if target == nil, let said = PDFImporter.summary(brought: stored.count, total: total) {
                    store.announce(said)
                }
            }
        }
    }

    /// Pages from the document camera come in the same way a PDF's do.
    private func importScan(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        let target = store.replaceTargetId
        Task {
            let stored = await Task.detached(priority: .userInitiated) { () -> [(src: String, natural: CGSize)] in
                images.compactMap { image in MediaStore.storeOpaque(image).map { ($0, image.size) } }
            }.value
            insertPictures(stored, replacing: target)
        }
    }

    /// One picture goes on this page (or into the slot being replaced);
    /// several become pages of their own after it, each fitted to the page.
    private func insertPictures(_ stored: [(src: String, natural: CGSize)], replacing target: String?) {
        guard !stored.isEmpty else { return }
        if let target {
            insertImage(stored[0].src, natural: stored[0].natural, replacing: target)
        } else if stored.count == 1 {
            place(stored[0].src, natural: stored[0].natural)
        } else {
            let w = store.design.width, h = store.design.height
            let pages = stored.map { item -> Page in
                let scale = min(w / max(item.natural.width, 1), h / max(item.natural.height, 1))
                var el = Element.image(item.src, w: (item.natural.width * scale).rounded(),
                                       h: (item.natural.height * scale).rounded())
                el.x = ((w - el.w) / 2).rounded()
                el.y = ((h - el.h) / 2).rounded()
                return Page(elements: [el])
            }
            let at = store.pageIndex + 1
            store.apply { $0.pages.insert(contentsOf: pages, at: at) }
            store.setPage(at)
        }
        dismiss()
    }

    // MARK: photos

    private var photosGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            // One when replacing — a replace has one slot to fill — and a
            // clip may fill it, so a frame or a grid's cell can hold one.
            Group {
                // The camera first: a photo or a video straight in, or into
                // the frame being replaced.
                CameraTiles { outcome in bringInCaptured(outcome) }
                PhotosPicker(selection: $pickedItems,
                             maxSelectionCount: store.replaceTargetId == nil ? 10 : 1,
                             matching: .any(of: [.images, .videos])) {
                    Label(store.replaceTargetId == nil ? "Add photos or video" : "Choose a replacement",
                          systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
                }
                if DocumentScanner.isSupported {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan a document", systemImage: "doc.viewfinder")
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
                    }
                    .fullScreenCover(isPresented: $scanning) {
                        DocumentScanner { images in
                            scanning = false
                            importScan(images)
                        }
                        .ignoresSafeArea()
                    }
                }
            }
            let logos = BrandKit.load().logos
            if !logos.isEmpty {
                sectionHeader("Brand logos")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(Array(logos.enumerated()), id: \.element) { index, src in
                        logoTile(src, index: index, count: logos.count)
                    }
                }
            }
            uploadsSection
            if !isReplacing {
                layoutsRow
                decorativeFramesRow
            }
            Button {
                importingPDF = true
            } label: {
                Label(isReplacing ? "Replace with a PDF page" : "Import a PDF (each page becomes a page)",
                      systemImage: "doc.richtext")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
            }
            let photos = favoritesFirst(filteredPhotos, kind: "photo", id: \.id)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    artworkTile(photo, index: index, count: photos.count)
                }
            }
        }
        .padding()
        .confirmationDialog("Delete this upload?", isPresented: Binding(
            get: { deletingUpload != nil }, set: { if !$0 { deletingUpload = nil } }),
                            titleVisibility: .visible, presenting: deletingUpload) { deletion in
            Button("Delete", role: .destructive) { deleteUpload(deletion) }
            Button("Cancel", role: .cancel) {}
        } message: { deletion in
            if deletion.use.designs > 0 {
                Text(Uploads.usedInNote(deletion.use.designs))
            }
        }
    }

    private func logoTile(_ src: String, index: Int, count: Int) -> some View {
        let inFrame = src == replaceSource
        return Button {
            pickLibraryPicture(src, natural: PhotoLibrary.resolve(src)?.size ?? CGSize(width: 4, height: 3))
        } label: {
            Group {
                if let ui = PhotoLibrary.resolve(src) {
                    Image(uiImage: PhotoLibrary.preview(ui, key: src))
                        .resizable().aspectRatio(contentMode: .fit)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(height: 72)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
            .overlay { if inFrame { currentRing(cornerRadius: 10) } }
        }
        .accessibilityLabel(AddSheetNames.picture(AddSheetNames.logo(index, of: count), starred: false, inFrame: inFrame))
    }

    /// One of the built-in pictures, named with its kind and place, starred
    /// and ringed as the uploads are.
    private func artworkTile(_ photo: PhotoDef, index: Int, count: Int) -> some View {
        let src = "asset:\(photo.id)"
        let starred = Favorites.isFavorite("photo", photo.id)
        let inFrame = src == replaceSource
        return Button {
            pickLibraryPicture(src, natural: PhotoLibrary.size)
        } label: {
            photoThumb(photo.id)
                .overlay { if inFrame { currentRing(cornerRadius: 9) } }
                .overlay(alignment: .topTrailing) { if starred { starBadge } }
        }
        .accessibilityLabel(AddSheetNames.picture(
            AddSheetNames.artwork(photo, index, of: count),
            starred: starred, inFrame: inFrame))
        .contextMenu { favoriteButton("photo", photo.id) }
    }

    // MARK: favourites

    /// Starred items lead, in their own order, then the rest as they were.
    private func favoritesFirst<T>(_ items: [T], kind: String, id: (T) -> String) -> [T] {
        let starred = Set(Favorites.ids(of: kind))
        guard !starred.isEmpty else { return items }
        return items.filter { starred.contains(id($0)) } + items.filter { !starred.contains(id($0)) }
    }

    private func favoriteButton(_ kind: String, _ id: String) -> some View {
        let on = Favorites.isFavorite(kind, id)
        return Button {
            Favorites.toggle(kind, id)
            favoritesVersion += 1
        } label: {
            Label(on ? "Remove from favourites" : "Add to favourites", systemImage: on ? "star.slash" : "star")
        }
    }

    // MARK: data

    @State private var showingData = false

    private var dataRow: some View {
        Button {
            showingData = true
        } label: {
            Label("Chart or table from typed data", systemImage: "chart.bar.xaxis")
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
        }
        .sheet(isPresented: $showingData) {
            DataSheet(store: store)
                .onDisappear { if !store.selection.isEmpty { dismiss() } }
        }
    }

    // MARK: components

    /// Always headed, so the feature can be found before it is used; each
    /// with its piece count, and deleting one — from every design's Add
    /// sheet, with no Undo — asks first, as on the Android twin.
    @ViewBuilder
    private var componentsSection: some View {
        let components = Components.load()
        sectionHeader("Components")
        if components.isEmpty {
            Text("Select what you build again and again — a footer, a price tag — and choose More ▸ Save selection as component.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(components) { component in componentTile(component) }
            }
            .confirmationDialog(removingComponent.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
                                isPresented: Binding(get: { removingComponent != nil },
                                                     set: { if !$0 { removingComponent = nil } }),
                                titleVisibility: .visible,
                                presenting: removingComponent) { component in
                Button("Delete", role: .destructive) {
                    Components.remove(component.id)
                    removingComponent = nil
                    favoritesVersion += 1
                }
                Button("Cancel", role: .cancel) { removingComponent = nil }
            } message: { _ in
                Text("Copies already in designs stay as they are.")
            }
        }
    }

    private func componentTile(_ component: Component) -> some View {
        let count = component.elements.count
        let pieces = count == 1 ? "1 piece" : "\(count) pieces"
        return Button {
            store.insertComponent(component)
            dismiss()
        } label: {
            VStack(spacing: 2) {
                componentThumb(component)
                Text(component.name).font(.caption2).lineLimit(1)
                Text(pieces).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(component.name), \(pieces)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Delete") { removingComponent = component }
        .contextMenu {
            Button(role: .destructive) {
                removingComponent = component
            } label: { Label("Delete component…", systemImage: "trash") }
        }
    }

    private func componentThumb(_ component: Component) -> some View {
        var design = Design(title: component.name, width: max(component.width, 1), height: max(component.height, 1))
        design.pages[0] = Page(background: .color("#ffffff"), elements: component.elements)
        let scale = min(96 / design.width, 64 / design.height)
        return PageRenderView(design: design, page: design.pages[0])
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: design.width * scale, height: design.height * scale)
            .frame(width: 100, height: 68)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var filteredPhotos: [PhotoDef] {
        guard !search.isEmpty else { return PhotoLibrary.photos }
        return PhotoLibrary.photos.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.category.localizedCaseInsensitiveContains(search)
        }
    }

    /// One picture from the sheet — a tile, a PDF's page, a scan — into the
    /// frame being replaced, else into the first of the selection's empty
    /// frames, else onto the page.
    private func place(_ src: String, natural: CGSize) {
        if store.replaceTargetId == nil, let frame = store.framesToFill.first,
           store.replacePicture(frame, with: src) {
            store.buzz(.confirm)
            return
        }
        insertImage(src, natural: natural)
    }

    private func insertImage(_ src: String, natural: CGSize, replacing: String? = nil,
                             cascade: Int = 0) {
        // Replace mode swaps the source in place, keeping the frame, corner
        // radius and filter. The crop and the straighten are reset, so the
        // new picture comes in level, centred and covering the frame — as
        // the Android twin's Crop.replaced leaves it. Locked means kept as it
        // is, whichever way the new picture arrived.
        if let targetId = replacing ?? store.replaceTargetId {
            store.replaceTargetId = nil
            if store.element(targetId)?.type == .image {
                guard store.replacePicture(targetId, with: src) else { return }
                store.selection = [targetId]
                store.buzz(.confirm)
                return
            }
        }
        // Half this page's width — a page may have its own size.
        let w = store.pageWidth * 0.5
        let h = natural.width > 0 ? w * natural.height / natural.width : w * 0.75
        store.add(.image(src, w: w.rounded(), h: h.rounded()))
        if cascade > 0, let id = store.selection.first,
           let i = store.page.elements.firstIndex(where: { $0.id == id }) {
            // Part of the same add, so nudged in place rather than through
            // updateSelected, which would make the offset its own undo step.
            let step = Double(cascade) * store.pageWidth * 0.04
            store.design.pages[store.pageIndex].elements[i].x += step
            store.design.pages[store.pageIndex].elements[i].y += step
        }
    }

    // MARK: stickers

    private var stickersGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            animatedStickersRow
            ForEach(filteredStickerGroups) { group in
                if !group.emoji.isEmpty {
                    sectionHeader(group.name)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                        ForEach(group.emoji, id: \.self) { glyph in stickerTile(glyph) }
                    }
                }
            }
        }
        .padding()
    }

    /// An emoji, read by VoiceOver by its own name, starred as the other
    /// tiles are.
    private func stickerTile(_ glyph: String) -> some View {
        let starred = Favorites.isFavorite("sticker", glyph)
        return Button {
            store.add(.sticker(glyph, size: min(store.pageWidth, store.pageHeight) * 0.18))
            dismiss()
        } label: {
            Text(glyph).font(.system(size: 34))
                .frame(width: 52, height: 52)
                .overlay(alignment: .topTrailing) { if starred { starBadge.scaleEffect(0.8) } }
        }
        .accessibilityValue(starred ? "Favourite" : "")
        .contextMenu { favoriteButton("sticker", glyph) }
    }

    /// The stickers that keep moving, each shown moving as it will in
    /// Present — still with Reduce Motion — found by its glyph's words.
    @ViewBuilder
    private var animatedStickersRow: some View {
        let moving = Stickers.searchAnimated(search)
        if !moving.isEmpty {
            sectionHeader("Animated")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(moving) { sticker in
                        Button {
                            store.add(sticker.element(size: min(store.pageWidth, store.pageHeight) * 0.18))
                            dismiss()
                        } label: {
                            AnimatedStickerFace(sticker: sticker)
                                .frame(width: 52, height: 52)
                        }
                        .accessibilityLabel(sticker.name)
                    }
                }
            }
        }
    }

    /// A search finds a group by its name, whole, or the stickers in it by
    /// their own words (Stickers.search); a group with none drops out.
    private var filteredStickerGroups: [StickerGroup] {
        let starred = Favorites.ids(of: "sticker")
        let favourites = starred.isEmpty ? [] : [StickerGroup(name: "Favourites", emoji: starred)]
        guard !search.isEmpty else { return favourites + ContentLibrary.stickerGroups }
        return Stickers.search(search, in: ContentLibrary.stickerGroups)
    }

    /// The Background sheet's choices, the same here as there.
    private var backgroundNote: some View {
        BackgroundChoices(store: store)
            .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

/// An animated sticker's glyph going through its loop, as it will on the
/// page; standing still with Reduce Motion.
private struct AnimatedStickerFace: View {
    let sticker: AnimatedSticker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            face(.settled)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: ElementAnimation.loopPeriod)
                face(ElementAnimation(kind: sticker.loop).state(at: t, size: 52))
            }
        }
    }

    private func face(_ state: ElementAnimation.State) -> some View {
        Text(sticker.glyph)
            .font(.system(size: 30))
            .scaleEffect(state.scale)
            .rotationEffect(.degrees(state.rotation))
            .offset(state.offset)
    }
}

/// Small template preview rendered with the real page renderer.
struct TemplateThumb: View {
    let template: Template
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
                    .aspectRatio(template.width / template.height, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task {
            if image == nil {
                image = TemplateThumbCache.thumbnail(for: template)
            }
        }
    }
}

@MainActor
enum TemplateThumbCache {
    // NSCache rather than a Dictionary. These are rendered at 320pt wide,
    // which on a 3x device is a 960px bitmap — a few megabytes each, and one
    // per template in the gallery. A plain Dictionary never gives any of that
    // back: it has no eviction and does not react to a memory warning, so the
    // cost stayed for the life of the process however long ago the user
    // scrolled past. Every other image cache in the app (PhotoLibrary,
    // ImageFilters, MediaStore) already uses NSCache; this one was the
    // exception.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 24
        return c
    }()

    static func thumbnail(for template: Template) -> UIImage? {
        let key = template.id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let design = template.instantiate()
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: design.pages[0]))
        renderer.scale = 320 / max(design.width, 1)
        let image = renderer.uiImage
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// A font combination's tile: drawn by the page's own renderer as it goes on
/// a page, its words measured in the real faces, on white so dark type shows
/// in dark mode too, and kept (ComboThumbCache).
struct ComboThumb: View {
    let combo: TextCombos.Combo
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.white
                    .aspectRatio(ComboThumbCache.width / ComboThumbCache.height, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline, lineWidth: 1))
        .task {
            if image == nil {
                image = ComboThumbCache.thumbnail(for: combo)
            }
        }
    }
}

@MainActor
enum ComboThumbCache {
    /// A tile's size in page units, and how much of it, either way, a
    /// combination may take — the Android twin's ComboTiles.
    static let width: Double = 360
    static let height: Double = 240
    private static let fill = 0.86

    /// NSCache, as TemplateThumbCache, so a memory warning gives them back.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 32
        return c
    }()

    static func thumbnail(for combo: TextCombos.Combo) -> UIImage? {
        let key = combo.id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let scale = min(width * fill / combo.w, height * fill / max(combo.h, 1))
        let placed = TextCombos.placed(combo, scale: scale, pageWidth: width, pageHeight: height)
        var design = Design(title: combo.name, width: width, height: height)
        design.pages = [Page(elements: TextCombos.measured(placed))]
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: design.pages[0]))
        renderer.scale = 1.5
        renderer.isOpaque = true
        let image = renderer.uiImage
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// A clip's first frame for its tile, decoded off the main thread: a row of
/// clips each decoding there held the sheet up as it opened.
private struct ClipPoster: View {
    let id: String
    @State private var poster: UIImage?

    var body: some View {
        Group {
            if let poster {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemGray5)
            }
        }
        .task(id: id) {
            let id = self.id
            poster = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                VideoStore.poster(id).map { PhotoLibrary.preview($0, key: VideoStore.src(id, at: nil)) }
            }.value
        }
    }
}
