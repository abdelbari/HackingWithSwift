// The print-ready PDF with "Colour profile: CMYK": each sheet laid out as
// the RGB print PDF lays it — fitted, actual size, tiled or several to a
// sheet, with bleed — drawn at 300 dpi onto white paper and written in press
// ink by CmykPdf, the crop marks over it in black ink alone and the TrimBox
// and BleedBox where the RGB file has them. Printing to a printer stays RGB.

import CoreGraphics
import UIKit

extension DesignExporter {

    /// One sheet to draw: what goes on it, its boxes and its marks.
    private struct CmykSheet {
        var draw: @MainActor (CGContext) -> Void
        var trim: CGRect?
        var bleed: CGRect?
        var marks: [(CGPoint, CGPoint)]
        /// The sheet's bookmark, as the RGB print PDF gives it.
        var title: String?
    }

    /// The print-ready PDF in CMYK, a sheet at a time, with `progress`
    /// after each and a pause between them; a cancelled file is deleted.
    /// It says what the RGB print PDF says about itself, bookmarks and all,
    /// as Android's does.
    @MainActor
    static func exportCmykPrintPDF(design: Design, range: PageRange = .all, current: Int = 0,
                                   options: PrintLayout.Options, bookmarks: Bool = true, to url: URL,
                                   progress: ((Double) -> Void)? = nil) async throws {
        let indices = range.indices(in: design, current: current)
        guard !indices.isEmpty else { throw ExportError.renderFailed }
        let sheets = cmykSheets(design: design, indices: indices, options: options, bookmarks: bookmarks)
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { throw ExportError.encodeFailed }
        var pacer = Pacer()
        do {
            let writer = try CmykPdf.SheetWriter(sheets: sheets.count, size: options.sheet) { try handle.write(contentsOf: $0) }
            for (n, sheet) in sheets.enumerated() {
                try await pacer.breathe()
                // Drawn here, on the main actor, as every page is drawn; then
                // inked and packed — every pixel of the sheet — off it, so
                // the app goes on answering while it is, and waited for
                // before the next sheet.
                guard let drawn = autoreleasepool(invoking: { sheetContext(options.sheet, draw: sheet.draw) }) else {
                    throw ExportError.renderFailed
                }
                let trim = sheet.trim, bleed = sheet.bleed, marks = sheet.marks
                try await Task.detached(priority: .userInitiated) {
                    try autoreleasepool {
                        try writer.add(DesignExporter.sheetPixels(drawn), trim: trim, bleed: bleed, marks: marks)
                    }
                }.value
                progress?(Double(n + 1) / Double(sheets.count))
            }
            try writer.finish()
            try await pacer.finish()
            try handle.close()
            // Its boxes are written with it; what it says about itself after.
            PDFUpdate.appendUpdate(to: url, metadata: metadata(for: design, titles: sheets.map(\.title)))
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    /// Every sheet of the print, in order, as exportPrintPDF lays them out,
    /// each drawn without its crop marks, which the PDF draws in ink.
    @MainActor
    private static func cmykSheets(design: Design, indices: [Int], options: PrintLayout.Options,
                                   bookmarks: Bool) -> [CmykSheet] {
        func title(_ index: Int) -> String? {
            bookmarks && design.pages.indices.contains(index)
                ? PDFMetadata.bookmarkTitle(design.pages[index], number: index + 1) : nil
        }
        var unmarked = options
        unmarked.cropMarks = false
        let sheetHeight = Double(options.sheet.height)
        if options.fit == .several {
            let plan = severalPlan(design: design, indices: indices, options: options)
            var several: [CmykSheet] = []
            for (n, pages) in plan.sheets.enumerated() {
                let mirrored = plan.duplex && n % 2 == 1
                let cells = severalCells(design: design, pages: pages, cols: plan.cols, mirrored: mirrored, options: options)
                let marks = options.cropMarks ? severalMarks(cells.map(\.cell), options: options) : []
                several.append(CmykSheet(draw: { cg in
                    drawSeveral(design: design, pages: pages, cols: plan.cols, mirrored: mirrored,
                                options: unmarked, flatten: false, into: cg)
                }, trim: nil, bleed: nil, marks: marks, title: pages.first.flatMap(title)))
            }
            return several
        }
        let designed = Bleed.shown(design)
        var out: [CmykSheet] = []
        for index in indices {
            let page = design.pages[index]
            let pagePts = PrintLayout.pagePoints(size: design.size(for: page), dpi: design.effectiveDPI, bleed: options.bleed)
            for (n, placement) in placements(pagePoints: pagePts, options: options).enumerated() {
                let boxes = designed
                    ? PrintLayout.boxes(sheet: placement.sheetRect, source: placement.source, page: pagePts,
                                        bleed: options.bleed, sheetHeight: sheetHeight)
                    : nil
                let marks = options.cropMarks
                    ? PrintLayout.sheetMarks(sheet: placement.sheetRect, source: placement.source, page: pagePts, bleed: options.bleed)
                    : []
                // A poster's first sheet alone carries the page's bookmark.
                out.append(CmykSheet(draw: { cg in
                    drawSheet(design: design, page: page, pagePoints: pagePts, placement: placement,
                              options: unmarked, flatten: false, into: cg)
                }, trim: boxes?.trim, bleed: boxes?.bleed, marks: marks, title: n == 0 ? title(index) : nil))
            }
        }
        return out
    }

    /// A sheet of `size` points drawn by `draw` — set up as the PDF writer
    /// sets a page up, top left and y down — at 300 dpi onto white paper.
    /// Laid out in memory as 0xAARRGGBB words, as Android's bitmaps give
    /// them.
    @MainActor
    private static func sheetContext(_ size: CGSize, draw: @MainActor (CGContext) -> Void) -> CGContext? {
        let px = CmykPdf.pixels(size)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGContext(data: nil, width: px.width, height: px.height, bitsPerComponent: 8,
                                 bytesPerRow: px.width * 4, space: space, bitmapInfo: info),
              cg.data != nil else { return nil }
        cg.setFillColor(gray: 1, alpha: 1)
        cg.fill(CGRect(x: 0, y: 0, width: px.width, height: px.height))
        cg.saveGState()
        cg.translateBy(x: 0, y: CGFloat(px.height))
        cg.scaleBy(x: CGFloat(px.width) / size.width, y: -CGFloat(px.height) / size.height)
        UIGraphicsPushContext(cg)
        draw(cg)
        UIGraphicsPopContext()
        cg.restoreGState()
        return cg
    }

    /// The drawn sheet's pixels, read by CmykPdf a band of rows at a time —
    /// on whichever thread inks it, as nothing here needs the main actor.
    private static func sheetPixels(_ cg: CGContext) -> CmykPdf.Sheet {
        let width = cg.width, stride = cg.bytesPerRow
        return CmykPdf.Sheet(width: width, height: cg.height, rows: { top, count, into in
            // The context is kept for as long as its pixels are read.
            withExtendedLifetime(cg) {
                guard let base = cg.data else { return }
                for row in 0..<count {
                    let start = (top + row) * stride
                    for x in 0..<width {
                        let word = base.loadUnaligned(fromByteOffset: start + x * 4, as: UInt32.self)
                        into[row * width + x] = UInt32(littleEndian: word)
                    }
                }
            }
        })
    }
}
