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
            case .renderFailed: return "could not render the page"
            case .encodeFailed: return "could not encode the image"
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
        SizePreset(name: "Instagram post (1080)", longEdge: 1080),
        SizePreset(name: "Story / Reel (1920)", longEdge: 1920),
        SizePreset(name: "Full HD (1920)", longEdge: 1920),
        SizePreset(name: "4K (3840)", longEdge: 3840),
        SizePreset(name: "A4 at 300 dpi (3508)", longEdge: 3508),
        SizePreset(name: "US Letter at 300 dpi (3300)", longEdge: 3300),
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
            guard el.type == .image, let src = el.src, let source = pixelSize(src),
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
        let chosen = page.elements.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return nil }
        let box = Geometry.union(chosen.map(Geometry.aabb)).integral
        guard box.width > 0, box.height > 0 else { return nil }
        var cropped = Design(title: design.title, width: box.width, height: box.height)
        cropped.id = design.id
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
        let pixels = Double(size.width) * Double(size.height)
        let bitsPerPixel = 0.15 + 2.6 * pow(max(0, min(1, quality)), 2)
        return max(2_048, Int(pixels * bitsPerPixel / 8))
    }

    /// The page as pixels. Everything raster goes through here: files, the
    /// clipboard, and any test that wants to look at the output.
    @MainActor
    static func render(design: Design, page: Page, scale: Double,
                       transparent: Bool = false) -> CGImage? {
        // A transparent export drops the page's own background rather than
        // just turning off compositing: "no background" has to mean the
        // background is gone, not that an opaque white one is drawn
        // without an alpha channel.
        var rendered = page
        if transparent { rendered.background = .color("#00000000") }
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: rendered))
        renderer.scale = CGFloat(effectiveScale(size: design.size(for: page), requested: scale))
        // Opaque unless asked otherwise: every page background is a
        // colour, a gradient, or an image over white, so compositing an
        // alpha channel is work both encoders would discard.
        renderer.isOpaque = !transparent
        // cgImage rather than uiImage: the encoders want a CGImage, and going
        // through UIImage only to unwrap it again would keep the wrapper
        // alive for the whole encode.
        return renderer.cgImage
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
            CGImageDestinationAddImage(destination, cg, [
                kCGImageDestinationLossyCompressionQuality: max(0.05, min(1, quality)),
            ] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw ExportError.encodeFailed
            }
        }
    }

    /// Which pages an export covers.
    enum PageRange: Equatable {
        case current
        case all
        /// Zero-based, inclusive.
        case range(Int, Int)

        func indices(in design: Design, current: Int) -> [Int] {
            let last = design.pages.count - 1
            guard last >= 0 else { return [] }
            switch self {
            case .current: return [min(max(current, 0), last)]
            case .all: return Array(0...last)
            case .range(let from, let to):
                let lower = min(max(min(from, to), 0), last)
                let upper = min(max(max(from, to), 0), last)
                return Array(lower...upper)
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

    /// Page units are pixels at 96dpi; PDF works in points at 72.
    static let pxToPt = 72.0 / 96.0

    /// The PDF, written a page at a time with `progress` after each, and a
    /// pause between pages so the sheet stays live and Cancel works. A
    /// cancelled PDF is deleted rather than left short.
    @MainActor
    static func exportPDF(design: Design, range: PageRange = .all, current: Int = 0,
                          to url: URL, progress: ((Double) -> Void)? = nil) async throws {
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        func bounds(_ page: Page) -> CGRect {
            let size = design.size(for: page)
            return CGRect(x: 0, y: 0, width: Double(size.width) * pxToPt, height: Double(size.height) * pxToPt)
        }
        let writer = try PDFWriter(url: url, bounds: bounds(design.pages[indices[0]]))
        var pacer = Pacer()
        do {
            for (n, index) in indices.enumerated() {
                try await pacer.breathe()
                // Each page at its own size: a deck can mix a slide and a
                // handout.
                let page = design.pages[index]
                let box = bounds(page)
                writer.page(box) { cg in
                    draw(design: design, page: page, into: cg, fitting: box)
                    linkAreas(of: page, in: design, onto: cg, pageHeight: box.height)
                }
                progress?(Double(n + 1) / Double(indices.count))
            }
            try await pacer.finish()
            writer.close()
        } catch {
            writer.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// A linked element clickable over its area, as in Canva's PDFs and the
    /// Android twin's. Given in the PDF's own space — points up from the
    /// bottom of the page — with UIKit's flip taken off, so the rectangle
    /// means the same however the context reads it.
    private static func linkAreas(of page: Page, in design: Design, onto cg: CGContext, pageHeight: Double) {
        let areas = Links.areas(design: design, page: page)
        guard !areas.isEmpty else { return }
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

    /// Where each piece of a page goes on the paper: one sheet for fitted
    /// or actual size, several for tiles.
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
        }
    }

    /// How many sheets of paper the pages will take.
    static func sheetCount(design: Design, indices: [Int], options: PrintLayout.Options) -> Int {
        indices.reduce(0) { total, index in
            let pagePts = PrintLayout.pagePoints(size: design.size(at: index), bleed: options.bleed)
            return total + placements(pagePoints: pagePts, options: options).count
        }
    }

    /// A print-ready PDF on real paper: each design page fitted, at actual
    /// size, or tiled across sheets; with optional bleed and crop marks.
    /// Written a sheet at a time, with `progress` after each and a pause
    /// between them, so a forty-sheet tiled poster can be watched and
    /// cancelled; a cancelled PDF is deleted.
    @MainActor
    static func exportPrintPDF(design: Design, range: PageRange = .all, current: Int = 0,
                               options: PrintLayout.Options, to url: URL,
                               progress: ((Double) -> Void)? = nil) async throws {
        let sheet = CGRect(origin: .zero, size: options.sheet)
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        let total = max(1, sheetCount(design: design, indices: indices, options: options))
        let writer = try PDFWriter(url: url, bounds: sheet)
        var pacer = Pacer()
        var done = 0
        do {
            for page in indices.map({ design.pages[$0] }) {
                let pagePts = PrintLayout.pagePoints(size: design.size(for: page), bleed: options.bleed)
                for placement in placements(pagePoints: pagePts, options: options) {
                    try await pacer.breathe()
                    writer.page(sheet) { cg in
                        drawSheet(design: design, page: page, pagePoints: pagePts,
                                  placement: placement, options: options, into: cg)
                    }
                    done += 1
                    progress?(Double(done) / Double(total))
                }
            }
            try await pacer.finish()
            writer.close()
        } catch {
            writer.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// One sheet of a print PDF: its piece of the page, and the crop marks.
    @MainActor
    private static func drawSheet(design: Design, page: Page, pagePoints pagePts: CGSize,
                                  placement: (sheetRect: CGRect, source: CGRect),
                                  options: PrintLayout.Options, into cg: CGContext) {
        cg.saveGState()
        // Show only this piece of the page.
        cg.clip(to: placement.sheetRect)
        // Map the source region of the (bled) page onto the sheet rect.
        let scale = placement.sheetRect.width / max(placement.source.width, 1)
        cg.translateBy(x: placement.sheetRect.minX - placement.source.minX * scale,
                       y: placement.sheetRect.minY - placement.source.minY * scale)
        cg.scaleBy(x: scale, y: scale)
        // Nothing past the bleed. The page enlarged evenly
        // runs past it on its long side, and a tile's source
        // reaches past the page's far edge, so without this
        // the last row or column of tiles printed artwork
        // beyond the bleed and under the crop marks.
        cg.clip(to: CGRect(origin: .zero, size: pagePts))
        // The page itself sits inside the bleed; the bleed is
        // the page's own edges carried out — drawn here as
        // the page enlarged evenly to cover it, the way a
        // print shop's bleed is made when none was designed.
        let bleedRect = CGRect(origin: .zero, size: pagePts)
        draw(design: design, page: page, into: cg, fitting: bleedRect)
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

        init(url: URL, bounds: CGRect) throws {
            try? FileManager.default.removeItem(at: url)
            var box = bounds
            guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else {
                throw ExportError.encodeFailed
            }
            self.context = context
        }

        /// One page of `box` (in points), drawn by `body`.
        func page(_ box: CGRect, body: (CGContext) -> Void) {
            var media = box
            let mediaData = Data(bytes: &media, count: MemoryLayout<CGRect>.size)
            let info = [kCGPDFContextMediaBox as String: mediaData] as CFDictionary
            context.beginPDFPage(info)
            context.saveGState()
            context.translateBy(x: 0, y: box.height)
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            autoreleasepool { body(context) }
            UIGraphicsPopContext()
            context.restoreGState()
            context.endPDFPage()
        }

        /// Finishes the file. Safe to call twice.
        func close() {
            guard !closed else { return }
            closed = true
            context.closePDF()
        }
    }

    /// Draw one page into an arbitrary context at `bounds`, as vectors.
    @MainActor
    private static func draw(design: Design, page: Page,
                             into context: CGContext, fitting bounds: CGRect) {
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: page))
        renderer.render { size, drawInContext in
            context.saveGState()
            // The view draws in the design's own units; scale that onto the
            // PDF page rather than resizing the view, so no layout depends on
            // the output size. Evenly, to cover `bounds`, and centred: a
            // bleed wider on one side than the other in proportion never
            // stretches the page, so a circle stays round. Cut at the page's
            // edge, as the canvas cuts it — the Android twin draws the same.
            let across = bounds.width / max(size.width, 1)
            let down = bounds.height / max(size.height, 1)
            let scale = max(across, down)
            let dx = bounds.minX + (bounds.width - size.width * scale) / 2
            let dy = bounds.minY + (bounds.height - size.height * scale) / 2
            context.translateBy(x: dx, y: dy)
            context.scaleBy(x: scale, y: scale)
            context.clip(to: CGRect(origin: .zero, size: size))
            drawInContext(context)
            context.restoreGState()
        }
    }

    // MARK: svg

    @MainActor
    static func exportSVG(design: Design, page: Page, to url: URL) throws {
        let markup = SVGExporter.svg(design: design, page: page)
        guard let data = markup.data(using: .utf8) else { throw ExportError.encodeFailed }
        try data.write(to: url)
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
