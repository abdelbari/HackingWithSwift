// Turning a design into a file.
//
// Split out of ExportSheet for two reasons. It is testable here — a View's
// private methods are not — and the export path is where a design tool most
// easily runs out of memory, so it deserves to be somewhere it can be read
// on its own.
//
// Two things changed when it moved:
//
// 1. Nothing accumulates in memory any more. The PDF path used to build the
//    whole document as one Data and write it afterwards, so a ten-page poster
//    held every rendered page at once; the raster path did the same with
//    pngData(). Both now stream straight to the destination URL, so peak
//    footprint is one page, whatever the document's length.
//
// 2. PDF pages are drawn as vectors rather than as page-sized bitmaps.
//    ImageRenderer.render hands the SwiftUI drawing to a CGContext directly,
//    so shapes and text land in the PDF as shapes and text: sharp at any zoom,
//    a fraction of the file size, and no page bitmap to allocate at all.

import CoreGraphics
import ImageIO
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Only the two rendering entry points need the main actor: ImageRenderer
// walks a SwiftUI view. The size arithmetic and the file naming are pure, and
// isolating them would force every caller — the sheet's footer, most of all —
// onto an await for no reason.
enum DesignExporter {

    enum RasterFormat {
        case png, jpeg

        var ext: String { self == .png ? "png" : "jpg" }
        var contentType: UTType { self == .png ? .png : .jpeg }
    }

