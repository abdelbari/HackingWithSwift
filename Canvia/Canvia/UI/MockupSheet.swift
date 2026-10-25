// Mockups: a page shown on a phone, a laptop, a framed print, a poster, a
// T-shirt, a mug — the scenes of MockupScenes, drawn in vectors. A page
// picker and a grid of scenes, each a live preview; the page is drawn by the
// page renderer (DesignExporter.render), cut to the window's shape
// (MockupGeometry.cover) and warped into its corners with
// CIPerspectiveTransform — round a mug, over the cylinder's mesh
// (MockupGeometry.mesh), a triangle at a time — all of it off the main
// thread but the page itself. A scene with a tint (a shirt, a mug) offers
// its colour. The result is saved to Photos, shared, added to the design as
// a picture (half the page wide, as any picture goes on), or made a design
// of its own, "<title> mockup". From the Export sheet's Share row and a
// design's card on Home, as on the Android twin.

import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct MockupSheet: View {
    let design: Design
    /// The editor's store, to add the mockup to the design; nil from Home.
    var store: DesignStore? = nil
    /// A design made of the mockup, to open: from Home. Nil in the editor,
    /// where it is saved beside this one, on Home.
    var onNewDesign: ((Design) -> Void)? = nil
    /// From Home: the design was saved with the mockup added to it, so its
    /// card is read again. Nil in the editor, which adds through `store`.
    var onChanged: (() -> Void)? = nil
    /// The page shown first: the page being edited, from the editor, as on
    /// the Android twin.
    var startPage = 0
    @Environment(\.dismiss) private var dismiss
    /// The page picked here; nil until one is, showing `startPage`.
    @State private var chosenPage: Int?
    @State private var sceneId = MockupScenes.all.first?.id ?? ""
    @State private var category: String?
    /// The colour each tinted scene was given, by scene id.
    @State private var tints: [String: String] = [:]
    /// The page as the previews draw it.
    @State private var page: CGImage?
    @State private var note: String?
    @State private var sharing: ShareURL?
    @State private var busy = false

    private var scene: MockupScenes.Scene? { MockupScenes.scene(sceneId) }

    private var pageIndex: Int {
        chosenPage ?? min(max(startPage, 0), max(design.pages.count - 1, 0))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    preview
                    if design.pages.count > 1 { pagePicker }
                    if let scene, scene.tint != nil { tintRow(scene) }
                    actions
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(.secondary)
                    }
                    categoryChips
                    sceneGrid
                }
                .padding()
            }
            .navigationTitle("Mockups")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task(id: pageIndex) { page = renderPage(longEdge: 520) }
        .sheet(item: $sharing) { item in ShareSheet(urls: [item.url]) }
    }

    // MARK: the parts

    @ViewBuilder
    private var preview: some View {
        if let scene {
            MockupTile(scene: scene, page: page, tint: tint(scene), width: 900)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel(tr("%@ mockup", scene.name))
        }
    }

    private var pagePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(design.pages.indices, id: \.self) { i in
                    chip(tr("Page %d", i + 1), selected: pageIndex == i) { chosenPage = i }
                }
            }
        }
    }

    private func tintRow(_ scene: MockupScenes.Scene) -> some View {
        ColorPicker(tr("Colour"), selection: Binding(
            get: { Color(hex: tint(scene) ?? "#ffffff") },
            set: { tints[scene.id] = UIColor($0).hexString }), supportsOpacity: false)
    }

    @ViewBuilder
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actionButtons }
            VStack(alignment: .leading, spacing: 8) { actionButtons }
        }
        .disabled(busy || scene == nil)
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Save to photos") { save() }
            .buttonStyle(.borderedProminent)
        Button("Share") { share() }
            .buttonStyle(.bordered)
        if store != nil || onChanged != nil {
            Button("Add to this design") { addToDesign() }
                .buttonStyle(.bordered)
        }
        Button("New design from mockup") { newDesign() }
            .buttonStyle(.bordered)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(tr("All"), selected: category == nil) { category = nil }
                ForEach(MockupScenes.categories, id: \.self) { name in
                    chip(tr(name, context: "mockup"), selected: category == name) { category = name }
                }
            }
        }
    }

    private var sceneGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
            ForEach(MockupScenes.inCategory(category)) { scene in
                Button { sceneId = scene.id } label: {
                    MockupTile(scene: scene, page: page, tint: tint(scene), width: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(scene.id == sceneId ? Theme.accent : Theme.hairline, lineWidth: scene.id == sceneId ? 3 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scene.name)
                .accessibilityAddTraits(scene.id == sceneId ? .isSelected : [])
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// The colour a tinted scene is drawn in: the one chosen, else its own.
    private func tint(_ scene: MockupScenes.Scene) -> String? {
        tints[scene.id] ?? scene.tint
    }

    // MARK: making it

    /// The page chosen, drawn by the page renderer, its longer side
    /// `longEdge` pixels.
    @MainActor
    private func renderPage(longEdge: Double) -> CGImage? {
        guard design.pages.indices.contains(pageIndex) else { return nil }
        let shown = design.pages[pageIndex]
        let size = design.size(for: shown)
        let scale = longEdge / max(Double(size.width), Double(size.height), 1)
        return DesignExporter.render(design: design, page: shown, scale: scale)
    }

    /// The mockup at the scene's own size, its page drawn sharp enough for
    /// it: the page on the main actor, where the page renderer works, the
    /// scene and the warp away from it.
    @MainActor
    private func finished() async -> UIImage? {
        guard let scene, let sharp = renderPage(longEdge: max(scene.width, scene.height)) else { return nil }
        return await MockupRenderer.drawn(scene: scene, page: sharp, tint: tint(scene), width: scene.width)
    }

    /// `use` with the finished mockup, the actions held still until it is
    /// done; said when it cannot be made.
    @MainActor
    private func finishing(_ use: @escaping @MainActor (UIImage) async -> Void) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            if let image = await finished() {
                await use(image)
            } else {
                failed()
            }
            busy = false
        }
    }

    /// The mockup as a PNG in the temporary folder, to save or share, named
    /// for the design as the Android twin names it.
    @MainActor
    private func file(_ image: UIImage) async -> URL? {
        let name = DesignExporter.fileBaseName(tr("%@ mockup", design.title))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).png")
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            guard let data = image.pngData() else { return nil }
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                return nil
            }
        }.value
    }

    @MainActor
    private func save() {
        finishing { image in
            guard let url = await file(image) else { return failed() }
            do {
                note = try await PhotoSaver.save([url]).message
            } catch {
                note = error.localizedDescription
            }
        }
    }

    @MainActor
    private func share() {
        finishing { image in
            guard let url = await file(image) else { return failed() }
            sharing = ShareURL(url: url)
        }
    }

    /// The mockup's size on a page `pageWidth` wide: half the page across,
    /// as tall as its own shape makes it, each rounded — the rule any
    /// picture goes on by (the Android twin's InsertSizes.picture), in the
    /// editor and from Home alike.
    nonisolated static func placed(_ image: CGSize, pageWidth: Double) -> (width: Double, height: Double) {
        let w = pageWidth * 0.5
        let h = image.width > 0 ? w * Double(image.height) / Double(image.width) : w * 0.75
        return (w.rounded(), h.rounded())
    }

    /// The mockup as a picture on the page on screen (`placed`), centred
    /// and selected — one step; onto the next unlocked page when this one
    /// is locked. From Home, onto the page chosen (`addFromHome`).
    @MainActor
    private func addToDesign() {
        finishing { image in
            guard let src = MediaStore.storeOpaque(image) else { return failed() }
            Uploads.record(source: src)
            guard let store else { return addFromHome(image, src: src) }
            // Onto the next unlocked page first, so the size is that page's.
            guard store.landsOnUnlockedPage() else { return }
            let size = Self.placed(image.size, pageWidth: store.pageWidth)
            // Marked with its scene, which a suggested description names.
            var picture = Element.image(src, w: size.width, h: size.height)
            picture.mockupId = sceneId
            if store.add(picture) {
                store.buzz(.confirm)
                dismiss()
            }
        }
    }

    /// From Home: the mockup on the page chosen — or, that page locked, the
    /// next one that is not (PageLocks.landing) — placed and centred as in
    /// the editor, and the design saved with its card's picture; as the
    /// Android twin's Home adds it. Every page from there on locked, it is
    /// said and nothing changes.
    @MainActor
    private func addFromHome(_ image: UIImage, src: String) {
        guard let target = PageLocks.landing(from: pageIndex, in: design.pages) else {
            note = tr("Every page from there on is locked")
            return
        }
        let page = design.size(for: design.pages[target])
        let size = Self.placed(image.size, pageWidth: Double(page.width))
        var picture = Element.image(src, w: size.width, h: size.height)
        picture.mockupId = sceneId
        picture.x = (Double(page.width) - size.width) / 2
        picture.y = (Double(page.height) - size.height) / 2
        var changed = design
        changed.pages[target].elements.append(picture)
        changed.updatedAt = Date().timeIntervalSince1970 * 1000
        guard DesignLibrary.save(changed) else { return failed() }
        DesignLibrary.writeThumbnail(for: changed)
        onChanged?()
        UIAccessibility.post(notification: .announcement, argument: tr("Added to the design"))
        dismiss()
    }

    /// A design of its own, the scene's size, the mockup filling its page:
    /// opened from Home, saved beside this one from the editor.
    @MainActor
    private func newDesign() {
        guard let scene else { return }
        finishing { image in
            guard let src = MediaStore.storeOpaque(image) else { return failed() }
            Uploads.record(source: src)
            var made = Design(title: tr("%@ mockup", design.title), width: scene.width, height: scene.height)
            made.pages[0].elements = [.image(src, w: scene.width, h: scene.height)]
            if let onNewDesign {
                dismiss()
                onNewDesign(made)
            } else if DesignLibrary.save(made) {
                note = tr("Saved as a new design on Home")
                store?.buzz(.confirm)
            } else {
                failed()
            }
        }
    }

    private func failed() {
        note = tr("Couldn't make the mockup")
        store?.buzz(.reject)
    }
}

