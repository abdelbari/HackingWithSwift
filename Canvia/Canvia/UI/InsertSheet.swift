// Insert sheet: templates, shapes, lines, text presets & pairings, photos,
// stickers, and photo-library uploads.

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
    /// The component whose deletion is being asked about.
    @State private var removingComponent: Component?
    /// The words typed for a code are more than a code holds.
    @State private var qrTooLong = false
    @FocusState private var qrFocused: Bool

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
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
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

    /// One picked item stored: a clip whole, shown by its poster frame, or
    /// a picture decoded, scaled and re-encoded — all off the main actor,
    /// where a full-resolution camera photo's decode belongs. Either is
    /// kept among your uploads, to use again.
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
            guard let prepared = ImageDownsampler.prepare(data),
                  let src = MediaStore.store(prepared) else { return nil }
            Uploads.record(source: src)
            return (src, prepared.natural, false)
        }.value
    }

    /// A search that finds nothing on this tab says so, rather than showing
    /// a blank scroll view that looks like a load that never finished.
    private var nothingMatches: Bool {
        guard !search.isEmpty else { return false }
        switch tab {
        // Nothing of any size: those of other sizes are a chip away, so
        // only a search nothing at all answers is said to be empty.
        case "Templates":
            return ContentLibrary.editorTemplates(width: store.pageWidth, height: store.pageHeight,
                                                  everySize: true, matching: search).isEmpty
        case "Elements":
            return !ContentLibrary.shapes.contains { ContentLibrary.shape($0, matches: search) }
        case "Photos": return filteredPhotos.isEmpty
        case "Stickers": return filteredStickerGroups.allSatisfy { $0.emoji.isEmpty }
        default: return false
        }
    }

    // MARK: templates

    /// Those made for this page's size lead; the rest, fitted to it, are a
    /// chip away. A tap starts the page over from the template, as one Undo.
    private var templatesGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
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

    // MARK: text

    private var textList: some View {
        VStack(alignment: .leading, spacing: 10) {
            textInsert("Add a heading", size: 0.08, weight: 700)
            textInsert("Add a subheading", size: 0.045, weight: 600)
            textInsert("Add body text", size: 0.028, weight: 400)
            textInsert("Page {page} of {pages}", size: 0.022, weight: 500)

            if !ContentLibrary.pairings.isEmpty {
                sectionHeader("Font pairings")
                ForEach(ContentLibrary.pairings) { pairing in
                    Button {
                        insertPairing(pairing)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pairing.name.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Text(pairing.heading.text)
                                .font(FontLibrary.font(
                                    family: pairing.heading.fontFamily, size: 19,
                                    weight: pairing.heading.fontWeight, italic: false))
                            Text(pairing.body.text)
                                .font(FontLibrary.font(
                                    family: pairing.body.fontFamily, size: 12,
                                    weight: pairing.body.fontWeight, italic: false))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                    }
                    .buttonStyle(.plain)
                }
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
            store.add(el)
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

    private func insertPairing(_ pairing: FontPairing) {
        // Placed on this page, which may have a size of its own: from the
        // design's size, a pairing ran off a narrower page.
        let scale = store.pageWidth / 1080
        let w = store.pageWidth * 0.72
        let x = store.pageWidth * 0.14
        let y0 = store.pageHeight * 0.38
        var heading = Element.text(pairing.heading.text,
                                   fontSize: pairing.heading.fontSize * scale, w: w)
        heading.fontFamily = pairing.heading.fontFamily
        heading.fontWeight = pairing.heading.fontWeight
        heading.letterSpacing = (pairing.heading.letterSpacing ?? 0) * scale
        heading.x = x; heading.y = y0
        heading.h = FontLibrary.layoutHeight(for: heading)

        var body = Element.text(pairing.body.text,
                                fontSize: pairing.body.fontSize * scale, w: w)
        body.fontFamily = pairing.body.fontFamily
        body.fontWeight = pairing.body.fontWeight
        body.letterSpacing = (pairing.body.letterSpacing ?? 0) * scale
        body.x = x; body.y = y0 + heading.h + 14 * scale
        body.h = FontLibrary.layoutHeight(for: body)

        store.applyToPage { page in
            page.elements.append(contentsOf: [heading, body])
        }
        store.selection = [heading.id, body.id]
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
        let shown = favoritesFirst(entries.filter { $0.kind == kind }.map(\.id), kind: "upload", id: { $0 })
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
        case .audio: return "Music you choose for a video shows here."
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

    /// A song brought in, by its own name. A tap makes it the design's
    /// soundtrack, as choosing it under Export does; the one playing now is
    /// ticked.
    private func musicRow(_ id: String, index: Int, count: Int) -> some View {
        let starred = Favorites.isFavorite("upload", id)
        let playing = store.design.motion?.soundtrack == id
        let name = AudioStore.label(for: id)
        return Button {
            chooseSoundtrack(id)
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

    /// The design's soundtrack, as one Undo, said, and the sheet out of the
    /// way.
    private func chooseSoundtrack(_ id: String) {
        var motion = store.design.motion ?? MotionSettings()
        motion.soundtrack = id
        store.apply { $0.motion = motion }
        store.buzz(.confirm)
        store.announce("Soundtrack: \(AudioStore.label(for: id))")
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

    private var svgImportRow: some View {
        Button {
            importingSVG = true
        } label: {
            Label("Custom shape from an SVG file", systemImage: "scribble.variable")
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
        }
        .fileImporter(isPresented: $importingSVG, allowedContentTypes: [.svg]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let d = SVGPath.importFirstPath(fromFileAt: url) else {
                // Said, and out of the way, as the Android twin refuses it.
                store.buzz(.reject)
                store.announce("No shape to take from that file", undoable: false)
                dismiss()
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
                            let margin = (width * 0.04).rounded()
                            let frames = PhotoGrids.elements(for: layout, width: width, height: height,
                                                             margin: margin, gutter: (margin / 2).rounded())
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
            if !isReplacing { layoutsRow }
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

    /// Sticker search matches on the group name — the glyphs themselves carry
    /// no searchable text — so a non-matching group drops out whole.
    private var filteredStickerGroups: [StickerGroup] {
        let starred = Favorites.ids(of: "sticker")
        let favourites = starred.isEmpty ? [] : [StickerGroup(name: "Favourites", emoji: starred)]
        guard !search.isEmpty else { return favourites + ContentLibrary.stickerGroups }
        return ContentLibrary.stickerGroups.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
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