    enum ExportError: LocalizedError {
        case renderFailed, encodeFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed: return tr("could not render the page")
            case .encodeFailed: return tr("could not encode the image")
            }
        }
    }

    // MARK: how big is too big

    /// The most pixels we will ever rasterise in one go.
    ///
    /// A bitmap costs 4 bytes a pixel, so this is a 128 MB allocation — about
    /// the largest a phone will hand out reliably while also holding the
    /// document, the editor and the encoder. The custom-size sheet allows
    /// 4000x4000, which is 16 megapixels, and 3x of that is 144 megapixels:
    /// 576 MB, and a jetsam kill on anything but the largest device. Asking
    /// for more now quietly gets less rather than getting nothing.
    static let pixelBudget: Double = 32_000_000

    /// The scale a request actually renders at, after the budget — for a
    /// page of `size`. Every page is budgeted at its own size: a 4000 × 4000
    /// page in a 1080 design, budgeted at 1080, came out at 144 megapixels.
    static func effectiveScale(size: CGSize, requested: Double) -> Double {
        let area = max(Double(size.width) * Double(size.height), 1)
        let ceiling = (pixelBudget / area).squareRoot()
        return min(max(requested, 0.01), ceiling)
    }

    /// The same for the design's own size.
    static func effectiveScale(design: Design, requested: Double) -> Double {
        effectiveScale(size: design.size, requested: requested)
    }

    static func effectiveScale(design: Design, requested: Int) -> Double {
        effectiveScale(design: design, requested: Double(requested))
    }

    /// The exported image's size in pixels, which is what the user is really
    /// choosing when they pick a scale.
    static func outputSize(size: CGSize, requested: Double) -> CGSize {
        let scale = effectiveScale(size: size, requested: requested)
        return CGSize(width: max(1, (Double(size.width) * scale).rounded()),
                      height: max(1, (Double(size.height) * scale).rounded()))
    }

    static func outputSize(design: Design, requested: Double) -> CGSize {
        outputSize(size: design.size, requested: requested)
    }

    static func outputSize(design: Design, requested: Int) -> CGSize {
        outputSize(design: design, requested: Double(requested))
    }

    /// True when the budget, not the user, decided the scale.
    static func isClamped(size: CGSize, requested: Double) -> Bool {
        effectiveScale(size: size, requested: requested) < requested - 0.001
    }

    static func isClamped(design: Design, requested: Double) -> Bool {
        isClamped(size: design.size, requested: requested)
    }

    static func isClamped(design: Design, requested: Int) -> Bool {
        isClamped(design: design, requested: Double(requested))
    }

    /// The scale that puts a page's longer side at `pixels`. Platforms
    /// specify sizes, not multipliers — "1080 wide", "4K" — so this is what
    /// the size field and the presets resolve through; worked out for each
    /// page at its own size, so every page of an export comes out that long.
    static func scale(forLongEdge pixels: Double, size: CGSize) -> Double {
        let edge = max(Double(size.width), Double(size.height), 1)
        return max(0.05, pixels / edge)
    }

    static func scale(forLongEdge pixels: Double, design: Design) -> Double {
        scale(forLongEdge: pixels, size: design.size)
    }

    /// The longer side, in pixels, at the requested scale after the budget.
    static func longEdge(size: CGSize, requested: Double) -> Double {
        let out = outputSize(size: size, requested: requested)
        return max(Double(out.width), Double(out.height))
    }

    static func longEdge(design: Design, requested: Double) -> Double {
        longEdge(size: design.size, requested: requested)
    }

    /// A named output size. Long edge only: the short edge follows the
    /// design's own ratio, which is what "export at 1080" means to anyone
    /// who says it.
    struct SizePreset: Identifiable {
        var name: String
        var longEdge: Double
        var id: String { name }
    }

    static let sizePresets: [SizePreset] = [
        SizePreset(name: tr("Instagram post (1080)"), longEdge: 1080),
        SizePreset(name: tr("Story / Reel (1920)"), longEdge: 1920),
        SizePreset(name: tr("Full HD (1920)"), longEdge: 1920),
        SizePreset(name: "4K (3840)", longEdge: 3840),
        SizePreset(name: tr("A4 at 300 dpi (3508)"), longEdge: 3508),
        SizePreset(name: tr("US Letter at 300 dpi (3300)"), longEdge: 3300),
    ]

    // MARK: resolution guard

    /// Below this on the long edge an export looks soft on any phone screen.
    static let softBelowLongEdge = 1080.0

    /// The image elements that will be upscaled at this export size: fewer
    /// source pixels than the pixels their frame covers in the output. A
    /// photo dragged out to fill a poster and exported at 3x is the classic
    /// case, and the output is blurry in a way nothing on screen showed.
    ///
    /// `pixelSize` resolves an element's source to its stored pixel size; a
    /// nil means unknown and is not flagged.
    static func upscaledImages(page: Page, scale: Double,
                               pixelSize: (String) -> CGSize?) -> [String] {
        page.elements.compactMap { el in
            guard el.type == .image, !el.isHidden, let src = el.src, let source = pixelSize(src),
                  source.width > 0, source.height > 0 else { return nil }
            // A cropped-in photo shows fewer of its pixels over the same
            // frame, so it needs proportionally more of them.
            let zoom = max(el.cropScale ?? 1, 1)
            let needed = max(el.w, el.h) * scale * zoom
            let has = max(source.width, source.height)
            return needed > has * 1.05 ? el.id : nil
        }
    }

    // MARK: selection

    /// A one-page design holding only `ids`, sized to their box, so "export
    /// the selection" is an ordinary page export of a smaller page. The
    /// page's background comes along: a cut-out over a colour should keep
    /// its colour unless the export is asked to be transparent.
    static func selectionDesign(design: Design, page: Page, ids: Set<String>) -> Design? {
        // A hidden element is never exported, chosen or not.
        let chosen = page.elements.filter { ids.contains($0.id) && !$0.isHidden }
        guard !chosen.isEmpty else { return nil }
        let box = Geometry.union(chosen.map(Geometry.aabb)).integral
        guard box.width > 0, box.height > 0 else { return nil }
        var cropped = Design(title: design.title, width: box.width, height: box.height)
        cropped.id = design.id
        // At the design's dpi, so the selection prints at its true size too.
        cropped.unit = design.unit
        cropped.dpi = design.dpi
        var only = page
        // The box is the page's size now. A page with a size of its own
        // would otherwise keep it, and render and print at that size with
        // the selection in its top corner.
        only.width = nil
        only.height = nil
        only.elements = chosen.map { el in
            var moved = el
            moved.x -= box.minX
            moved.y -= box.minY
            return moved
        }
        cropped.pages = [only]
        return cropped
    }

    // MARK: raster

    /// Rough bytes a JPEG of this design will come to at a given quality.
    ///
    /// A guess, and labelled as one — but the shape of it is right, and the
    /// alternative (encoding the whole page on every slider tick) is worse
    /// than a guess by a wide margin. Calibrated against photographic content
    /// at 4:2:0 chroma: about 0.55 bits per pixel at quality 0.5, scaling with
    /// roughly the square of quality.
    static func estimatedJPEGBytes(design: Design, requested: Double, quality: Double) -> Int {
        estimatedJPEGBytes(size: design.size, requested: requested, quality: quality)
    }

    static func estimatedJPEGBytes(size pageSize: CGSize, requested: Double, quality: Double) -> Int {
        let size = outputSize(size: pageSize, requested: requested)
        return jpegBytes(pixels: Double(size.width) * Double(size.height), quality: quality)
    }

    /// Rough bytes of a JPEG of `pixels` pixels at `quality`, by the
    /// calibration above.
    static func jpegBytes(pixels: Double, quality: Double) -> Int {
        let bitsPerPixel = 0.15 + 2.6 * pow(max(0, min(1, quality)), 2)
        return max(2_048, Int(pixels * bitsPerPixel / 8))
    }

    /// The page as pixels. Everything raster goes through here: files, the
    /// clipboard, and any test that wants to look at the output.
    ///
    /// With a `bleed`, in page units, the picture is of the page and that
    /// much round it (PageRenderView) — only the print-ready PDF flattened
    /// asks for one.
    @MainActor
    static func render(design: Design, page: Page, scale: Double,
                       transparent: Bool = false, bleed: Double = 0) -> CGImage? {
        // A transparent export drops the page's own background rather than
        // just turning off compositing: "no background" has to mean the
        // background is gone, not that an opaque white one is drawn
        // without an alpha channel.
        var rendered = page
        if transparent { rendered.background = .color("#00000000") }
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: rendered, bleed: bleed))
        let size = design.size(for: page)
        let reach = max(bleed, 0)
        let drawn = CGSize(width: Double(size.width) + 2 * reach, height: Double(size.height) + 2 * reach)
        renderer.scale = CGFloat(effectiveScale(size: drawn, requested: scale))
        // Opaque unless asked otherwise: every page background is a
        // colour, a gradient, or an image over white, so compositing an
        // alpha channel is work both encoders would discard.
        renderer.isOpaque = !transparent
        // cgImage rather than uiImage: the encoders want a CGImage, and going
        // through UIImage only to unwrap it again would keep the wrapper
        // alive for the whole encode.
        return renderer.cgImage
    }

    /// The dpi a picture of `page` is written with: the design's own, at
    /// the scale it renders at — its true size whatever the scale — or nil
    /// for a design with none.
    static func imageDPI(design: Design, page: Page, requested: Double) -> Double? {
        guard design.dpi != nil || design.physicalUnit != nil else { return nil }
        return design.effectiveDPI * effectiveScale(size: design.size(for: page), requested: requested)
    }

    @MainActor
    static func exportRaster(design: Design, page: Page, format: RasterFormat,
                             scale: Double, quality: Double = 0.92,
                             transparent: Bool = false, to url: URL) throws {
        try autoreleasepool {
            guard let cg = render(design: design, page: page, scale: scale,
                                  transparent: transparent) else { throw ExportError.renderFailed }
            guard let destination = CGImageDestinationCreateWithURL(
                url as CFURL, format.contentType.identifier as CFString, 1, nil)
            else { throw ExportError.encodeFailed }
            var properties: [CFString: Any] = [
                kCGImageDestinationLossyCompressionQuality: max(0.05, min(1, quality)),
            ]
            // A design in a physical unit says its dpi, so the picture opens
            // at the design's true size; one in pixels says nothing, as
            // before.
            if let dpi = imageDPI(design: design, page: page, requested: scale) {
                properties[kCGImagePropertyDPIWidth] = dpi
                properties[kCGImagePropertyDPIHeight] = dpi
            }
            CGImageDestinationAddImage(destination, cg, properties as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ExportError.encodeFailed
            }
        }
    }

    /// Which pages an export covers.
    enum PageRange: Equatable {
        /// The page on screen — even a hidden one, since it was asked for.
        case current
        /// Every page not hidden.
        case all
        /// Zero-based, inclusive; hidden pages in it are left out too.
        case range(Int, Int)
        /// The pages picked by id in Export's Choose…, in the design's
        /// order — a hidden one too, since it was ticked.
        case chosen([String])

        func indices(in design: Design, current: Int) -> [Int] {
            let last = design.pages.count - 1
            guard last >= 0 else { return [] }
            switch self {
            case .current: return [min(max(current, 0), last)]
            case .all: return design.visiblePageIndices
            case .chosen(let ids):
                let picked = Set(ids)
                return design.pages.indices.filter { picked.contains(design.pages[$0].id) }
            case .range(let from, let to):
                let lower = min(max(min(from, to), 0), last)
                let upper = min(max(max(from, to), 0), last)
                return Array(lower...upper).filter { design.pages[$0].hidden != true }
            }
        }
    }

    /// One file per page, named `<design>-1.png` and so on.
    ///
    /// Separate files rather than one strip: a page range exists so each page
    /// can be posted or sent on its own, and stitching them back apart is
    /// exactly the work this is meant to save.
    ///
    /// With a `longEdge` above 0, each page is scaled so its own longer side
    /// is that many pixels — a deck of mixed sizes all come out 1080 on the
    /// long side — and `scale` is ignored.
    @MainActor
    static func exportPages(design: Design, range: PageRange, current: Int,
                            format: RasterFormat, scale: Double, longEdge: Double = 0,
                            quality: Double = 0.92, transparent: Bool = false,
                            progress: ((Double) -> Void)? = nil) async throws -> [URL] {
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        var urls: [URL] = []
        var pacer = Pacer()
        for (n, index) in indices.enumerated() {
            // A page is the unit: a cancelled export leaves no half-written
            // file behind, and nothing from the pages it had finished either.
            do { try await pacer.breathe() } catch {
                for url in urls { try? FileManager.default.removeItem(at: url) }
                throw error
            }
            let suffix = indices.count > 1 ? "-\(index + 1)" : ""
            let url = fileURL(for: design, ext: format.ext, suffix: suffix)
            let page = design.pages[index]
            let pageScale = longEdge > 0 ? DesignExporter.scale(forLongEdge: longEdge, size: design.size(for: page)) : scale
            try exportRaster(design: design, page: page, format: format,
                             scale: pageScale, quality: quality, transparent: transparent, to: url)
            urls.append(url)
            progress?(Double(n + 1) / Double(indices.count))
        }
        do { try await pacer.finish() } catch {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return urls
    }

    // MARK: pacing

    /// Lets the screen move during a long export. Pages and frames are drawn
    /// on the main actor, because ImageRenderer walks a SwiftUI view there;
    /// drawn back to back, the progress bar froze and Cancel could not be
    /// tapped until the whole file was written. Between pages the export
    /// steps aside for a moment — a thirtieth of a second at most apart, so a
    /// three-hundred-frame GIF is not slowed by three hundred pauses — and a
    /// Cancel lands there.
    struct Pacer {
        /// How long the work may run before it steps aside again.
        var interval: TimeInterval = 1.0 / 30.0
        /// The distant past, so the first call always steps aside: the
        /// progress card is drawn before the first page, not after it.
        private(set) var last = Date.distantPast

        init(interval: TimeInterval = 1.0 / 30.0) {
            self.interval = interval
        }

        /// True when the work has run long enough since the last pause.
        static func isDue(since last: Date, now: Date, interval: TimeInterval) -> Bool {
            now.timeIntervalSince(last) >= interval
        }

        /// Throws CancellationError once the export has been cancelled.
        mutating func breathe() async throws {
            try Task.checkCancellation()
            guard Pacer.isDue(since: last, now: Date(), interval: interval) else { return }
            // Out of the app with its background time run out, an export
            // waits here, between two pages or frames, until the app is back
            // (ExportQueue).
            try await ExportQueue.waitWhilePaused()
            // A sleep rather than Task.yield: a yield on the main actor can
            // be picked straight back up before the run loop draws or reads
            // a touch; a sleep lets it turn once.
            try await Task.sleep(nanoseconds: 1_000_000)
            last = Date()
        }

        /// The last pause, always taken: a Cancel tapped while the last page
        /// drew — on a one-page export, the only one — lands here, before
        /// the file is handed on to be shared or printed, not after.
        func finish() async throws {
            try await Task.sleep(nanoseconds: 1_000_000)
            try Task.checkCancellation()
        }
    }

    // MARK: pdf

    /// The PDF, written a page at a time with `progress` after each, and a
    /// pause between pages so the sheet stays live and Cancel works. A
    /// cancelled PDF is deleted rather than left short.
    ///
    /// Flattened, each page is one picture at 300 dpi instead — no text to
    /// reflow in another font, no links — which is what some print shops
    /// ask for.
    ///
    /// With `notes`, a page with notes is followed by a notes page of its
    /// size (drawNotesPage); with `compress`, every photo is drawn from a
    /// copy at 150 dpi of the size it prints at, as JPEG at 0.75
    /// (compressedForPDF), and nothing else changes.
    ///
    /// Finished, the file says what it is (PDFMetadata): its title,
    /// language and maker, with `bookmarks` an outline entry for each page
    /// — none for a notes page, which its page's leads to — and each
    /// page's pictures' alt texts, flattened or not.
    @MainActor
    static func exportPDF(design source: Design, range: PageRange = .all, current: Int = 0, flatten: Bool = false,
                          notes: Bool = false, compress: Bool = false, bookmarks: Bool = true,
                          to url: URL, progress: ((Double) -> Void)? = nil) async throws {
        let indices = range.indices(in: source, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        defer { if compress { CompressedPhotos.clear() } }
        var design = source
        if compress { design = try await compressedForPDF(source, indices: indices) }
        let sheets = ExportChoices.pdfSheets(design: design, indices: indices, notes: notes)
        // Page units are pixels at the design's dpi; PDF works in points
        // at 72 — so a page comes out at its true size.
        let pxToPt = PrintLayout.pxToPt(design)
        func bounds(_ page: Page) -> CGRect {
            let size = design.size(for: page)
            return CGRect(x: 0, y: 0, width: Double(size.width) * pxToPt, height: Double(size.height) * pxToPt)
        }
        let writer = try PDFWriter(url: url, bounds: bounds(design.pages[indices[0]]), title: design.title)
        var pacer = Pacer()
        // One entry per sheet written, in the order written: the file's
        // pages, not the design's.
        var titles: [String?] = []
        var figures: [[PDFUpdate.Picture]] = []
        do {
            for (n, sheet) in sheets.enumerated() {
                try await pacer.breathe()
                // Each page at its own size: a deck can mix a slide and a
                // handout. A notes page is the size of its page.
                switch sheet {
                case .page(let index):
                    let page = design.pages[index]
                    let box = bounds(page)
                    writer.page(box) { cg in
                        if flatten {
                            drawFlattened(design: design, page: page, fitting: box)
                        } else {
                            draw(design: design, page: page, into: cg, fitting: box)
                            linkAreas(of: page, in: design, onto: cg, pageHeight: box.height)
                        }
                    }
                    titles.append(bookmarks ? PDFMetadata.bookmarkTitle(page, number: index + 1) : nil)
                    figures.append(figureAreas(of: page, in: design, pageHeight: Double(box.height)))
                case .notes(let index):
                    let page = design.pages[index]
                    let box = bounds(page)
                    writer.page(box) { cg in drawNotesPage(design: design, page: page, box: box, flatten: flatten, into: cg) }
                    titles.append(nil)
                    figures.append([])
                }
                progress?(Double(n + 1) / Double(sheets.count))
            }
            try await pacer.finish()
            writer.close()
            // A file whose metadata could not be added is still the PDF.
            PDFUpdate.appendUpdate(to: url, metadata: metadata(for: design, titles: titles, figures: figures))
        } catch {
            writer.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    // MARK: notes pages

    /// A notes page of `box` (points): white, the page's picture fitted in
    /// its top third, and the notes below in the body font at 14 pt,
    /// wrapped — cut off at the page's foot should they run past it.
    /// Flattened, the whole notes page is one picture at 300 dpi, as every
    /// flattened page is.
    @MainActor
    private static func drawNotesPage(design: Design, page: Page, box: CGRect, flatten: Bool, into cg: CGContext) {
        guard flatten else {
            drawNotesContent(design: design, page: page, box: box, into: cg)
            return
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = flattenDPI / 72
        format.opaque = true
        let picture = UIGraphicsImageRenderer(size: box.size, format: format).image { context in
            drawNotesContent(design: design, page: page, box: CGRect(origin: .zero, size: box.size),
                             into: context.cgContext)
        }
        picture.draw(in: box)
    }

    /// What a notes page shows, drawn into `cg`, the current UIKit context,
    /// y running down: laid out by ExportChoices' notes numbers, the
    /// Android twin's PdfNotes.
    @MainActor
    private static func drawNotesContent(design: Design, page: Page, box: CGRect, into cg: CGContext) {
        cg.setFillColor(UIColor.white.cgColor)
        cg.fill(box)
        let thumb = ExportChoices.notesThumbnail(box.size).offsetBy(dx: box.minX, dy: box.minY)
        draw(design: design, page: page, into: cg, fitting: thumb)
        cg.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
        cg.setLineWidth(1)
        cg.stroke(thumb)
        let body = ExportChoices.notesTextBox(box.size).offsetBy(dx: box.minX, dy: box.minY)
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        let font = FontLibrary.uiFont(family: ExportChoices.notesFamily, size: ExportChoices.notesPointSize,
                                      weight: 400, italic: false)
        let colour = UIColor(hex: ExportChoices.notesColor)
        let words = NSAttributedString(string: (page.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                       attributes: [.font: font, .foregroundColor: colour, .paragraphStyle: style])
        cg.saveGState()
        cg.clip(to: body)
        words.draw(with: body, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        cg.restoreGState()
    }

    // MARK: compressed photos

    /// `design` with every photo on the pages of `indices` (and the master
    /// behind them) drawn from a copy re-encoded at ExportChoices'
    /// compressDPI of the size it prints at — one copy a source, at its
    /// largest use (ExportChoices.compressedPixels) — as JPEG at its
    /// compressQuality: a picture with see-through parts kept as it is,
    /// smaller, since JPEG has no transparency; never larger than it was.
    /// Each photo is read and re-encoded off the main thread, the export
    /// pausing between them, so the sheet stays live and Cancel works. The
    /// copies are kept by stand-in sources (CompressedPhotos) until cleared.
    @MainActor
    static func compressedForPDF(_ design: Design, indices: [Int]) async throws -> Design {
        let dpi = design.effectiveDPI
        var standIns: [String: String] = [:]
        var pacer = Pacer()
        for photo in ExportChoices.pdfPhotos(design: design, indices: indices) {
            try await pacer.breathe()
            let src = photo.src, uses = photo.uses
            // A library picture is drawn by the app, here; an upload is
            // read from disk with the rest, off the main thread.
            let drawn = src.hasPrefix("asset:") ? PhotoLibrary.resolve(src) : nil
            let made = await Task.detached(priority: .userInitiated) { () -> (name: String, copy: UIImage)? in
                guard let image = drawn ?? PhotoLibrary.resolve(src) else { return nil }
                let natural = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
                let kept = ExportChoices.compressedPixels(natural: natural, uses: uses, dpi: dpi)
                guard let copy = DesignExporter.reencoded(image, to: kept) else { return nil }
                // Named by its size too, so the same name is always the
                // same picture, whatever a filter's cache kept of an
                // earlier export.
                return (CompressedPhotos.prefix + "\(Int(kept.width))x\(Int(kept.height)):" + src, copy)
            }.value
            guard let made else { continue }
            CompressedPhotos.staged[made.name] = made.copy
            standIns[src] = made.name
        }
        var out = design
        var pages = Set(indices)
        if let master = design.masterPageId, let at = design.pages.firstIndex(where: { $0.id == master }) {
            pages.insert(at)
        }
        for index in pages.sorted() where out.pages.indices.contains(index) {
            if case .image(let src) = out.pages[index].background, let replaced = standIns[src] {
                out.pages[index].background = .image(replaced)
            }
            for i in out.pages[index].elements.indices {
                let el = out.pages[index].elements[i]
                guard el.type == .image, let src = el.src, let replaced = standIns[src] else { continue }
                out.pages[index].elements[i].src = replaced
            }
        }
        return out
    }

    /// `image` at `size` pixels: a JPEG at the compress quality when it is
    /// opaque, else the smaller bitmap as it is.
    private static func reencoded(_ image: UIImage, to size: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let opaque = image.cgImage.map { !ImageDownsampler.hasTransparentPixels($0) } ?? true
        format.opaque = opaque
        let smaller = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard opaque else { return smaller }
        return smaller.jpegData(compressionQuality: ExportChoices.compressQuality).flatMap(UIImage.init(data:))
    }

    /// A linked element clickable over its area, as in Canva's PDFs and the
    /// Android twin's. Given in the PDF's own space — points up from the
    /// bottom of the page — with UIKit's flip taken off, so the rectangle
    /// means the same however the context reads it.
    private static func linkAreas(of page: Page, in design: Design, onto cg: CGContext, pageHeight: Double) {
        let areas = Links.areas(design: design, page: page)
        guard !areas.isEmpty else { return }
        let pxToPt = PrintLayout.pxToPt(design)
        cg.saveGState()
        cg.concatenate(cg.ctm.inverted())
        for area in areas {
            guard let target = URL(string: area.url) else { continue }
            let rect = CGRect(x: area.rect.minX * pxToPt,
                              y: pageHeight - area.rect.maxY * pxToPt,
                              width: area.rect.width * pxToPt,
                              height: area.rect.height * pxToPt)
            cg.setURL(target as CFURL, for: rect)
        }
        cg.restoreGState()
    }

    /// The page's pictures with alt text (PDFMetadata.figures), each over
    /// its area in the PDF's own space — points up from the bottom of the
    /// page — as the alt-text annotations take them.
    private static func figureAreas(of page: Page, in design: Design, pageHeight: Double) -> [PDFUpdate.Picture] {
        let pxToPt = PrintLayout.pxToPt(design)
        return PDFMetadata.figures(design, page: page).map { f in
            PDFUpdate.Picture(left: f.x * pxToPt, bottom: pageHeight - (f.y + f.h) * pxToPt,
                             right: (f.x + f.w) * pxToPt, top: pageHeight - f.y * pxToPt, alt: f.alt)
        }
    }

    /// What a PDF of `design` says about itself: its title, this app at its
    /// version, its language — the design's, else the app's — `titles`,
    /// one per sheet of the file, and `figures`, each sheet's alt texts.
    static func metadata(for design: Design, titles: [String?], figures: [[PDFUpdate.Picture]] = []) -> PDFUpdate.Metadata {
        PDFUpdate.Metadata(info: PDFMetadata.info(design, version: PDFMetadata.appVersion),
                           lang: PDFMetadata.language(design, appLanguage: AppLanguage.current()),
                           bookmarks: titles, figures: figures)
    }

    /// Where each piece of a page goes on the paper: one sheet for fitted
    /// or actual size, several for tiles; for several to a sheet, every
    /// cell of the sheet it fills when repeated.
    static func placements(pagePoints pagePts: CGSize,
                           options: PrintLayout.Options) -> [(sheetRect: CGRect, source: CGRect)] {
        switch options.fit {
        case .fit:
            return [(PrintLayout.fitRect(page: pagePts, in: options.printable),
                     CGRect(origin: .zero, size: pagePts))]
        case .actual:
            let r = CGRect(x: options.printable.midX - pagePts.width / 2,
                           y: options.printable.midY - pagePts.height / 2,
                           width: pagePts.width, height: pagePts.height)
            return [(r, CGRect(origin: .zero, size: pagePts))]
        case .tile:
            return PrintLayout.tiles(page: pagePts, printable: options.printable.size,
                                     overlap: options.overlap).map { tile in
                (CGRect(origin: options.printable.origin, size: tile.size), tile)
            }
        case .several:
            return PrintLayout.grid(page: pagePts, printable: options.printable, gap: options.gapPoints).cells.map { cell in
                (cell, CGRect(origin: .zero, size: pagePts))
            }
        }
    }

    /// Several to a sheet: the pages on each sheet, cell by cell, how many
    /// cells a sheet has and how many across. The grid is cut for the first
    /// page's size. Double-sided only for a design of exactly two pages,
    /// both printed.
    static func severalPlan(design: Design, indices: [Int],
                            options: PrintLayout.Options) -> (sheets: [[Int]], perSheet: Int, cols: Int, duplex: Bool) {
        guard let first = indices.first else { return ([], 0, 1, false) }
        let pagePts = PrintLayout.pagePoints(size: design.size(at: first), dpi: design.effectiveDPI, bleed: options.bleed)
        let grid = PrintLayout.grid(page: pagePts, printable: options.printable, gap: options.gapPoints)
        let duplex = options.duplex && design.pages.count == 2 && indices.count == 2
        let sheets = PrintLayout.severalSheets(indices: indices, perSheet: grid.cells.count, mode: options.several,
                                               duplex: duplex)
        return (sheets, grid.cells.count, grid.cols, duplex)
    }

    /// How many sheets of paper the pages will take.
    static func sheetCount(design: Design, indices: [Int], options: PrintLayout.Options) -> Int {
        if options.fit == .several { return severalPlan(design: design, indices: indices, options: options).sheets.count }
        return indices.reduce(0) { total, index in
            let pagePts = PrintLayout.pagePoints(size: design.size(at: index), dpi: design.effectiveDPI, bleed: options.bleed)
            return total + placements(pagePoints: pagePts, options: options).count
        }
    }

    /// A print-ready PDF on real paper: each design page fitted, at actual
    /// size, or tiled across sheets; with optional bleed and crop marks. A
    /// design with a bleed of its own prints it: the page at its true size,
    /// what was put past the trim in the band (PrintLayout.drawing).
    /// Written a sheet at a time, with `progress` after each and a pause
    /// between them, so a forty-sheet tiled poster can be watched and
    /// cancelled; a cancelled PDF is deleted. It says what the plain PDF
    /// says about itself (PDFMetadata), with a bookmark on each page's first
    /// sheet — a sheet of several is bookmarked by the first page on it —
    /// and no alt texts, its pages being laid out on paper.
    @MainActor
    static func exportPrintPDF(design: Design, range: PageRange = .all, current: Int = 0,
                               options: PrintLayout.Options, flatten: Bool = false, bookmarks: Bool = true,
                               to url: URL, progress: ((Double) -> Void)? = nil) async throws {
        let sheet = CGRect(origin: .zero, size: options.sheet)
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        let total = max(1, sheetCount(design: design, indices: indices, options: options))
        let writer = try PDFWriter(url: url, bounds: sheet, title: design.title)
        let designed = Bleed.shown(design)
        var pacer = Pacer()
        var done = 0
        var titles: [String?] = []
        func title(_ index: Int) -> String? {
            bookmarks && design.pages.indices.contains(index)
                ? PDFMetadata.bookmarkTitle(design.pages[index], number: index + 1) : nil
        }
        do {
            if options.fit == .several {
                // Several to a sheet: a sheet at a time, the back of a
                // double-sided pair mirrored.
                let plan = severalPlan(design: design, indices: indices, options: options)
                for (n, pages) in plan.sheets.enumerated() {
                    try await pacer.breathe()
                    let mirrored = plan.duplex && n % 2 == 1
                    writer.page(sheet) { cg in
                        drawSeveral(design: design, pages: pages, cols: plan.cols, mirrored: mirrored,
                                    options: options, flatten: flatten, into: cg)
                    }
                    titles.append(pages.first.flatMap(title))
                    done += 1
                    progress?(Double(done) / Double(total))
                }
            }
            for index in indices where options.fit != .several {
                let page = design.pages[index]
                let pagePts = PrintLayout.pagePoints(size: design.size(for: page), dpi: design.effectiveDPI, bleed: options.bleed)
                for (n, placement) in placements(pagePoints: pagePts, options: options).enumerated() {
                    try await pacer.breathe()
                    // A sheet holding a whole page of a design with a bleed
                    // of its own says where its trim and bleed are, for the
                    // print shop's software — the two the same with the
                    // stepper at 0 — as Android adds them. One without
                    // prints exactly as before, with neither.
                    let boxes = designed
                        ? PrintLayout.boxes(sheet: placement.sheetRect, source: placement.source, page: pagePts,
                                            bleed: options.bleed, sheetHeight: Double(sheet.height))
                        : nil
                    writer.page(sheet, trim: boxes?.trim, bleed: boxes?.bleed) { cg in
                        drawSheet(design: design, page: page, pagePoints: pagePts,
                                  placement: placement, options: options, flatten: flatten, into: cg)
                    }
                    // A poster's first sheet alone carries the page's bookmark.
                    titles.append(n == 0 ? title(index) : nil)
                    done += 1
                    progress?(Double(done) / Double(total))
                }
            }
            try await pacer.finish()
            writer.close()
            PDFUpdate.appendUpdate(to: url, metadata: metadata(for: design, titles: titles))
        } catch {
            writer.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// One sheet of several pages: each fitted into its cell — at actual
    /// size when it is the first page's size, a page of another shape whole
    /// and centred in it, as the Android twin places it — the columns
    /// mirrored on the back of a double-sided pair; then the crop marks
    /// they share, clear of every page and its bleed.
    @MainActor
    private static func drawSeveral(design: Design, pages: [Int], cols: Int, mirrored: Bool,
                                    options: PrintLayout.Options, flatten: Bool, into cg: CGContext) {
        guard let first = pages.first else { return }
        let firstPts = PrintLayout.pagePoints(size: design.size(at: first), dpi: design.effectiveDPI, bleed: options.bleed)
        let cells = PrintLayout.grid(page: firstPts, printable: options.printable, gap: options.gapPoints).cells
        var unmarked = options
        unmarked.cropMarks = false
        var placed: [CGRect] = []
        for (slot, index) in pages.enumerated() {
            let at = PrintLayout.cellIndex(slot, cols: cols, mirrored: mirrored)
            guard cells.indices.contains(at), design.pages.indices.contains(index) else { continue }
            let pagePts = PrintLayout.pagePoints(size: design.size(at: index), dpi: design.effectiveDPI, bleed: options.bleed)
            drawSheet(design: design, page: design.pages[index], pagePoints: pagePts,
                      placement: (PrintLayout.fitRect(page: pagePts, in: cells[at]), CGRect(origin: .zero, size: pagePts)),
                      options: unmarked, flatten: flatten, into: cg)
            placed.append(cells[at])
        }
        guard options.cropMarks else { return }
        let trims = placed.map { $0.insetBy(dx: options.bleed, dy: options.bleed) }
        cg.setStrokeColor(gray: 0, alpha: 1)
        cg.setLineWidth(0.5)
        for (a, b) in PrintLayout.gridMarks(trims: trims, placed: placed, gap: options.bleed + 4) {
            cg.move(to: a)
            cg.addLine(to: b)
        }
        cg.strokePath()
    }

    /// One sheet of a print PDF: its piece of the page, and the crop marks.
    @MainActor
    private static func drawSheet(design: Design, page: Page, pagePoints pagePts: CGSize,
                                  placement: (sheetRect: CGRect, source: CGRect),
                                  options: PrintLayout.Options, flatten: Bool = false, into cg: CGContext) {
        cg.saveGState()
        // Show only this piece of the page.
        cg.clip(to: placement.sheetRect)
        // Map the source region of the (bled) page onto the sheet rect.
        let scale = placement.sheetRect.width / max(placement.source.width, 1)
        cg.translateBy(x: placement.sheetRect.minX - placement.source.minX * scale,
                       y: placement.sheetRect.minY - placement.source.minY * scale)
        cg.scaleBy(x: scale, y: scale)
        // Nothing past the bleed. A page enlarged evenly
        // runs past it on its long side, and a tile's source
        // reaches past the page's far edge, so without this
        // the last row or column of tiles printed artwork
        // beyond the bleed and under the crop marks.
        cg.clip(to: CGRect(origin: .zero, size: pagePts))
        // The page itself sits inside the bleed. A design with
        // a bleed of its own is drawn at its true size, what it
        // put past the trim filling the band; one without is
        // enlarged evenly to cover it, the way a print shop's
        // bleed is made when none was designed.
        let drawing = PrintLayout.drawing(size: design.size(for: page), bleed: options.bleed,
                                          pxToPt: PrintLayout.pxToPt(design), designed: Bleed.shown(design))
        if flatten {
            drawFlattened(design: design, page: page, drawing: drawing)
        } else {
            draw(design: design, page: page, into: cg, drawing: drawing)
        }
        cg.restoreGState()
        if options.cropMarks {
            cg.setStrokeColor(gray: 0, alpha: 1)
            cg.setLineWidth(0.5)
            let marks = PrintLayout.sheetMarks(sheet: placement.sheetRect, source: placement.source,
                                               page: pagePts, bleed: options.bleed)
            for (a, b) in marks {
                cg.move(to: a); cg.addLine(to: b)
            }
            cg.strokePath()
        }
    }

    /// A PDF written a page at a time, so an export can step aside between
    /// pages — UIGraphicsPDFRenderer takes every page in one closure and
    /// gives nowhere to pause. Each page is set up as that renderer sets its
    /// pages up: origin at the top left, y running down, and the context
    /// current for UIKit drawing while the page is drawn, so everything
    /// drawn into it lands where it did before.
    @MainActor
    final class PDFWriter {
        private let context: CGContext
        private var closed = false

        /// `title` is the design's, said as the file's own (PDFMetadata),
        /// with Canvia as its creator; the rest of what the file says about
        /// itself is added once it is finished (PDFUpdate), and the title
        /// and creator stand should that fail.
        init(url: URL, bounds: CGRect, title: String? = nil) throws {
            try? FileManager.default.removeItem(at: url)
            var box = bounds
            var info: [String: String] = [kCGPDFContextCreator as String: PDFMetadata.creator,
                                          kCGPDFContextAuthor as String: PDFMetadata.creator]
            if let title { info[kCGPDFContextTitle as String] = title }
            guard let context = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else {
                throw ExportError.encodeFailed
            }
            self.context = context
        }

        /// One page of `box` (in points), drawn by `body` — with its
        /// TrimBox and BleedBox, in the PDF's own points up from the
        /// bottom, when given.
        func page(_ box: CGRect, trim: CGRect? = nil, bleed: CGRect? = nil, body: (CGContext) -> Void) {
            var info = [kCGPDFContextMediaBox as String: Self.boxData(box)]
            if let trim { info[kCGPDFContextTrimBox as String] = Self.boxData(trim) }
            if let bleed { info[kCGPDFContextBleedBox as String] = Self.boxData(bleed) }
            context.beginPDFPage(info as CFDictionary)
            context.saveGState()
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            autoreleasepool { body(context) }
            UIGraphicsPopContext()
            context.restoreGState()
            context.endPDFPage()
        }

        /// A box as the page's info dictionary takes it.
        private static func boxData(_ box: CGRect) -> Data {
            var rect = box
            return Data(bytes: &rect, count: MemoryLayout<CGRect>.size)
        }

        /// Finishes the file. Safe to call twice.
        func close() {
            guard !closed else { return }
            closed = true
            context.closePDF()
        }
    }

    /// The page of `size` scaled evenly to cover `bounds`, and centred: a
    /// bleed wider on one side than the other in proportion never stretches
    /// the page, so a circle stays round. Cut at the page's edge, as the
    /// canvas cuts it — the Android twin draws the same.
    private static func covering(_ bounds: CGRect, size: CGSize) -> PrintLayout.Drawing {
        let w = Double(size.width), h = Double(size.height)
        let scale = max(Double(bounds.width) / max(w, 1), Double(bounds.height) / max(h, 1))
        return PrintLayout.Drawing(origin: CGPoint(x: Double(bounds.minX) + (Double(bounds.width) - w * scale) / 2,
                                                   y: Double(bounds.minY) + (Double(bounds.height) - h * scale) / 2),
                                   scale: scale, clip: CGRect(x: 0, y: 0, width: w, height: h))
    }

    /// Draw one page into an arbitrary context at `bounds`, as vectors.
    @MainActor
    private static func draw(design: Design, page: Page,
                             into context: CGContext, fitting bounds: CGRect) {
        draw(design: design, page: page, into: context, drawing: covering(bounds, size: design.size(for: page)))
    }

    /// Draw one page as `drawing` places it, as vectors: the view draws in
    /// the design's own units, scaled onto the PDF page rather than resized,
    /// so no layout depends on the output size. A clip reaching past the
    /// page is a designed bleed, drawn by the page itself out to there.
    @MainActor
    private static func draw(design: Design, page: Page,
                             into context: CGContext, drawing: PrintLayout.Drawing) {
        let reach = max(0, -Double(drawing.clip.minX))
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: page, bleed: reach))
        renderer.render { size, drawInContext in
            context.saveGState()
            // The view's top left is the bleed's, `reach` before the page's.
            context.translateBy(x: Double(drawing.origin.x) - reach * drawing.scale,
                                y: Double(drawing.origin.y) - reach * drawing.scale)
            context.scaleBy(x: drawing.scale, y: drawing.scale)
            context.clip(to: CGRect(origin: .zero, size: size))
            drawInContext(context)
            context.restoreGState()
        }
    }

    /// The scale a flattened PDF renders a page at: 300 dpi from the
    /// design's own, so a 96-dpi design is drawn at 3.125× and an A4 page
    /// at 300 dpi at 1× — within the pixel budget, as every render is.
    static let flattenDPI = 300.0

    static func flattenScale(_ design: Design) -> Double {
        flattenDPI / design.effectiveDPI
    }

    /// One page as a single picture filling `bounds` — evenly, centred and
    /// cut at the page's edge, as the vector page is drawn — in the current
    /// UIKit context, which the PDF writer has set up the right way up.
    @MainActor
    private static func drawFlattened(design: Design, page: Page, fitting bounds: CGRect) {
        drawFlattened(design: design, page: page, drawing: covering(bounds, size: design.size(for: page)))
    }

    /// The same placed as `drawing` places it: with a designed bleed, the
    /// picture is of the page and its band.
    @MainActor
    private static func drawFlattened(design: Design, page: Page, drawing: PrintLayout.Drawing) {
        let reach = max(0, -Double(drawing.clip.minX))
        guard let cg = render(design: design, page: page, scale: flattenScale(design), bleed: reach) else { return }
        let rect = CGRect(x: Double(drawing.origin.x) + Double(drawing.clip.minX) * drawing.scale,
                          y: Double(drawing.origin.y) + Double(drawing.clip.minY) * drawing.scale,
                          width: Double(drawing.clip.width) * drawing.scale,
                          height: Double(drawing.clip.height) * drawing.scale)
        UIImage(cgImage: cg).draw(in: rect)
    }

    // MARK: svg

    @MainActor
    static func exportSVG(design: Design, page: Page, to url: URL) throws {
        let markup = SVGExporter.svg(design: design, page: page)
        guard let data = markup.data(using: .utf8) else { throw ExportError.encodeFailed }
        try data.write(to: url)
    }

    /// One .svg per page of `range`, named with its page number only when
    /// there is more than one, to share together.
    @MainActor
    static func exportSVGs(design: Design, range: PageRange, current: Int) throws -> [URL] {
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        var urls: [URL] = []
        do {
            for index in indices {
                let suffix = indices.count > 1 ? "-\(index + 1)" : ""
                let url = fileURL(for: design, ext: "svg", suffix: suffix)
                try exportSVG(design: design, page: design.pages[index], to: url)
                urls.append(url)
            }
        } catch {
            for url in urls { try? FileManager.default.removeItem(at: url) }
            throw error
        }
        return urls
    }

    // MARK: destination

    /// A temporary file named after the design, so the share sheet offers
    /// something recognisable rather than "file.png".
    static func fileURL(for design: Design, ext: String, suffix: String = "") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(fileBaseName(design.title))\(suffix).\(ext)")
    }

    /// The longest name an export takes from a title, in characters.
    static let maxNameLength = 60

    /// What an exported file is called, before its page number and
    /// extension — the same name on both phones. Letters and digits of any
    /// script are kept ("Café menu" is "Café-menu", a Japanese title stays
    /// Japanese), with combining marks, underscores and hyphens; anything
    /// else goes, the ends are trimmed, and a run of spaces is one hyphen:
    /// "Q3 / report" is "Q3-report", not "Q3--report". Nothing left is
    /// "design". Cut at sixty characters, never through a letter.
    static func fileBaseName(_ title: String) -> String {
        let kept = title
            .replacingOccurrences(of: "[^\\p{L}\\p{M}\\p{Nd}\\p{Nl}\\p{Pc}\\u200C\\u200D \\-]", with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " +", with: "-", options: .regularExpression)
        guard !kept.isEmpty else { return "design" }
        let scalars = kept.unicodeScalars
        guard scalars.count > maxNameLength else { return kept }
        var cut = String(String.UnicodeScalarView(scalars.prefix(maxNameLength)))
        while cut.hasSuffix("-") { cut.removeLast() }
        return cut.isEmpty ? "design" : cut
    }
}
