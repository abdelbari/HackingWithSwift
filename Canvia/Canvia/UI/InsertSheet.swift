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
    @State private var qrPayload = ""
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
            // Capture the replace target now: loading is async, and the sheet
            // (and with it store.replaceTargetId) may be gone by the time it
            // finishes — the pick should still replace, not insert a stray.
            let target = store.replaceTargetId
            Task {
                // Several at once land as a cascade, each a step down and
                // right from the last, so ten photos are ten visible photos
                // and not one photo ten deep.
                var placed = 0
                for item in items {
                    guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
                    // Decoding, scaling, re-encoding and the file write all
                    // happen off the main actor, where a full-resolution
                    // camera photo's decode belongs.
                    let stored = await Task.detached(priority: .userInitiated) {
                        () -> (src: String, natural: CGSize)? in
                        guard let prepared = ImageDownsampler.prepare(data),
                              let src = MediaStore.store(prepared) else { return nil }
                        return (src, prepared.natural)
                    }.value
                    guard let stored else { continue }
                    insertImage(stored.src, natural: stored.natural,
                                replacing: placed == 0 ? target : nil,
                                cascade: placed)
                    placed += 1
                }
                if placed > 0 { dismiss() }
            }
        }
    }

    /// A search that finds nothing on this tab says so, rather than showing
    /// a blank scroll view that looks like a load that never finished.
    private var nothingMatches: Bool {
        guard !search.isEmpty else { return false }
        switch tab {
        case "Templates": return filteredTemplates.isEmpty
        case "Elements":
            return !ContentLibrary.shapes.contains { $0.name.localizedCaseInsensitiveContains(search) }
        case "Photos": return filteredPhotos.isEmpty
        case "Stickers": return filteredStickerGroups.allSatisfy { $0.emoji.isEmpty }
        default: return false
        }
    }

    // MARK: templates

    private var templatesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
            ForEach(filteredTemplates) { template in
                Button {
                    let page = template.makePage(for: store.design)
                    store.applyToPage { current in
                        current.background = page.background
                        current.elements = page.elements
                    }
                    store.selection.removeAll()
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        TemplateThumb(template: template)
                        Text(template.name).font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding()
    }

    private var filteredTemplates: [Template] {
        guard !search.isEmpty else { return ContentLibrary.templates }
        return ContentLibrary.templates.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.category.localizedCaseInsensitiveContains(search)
        }
    }

    // MARK: shapes + lines

    private var elementsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("QR code")
            qrRow
            sectionHeader("Lines")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                lineTile("line.diagonal", nil, nil)
                lineTile("arrow.right", nil, "arrow")
                lineTile("arrow.left.and.right", "arrow", "arrow")
                lineTile("ellipsis", "dot", "dot")
            }
            ForEach(ContentLibrary.shapeCategories, id: \.self) { category in
                let shapes = ContentLibrary.shapes.filter {
                    $0.category == category &&
                    (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
                }
                if !shapes.isEmpty {
                    sectionHeader(category)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 10)], spacing: 10) {
                        ForEach(shapes) { shape in
                            Button {
                                let size = min(store.design.width, store.design.height) * 0.28
                                store.add(.shape(shape.id, w: size, h: size))
                                dismiss()
                            } label: {
                                LibraryShape(definition: shape, cornerRadius: 0)
                                    .fill(Color(hex: "#545d6b"))
                                    .padding(8)
                                    .frame(width: 64, height: 64)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    /// A code is generated from its payload every time it is drawn, so the
    /// element's source is the payload itself and there is nothing to store.
    private var qrRow: some View {
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

            Button("Add", action: addQRCode)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(trimmedQRPayload.isEmpty)
        }
    }

    private var trimmedQRPayload: String {
        qrPayload.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addQRCode() {
        let payload = trimmedQRPayload
        guard !payload.isEmpty else { return }
        qrFocused = false
        // Square, because a QR code that is not square has been stretched and
        // no longer scans.
        let size = min(store.design.width, store.design.height) * 0.3
        store.add(.image(CodeGenerator.source(for: payload), w: size.rounded(), h: size.rounded()))
        qrPayload = ""
        dismiss()
    }

    private func lineTile(_ icon: String, _ start: String?, _ end: String?) -> some View {
        Button {
            var el = Element.line(w: store.design.width * 0.3)
            el.startCap = start ?? "none"
            el.endCap = end ?? "none"
            store.add(el)
            dismiss()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
        }
    }

    // MARK: text

    private var textList: some View {
        VStack(alignment: .leading, spacing: 10) {
            textInsert("Add a heading", size: 0.08, weight: 700)
            textInsert("Add a subheading", size: 0.045, weight: 600)
            textInsert("Add body text", size: 0.028, weight: 400)

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
            var el = Element.text(label, fontSize: (store.design.width * size).rounded(),
                                  w: (store.design.width * 0.72).rounded())
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
        let scale = store.design.width / 1080
        let w = store.design.width * 0.72
        let x = store.design.width * 0.14
        let y0 = store.design.height * 0.38
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

    // MARK: layouts

    /// Grid layouts: empty frames in one tap, filled with Replace.
    private var layoutsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Photo grids")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(PhotoGrids.layouts) { layout in
                        Button {
                            let margin = (store.design.width * 0.04).rounded()
                            let frames = PhotoGrids.elements(for: layout, width: store.design.width,
                                                             height: store.design.height,
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
    /// their own after it, each picture fitted to the page.
    private func importPDF(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if scoped { url.stopAccessingSecurityScopedResource() }
        guard let data else { return }
        let target = store.replaceTargetId
        Task {
            let stored = await Task.detached(priority: .userInitiated) { () -> [(src: String, natural: CGSize)] in
                PDFImporter.pages(of: data).compactMap { image in
                    MediaStore.storeOpaque(image).map { ($0, image.size) }
                }
            }.value
            guard !stored.isEmpty else { return }
            if stored.count == 1 || target != nil {
                insertImage(stored[0].src, natural: stored[0].natural, replacing: target)
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
    }

    // MARK: photos

    private var photosGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            // One when replacing — a replace has one slot to fill.
            PhotosPicker(selection: $pickedItems,
                         maxSelectionCount: store.replaceTargetId == nil ? 10 : 1,
                         matching: .images) {
                Label(store.replaceTargetId == nil ? "Add from Photo Library" : "Choose a replacement",
                      systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
            }
            let logos = BrandKit.load().logos
            if !logos.isEmpty {
                sectionHeader("Brand logos")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(logos, id: \.self) { src in
                        Button {
                            let natural = PhotoLibrary.resolve(src)?.size ?? CGSize(width: 4, height: 3)
                            insertImage(src, natural: natural)
                            dismiss()
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
                        }
                        .accessibilityLabel("Brand logo")
                    }
                }
            }
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(filteredPhotos) { photo in
                    Button {
                        insertImage("asset:\(photo.id)", natural: PhotoLibrary.size)
                        dismiss()
                    } label: {
                        photoThumb(photo.id)
                    }
                }
            }
        }
        .padding()
    }

    private var filteredPhotos: [PhotoDef] {
        guard !search.isEmpty else { return PhotoLibrary.photos }
        return PhotoLibrary.photos.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.category.localizedCaseInsensitiveContains(search)
        }
    }

    private func insertImage(_ src: String, natural: CGSize, replacing: String? = nil,
                             cascade: Int = 0) {
        // Replace mode swaps the source in place, keeping the frame, corner
        // radius and filter — only the crop is reset for the new picture.
        if let targetId = replacing ?? store.replaceTargetId {
            store.replaceTargetId = nil
            if store.page.elements.contains(where: { $0.id == targetId && $0.type == .image }) {
                store.applyToPage { page in
                    if let i = page.elements.firstIndex(where: { $0.id == targetId }) {
                        page.elements[i].src = src
                        page.elements[i].cropScale = 1
                        page.elements[i].cropX = 0.5
                        page.elements[i].cropY = 0.5
                    }
                }
                store.selection = [targetId]
                return
            }
        }
        let w = store.design.width * 0.5
        let h = natural.width > 0 ? w * natural.height / natural.width : w * 0.75
        store.add(.image(src, w: w.rounded(), h: h.rounded()))
        if cascade > 0, let id = store.selection.first,
           let i = store.page.elements.firstIndex(where: { $0.id == id }) {
            // Part of the same add, so nudged in place rather than through
            // updateSelected, which would make the offset its own undo step.
            let step = Double(cascade) * store.design.width * 0.04
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
                        ForEach(group.emoji, id: \.self) { glyph in
                            Button {
                                store.add(.sticker(glyph, size: min(store.design.width, store.design.height) * 0.18))
                                dismiss()
                            } label: {
                                Text(glyph).font(.system(size: 34))
                                    .frame(width: 52, height: 52)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    /// Sticker search matches on the group name — the glyphs themselves carry
    /// no searchable text — so a non-matching group drops out whole.
    private var filteredStickerGroups: [StickerGroup] {
        guard !search.isEmpty else { return ContentLibrary.stickerGroups }
        return ContentLibrary.stickerGroups.filter {
            $0.name.localizedCaseInsensitiveContains(search)
        }
    }

    private var backgroundNote: some View {
        BackgroundInline(store: store)
            .padding()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.top, 8)
    }
}

/// Inline background section for the insert sheet's last tab.
private struct BackgroundInline: View {
    @Bindable var store: DesignStore
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BACKGROUND COLOR").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ContentLibrary.defaultSwatches, id: \.self) { hex in
                    Button { store.applyToPage { $0.background = .color(hex) } } label: {
                        RoundedRectangle(cornerRadius: 9).fill(Color(hex: hex))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.black.opacity(0.12)))
                            .frame(height: 40)
                    }
                }
            }
            Text("GRADIENTS").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ContentLibrary.gradients) { preset in
                    Button { store.applyToPage { $0.background = .gradient(preset.paint) } } label: {
                        let pts = preset.paint.unitPoints
                        RoundedRectangle(cornerRadius: 9)
                            .fill(LinearGradient(
                                stops: preset.stops.map { .init(color: Color(hex: $0.color), location: $0.offset) },
                                startPoint: pts.start, endPoint: pts.end))
                            .frame(height: 40)
                    }
                }
            }
            Text("PHOTOS").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 10)], spacing: 10) {
                ForEach(PhotoLibrary.photos) { photo in
                    Button { store.applyToPage { $0.background = .image("asset:\(photo.id)") } } label: {
                        photoThumb(photo.id)
                    }
                }
            }
        }
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
