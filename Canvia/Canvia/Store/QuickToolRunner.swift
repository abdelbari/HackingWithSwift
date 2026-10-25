// Home's quick file tools at work (QuickTools plans them): the files
// picked, copied in while the picker's access lasts, and what each tool
// makes of them — PDFs merged and split page by page as they are (PDFKit),
// compressed by drawing their pages afresh at the export compressor's 150
// dpi, pages drawn as pictures, photos laid on PDF pages, and pictures
// resized, converted or compressed. Each runs on the export queue under the
// export pill (ExportQueue), its files handed on as an export's are, and a
// failure is kept to try again (ExportFailure); nothing is saved as a
// design. The Android twin's QuickToolRunner.

import Foundation
import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers

enum QuickToolRunner {

    /// A file picked: where its copy is, the name it came with, and its
    /// pages (a PDF's, and each one's size in points) or its pixels (a
    /// picture's, as it is shown, turned upright).
    struct Picked: Identifiable, Equatable, Sendable {
        let id = UUID()
        var file: URL
        var name: String
        var pages: Int
        var width: Int
        var height: Int
        var pageSizes: [CGSize] = []

        var input: QuickTools.Input { QuickTools.Input(name: name, pages: pages) }
        var isPdf: Bool { !pageSizes.isEmpty }
    }

    /// What was chosen beyond the plan's options.
    struct Choices: Equatable, Sendable {
        var options = QuickTools.Options()
        var resize = QuickTools.Resize(longEdge: 1080)
        var paper = QuickTools.PhotoPaper.a4
        var margin = 0.0
        /// A JPEG's quality, 0 to 1.
        var quality = 0.85
        /// Compress a picture to 256 colours as a PNG rather than as a JPEG.
        var colours256 = false
        /// PDF to pictures: into the phone's photos.
        var toPhotos = false
    }

    /// Where picked files and made files wait: the caches, swept as an
    /// export's are.
    private static var folder: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quicktools", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: picking

    /// `urls` copied in, each read for its pages or pixels; one that does
    /// not read is left out. Off the main thread.
    static func pick(_ urls: [URL]) -> [Picked] {
        urls.compactMap(pickOne)
    }

