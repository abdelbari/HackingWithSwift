// A Doc as the rest of the app draws it: laid out on its pages
// (Docs.paginated), its words measured as text boxes are and set in the
// brand kit's heading and body faces — what a thumbnail, a PDF, a print, a
// planned post and Convert to design take — and written as a Word document
// (DocxWriter). Anything but a Doc as it is. The Android twin's DocPages.

import SwiftUI
import UIKit

enum DocPages {

    /// The faces a Doc's words are set in: the kit in use's heading and
    /// body roles, each standing in for the other, or the default face.
    static func styles(_ fonts: BrandFonts = BrandKit.load().fonts) -> Docs.Styles {
        Docs.Styles(heading: fonts.heading ?? fonts.body, body: fonts.body ?? fonts.heading)
    }

    /// `design` laid out on pages when it is a Doc.
    static func drawn(_ design: Design) -> Design {
        Docs.isDoc(design) ? Docs.paginated(design, styles: styles()) : design
    }

    /// A picture or chart block as the PNG a Word document holds: the
    /// text's width across at twice its pixels, 0.6 of it tall, as the Doc
    /// lays it out, on white.
    @MainActor
    static func png(_ design: Design, _ block: DocBlock) -> Data? {
        guard let sheet = sheet(design, block) else { return nil }
        let renderer = ImageRenderer(content: PageRenderView(design: sheet, page: sheet.pages[0]))
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage?.pngData()
    }

    /// A picture or chart block alone on a sheet the text's width across
    /// and 0.6 of it tall, as the Doc lays it out: what the Word document's
    /// PNG and the editor's chart show. Nil for a block that draws nothing.
    static func sheet(_ design: Design, _ block: DocBlock) -> Design? {
        let setup = Docs.pageSetup(design)
        let width = Double(Docs.pageSize(setup).width) - 2 * Docs.margin(setup)
        let els = Docs.elements([block], unit: 0...0, x: 0, y: 0, width: width, styles: styles(),
                                heightFor: FontLibrary.layoutHeight(for:))
        guard !els.isEmpty else { return nil }
        var sheet = Design(title: design.title, width: width, height: (width * Docs.pictureRatio).rounded())
        sheet.pages = [Page(elements: els)]
        return sheet
    }

    /// The Word document's faces: the kit's heading and body families'
    /// names, Calibri for the default face.
    static func wordFaces() -> (heading: String, body: String) {
        let s = styles()
        func name(_ family: String?) -> String {
            guard let family, family != "sans" else { return "Calibri" }
            return FontLibrary.of(family).name
        }
        return (name(s.heading?.family), name(s.body?.family))
    }

    /// `design` written as a .docx at `url` (DocxWriter); a file that fails
    /// part-way is removed.
    @MainActor
    static func writeDocx(_ design: Design, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else { throw DesignExporter.ExportError.encodeFailed }
        defer { try? handle.close() }
        let faces = wordFaces()
        do {
            try DocxWriter.write(design, heading: faces.heading, body: faces.body,
                                 png: { png(design, $0) }, sink: { try handle.write(contentsOf: $0) })
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
