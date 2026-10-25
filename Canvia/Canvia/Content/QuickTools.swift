// Home's quick file tools — Merge PDFs, Split a PDF, PDF to pictures,
// Photos to PDF, Resize, Convert and Compress a picture — planned before any
// file is read or written: what each makes, called what, from which pages of
// which file (plan); how a picture is resized (resized); where a photo sits
// on a PDF page (photoPage); and about how big the result is. Nothing here
// is saved as a design. The Android twin's QuickTools (core/content/
// QuickTools.kt) by the same rules, with the shared fixture
// Fixtures/quick-tools.json.

import CoreGraphics
import Foundation

enum QuickTools {

    /// The tools, in Home's order; the raw value is each one's name in the
    /// fixture.
    enum Tool: String, CaseIterable, Identifiable, Sendable {
        case merge
        case split
        case pdfToPictures
        case photosToPdf
        case resize
        case convert
        case compress

        var id: String { rawValue }

        /// What Home's Tools row calls it.
        var title: String {
            switch self {
            case .merge: return tr("Merge PDFs")
            case .split: return tr("Split a PDF")
            case .pdfToPictures: return tr("PDF to pictures")
            case .photosToPdf: return tr("Photos to PDF")
            case .resize: return tr("Resize a picture")
            case .convert: return tr("Convert a picture")
            case .compress: return tr("Compress")
            }
        }

        var systemImage: String {
            switch self {
            case .merge: return "doc.on.doc"
            case .split: return "scissors"
            case .pdfToPictures: return "photo.on.rectangle"
            case .photosToPdf: return "doc.richtext"
            case .resize: return "arrow.up.left.and.arrow.down.right"
            case .convert: return "arrow.triangle.2.circlepath"
            case .compress: return "arrow.down.right.and.arrow.up.left"
            }
        }
    }

    /// A file picked: its name as it came — "Report.pdf" — and, for a PDF,
    /// how many pages it has; a picture is one page.
    struct Input: Equatable, Sendable {
        var name: String
        var pages: Int = 1
    }

    /// What was chosen. `pages`: the pages of the one PDF to split or turn
    /// into pictures, counted from 0; nil for every page. `each`: Split
    /// makes a PDF of each page chosen rather than one of them all.
    /// `format`: the pictures' type, "png" or "jpg" — what Convert and
    /// Compress make, and what PDF to pictures draws; nil for Resize keeps a
    /// picture's own type, Convert and PDF to pictures make a PNG and
    /// Compress a JPEG, as its JPEG quality is what is first chosen. `zip`:
    /// PDF to pictures' several pictures as one ZIP.
    struct Options: Equatable, Sendable {
        var pages: [Int]? = nil
        var each = false
        var format: String? = nil
        var zip = false
    }

    /// Page `page` of input `input`, both counted from 0.
    struct Ref: Equatable, Sendable {
        var input: Int
        var page: Int
    }

    /// One file made: its name and the pages in it, in order.
    struct Output: Equatable, Sendable {
        var name: String
        var pages: [Ref]
    }

    /// What a tool makes: its files, and the ZIP they go in, if they do.
    struct Plan: Equatable, Sendable {
        var outputs: [Output]
        var zip: String? = nil
    }