    private static func pickOne(_ url: URL) -> Picked? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var name = url.lastPathComponent
        var ext = QuickTools.fileExtension(name)
        if ext.isEmpty {
            // A name with no extension takes the type it is, so the plan
            // reads it as what it is.
            ext = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.conforms(to: .pdf) == true ? "pdf" : "jpg"
            name += ".\(ext)"
        }
        let copy = folder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        guard (try? FileManager.default.copyItem(at: url, to: copy)) != nil else { return nil }
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: copy), pdf.pageCount > 0 else {
                try? FileManager.default.removeItem(at: copy)
                return nil
            }
            let sizes = (0..<pdf.pageCount).map { pdf.page(at: $0)?.bounds(for: .mediaBox).size ?? CGSize(width: 595, height: 842) }
            return Picked(file: copy, name: name, pages: sizes.count, width: 0, height: 0, pageSizes: sizes)
        }
        guard let size = pixelSize(copy) else {
            try? FileManager.default.removeItem(at: copy)
            return nil
        }
        return Picked(file: copy, name: name, pages: 1, width: size.width, height: size.height)
    }

    /// A picture's pixels as it is shown — turned upright by its EXIF
    /// orientation — from its header alone; nil for no picture.
    static func pixelSize(_ url: URL) -> QuickTools.Size? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, w > 0, h > 0 else { return nil }
        // Orientations 5 to 8 turn the picture a quarter.
        let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return orientation >= 5 ? QuickTools.Size(width: h, height: w) : QuickTools.Size(width: w, height: h)
    }

    // MARK: how big

    /// About how many bytes `tool` makes of `picked` with `choices`.
    static func estimate(_ tool: QuickTools.Tool, _ picked: [Picked], _ choices: Choices) -> Int {
        let plan = QuickTools.plan(tool, picked.map(\.input), choices.options)
        func pageSize(_ ref: QuickTools.Ref) -> CGSize {
            guard picked.indices.contains(ref.input), picked[ref.input].pageSizes.indices.contains(ref.page) else {
                return CGSize(width: 595, height: 842)
            }
            return picked[ref.input].pageSizes[ref.page]
        }
        return plan.outputs.reduce(0) { sum, out in sum + estimate(tool, out, picked, choices, pageSize) }
    }

    private static func estimate(_ tool: QuickTools.Tool, _ out: QuickTools.Output, _ picked: [Picked],
                                 _ choices: Choices, _ pageSize: (QuickTools.Ref) -> CGSize) -> Int {
        let ext = QuickTools.fileExtension(out.name)
        guard let first = out.pages.first, picked.indices.contains(first.input) else { return 0 }
        let one = picked[first.input]
        switch tool {
        case .merge, .split:
            return QuickTools.pdfBytes(out.pages.map(pageSize), dpi: QuickTools.pdfDPI, quality: 0.9)
        case .pdfToPictures:
            let p = pageSize(first)
            let w = Int(Double(p.width) * QuickTools.pdfDPI / 72), h = Int(Double(p.height) * QuickTools.pdfDPI / 72)
            return ext == "jpg" ? QuickTools.jpegBytes(width: w, height: h, quality: choices.quality)
                : QuickTools.pngBytes(width: w, height: h)
        case .photosToPdf:
            return out.pages.reduce(0) { sum, ref in
                guard picked.indices.contains(ref.input) else { return sum }
                let photo = picked[ref.input]
                return sum + ExportChoices.pdfSheetBytes + QuickTools.jpegBytes(width: photo.width, height: photo.height, quality: 0.9)
            }
        case .compress:
            if ext == "pdf" {
                return QuickTools.pdfBytes(one.pageSizes, dpi: ExportChoices.compressDPI, quality: ExportChoices.compressQuality)
            }
            return choices.colours256 ? QuickTools.pngBytes(width: one.width, height: one.height, colours256: true)
                : QuickTools.jpegBytes(width: one.width, height: one.height, quality: choices.quality)
        case .resize, .convert:
            let r = tool == .resize ? QuickTools.resized(width: one.width, height: one.height, choices.resize)
                : QuickTools.Resized(width: one.width, height: one.height, crop: .zero)
            return ext == "jpg" ? QuickTools.jpegBytes(width: r.width, height: r.height, quality: QuickTools.pictureQuality)
                : QuickTools.pngBytes(width: r.width, height: r.height)
        }
    }

    // MARK: on the queue

    /// `tool` run on `picked` on the export queue, under the pill: its
    /// files to the share sheet — Save to Files among it — or, PDF to
    /// pictures To Photos, into the phone's photos. Tried again as it was
    /// should it fail.
    @MainActor
    static func run(_ tool: QuickTools.Tool, _ picked: [Picked], _ choices: Choices) {
        let work: ExportQueue.Work = { report in
            let files = try await make(tool, picked, choices, report: report)
            guard tool == .pdfToPictures && choices.toPhotos else { return ExportQueue.Result(urls: files) }
            let outcome = try await PhotoSaver.save(files)
            return ExportQueue.Result(photosNote: outcome.message, photosSaved: outcome.anySaved)
        }
        let plan = QuickTools.plan(tool, picked.map(\.input), choices.options)
        ExportQueue.shared.enqueue(ExportQueue.Job(label: tool.title, designId: "",
                                                   title: plan.zip ?? plan.outputs.first?.name,
                                                   units: max(plan.outputs.count, 1), work: work))
    }

    /// What `tool` makes of `picked`, as files waiting in the caches — the
    /// ZIP alone when the plan has one, never when not `zipped`, as Open as
    /// a design asks: a ZIP is no design, its files are. Away from the main
    /// actor.
    static func make(_ tool: QuickTools.Tool, _ picked: [Picked], _ choices: Choices, zipped: Bool = true,
                     report progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> [URL] {
        let planned = QuickTools.plan(tool, picked.map(\.input), choices.options)
        let plan = zipped ? planned : QuickTools.Plan(outputs: planned.outputs)
        guard !plan.outputs.isEmpty else { throw DesignExporter.ExportError.renderFailed }
        let dir = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let made = try await Task.detached(priority: .userInitiated) { () throws -> [URL] in
            var files: [URL] = []
            let steps = Double(plan.outputs.count + (plan.zip == nil ? 0 : 1))
            for (n, out) in plan.outputs.enumerated() {
                try Task.checkCancellation()
                let url = dir.appendingPathComponent(out.name)
                try autoreleasepool {
                    try QuickToolRunner.write(tool, out, picked, choices, to: url)
                }
                files.append(url)
                progress(Double(n + 1) / steps)
            }
            return files
        }.value
        guard let zip = plan.zip else { return made }
        // The pictures in one ZIP, each under its own name, as an export's.
        let url = dir.appendingPathComponent(zip)
        try await Task.detached(priority: .userInitiated) {
            try ExportJobs.writeZip(made, to: url)
        }.value
        for file in made { try? FileManager.default.removeItem(at: file) }
        progress(1)
        return [url]
    }

    /// One file of the plan, written to `url`.
    private static func write(_ tool: QuickTools.Tool, _ out: QuickTools.Output, _ picked: [Picked],
                              _ choices: Choices, to url: URL) throws {
        let ext = QuickTools.fileExtension(out.name)
        switch tool {
        case .merge, .split:
            try copyPages(out.pages, picked, to: url)
        case .pdfToPictures:
            guard let ref = out.pages.first, let page = pdfPage(ref, picked),
                  let cg = drawn(page, dpi: QuickTools.pdfDPI, opaque: ext == "jpg") else {
                throw DesignExporter.ExportError.renderFailed
            }
            try DesignExporter.writePicture(cg, format: ext == "jpg" ? .jpeg : .png, quality: choices.quality,
                                            dpi: QuickTools.pdfDPI, to: url)
        case .photosToPdf:
            try photosPDF(out.pages.compactMap { picked.indices.contains($0.input) ? picked[$0.input] : nil },
                          choices, to: url)
        case .compress where ext == "pdf":
            guard let ref = out.pages.first, picked.indices.contains(ref.input) else { throw DesignExporter.ExportError.renderFailed }
            try compressedPDF(picked[ref.input], to: url)
        case .resize, .convert, .compress:
            guard let ref = out.pages.first, picked.indices.contains(ref.input) else { throw DesignExporter.ExportError.renderFailed }
            try picture(tool, picked[ref.input], choices, ext: ext, to: url)
        }
    }

    // MARK: PDFs

    private static func pdfPage(_ ref: QuickTools.Ref, _ picked: [Picked]) -> PDFPage? {
        guard picked.indices.contains(ref.input) else { return nil }
        return PDFDocument(url: picked[ref.input].file)?.page(at: ref.page)
    }

    /// The pages `refs` of their PDFs, as they are, in one PDF.
    private static func copyPages(_ refs: [QuickTools.Ref], _ picked: [Picked], to url: URL) throws {
        var documents: [Int: PDFDocument] = [:]
        let out = PDFDocument()
        for ref in refs {
            guard picked.indices.contains(ref.input) else { continue }
            if documents[ref.input] == nil { documents[ref.input] = PDFDocument(url: picked[ref.input].file) }
            guard let page = documents[ref.input]?.page(at: ref.page)?.copy() as? PDFPage else { continue }
            out.insert(page, at: out.pageCount)
        }
        guard out.pageCount > 0, out.write(to: url) else { throw DesignExporter.ExportError.encodeFailed }
    }

    /// A PDF page drawn as a picture at `dpi`, on white when `opaque`.
    private static func drawn(_ page: PDFPage, dpi: Double, opaque: Bool) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        let scale = dpi / 72
        let size = CGSize(width: max(1, (box.width * scale).rounded()), height: max(1, (box.height * scale).rounded()))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = opaque
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            if opaque {
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            let cg = ctx.cgContext
            // PDF space runs up from the bottom.
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: scale, y: -scale)
            cg.translateBy(x: -box.minX, y: -box.minY)
            page.draw(with: .mediaBox, to: cg)
        }
        return image.cgImage
    }

    /// Each page drawn afresh at the export compressor's 150 dpi as a JPEG
    /// of its quality (ExportChoices.compressDPI, compressQuality), as
    /// Compress PDF does for a design.
    private static func compressedPDF(_ file: Picked, to url: URL) throws {
        guard let pdf = PDFDocument(url: file.file), pdf.pageCount > 0 else { throw DesignExporter.ExportError.renderFailed }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        try renderer.writePDF(to: url) { ctx in
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let bounds = CGRect(origin: .zero, size: page.bounds(for: .mediaBox).size)
                ctx.beginPage(withBounds: bounds, pageInfo: [:])
                guard let cg = drawn(page, dpi: ExportChoices.compressDPI, opaque: true),
                      let data = UIImage(cgImage: cg).jpegData(compressionQuality: ExportChoices.compressQuality),
                      let jpeg = UIImage(data: data) else { continue }
                jpeg.draw(in: bounds)
            }
        }
    }

    /// A page for each photo, on the paper and with the margin chosen
    /// (QuickTools.photoPage).
    private static func photosPDF(_ photos: [Picked], _ choices: Choices, to url: URL) throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        try renderer.writePDF(to: url) { ctx in
            for photo in photos {
                guard let image = UIImage(contentsOfFile: photo.file.path) else { continue }
                let placed = QuickTools.photoPage(width: photo.width, height: photo.height, paper: choices.paper,
                                                  margin: choices.margin)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: placed.page), pageInfo: [:])
                image.draw(in: placed.box)
            }
        }
    }

    // MARK: pictures

    /// A picture resized, converted or compressed: drawn upright at its new
    /// size from the part kept, then written as `ext` — a compressed PNG in
    /// 256 colours (PngWriter).
    private static func picture(_ tool: QuickTools.Tool, _ file: Picked, _ choices: Choices, ext: String,
                                to url: URL) throws {
        guard let image = UIImage(contentsOfFile: file.file.path) else { throw DesignExporter.ExportError.renderFailed }
        let made = tool == .resize ? QuickTools.resized(width: file.width, height: file.height, choices.resize)
            : QuickTools.Resized(width: file.width, height: file.height,
                                 crop: CGRect(x: 0, y: 0, width: file.width, height: file.height))
        let size = CGSize(width: made.width, height: made.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = ext == "jpg"
        let drawn = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            if ext == "jpg" {
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
            }
            // The part kept stretched over the whole picture made.
            let sx = size.width / max(made.crop.width, 1)
            let sy = size.height / max(made.crop.height, 1)
            image.draw(in: CGRect(x: -made.crop.minX * sx, y: -made.crop.minY * sy,
                                  width: CGFloat(file.width) * sx, height: CGFloat(file.height) * sy))
        }
        guard let cg = drawn.cgImage else { throw DesignExporter.ExportError.renderFailed }
        if tool == .compress && choices.colours256 && ext == "png" {
            guard let rgba = PngWriter.rgba(of: cg),
                  let data = PngWriter.png(rgba: rgba, width: cg.width, height: cg.height, dpi: nil) else {
                throw DesignExporter.ExportError.encodeFailed
            }
            try data.write(to: url, options: .atomic)
            return
        }
        // Resize and Convert keep a JPEG's look; Compress takes the quality chosen.
        let quality = tool == .compress ? choices.quality : QuickTools.pictureQuality
        try DesignExporter.writePicture(cg, format: ext == "jpg" ? .jpeg : .png, quality: quality, dpi: nil, to: url)
    }
}
