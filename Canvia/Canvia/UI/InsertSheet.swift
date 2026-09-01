// Insert sheet: templates, shapes, lines, text presets & pairings, photos,
// stickers, and photo-library uploads.

import SwiftUI
import PhotosUI

struct InsertSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var tab = "Templates"
    @State private var search = ""
    @State private var pickedItem: PhotosPickerItem?

    private let tabs = ["Templates", "Elements", "Text", "Photos", "Stickers", "Background"]

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
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Add to design")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .onChange(of: pickedItem) {
            guard let item = pickedItem else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let src = MediaStore.store(image) {
                    await MainActor.run {
                        insertImage(src, natural: image.size)
                        dismiss()
                    }
                }
            }
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
                                .font(Font(FontLibrary.uiFont(
                                    family: pairing.heading.fontFamily, size: 19,
                                    weight: pairing.heading.fontWeight, italic: false)))
                            Text(pairing.body.text)
                                .font(Font(FontLibrary.uiFont(
                                    family: pairing.body.fontFamily, size: 12,
                                    weight: pairing.body.fontWeight, italic: false)))
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
            el.h = FontLibrary.measuredHeight(for: el)
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
        heading.h = FontLibrary.measuredHeight(for: heading)

        var body = Element.text(pairing.body.text,
                                fontSize: pairing.body.fontSize * scale, w: w)
        body.fontFamily = pairing.body.fontFamily
        body.fontWeight = pairing.body.fontWeight
        body.letterSpacing = (pairing.body.letterSpacing ?? 0) * scale
        body.x = x; body.y = y0 + heading.h + 14 * scale
        body.h = FontLibrary.measuredHeight(for: body)

        store.applyToPage { page in
            page.elements.append(contentsOf: [heading, body])
        }
        store.selection = [heading.id, body.id]
    }

    // MARK: photos

    private var photosGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label("Add from Photo Library", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(hex: "#f1e8ff")))
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

    private func insertImage(_ src: String, natural: CGSize) {
        let w = store.design.width * 0.5
        let h = natural.width > 0 ? w * natural.height / natural.width : w * 0.75
        store.add(.image(src, w: w.rounded(), h: h.rounded()))
    }

    // MARK: stickers

    private var stickersGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ContentLibrary.stickerGroups) { group in
                let emoji = group.emoji.filter {
                    search.isEmpty || group.name.localizedCaseInsensitiveContains(search)
                }
                if !emoji.isEmpty {
                    sectionHeader(group.name)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                        ForEach(emoji, id: \.self) { glyph in
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
    private static var cache: [String: UIImage] = [:]

    static func thumbnail(for template: Template) -> UIImage? {
        if let cached = cache[template.id] { return cached }
        let design = template.instantiate()
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: design.pages[0]))
        renderer.scale = 320 / max(design.width, 1)
        let image = renderer.uiImage
        if let image { cache[template.id] = image }
        return image
    }
}