/// A scene with the page in it, drawn `width` pixels across once the page
/// is there (MockupRenderer, off the main thread); its background until
/// then. Drawn again a breath after the last change, so a colour dragged
/// through the picker is drawn once it rests, not at every step.
struct MockupTile: View {
    let scene: MockupScenes.Scene
    let page: CGImage?
    let tint: String?
    let width: Double
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                scene.background.paint.fillView()
                    .aspectRatio(scene.width / max(scene.height, 1), contentMode: .fit)
            }
        }
        .task(id: key) {
            guard let page else { return }
            if image != nil {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
            }
            let drawn = await MockupRenderer.drawn(scene: scene, page: page, tint: tint, width: width)
            guard !Task.isCancelled else { return }
            image = drawn
        }
    }

    /// What the picture is drawn again for.
    private var key: String {
        "\(scene.id)|\(tint ?? "")|\(page.map { "\($0.width)x\($0.height)|\(ObjectIdentifier($0).hashValue)" } ?? "")"
    }
}

/// A scene drawn with a page in it: its background, its layers — tinted
/// ones in the tint — the page warped into its window and the window's
/// glare over it. Core Graphics, Core Image and an image renderer only, so
/// it draws on any thread; `drawn` draws away from the main one.
enum MockupRenderer {

    private static let context = CIContext()