    /// What `tool` makes of `inputs` with `options` — names after the first
    /// file's, as an export is named after its design:
    ///
    ///  - Merge PDFs: "<first file> merged.pdf", every page of each, in the
    ///    order picked.
    ///  - Split a PDF: the pages chosen as "<file> split.pdf"; or, `each`,
    ///    each as "<file> page <n>.pdf", together in "<file> split.zip"
    ///    when there are several.
    ///  - PDF to pictures: each page chosen as "<file>-<n>.<png|jpg>" — no
    ///    "-<n>" when there is only one — in "<file>.zip" when `zip` and
    ///    there are several.
    ///  - Photos to PDF: "<first file>.pdf", a page for each photo.
    ///  - Resize: "<file> resized.<type>" for each picture.
    ///  - Convert: "<file>.<format>" for each.
    ///  - Compress: "<file> compressed.pdf" for a PDF, "<file>
    ///    compressed.<jpg|png>" for a picture — a JPEG unless `format` says.
    ///
    /// "<file>" is a file's name without its last extension, trimmed —
    /// "file" when nothing is left. A name already made gets " 2", " 3"
    /// before its extension. A page number <n> counts from 1. Pages chosen
    /// are kept in order, once each, those past the end left out.
    static func plan(_ tool: Tool, _ inputs: [Input], _ options: Options = Options()) -> Plan {
        guard let firstInput = inputs.first else { return Plan(outputs: []) }
        let first = stem(firstInput.name)
        var made: [Output] = []
        var names = Set<String>()
        func add(_ name: String, _ pages: [Ref]) {
            made.append(Output(name: unique(name, &names), pages: pages))
        }
        var zip: String?
        switch tool {
        case .merge:
            add("\(first) merged.pdf", inputs.enumerated().flatMap { i, input in
                (0..<max(input.pages, 0)).map { Ref(input: i, page: $0) }
            })
        case .split:
            let pages = chosen(firstInput, options.pages)
            if options.each {
                for p in pages { add("\(first) page \(p + 1).pdf", [Ref(input: 0, page: p)]) }
                if pages.count > 1 { zip = "\(first) split.zip" }
            } else if !pages.isEmpty {
                add("\(first) split.pdf", pages.map { Ref(input: 0, page: $0) })
            }
        case .pdfToPictures:
            let pages = chosen(firstInput, options.pages)
            let ext = pictureType(options.format ?? "png")
            for p in pages { add(first + pageSuffix(p, files: pages.count) + ".\(ext)", [Ref(input: 0, page: p)]) }
            if options.zip && pages.count > 1 { zip = "\(first).zip" }
        case .photosToPdf:
            add("\(first).pdf", inputs.indices.map { Ref(input: $0, page: 0) })
        case .resize:
            for (i, input) in inputs.enumerated() {
                add("\(stem(input.name)) resized.\(pictureType(options.format ?? fileExtension(input.name)))",
                    [Ref(input: i, page: 0)])
            }
        case .convert:
            for (i, input) in inputs.enumerated() {
                add("\(stem(input.name)).\(pictureType(options.format ?? "png"))", [Ref(input: i, page: 0)])
            }
        case .compress:
            for (i, input) in inputs.enumerated() {
                if isPdf(input.name) {
                    add("\(stem(input.name)) compressed.pdf", (0..<max(input.pages, 0)).map { Ref(input: i, page: $0) })
                } else {
                    add("\(stem(input.name)) compressed.\(pictureType(options.format ?? "jpg"))",
                        [Ref(input: i, page: 0)])
                }
            }
        }
        return Plan(outputs: made, zip: zip)
    }

    /// "-<n>" after a picture's name when there are several, n from 1;
    /// nothing for one — as an export names its pages.
    static func pageSuffix(_ pageIndex: Int, files: Int) -> String {
        files > 1 ? "-\(pageIndex + 1)" : ""
    }

    /// `pages` of `input` kept in order, once each, within it; every page
    /// for nil.
    private static func chosen(_ input: Input, _ pages: [Int]?) -> [Int] {
        let all = Array(0..<max(input.pages, 0))
        guard let pages else { return all }
        return Array(Set(pages.filter { $0 >= 0 && $0 < input.pages })).sorted()
    }

    /// A file's name without its last extension, trimmed; "file" for none.
    static func stem(_ name: String) -> String {
        let base = name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? name
        var cut = base
        if let dot = base.lastIndex(of: "."), dot > base.startIndex { cut = String(base[..<dot]) }
        let trimmed = cut.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "file" : trimmed
    }

    /// A file's extension, lower case; "" for none.
    static func fileExtension(_ name: String) -> String {
        let base = name.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? name
        guard let dot = base.lastIndex(of: "."), dot > base.startIndex else { return "" }
        return String(base[base.index(after: dot)...]).lowercased()
    }

    static func isPdf(_ name: String) -> Bool { fileExtension(name) == "pdf" }

