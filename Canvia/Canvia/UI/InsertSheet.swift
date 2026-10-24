// Insert sheet: templates, shapes, lines, icons, text presets & font
// combinations, photos, stickers, photo-library uploads, and — when the
// brand kit in use has any — its logos, photos, graphics, colours and text
// roles under Brand.
//
// The search above the tabs finds every kind of element at once — shapes,
// icons, graphics, stickers, frames, grids, lines, charts and tables,
// artwork — in sections (ElementSearch, ElementResults), on every tab but
// Templates, Text and Stickers, which search their own (Stickers the whole
// emoji catalogue, EmojiPicker). What was put on a page lately leads
// Elements as Recently used, and the emoji put on lately lead Stickers, as
// on the Android twin.

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

struct InsertSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// A sticker's tile, and the text styles' previews, growing with
    /// Larger Text.
    @ScaledMetric(relativeTo: .largeTitle) private var stickerSide: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var previewScale: Double = 1
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
    /// A built-in template of several pages, while its pages are shown.
    @State private var templateSet: Template?
    /// A template, while its preview is up.
    @State private var previewing: Template?
    /// The component whose deletion is being asked about.
    @State private var removingComponent: Component?
    /// The words typed for a code are more than a code holds.
    @State private var qrTooLong = false
    /// The code composer, open on a kind of QR code or a barcode.
    @State private var composing: CodeStart?
    @FocusState private var qrFocused: Bool
    /// Recently used, read as the sheet opens.
    @State private var recent: [ElementSearch.Hit] = []
    /// The emoji put on lately, read as the sheet opens.
    @State private var recentEmoji: [String] = []
    /// The brand kit in use, read as the sheet opens.
    @State private var brandKit = BrandKit()

    // Six in a segmented control, which gives each the same width: a
    // seventh cuts the longer names short on a small phone. Icons are a
    // section of Elements for that reason.
    private static let baseTabs = ["Templates", "Elements", "Text", "Photos", "Stickers", "Background"]

    /// The tabs, and Brand last — the rule both phones keep — when the kit
    /// in use has anything the tab lists (BrandKit.showsBrandTab); then all
    /// seven as a row of chips that scrolls, as the font sheet's categories
    /// are.
    private var tabs: [String] {
        Self.baseTabs + (brandKit.showsBrandTab ? ["Brand"] : [])
    }

    private var isReplacing: Bool { store.replaceTargetId != nil }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabBar

                ScrollView {
                    Color.clear.frame(height: 0).id(favoritesVersion)
                    if searchesElements {
                        ElementResults(query: search) { insertHit($0) }
                    } else if nothingMatches {
                        ContentUnavailableView.search(text: search)
                            .padding(.top, 40)
                    } else {
                        switch tab {
                        case "Templates": templatesGrid
                        case "Elements": elementsGrid
                        case "Text": textList
                        case "Photos": photosGrid
                        case "Stickers": stickersGrid
                        case "Brand": brandGrid
                        default: backgroundNote
                        }
                    }
                }
                // Here rather than on its row, which a search puts away.
                .sheet(isPresented: $showingData) {
                    DataSheet(store: store, start: dataStart)
                        .onDisappear { if !store.selection.isEmpty { dismiss() } }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: searchPrompt)
            .navigationTitle(isReplacing ? tr("Replace image") : tr("Add to design"))
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
            recent = ElementSearch.recent()
            recentEmoji = EmojiCatalogue.recent()
            brandKit = BrandKit.load()
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
            store.announce(tr("Bringing them in…"), undoable: false)
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
                store.announce(target != nil ? tr("Couldn't open that photo")
                               : items.count == 1 ? tr("Couldn't open that") : tr("Couldn't open those"),
                               undoable: false)
            } else if missed > 0 {
                store.buzz(.reject)
                store.announce(missed == 1 ? tr("One couldn't be opened")
                               : trn("%d couldn't be opened|%d couldn't be opened", missed),
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

    /// What the search field says: the tabs whose search is their own say
    /// what they find, the rest find every kind of element.
    private var searchPrompt: Text? {
        switch tab {
        case "Templates": return nil
        case "Text": return Text("Search font combinations")
        case "Stickers": return Text("Search emoji")
        default: return isReplacing ? nil : Text("Search elements")
        }
    }

    /// Whether the search shows every kind of element (ElementResults) in
    /// place of the tab: on any tab but Templates, Text and Stickers, which
    /// search their own, and not while a picture is being replaced, when
    /// Photos searches its pictures.
    private var searchesElements: Bool {
        !["Templates", "Text", "Stickers"].contains(tab) && !isReplacing && !ElementSearch.normalised(search).isEmpty
    }

    /// A thing found by the search, or in Recently used, put on the page as
    /// its own tab puts it; a chart or the table opens the data sheet on
    /// it, and the QR code its field, where what it is made from is typed.
    private func insertHit(_ hit: ElementSearch.Hit) {
        switch hit.kind {
        case .shape: addShape(hit.id)
        case .icon: if let icon = IconLibrary.icon(hit.id) { addIcon(icon) }
        case .graphic: if let graphic = GraphicsLibrary.graphic(hit.id) { addPackGraphic(graphic) }
        case .sticker: addSticker(hit.id)
        case .photoFrame: if let preset = DecorativeFrames.preset(hit.id) { insertDecorativeFrame(preset) }
        case .grid: if let layout = PhotoGrids.layout(hit.id) { addGrid(layout) }
        case .line: if let preset = ElementSearch.linePresets.first(where: { $0.name == hit.id }) { addLinePreset(preset) }
        case .stockArt:
            // Onto the next unlocked page when this one is locked, or not
            // at all — and remembered only when it goes on.
            guard store.landsOnUnlockedPage() else {
                dismiss()
                return
            }
            ElementSearch.remember(.stockArt, hit.id)
            pickLibraryPicture("asset:\(hit.id)", natural: PhotoLibrary.size)
        case .chart, .table:
            dataStart = hit.id
            search = ""
            showingData = true
        case .qr:
            search = ""
            tab = "Elements"
            // Once the tab is there to hold the field.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                qrFocused = true
            }
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
        case "Photos": return filteredPhotos.isEmpty
        case "Stickers":
            return EmojiCatalogue.search(search).isEmpty && Stickers.searchAnimated(search).isEmpty
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
                 ? tr("No template is called that, or is of that kind.")
                 : ContentLibrary.editorTemplatesNote(exactCount: exactTemplates.count, addsPage: store.templateAddsPage))
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
        .sheet(item: $templateSet) { template in
            TemplateSetSheet(template: template, note: TemplateSetSheet.editorNote(empty: DesignStore.isEmptyForTemplates(store.design)),
                             applyAll: { applyAll(template) }, usePage: { startOver(from: template, page: $0) },
                             addPage: { addAsPage(template, page: $0) })
        }
        // A template's own page first, as on Home: Customize starts this
        // page over from it — or, for every page of a set, applies them all.
        .sheet(item: $previewing, onDismiss: { favoritesVersion += 1 }) { template in
            TemplatePreviewSheet(template: template,
                                 note: TemplateSetSheet.editorNote(empty: DesignStore.isEmptyForTemplates(store.design))) {
                chosen, page in
                // One page: onto this page, or as a new page when this one has
                // something on it, as a tap did before the preview.
                if page == nil && chosen.pageCount > 1 { applyAll(chosen) } else { usePage(chosen, page ?? 0) }
            }
        }
    }

    private func templateTile(_ template: Template) -> some View {
        let starred = Favorites.isFavorite("template", template.id)
        return Button {
            // A tap looks at it first; a hold offers Use on this page and
            // Add as new page.
            previewing = template
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                TemplateThumb(template: template)
                    .overlay(alignment: .topTrailing) { if starred { starBadge } }
                Text(template.name).font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityLabel(templateLabel(template, starred: starred))
        .contextMenu {
            // Both, whatever a tap would do; a template of several gives
            // its first page, as on the Android twin.
            Button { startOver(from: template, page: 0) } label: {
                Label("Use on this page", systemImage: "arrow.triangle.2.circlepath")
            }
            Button { addAsPage(template, page: 0) } label: {
                Label("Add as new page", systemImage: "plus.rectangle.on.rectangle")
            }
            favoriteButton("template", template.id)
        }
    }

    /// Page `index` of a template, chosen in its preview: on a new page
    /// after this one when this page has something on it or is locked, else
    /// in place of this page (DesignStore.templateAddsPage).
    private func usePage(_ template: Template, _ index: Int) {
        if store.templateAddsPage { addAsPage(template, page: index) } else { startOver(from: template, page: index) }
    }

    /// "Add as new page": page `index` of the template, fitted to this
    /// page's size, on a new page after it — one Undo. A locked page does
    /// not stop it: nothing is overwritten.
    private func addAsPage(_ template: Template, page index: Int) {
        let page = template.makePage(at: index, width: store.pageWidth, height: store.pageHeight)
        store.addTemplatePage(page, name: template.name)
        dismiss()
    }

    /// "Northwind Pitch Deck, 10 pages, favourite".
    private func templateLabel(_ template: Template, starred: Bool) -> String {
        var label = template.name
        if template.pageCount > 1 { label += ", " + trn("%d page|%d pages", template.pageCount) }
        return starred ? tr("%@, favourite", label) : label
    }

    /// Every page of a set, fitted to this page: an empty design becomes
    /// them, any other gets them after this page — one Undo.
    private func applyAll(_ template: Template) {
        // A locked page takes nothing, after it or in its place.
        guard !store.refusesLockedPage() else { return }
        store.applyTemplateSet(template.makePages(width: store.pageWidth, height: store.pageHeight),
                               name: template.name)
        dismiss()
    }

    /// The page's background and every element give way to the template's
    /// (page `index` of it), fitted to this page's own size — which in a
    /// design of mixed sizes need not be the document's — as one step the
    /// toast can take back. A set of several pages shows them first.
    private func startOver(from template: Template, page index: Int? = nil) {
        // A locked page keeps what is on it.
        guard !store.refusesLockedPage() else { return }
        guard template.pageCount == 1 || index != nil else {
            templateSet = template
            return
        }
        let page = template.makePage(at: index ?? 0, width: store.pageWidth, height: store.pageHeight)
        store.applyToPage { current in
            current.background = page.background
            current.elements = page.elements
        }
        store.selection.removeAll()
        store.buzz(.confirm)
        store.announce(tr("Started over from \u{201C}%@\u{201D}", template.name))
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

    /// The six papers a sticky note comes in (StickyNotes), square, each
    /// named for VoiceOver by its colour.
    private var stickyRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
            ForEach(StickyNotes.colours, id: \.self) { paper in
                Button {
                    store.addStickyNote(paper)
                    dismiss()
                } label: {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hex: paper))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(StickyNotes.spoken(paper))
            }
        }
    }

    private var elementsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                // On a whiteboard, its own insert first: a sticky note in
                // one of six papers, in the middle of what is on screen.
                if search.isEmpty && store.isWhiteboard {
                    sectionHeader(tr("Sticky note"))
                    stickyRow
                }
                // What was put on a page lately, of every kind, first.
                if !recent.isEmpty {
                    sectionHeader(tr("Recently used"))
                    HitRow(hits: recent) { insertHit($0) }
                }
            }
            sectionHeader(tr("QR code"))
            qrRow
            sectionHeader(tr("Lines"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                ForEach(ElementSearch.linePresets, id: \.name) { preset in lineTile(preset) }
            }
            Group {
                dataRow
                svgImportRow
                componentsSection
            }
            GraphicsSection { addPackGraphic($0) }
            let starred = search.isEmpty ? Favorites.ids(of: "shape").compactMap { ContentLibrary.shapeMap[$0] } : []
            ForEach(["Favourites"] + ContentLibrary.shapeCategories, id: \.self) { category in
                let shapes = category == "Favourites" ? starred : ContentLibrary.shapes.filter {
                    $0.category == category && ContentLibrary.shape($0, matches: search)
                }
                if !shapes.isEmpty {
                    sectionHeader(category == "Favourites" ? tr("Favourites") : ContentLibrary.shapeGroupName(category))
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
            addShape(shape.id)
        } label: {
            LibraryShape(definition: shape, cornerRadius: 0)
                .fill(Color(hex: "#545d6b"))
                .padding(8)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .overlay(alignment: .topTrailing) { if starred { starBadge } }
        }
        .accessibilityLabel(starred ? tr("%@, favourite", shape.name) : shape.name)
        .contextMenu { favoriteButton("shape", shape.id) }
    }

    /// From this page's size — a page may have its own.
    private func addShape(_ id: String) {
        let size = min(store.pageWidth, store.pageHeight) * 0.28
        if store.add(.shape(id, w: size, h: size)) { ElementSearch.remember(.shape, id) }
        dismiss()
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
            codeKinds
        }
        .sheet(item: $composing) { start in
            CodeComposerSheet(store: store, barcode: start.kind == nil, kind: start.kind ?? .link)
        }
    }

    /// What the composer opens on: a QR code's form of a kind, or a
    /// barcode (no kind).
    struct CodeStart: Identifiable {
        var kind: QRForms.ContentType?
        var id: String { kind?.rawValue ?? "barcode" }
    }

    /// A QR code of another kind — Wi-Fi, a contact, an email, a text, a
    /// phone number — or a barcode, from the composer.
    private var codeKinds: some View {
        Menu {
            ForEach(QRForms.ContentType.allCases) { kind in
                Button(kind.name) { composing = CodeStart(kind: kind) }
            }
            Button("Barcode") { composing = CodeStart(kind: nil) }
        } label: {
            Label("More", systemImage: "barcode")
                .font(.subheadline)
        }
        .padding(.leading, 54)
    }

    static var qrTooLongMessage: String { tr("That is too long for a QR code.") }

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
        if store.add(.image(CodeGenerator.source(for: payload), w: size.rounded(), h: size.rounded())) {
            ElementSearch.remember(.qr, "qr")
        }
        qrPayload = ""
        dismiss()
    }

    /// A line with its ends, named under the tile as the Android twin's
    /// line presets are, so it can be told apart by eye and by VoiceOver.
    private func lineTile(_ preset: ElementSearch.LinePreset) -> some View {
        // Its name is also what Recently used keeps; shown in the app's
        // language.
        let name = tr(preset.name)
        return Button {
            addLinePreset(preset)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: preset.symbol)
                    .font(.title3)
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

    /// 30% of the page wide, with the preset's ends.
    private func addLinePreset(_ preset: ElementSearch.LinePreset) {
        var el = Element.line(w: store.pageWidth * 0.3)
        el.startCap = preset.start ?? "none"
        el.endCap = preset.end ?? "none"
        if store.add(el) { ElementSearch.remember(.line, preset.name) }
        dismiss()
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
            IconGroup(category: tr("Icons \u{00B7} %@", $0.category), icons: $0.icons)
        }
        let starred = Favorites.ids(of: "icon").compactMap { IconLibrary.icon($0) }
        if search.trimmingCharacters(in: .whitespaces).isEmpty && !starred.isEmpty {
            groups.insert(IconGroup(category: tr("Favourite icons"), icons: starred), at: 0)
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
        .accessibilityLabel(starred ? tr("%@, favourite", icon.name) : icon.name)
        .contextMenu { favoriteButton("icon", icon.id) }
    }

    /// One of the illustrated graphics, as an SVG graphic goes on: its
    /// shapes in their own colours, one group at 0.4 of the page's shorter
    /// side, centred and selected — one Undo, as on the Android twin.
    private func addPackGraphic(_ graphic: GraphicDef) {
        if store.addPackGraphic(graphic) { ElementSearch.remember(.graphic, graphic.id) }
        dismiss()
    }

    /// In the middle of this page — a page may have a size of its own — in
    /// the brand kit's first colour, or ink that reads on the page, and
    /// selected: one Undo, as on the Android twin.
    private func addIcon(_ icon: IconDef) {
        let fill = IconLibrary.fill(for: store.page, brandColours: BrandKit.load().colors)
        let el = IconLibrary.element(icon, pageWidth: store.pageWidth, pageHeight: store.pageHeight, fill: fill)
        if store.add(el) { ElementSearch.remember(.icon, icon.id) }
        dismiss()
    }

    // MARK: text

    /// The role inserts and a page number, then the font combinations: chips
    /// for their categories, this phone's Recently used, From your brand
    /// when the kit sets a title, heading or body face, and the grid, two to
    /// a row, the six pairings first. A search keeps the combinations whose
    /// name, a tag or category has it, and only them — as on the Android
    /// twin.
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
            ComboChoices(search: search, fonts: fonts) { combo in
                store.addTextCombo(combo)
                RecentCombos.record(combo.id)
                dismiss()
            }
        }
        .padding()
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
                .font(.system(size: (12 + size * 160) * previewScale, weight: Self.previewWeight(weight)))
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
            sectionHeader(tr("Your uploads"))
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
        case .image: return tr("Photos you add show here.")
        case .video: return tr("Videos you add show here.")
        case .audio: return tr("Music and voice-overs you add show here.")
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
                store.announce(tr("Couldn't open that"), undoable: false)
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
        store.announce(tr("Added %@", AudioStore.label(for: id)))
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
    private var starBadge: some View { Self.favouriteStar }

    /// The star itself, for the tiles of other views of the sheet's.
    static var favouriteStar: some View {
        Image(systemName: "star.fill")
            .font(.caption2.weight(.bold))
            .imageScale(.small)
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
            svgButton(tr("Graphic from an SVG file"), symbol: "square.on.circle", whole: true)
            svgButton(tr("Custom shape from an SVG file"), symbol: "scribble.variable", whole: false)
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
            guard size <= SvgImport.maxBytes else { return .refused(tr("That SVG is larger than 2 MB")) }
            guard let data = try? Data(contentsOf: url) else { return .refused(tr("Couldn't open that")) }
            guard data.count <= SvgImport.maxBytes else { return .refused(tr("That SVG is larger than 2 MB")) }
            guard let text = String(data: data, encoding: .utf8),
                  let graphic = SvgImport.graphic(text, pageWidth: pageWidth, pageHeight: pageHeight) else {
                return .refused(tr("No shape to take from that file"))
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

    private func refuseSVG(_ note: String = tr("No shape to take from that file")) {
        store.buzz(.reject)
        store.announce(note, undoable: false)
        dismiss()
    }

    // MARK: layouts

    /// Grid layouts: empty frames in one tap, filled by photos dragged onto
    /// them, picked while the grid is selected, or with Replace.
    private var layoutsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(tr("Photo grids"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhotoGrids.layouts) { layout in
                        Button {
                            addGrid(layout)
                        } label: {
                            VStack(spacing: 4) {
                                Self.layoutThumb(layout)
                                Text(tr(layout.name)).font(.caption2)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tr(layout.name)) photo grid")
                    }
                }
            }
        }
    }

    /// Laid out across this page, which may be a size of its own, not the
    /// document's.
    private func addGrid(_ layout: PhotoGrids.Layout) {
        // Onto the next unlocked page when this one is locked, or not at all.
        guard store.landsOnUnlockedPage() else { return }
        // Laid out across this page, which may be a size of its own, not
        // the document's.
        let width = store.pageWidth, height = store.pageHeight
        let margin = PhotoGrids.margin(forWidth: width)
        let frames = PhotoGrids.elements(for: layout, width: width, height: height,
                                         margin: margin, gutter: PhotoGrids.gutter(margin: margin))
        store.applyToPage { $0.elements.append(contentsOf: frames) }
        store.selection = Set(frames.map(\.id))
        ElementSearch.remember(.grid, layout.id)
        dismiss()
    }

    static func layoutThumb(_ layout: PhotoGrids.Layout) -> some View {
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
            sectionHeader(tr("Photo frames"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(DecorativeFrames.presets) { preset in
                        Button {
                            insertDecorativeFrame(preset)
                        } label: {
                            VStack(spacing: 4) {
                                Self.decorativeFrameThumb(preset)
                                Text(tr(preset.name)).font(.caption2).lineLimit(1)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(tr(preset.name)) photo frame")
                    }
                }
            }
        }
    }

    /// Letters & numbers: A to Z and 0 to 9, each an empty photo frame in
    /// the glyph's shape (GlyphFrames), put in the middle of the page and
    /// selected, so a photo picked next goes straight into it.
    private var glyphFramesRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(tr("Letters & numbers"))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(GlyphFrames.all) { frame in
                        Button {
                            insertGlyphFrame(frame)
                        } label: {
                            LibraryShape(definition: frame.shape, cornerRadius: 0)
                                .fill(Theme.inkSecondary)
                                .frame(width: 44 * frame.width / 100, height: 44)
                                .frame(width: 56, height: 56)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemGray6)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(GlyphFrames.label(frame))
                    }
                }
            }
        }
    }

    /// On this page, which may be a size of its own, as one step — on the
    /// next unlocked page when this one is locked (DesignStore.add).
    private func insertGlyphFrame(_ frame: GlyphFrames.Frame) {
        let made = GlyphFrames.element(frame, page: CGSize(width: store.pageWidth, height: store.pageHeight))
        guard store.add(made, centered: false) else { return }
        store.selection = [made.id]
        dismiss()
    }

    /// Laid out on this page, which may be a size of its own, as one step.
    private func insertDecorativeFrame(_ preset: FrameDef) {
        guard store.landsOnUnlockedPage() else { return }
        let made = DecorativeFrames.elements(preset, page: CGSize(width: store.pageWidth, height: store.pageHeight))
        guard !made.isEmpty else { return }
        store.applyToPage { $0.elements.append(contentsOf: made) }
        store.selection = Set(made.map(\.id))
        ElementSearch.remember(.photoFrame, preset.id)
        dismiss()
    }

    /// The frame drawn by the page renderer at its own size, scaled down.
    static func decorativeFrameThumb(_ preset: FrameDef) -> some View {
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
            store.announce(tr("Couldn't open that PDF"), undoable: false)
            return
        }
        store.announce(tr("Opening the PDF…"), undoable: false)
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
                store.announce(tr("That PDF is locked with a password"), undoable: false)
            case .unreadable:
                store.buzz(.reject)
                store.announce(tr("Couldn't open that PDF"), undoable: false)
            case .pages(_, let total):
                guard !stored.isEmpty else {
                    store.buzz(.reject)
                    store.announce(tr("Couldn't open that PDF"), undoable: false)
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
                    Label(store.replaceTargetId == nil ? tr("Add photos or video") : tr("Choose a replacement"),
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
                sectionHeader(tr("Brand logos"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(Array(logos.enumerated()), id: \.element) { index, src in
                        logoTile(src, label: AddSheetNames.logo(index, of: logos.count))
                    }
                }
            }
            uploadsSection
            if !isReplacing {
                layoutsRow
                decorativeFramesRow
                glyphFramesRow
            }
            Button {
                importingPDF = true
            } label: {
                Label(isReplacing ? tr("Replace with a PDF page") : tr("Import a PDF (each page becomes a page)"),
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

    /// A brand logo, photo or picture graphic, drawn whole, named `label`.
    private func logoTile(_ src: String, label: String) -> some View {
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
        .accessibilityLabel(AddSheetNames.picture(label, starred: false, inFrame: inFrame))
    }

    /// One of the built-in pictures, named with its kind and place, starred
    /// and ringed as the uploads are.
    private func artworkTile(_ photo: PhotoDef, index: Int, count: Int) -> some View {
        let src = "asset:\(photo.id)"
        let starred = Favorites.isFavorite("photo", photo.id)
        let inFrame = src == replaceSource
        return Button {
            if !isReplacing {
                // Onto the next unlocked page when this one is locked, or
                // not at all — and remembered only when it goes on.
                guard store.landsOnUnlockedPage() else {
                    dismiss()
                    return
                }
                ElementSearch.remember(.stockArt, photo.id)
            }
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

    // MARK: brand

    /// The tab picker: segmented for six, chips for seven.
    @ViewBuilder
    private var tabBar: some View {
        if tabs.count > Self.baseTabs.count {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs, id: \.self) { name in tabChip(name) }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .padding(.top, 4)
        } else {
            Picker("Section", selection: $tab) {
                ForEach(tabs, id: \.self) { Text(tr($0)) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private func tabChip(_ name: String) -> some View {
        let selected = tab == name
        return Button { tab = name } label: {
            Text(tr(name))
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The kit in use, in the order the Android twin lists it: its logos,
    /// photos and graphics to place, its colours to paint with, and a text
    /// in each role it sets a face for.
    private var brandGrid: some View {
        let kit = brandKit
        let roles = BrandFonts.Role.allCases.filter { kit.fonts[$0] != nil }
        return VStack(alignment: .leading, spacing: 10) {
            brandPictures(tr("Logos"), kit.logos) { AddSheetNames.logo($0, of: $1) }
            brandPictures(tr("Photos"), kit.photos) { AddSheetNames.brandPhoto($0, of: $1) }
            brandPictures(tr("Graphics"), kit.graphics) { AddSheetNames.brandGraphic($0, of: $1) }
            if !kit.colors.isEmpty {
                sectionHeader(tr("Colours"))
                ForEach(Array(kit.palettes.filter { !$0.colors.isEmpty }.enumerated()), id: \.offset) { _, palette in
                    brandPalette(palette)
                }
            }
            if !roles.isEmpty {
                sectionHeader(tr("Text"))
                ForEach(roles) { role in
                    roleInsert(role, face: kit.fonts[role])
                }
            }
        }
        .padding()
    }

    /// One of the kit's lists of pictures under its heading, when it has
    /// any: a picture placed as a logo is, an SVG graphic as a graphic.
    @ViewBuilder
    private func brandPictures(_ title: String, _ sources: [String],
                               label: @escaping (Int, Int) -> String) -> some View {
        if !sources.isEmpty {
            sectionHeader(title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(Array(sources.enumerated()), id: \.element) { index, src in
                    if let id = BrandKit.svgID(src) {
                        brandGraphicTile(id, label: label(index, sources.count))
                    } else {
                        logoTile(src, label: label(index, sources.count))
                    }
                }
            }
        }
    }

    /// An SVG graphic of the kit's: a tap places the whole graphic.
    private func brandGraphicTile(_ id: String, label: String) -> some View {
        Button {
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
        }
        .accessibilityLabel(label)
    }

    /// A palette's swatches under its name.
    private func brandPalette(_ palette: BrandPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(palette.name)
                .font(.footnote)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 10)], spacing: 10) {
                ForEach(palette.colors, id: \.self) { hex in
                    brandSwatch(hex)
                }
            }
        }
    }

    /// A tap paints what is selected in the colour, as a colour picker
    /// does; with nothing selected, the page's background
    /// (DesignStore.paintBrandColour).
    private func brandSwatch(_ hex: String) -> some View {
        Button {
            store.paintBrandColour(hex)
            dismiss()
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(hex: hex))
                .frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AddSheetNames.brandColour(hex, selection: !store.selection.isEmpty))
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
            Label(on ? tr("Remove from favourites") : tr("Add to favourites"), systemImage: on ? "star.slash" : "star")
        }
    }

    // MARK: data

    @State private var showingData = false
    /// What the data sheet opens on when the search found it: a chart's
    /// kind, or "table".
    @State private var dataStart: String?

    private var dataRow: some View {
        Button {
            dataStart = nil
            showingData = true
        } label: {
            Label("Chart or table from typed data", systemImage: "chart.bar.xaxis")
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
        }
    }

    // MARK: components

    /// Always headed, so the feature can be found before it is used; each
    /// with its piece count, and deleting one — from every design's Add
    /// sheet, with no Undo — asks first, as on the Android twin.
    @ViewBuilder
    private var componentsSection: some View {
        let components = Components.load()
        sectionHeader(tr("Components"))
        if components.isEmpty {
            Text("Select what you build again and again — a footer, a price tag — and choose More ▸ Save selection as component.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(components) { component in componentTile(component) }
            }
            .confirmationDialog(removingComponent.map { tr("Delete \u{201C}%@\u{201D}?", $0.name) } ?? "",
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
        let pieces = trn("%d piece|%d pieces", count)
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

    /// What was put on lately, the stickers that move, those starred, then
    /// the whole emoji catalogue a group at a time (EmojiPicker) — or what
    /// a search finds among them.
    private var stickersGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            if search.isEmpty && !recentEmoji.isEmpty {
                sectionHeader(tr("Recently used"))
                glyphRow(recentEmoji)
            }
            animatedStickersRow
            let starred = Favorites.ids(of: "sticker")
            if search.isEmpty && !starred.isEmpty {
                sectionHeader(tr("Favourites"))
                glyphRow(starred)
            }
            EmojiPicker(query: search, side: stickerSide, favouritesVersion: $favoritesVersion) { addSticker($0) }
        }
        .padding()
    }

    /// Glyphs to scroll across: Recently used, and those starred.
    private func glyphRow(_ glyphs: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(glyphs, id: \.self) { glyph in stickerTile(glyph) }
            }
        }
    }

    /// An emoji, read by VoiceOver by its own name. Stars are kept by the
    /// plain glyph in the picker below, as on Android, so these rows offer
    /// none: Recently used holds toned glyphs.
    private func stickerTile(_ glyph: String) -> some View {
        Button {
            addSticker(glyph)
        } label: {
            Text(glyph).font(.largeTitle)
                .frame(width: stickerSide, height: stickerSide)
        }
        .accessibilityLabel(EmojiCatalogue.of(glyph)?.name ?? glyph)
    }

    /// A text style's weight in its preview.
    private static func previewWeight(_ weight: Int) -> Font.Weight {
        weight >= 700 ? .bold : weight >= 600 ? .semibold : .regular
    }

    private func addSticker(_ glyph: String) {
        if store.add(.sticker(glyph, size: min(store.pageWidth, store.pageHeight) * 0.18)) {
            ElementSearch.remember(.sticker, glyph)
            EmojiCatalogue.remember(glyph)
        }
        dismiss()
    }

    /// The stickers that keep moving, each shown moving as it will in
    /// Present — still with Reduce Motion — found by its glyph's words.
    @ViewBuilder
    private var animatedStickersRow: some View {
        let moving = Stickers.searchAnimated(search)
        if !moving.isEmpty {
            sectionHeader(tr("Animated"))
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

    /// The Background sheet's choices, the same here as there.
    private var backgroundNote: some View {
        BackgroundChoices(store: store)
            .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Self.header(title)
    }

    /// A section's heading, as every list in the sheet heads one.
    static func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

/// An animated sticker's glyph going through its loop, as it will on the
/// page; standing still with Reduce Motion.
private struct AnimatedStickerFace: View {
    let sticker: AnimatedSticker
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var glyphSize: CGFloat = 30

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
            .font(.system(size: glyphSize))
            .scaleEffect(state.scale)
            .rotationEffect(.degrees(state.rotation))
            .offset(state.offset)
    }
}

/// Small template preview rendered with the real page renderer, with its
/// page count when it has several pages (unless `badge` is off).
struct TemplateThumb: View {
    let template: Template
    var badge = true
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
        .overlay(alignment: .bottomTrailing) { PageCountBadge(count: badge ? template.pageCount : 1) }
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
        // By its faces too: one in the brand's (TextCombos.branded) is drawn
        // again when the kit's faces change.
        let faces = combo.elements.map { "\($0.fontFamily ?? "")/\($0.fontWeight ?? 0)" }.joined(separator: ",")
        let key = "\(combo.id)#\(faces)" as NSString
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