    /// `image`, drawn off the main thread.
    static func drawn(scene: MockupScenes.Scene, page: CGImage, tint: String?, width: Double) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            MockupRenderer.image(scene: scene, page: page, tint: tint, width: width)
        }.value
    }

    static func image(scene: MockupScenes.Scene, page: CGImage, tint: String?, width: Double) -> UIImage? {
        guard scene.width > 0, scene.height > 0, width > 0 else { return nil }
        let scale = width / scene.width
        let size = CGSize(width: scene.width * scale, height: scene.height * scale)
        let warped = scene.screen.cylinder == nil ? perspective(page, scene: scene, scale: scale) : nil
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { drawing in
            let cg = drawing.cgContext
            cg.scaleBy(x: scale, y: scale)
            let bounds = CGRect(x: 0, y: 0, width: scene.width, height: scene.height)
            fill(CGPath(rect: bounds, transform: nil), with: scene.background.paint, in: cg)
            for layer in scene.layers { draw(layer, tint: tint, scale: scale, in: cg) }
            let window = windowPath(scene.screen.corners, radius: scene.screen.radius)
            cg.saveGState()
            if let cylinder = scene.screen.cylinder {
                wrap(page, scene: scene, cylinder: cylinder, in: cg)
            } else if let warped {
                cg.addPath(window)
                cg.clip()
                UIImage(cgImage: warped).draw(in: bounds)
            }
            cg.restoreGState()
            if let overlay = scene.overlay {
                cg.saveGState()
                cg.setAlpha(min(max(overlay.opacity, 0), 1))
                fill(window, with: overlay.fill.paint, in: cg)
                cg.restoreGState()
            }
        }
    }

    // MARK: the scene

    private static func draw(_ layer: MockupScenes.Layer, tint: String?, scale: Double, in cg: CGContext) {
        let path = SVGPath.path(layer.path)
        let paint = layer.tinted == true ? Paint.solid(tint ?? layer.fill.paint.primaryColor) : layer.fill.paint
        cg.saveGState()
        cg.setAlpha(min(max(layer.opacity ?? 1, 0), 1))
        if let blur = layer.blur, blur > 0 {
            // Soft: the shape with a shadow of its own colour round it.
            cg.setShadow(offset: .zero, blur: blur * scale, color: UIColor(hex: paint.primaryColor).cgColor)
        }
        fill(path, with: paint, in: cg)
        cg.restoreGState()
    }

    /// `path` filled with `paint`: a colour, or a gradient across its box
    /// at the paint's angle.
    private static func fill(_ path: CGPath, with paint: Paint, in cg: CGContext) {
        guard paint.kind == "gradient", let stops = paint.stops, !stops.isEmpty,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: stops.map { UIColor(hex: $0.color).cgColor } as CFArray,
                                        locations: stops.map { CGFloat($0.offset) }) else {
            cg.addPath(path)
            cg.setFillColor(UIColor(hex: paint.color ?? "#000000").cgColor)
            cg.fillPath()
            return
        }
        let box = path.boundingBoxOfPath
        let ends = paint.unitPoints
        let start = CGPoint(x: box.minX + ends.start.x * box.width, y: box.minY + ends.start.y * box.height)
        let end = CGPoint(x: box.minX + ends.end.x * box.width, y: box.minY + ends.end.y * box.height)
        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        cg.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        cg.restoreGState()
    }

    /// The window: its four corners, rounded by `radius`.
    private static func windowPath(_ corners: [CGPoint], radius: Double) -> CGPath {
        let path = CGMutablePath()
        guard corners.count == 4 else { return path }
        guard radius > 0 else {
            path.addLines(between: corners)
            path.closeSubpath()
            return path
        }
        path.move(to: CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2))
        for i in 0..<4 {
            path.addArc(tangent1End: corners[(i + 1) % 4], tangent2End: corners[(i + 2) % 4], radius: radius)
        }
        path.closeSubpath()
        return path
    }

    // MARK: the page

    /// The part of the page the window shows (MockupGeometry.cover), its
    /// corners pinned to the window's with CIPerspectiveTransform, on a
    /// scene-sized picture `scale` times the scene's pixels.
    private static func perspective(_ page: CGImage, scene: MockupScenes.Scene, scale: Double) -> CGImage? {
        let pageWidth = Double(page.width), pageHeight = Double(page.height)
        let crop = MockupGeometry.cover(width: pageWidth, height: pageHeight, aspect: scene.screen.aspect)
        // Core Image counts up from the bottom.
        let flipped = CGRect(x: crop.minX, y: pageHeight - crop.maxY, width: crop.width, height: crop.height)
        let input = CIImage(cgImage: page).cropped(to: flipped)
            .transformed(by: CGAffineTransform(translationX: -flipped.minX, y: -flipped.minY))
        let height = scene.height * scale
        let corners = scene.screen.corners.map { CGPoint(x: Double($0.x) * scale, y: height - Double($0.y) * scale) }
        guard corners.count == 4 else { return nil }
        let filter = CIFilter.perspectiveTransform()
        filter.inputImage = input
        filter.topLeft = corners[0]
        filter.topRight = corners[1]
        filter.bottomRight = corners[2]
        filter.bottomLeft = corners[3]
        let canvas = CGRect(x: 0, y: 0, width: scene.width * scale, height: height)
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output.cropped(to: canvas), from: canvas)
    }

    /// The page round a mug: the mesh's cells, each split in two triangles,
    /// each drawn with the turn and stretch that takes the page's matching
    /// triangle onto it.
    private static func wrap(_ page: CGImage, scene: MockupScenes.Scene, cylinder: MockupScenes.Cylinder,
                             in cg: CGContext) {
        let picture = UIImage(cgImage: page)
        let crop = MockupGeometry.cover(width: Double(page.width), height: Double(page.height), aspect: scene.screen.aspect)
        let columns = MockupGeometry.meshColumns, rows = MockupGeometry.meshRows
        let mesh = MockupGeometry.mesh(scene.screen.corners, cylinder: cylinder)
        guard mesh.count == (columns + 1) * (rows + 1) else { return }
        func source(_ c: Int, _ r: Int) -> CGPoint {
            CGPoint(x: crop.minX + crop.width * Double(c) / Double(columns),
                    y: crop.minY + crop.height * Double(r) / Double(rows))
        }
        for r in 0..<rows {
            for c in 0..<columns {
                let tl = r * (columns + 1) + c
                let corners = [mesh[tl], mesh[tl + 1], mesh[tl + columns + 2], mesh[tl + columns + 1]]
                let from = [source(c, r), source(c + 1, r), source(c + 1, r + 1), source(c, r + 1)]
                triangle([from[0], from[1], from[2]], [corners[0], corners[1], corners[2]], picture, in: cg)
                triangle([from[0], from[2], from[3]], [corners[0], corners[2], corners[3]], picture, in: cg)
            }
        }
    }

    /// The page's triangle `from` drawn onto the triangle `to`.
    private static func triangle(_ from: [CGPoint], _ to: [CGPoint], _ picture: UIImage, in cg: CGContext) {
        guard let map = affine(from, to) else { return }
        let clip = CGMutablePath()
        clip.addLines(between: to)
        clip.closeSubpath()
        cg.saveGState()
        cg.addPath(clip)
        cg.clip()
        cg.concatenate(map)
        picture.draw(at: .zero)
        cg.restoreGState()
    }

    /// The turn, stretch and move that takes three points onto three
    /// others; nil for a triangle with no area.
    private static func affine(_ s: [CGPoint], _ d: [CGPoint]) -> CGAffineTransform? {
        let sx1 = Double(s[1].x - s[0].x), sy1 = Double(s[1].y - s[0].y)
        let sx2 = Double(s[2].x - s[0].x), sy2 = Double(s[2].y - s[0].y)
        let dx1 = Double(d[1].x - d[0].x), dy1 = Double(d[1].y - d[0].y)
        let dx2 = Double(d[2].x - d[0].x), dy2 = Double(d[2].y - d[0].y)
        let det = sx1 * sy2 - sx2 * sy1
        guard abs(det) > 1e-9 else { return nil }
        let a = (dx1 * sy2 - dx2 * sy1) / det
        let c = (dx2 * sx1 - dx1 * sx2) / det
        let b = (dy1 * sy2 - dy2 * sy1) / det
        let e = (dy2 * sx1 - dy1 * sx2) / det
        let tx = Double(d[0].x) - a * Double(s[0].x) - c * Double(s[0].y)
        let ty = Double(d[0].y) - b * Double(s[0].x) - e * Double(s[0].y)
        return CGAffineTransform(a: a, b: b, c: c, d: e, tx: tx, ty: ty)
    }
}