    /// The type a picture is written as: a JPEG — or a HEIC, which is read
    /// but never written — as "jpg", anything else as "png".
    static func pictureType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg", "heic", "heif": return "jpg"
        default: return "png"
        }
    }

    /// `name`, or with " 2", " 3"… before its extension when `taken` has
    /// it; added to `taken`.
    private static func unique(_ name: String, _ taken: inout Set<String>) -> String {
        var n = 1
        var candidate = name
        while taken.contains(candidate) {
            n += 1
            if let dot = name.lastIndex(of: "."), dot > name.startIndex {
                candidate = String(name[..<dot]) + " \(n)" + String(name[dot...])
            } else {
                candidate = "\(name) \(n)"
            }
        }
        taken.insert(candidate)
        return candidate
    }

    // MARK: resizing a picture

    /// How a picture is resized: its longer edge to `longEdge` pixels, or
    /// to `percent` of its size, or to `size` — fitted inside it, its shape
    /// kept, or, `cover`, filling it and cut to it, centred.
    struct Resize: Equatable, Sendable {
        var longEdge: Int? = nil
        var percent: Double? = nil
        var size: Size? = nil
        var cover = false
    }

    /// A size in whole pixels.
    struct Size: Hashable, Sendable {
        var width: Int
        var height: Int
    }

    /// The picture made: `width` × `height` pixels from the part `crop` of
    /// the original — all of it unless covering.
    struct Resized: Equatable, Sendable {
        var width: Int
        var height: Int
        var crop: CGRect
    }

    /// A `width` × `height` picture resized as `resize` says; each edge
    /// rounded to a whole pixel, halves up, at least 1. Covering `size`,
    /// the part kept is the largest of its shape, centred.
    static func resized(width: Int, height: Int, _ resize: Resize) -> Resized {
        let whole = CGRect(x: 0, y: 0, width: width, height: height)
        func px(_ v: Double) -> Int { max(1, Int((v + 0.5).rounded(.down))) }
        let w = Double(width), h = Double(height)
        if let edge = resize.longEdge {
            let s = Double(edge) / Double(max(width, height, 1))
            return Resized(width: px(w * s), height: px(h * s), crop: whole)
        }
        if let percent = resize.percent {
            let s = percent / 100
            return Resized(width: px(w * s), height: px(h * s), crop: whole)
        }
        guard let target = resize.size else { return Resized(width: width, height: height, crop: whole) }
        if resize.cover {
            let want = Double(target.width) / Double(max(target.height, 1))
            let crop: CGRect
            if w / max(h, 1) > want {
                let cw = h * want
                crop = CGRect(x: (w - cw) / 2, y: 0, width: cw, height: h)
            } else {
                let ch = w / want
                crop = CGRect(x: 0, y: (h - ch) / 2, width: w, height: ch)
            }
            return Resized(width: max(1, target.width), height: max(1, target.height), crop: crop)
        }
        let s = min(Double(target.width) / max(w, 1), Double(target.height) / max(h, 1))
        return Resized(width: px(w * s), height: px(h * s), crop: whole)
    }

    // MARK: photos on PDF pages

    /// The paper Photos to PDF puts each photo on: A4 or Letter — turned
    /// landscape for a landscape photo — or the photo's own shape.
    enum PhotoPaper: String, CaseIterable, Identifiable, Sendable {
        case a4, letter, fit

        var id: String { rawValue }

        /// In points; none for Fit.
        var size: CGSize? {
            switch self {
            case .a4: return CGSize(width: 595, height: 842)
            case .letter: return CGSize(width: 612, height: 792)
            case .fit: return nil
            }
        }

        var title: String {
            switch self {
            case .a4: return "A4"
            case .letter: return "Letter"
            case .fit: return tr("Fit to photo")
            }
        }
    }

    /// The longer edge of a Fit page, before its margins, in points: an
    /// A4's.
    static let fitLongEdge = 842.0

    /// The margins Photos to PDF offers, in points: none, a quarter of an
    /// inch, half an inch.
    static let margins: [Double] = [0, 18, 36]

    /// The page a `width` × `height` photo goes on, in points, and where it
    /// sits there: on `paper` — portrait, or landscape when the photo is
    /// wider than tall — within `margin` of each edge, as large as fits and
    /// centred; on a Fit page its own shape, `fitLongEdge` along its longer
    /// side, with `margin` all round.
    static func photoPage(width: Int, height: Int, paper: PhotoPaper, margin: Double) -> (page: CGSize, box: CGRect) {
        let w = Double(max(1, width))
        let h = Double(max(1, height))
        guard let size = paper.size else {
            let s = fitLongEdge / max(w, h)
            return (CGSize(width: w * s + 2 * margin, height: h * s + 2 * margin),
                    CGRect(x: margin, y: margin, width: w * s, height: h * s))
        }
        let page = w > h ? CGSize(width: size.height, height: size.width) : size
        let roomW = max(1, Double(page.width) - 2 * margin)
        let roomH = max(1, Double(page.height) - 2 * margin)
        let s = min(roomW / w, roomH / h)
        let bw = w * s, bh = h * s
        return (page, CGRect(x: (Double(page.width) - bw) / 2, y: (Double(page.height) - bh) / 2, width: bw, height: bh))
    }

    // MARK: how big

    /// The resolution a PDF's pages are drawn at when merged, split or
    /// turned into pictures: finer than the export compressor's.
    static let pdfDPI = 200.0

    /// A JPEG's bytes for `width` × `height` pixels at `quality`, 0 to 1:
    /// 0.15 + 2.6 q² bits a pixel, as the PDF estimate counts them.
    static func jpegBytes(width: Int, height: Int, quality: Double) -> Int {
        Int(Double(width) * Double(height) * (0.15 + 2.6 * quality * quality) / 8)
    }

    /// A PNG's bytes, about: two a pixel — one in 256 colours, half of one.
    static func pngBytes(width: Int, height: Int, colours256: Bool = false) -> Int {
        width * height * (colours256 ? 1 : 4) / 2
    }

    /// A PDF's bytes for pages `pages` in points, each drawn at `dpi` as a
    /// JPEG of `quality`: ExportChoices.pdfSheetBytes a page and its
    /// picture.
    static func pdfBytes(_ pages: [CGSize], dpi: Double, quality: Double) -> Int {
        pages.reduce(0) { sum, p in
            sum + ExportChoices.pdfSheetBytes
                + jpegBytes(width: Int(Double(p.width) * dpi / 72), height: Int(Double(p.height) * dpi / 72), quality: quality)
        }
    }
}
