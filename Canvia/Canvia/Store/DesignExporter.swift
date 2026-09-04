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

    /// The scale a request actually renders at, after the budget.
    static func effectiveScale(design: Design, requested: Double) -> Double {
        let area = max(design.width * design.height, 1)
        let ceiling = (pixelBudget / area).squareRoot()
        return min(max(requested, 0.01), ceiling)
    }

    static func effectiveScale(design: Design, requested: Int) -> Double {
        effectiveScale(design: design, requested: Double(requested))
    }

    /// The exported image's size in pixels, which is what the user is really
    /// choosing when they pick a scale.
    static func outputSize(design: Design, requested: Double) -> CGSize {
        let scale = effectiveScale(design: design, requested: requested)
        return CGSize(width: (design.width * scale).rounded(),
                      height: (design.height * scale).rounded())
    }

    static func outputSize(design: Design, requested: Int) -> CGSize {
        outputSize(design: design, requested: Double(requested))
    }

    /// True when the budget, not the user, decided the scale.
    static func isClamped(design: Design, requested: Double) -> Bool {
        effectiveScale(design: design, requested: requested) < requested - 0.001
    }

    static func isClamped(design: Design, requested: Int) -> Bool {
        isClamped(design: design, requested: Double(requested))
    }

    /// The scale that puts the design's longer side at `pixels`. Platforms
    /// specify sizes, not multipliers — "1080 wide", "4K" — so this is what
    /// the size field and the presets resolve through.
    static func scale(forLongEdge pixels: Double, design: Design) -> Double {
        let edge = max(design.width, design.height, 1)
        return max(0.05, pixels / edge)
    }

    /// The longer side, in pixels, at the requested scale after the budget.
    static func longEdge(design: Design, requested: Double) -> Double {
        let size = outputSize(design: design, requested: requested)
        return max(size.width, size.height)
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
        let size = outputSize(design: design, requested: requested)
        let pixels = size.width * size.height
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
        renderer.scale = CGFloat(effectiveScale(design: design, requested: scale))
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
    @MainActor
    static func exportPages(design: Design, range: PageRange, current: Int,
                            format: RasterFormat, scale: Double, quality: Double = 0.92,
                            transparent: Bool = false,
                            progress: ((Double) -> Void)? = nil) throws -> [URL] {
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        var urls: [URL] = []
        for (n, index) in indices.enumerated() {
            // A page is the unit: a cancelled export leaves no half-written
            // file behind, and nothing from the pages it had finished either.
            if Task.isCancelled {
                for url in urls { try? FileManager.default.removeItem(at: url) }
                throw CancellationError()
            }
            let suffix = indices.count > 1 ? "-\(index + 1)" : ""
            let url = fileURL(for: design, ext: format.ext, suffix: suffix)
            try exportRaster(design: design, page: design.pages[index], format: format,
                             scale: scale, quality: quality, transparent: transparent, to: url)
            urls.append(url)
            progress?(Double(n + 1) / Double(indices.count))
        }
        return urls
    }

    // MARK: pdf

    /// Page units are pixels at 96dpi; PDF works in points at 72.
    static let pxToPt = 72.0 / 96.0

    @MainActor
    static func exportPDF(design: Design, range: PageRange = .all, current: Int = 0,
                          to url: URL) throws {
        let bounds = CGRect(x: 0, y: 0,
                            width: design.width * pxToPt,
                            height: design.height * pxToPt)
        let indices = range.indices(in: design, current: current)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { ctx in
            for page in indices.map({ design.pages[$0] }) {
                autoreleasepool {
                    ctx.beginPage()
                    draw(design: design, page: page, into: ctx.cgContext, fitting: bounds)
                }
            }
        }
    }

    /// A print-ready PDF on real paper: each design page fitted, at actual
    /// size, or tiled across sheets; with optional bleed and crop marks.
    @MainActor
    static func exportPrintPDF(design: Design, range: PageRange = .all, current: Int = 0,
                               options: PrintLayout.Options, to url: URL) throws {
        let sheet = CGRect(origin: .zero, size: options.sheet)
        let indices = range.indices(in: design, current: current)
        let pagePts = PrintLayout.pagePoints(design: design, bleed: options.bleed)
        try UIGraphicsPDFRenderer(bounds: sheet).writePDF(to: url) { ctx in
            for page in indices.map({ design.pages[$0] }) {
                let placements: [(sheetRect: CGRect, source: CGRect)]
                switch options.fit {
                case .fit:
                    placements = [(PrintLayout.fitRect(page: pagePts, in: options.printable),
                                   CGRect(origin: .zero, size: pagePts))]
                case .actual:
                    let r = CGRect(x: options.printable.midX - pagePts.width / 2,
                                   y: options.printable.midY - pagePts.height / 2,
                                   width: pagePts.width, height: pagePts.height)
                    placements = [(r, CGRect(origin: .zero, size: pagePts))]
                case .tile:
                    placements = PrintLayout.tiles(page: pagePts, printable: options.printable.size,
                                                   overlap: options.overlap).map { tile in
                        (CGRect(origin: options.printable.origin, size: tile.size), tile)
                    }
                }
                for placement in placements {
                    autoreleasepool {
                        ctx.beginPage()
                        let cg = ctx.cgContext
                        cg.saveGState()
                        // Show only this piece of the page.
                        cg.clip(to: placement.sheetRect)
                        // Map the source region of the (bled) page onto the sheet rect.
                        let scale = placement.sheetRect.width / max(placement.source.width, 1)
                        cg.translateBy(x: placement.sheetRect.minX - placement.source.minX * scale,
                                       y: placement.sheetRect.minY - placement.source.minY * scale)
                        cg.scaleBy(x: scale, y: scale)
                        // The page itself sits inside the bleed; the bleed is
                        // the page's own edge colours stretched — drawn here
                        // as the page scaled up by the bleed, the way a
                        // print shop's bleed is made when none was designed.
                        let bleedRect = CGRect(origin: .zero, size: pagePts)
                        draw(design: design, page: page, into: cg, fitting: bleedRect)
                        cg.restoreGState()
                        if options.cropMarks {
                            let trimmed = placement.sheetRect.insetBy(dx: options.bleed * scale, dy: options.bleed * scale)
                            cg.setStrokeColor(gray: 0, alpha: 1)
                            cg.setLineWidth(0.5)
                            for (a, b) in PrintLayout.cropMarkSegments(around: trimmed) {
                                cg.move(to: a); cg.addLine(to: b)
                            }
                            cg.strokePath()
                        }
                    }
                }
            }
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
            // the output size.
            context.scaleBy(x: bounds.width / max(size.width, 1),
                            y: bounds.height / max(size.height, 1))
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
        // Keep word characters, spaces and hyphens; drop everything else.
        // \\w already covers digits and underscore, and the hyphen is escaped
        // rather than left next to a class shorthand where an engine has to
        // guess whether it meant a range.
        let name = design.title
            .replacingOccurrences(of: "[^\\w\\- ]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "-")
        let base = name.isEmpty ? "design" : name
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(base)\(suffix).\(ext)")
    }
}
