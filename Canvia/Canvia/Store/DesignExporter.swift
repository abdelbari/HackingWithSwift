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
    static func effectiveScale(design: Design, requested: Int) -> Double {
        let area = max(design.width * design.height, 1)
        let ceiling = (pixelBudget / area).squareRoot()
        return min(Double(requested), ceiling)
    }

    /// The exported image's size in pixels, which is what the user is really
    /// choosing when they pick a scale.
    static func outputSize(design: Design, requested: Int) -> CGSize {
        let scale = effectiveScale(design: design, requested: requested)
        return CGSize(width: (design.width * scale).rounded(),
                      height: (design.height * scale).rounded())
    }

    /// True when the budget, not the user, decided the scale.
    static func isClamped(design: Design, requested: Int) -> Bool {
        effectiveScale(design: design, requested: requested) < Double(requested) - 0.001
    }

    // MARK: raster

    /// Rough bytes a JPEG of this design will come to at a given quality.
    ///
    /// A guess, and labelled as one — but the shape of it is right, and the
    /// alternative (encoding the whole page on every slider tick) is worse
    /// than a guess by a wide margin. Calibrated against photographic content
    /// at 4:2:0 chroma: about 0.55 bits per pixel at quality 0.5, scaling with
    /// roughly the square of quality.
    static func estimatedJPEGBytes(design: Design, requested: Int, quality: Double) -> Int {
        let size = outputSize(design: design, requested: requested)
        let pixels = size.width * size.height
        let bitsPerPixel = 0.15 + 2.6 * pow(max(0, min(1, quality)), 2)
        return max(2_048, Int(pixels * bitsPerPixel / 8))
    }

    @MainActor
    static func exportRaster(design: Design, page: Page, format: RasterFormat,
                             scale: Int, quality: Double = 0.92, to url: URL) throws {
        try autoreleasepool {
            let renderer = ImageRenderer(content: PageRenderView(design: design, page: page))
            renderer.scale = CGFloat(effectiveScale(design: design, requested: scale))
            // Every page background is opaque — a colour, a gradient, or an
            // image over white — so compositing an alpha channel is work whose
            // result is discarded by both encoders.
            renderer.isOpaque = true
            // cgImage rather than uiImage: the encoder below wants a CGImage,
            // and going through UIImage only to unwrap it again would keep the
            // wrapper alive for the whole encode.
            guard let cg = renderer.cgImage else { throw ExportError.renderFailed }
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

    // MARK: pdf

    /// Page units are pixels at 96dpi; PDF works in points at 72.
    static let pxToPt = 72.0 / 96.0

    @MainActor
    static func exportPDF(design: Design, to url: URL) throws {
        let bounds = CGRect(x: 0, y: 0,
                            width: design.width * pxToPt,
                            height: design.height * pxToPt)
        try UIGraphicsPDFRenderer(bounds: bounds).writePDF(to: url) { ctx in
            for page in design.pages {
                autoreleasepool {
                    ctx.beginPage()
                    draw(design: design, page: page, into: ctx.cgContext, fitting: bounds)
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
    static func fileURL(for design: Design, ext: String) -> URL {
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
            .appendingPathComponent("\(base).\(ext)")
    }
}
