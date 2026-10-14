// What Export remembers: the pages chosen for each design, for as long as
// the app is open, and — with "Remember these settings" on — the last
// export's format, size, quality, background, page choice and PDF options,
// kept as JSON under @AppStorage "exportLast", the same keys as the Android
// twin's Prefs "export_last". The pages chosen by id are a design's own and
// never stored. And the PDF's own sums, as the Android twin's ExportPlan
// makes them: the notes pages it adds, the pixels a compressed PDF keeps of
// each photo, and the size the PDF row says it will come to.

import CoreGraphics
import Foundation

enum ExportChoices {

    /// The pages ticked in Choose…, by design id, for this session.
    static var chosenByDesign: [String: [String]] = [:]

    /// The pages ticked the first time: every page shown — hidden ones
    /// unticked.
    static func defaultChosen(_ design: Design) -> [String] {
        design.visiblePageIndices.map { design.pages[$0].id }
    }

    /// The pages ticked for `design`: as left this session, without any
    /// page since deleted, in the design's order; else the default.
    static func chosen(for design: Design) -> [String] {
        guard let kept = chosenByDesign[design.id] else { return defaultChosen(design) }
        let picked = Set(kept)
        return design.pages.map(\.id).filter { picked.contains($0) }
    }

    static func remember(_ ids: [String], for design: Design) {
        chosenByDesign[design.id] = ids
    }

    /// One page ticked or unticked, the rest kept in the design's order.
    static func toggled(_ ids: [String], _ id: String, in design: Design) -> [String] {
        var picked = Set(ids)
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
        return design.pages.map(\.id).filter { picked.contains($0) }
    }

    /// The range as an export takes it: a one-page design has no Pages row
    /// to change it, so it is that page — even hidden, or with nothing
    /// ticked — as the Android twin's ExportPlan.pagesFor has it.
    static func exportRange(_ range: DesignExporter.PageRange, in design: Design) -> DesignExporter.PageRange {
        design.pages.count == 1 ? .current : range
    }

    /// "3 of 8 pages", as the rows say a choice.
    static func countText(_ chosen: Int, of total: Int) -> String {
        "\(chosen) of \(total) \(total == 1 ? "page" : "pages")"
    }

    // MARK: in the background — the Android twin's ExportPlan words

    /// Asked when the sheet is closed with an export running; Keep is the
    /// default.
    static let keepQuestion = "Keep exporting in the background?"
    static let keep = "Keep"
    static let stop = "Stop"

    /// The pill while an export runs: "Rendering the video 42%".
    static func pillText(label: String, fraction: Double) -> String {
        "\(label) \(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// "1 more waiting", under the progress while others wait their turn.
    static func waitingText(_ count: Int) -> String {
        "\(count) more waiting"
    }

    /// The notifications: done, with Share and Open; failed; paused.
    static let readyTitle = "Your export is ready"
    static let failedTitle = "Export failed"
    static let pausedTitle = "Export paused"
    static let paused = "Paused — return to Canvia to finish"
    static let shareAction = "Share"
    static let openAction = "Open"

    /// "Export failed: <why>", in the sheet or the pill.
    static func failedText(_ reason: String) -> String {
        "Export failed: \(reason)"
    }

    /// Said when a video's music could not be mixed in.
    static let musicLost = "Couldn't add the music, so it has none."

    // MARK: PDF options

    /// What a sheet of the PDF holds: a page, or the notes page after it.
    enum PDFSheet: Equatable {
        case page(Int)
        case notes(Int)
    }

    /// Whether a page has notes to print: any that are more than spaces.
    static func hasNotes(_ page: Page) -> Bool {
        page.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    /// The PDF's sheets, in order: each page of `indices`, and — with
    /// "Include notes" — a notes page straight after each page that has
    /// notes, so there are as many notes pages as pages with notes.
    static func pdfSheets(design: Design, indices: [Int], notes: Bool) -> [PDFSheet] {
        indices.filter { design.pages.indices.contains($0) }.flatMap { index -> [PDFSheet] in
            notes && hasNotes(design.pages[index]) ? [.page(index), .notes(index)] : [.page(index)]
        }
    }

    /// A notes page: the page's picture fitted in its top third, then the
    /// notes below it in the body font, the app's "sans", at 14 pt,
    /// wrapped. Its margin is 6% of its shorter side.
    static let notesFamily = "sans"
    static let notesPointSize = 14.0
    static let notesMarginShare = 0.06

    /// "Compress": every photo at 150 dpi of the size it prints at, as JPEG
    /// at 0.75; nothing else is flattened.
    static let compressDPI = 150.0
    static let compressQuality = 0.75
    /// What a PDF sheet costs before its photos, in the size estimate.
    static let pdfSheetBytes = 30_000

    /// Said where the Compress switch is, on the print-ready PDF.
    static let printKeepsQuality = "Print-ready PDFs keep full quality"

    /// The pixels a photo of `natural` pixels keeps in a compressed PDF:
    /// 150 for each inch it prints across — its natural shape scaled to
    /// cover its `box` (page pixels), as it is drawn, and zoomed by its
    /// crop, at `pointsPerPixel` of the design — never more than it has.
    /// Each side to the nearest pixel, a half rounded up.
    static func compressedPixels(natural: CGSize, box: CGSize, cropScale: Double,
                                 pointsPerPixel: Double) -> CGSize {
        let nw = Double(natural.width), nh = Double(natural.height)
        guard nw > 0, nh > 0 else { return natural }
        let cover = max(Double(box.width) / nw, Double(box.height) / nh) * max(cropScale, 1)
        // Inches each of its pixels prints at, times the dots wanted an inch.
        let keep = min(1, compressDPI * cover * pointsPerPixel / 72)
        return CGSize(width: max(1, (nw * keep).rounded()), height: max(1, (nh * keep).rounded()))
    }

    /// A photo the PDF draws: its source, the box it fills in page pixels,
    /// and its crop's zoom.
    struct PDFPhoto: Equatable {
        var src: String
        var box: CGSize
        var cropScale: Double
    }

    /// Whether a picture source is a photo that compressing re-encodes: one
    /// of the library's or your uploads, not a clip, an animated picture or
    /// a code drawn on the fly.
    static func isPhoto(_ src: String?) -> Bool {
        guard let src, src.hasPrefix("media:") || src.hasPrefix("asset:") else { return false }
        return !VideoStore.isVideo(src) && !AnimStore.isAnim(src)
    }

    /// The photos page `page` draws: its background photo, then each photo
    /// on it, the master's behind it first.
    static func photos(on page: Page, in design: Design) -> [PDFPhoto] {
        var out: [PDFPhoto] = []
        if case .image(let src) = page.background, isPhoto(src) {
            out.append(PDFPhoto(src: src, box: design.size(for: page), cropScale: 1))
        }
        for el in design.drawnElements(on: page) where el.type == .image && isPhoto(el.src) {
            out.append(PDFPhoto(src: el.src ?? "", box: CGSize(width: el.w, height: el.h), cropScale: el.cropScale ?? 1))
        }
        return out
    }

    /// The PDF's size, roughly: 30 KB a sheet, notes pages counted, and
    /// each photo as a JPEG at 0.75 of the pixels it keeps — the downsampled
    /// pixels when compressing, all of them when not. `pixelSize` gives a
    /// photo's pixels, nil for one not on this phone.
    static func estimatedPDFBytes(design: Design, indices: [Int], notes: Bool, compress: Bool,
                                  pixelSize: (String) -> CGSize?) -> Int {
        var bytes = pdfSheets(design: design, indices: indices, notes: notes).count * pdfSheetBytes
        for index in indices where design.pages.indices.contains(index) {
            for photo in photos(on: design.pages[index], in: design) {
                guard let natural = pixelSize(photo.src) else { continue }
                let kept = compress
                    ? compressedPixels(natural: natural, box: photo.box, cropScale: photo.cropScale,
                                       pointsPerPixel: design.pointsPerPixel)
                    : natural
                bytes += DesignExporter.jpegBytes(pixels: Double(kept.width) * Double(kept.height),
                                                  quality: compressQuality)
            }
        }
        return bytes
    }

    /// "About 3.2 MB", or "About 450 KB" under a megabyte — decimal, as a
    /// file's size is said.
    static func sizeText(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return String(format: "About %.1f MB", Double(bytes) / 1_000_000) }
        return "About \(max(1, Int((Double(bytes) / 1000).rounded()))) KB"
    }
}

/// The last export, as "Remember these settings" keeps it:
/// {"format":"png","scale":2,"longEdge":null,"jpegQuality":0.85,
///  "transparent":false,"pages":"all","pdfNotes":false,"pdfCompress":false}.
struct ExportLast: Codable, Equatable {
    /// "png" | "jpg" | "pdf" | "print" | "svg" | "pptx" | "mp4" | "gif".
    var format: String
    var scale: Double
    /// The long edge typed, in pixels; nil when the scale applies.
    var longEdge: Int?
    var jpegQuality: Double
    var transparent: Bool
    /// "all" | "current" | "chosen".
    var pages: String
    /// The PDF's "Include notes" and "Compress".
    var pdfNotes = false
    var pdfCompress = false

    static let key = "exportLast"
    static let formats: Set<String> = ["png", "jpg", "pdf", "print", "svg", "pptx", "mp4", "gif"]
    static let pageChoices: Set<String> = ["all", "current", "chosen"]

    private enum CodingKeys: String, CodingKey {
        case format, scale, longEdge, jpegQuality, transparent, pages, pdfNotes, pdfCompress
    }

    init(format: String, scale: Double, longEdge: Int?, jpegQuality: Double, transparent: Bool, pages: String,
         pdfNotes: Bool = false, pdfCompress: Bool = false) {
        self.format = format
        self.scale = scale
        self.longEdge = longEdge
        self.jpegQuality = jpegQuality
        self.transparent = transparent
        self.pages = pages
        self.pdfNotes = pdfNotes
        self.pdfCompress = pdfCompress
    }

    /// Lenient, as a setting from another build may be: what does not read
    /// takes the sheet's own default.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = (try? c.decode(String.self, forKey: .format)) ?? "png"
        format = Self.formats.contains(f) ? f : "png"
        scale = min(max((try? c.decode(Double.self, forKey: .scale)) ?? 2, 1), 3)
        longEdge = (try? c.decode(Int.self, forKey: .longEdge)).flatMap { $0 >= 16 ? $0 : nil }
        jpegQuality = min(max((try? c.decode(Double.self, forKey: .jpegQuality)) ?? 0.92, 0.3), 1)
        transparent = (try? c.decode(Bool.self, forKey: .transparent)) ?? false
        let p = (try? c.decode(String.self, forKey: .pages)) ?? "all"
        pages = Self.pageChoices.contains(p) ? p : "all"
        // Missing, or not a true or false, is off.
        pdfNotes = (try? c.decode(Bool.self, forKey: .pdfNotes)) ?? false
        pdfCompress = (try? c.decode(Bool.self, forKey: .pdfCompress)) ?? false
    }

    /// Every key written, the long edge as null when there is none, in the
    /// order the Android twin writes them.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encode(scale, forKey: .scale)
        if let longEdge { try c.encode(longEdge, forKey: .longEdge) } else { try c.encodeNil(forKey: .longEdge) }
        try c.encode(jpegQuality, forKey: .jpegQuality)
        try c.encode(transparent, forKey: .transparent)
        try c.encode(pages, forKey: .pages)
        try c.encode(pdfNotes, forKey: .pdfNotes)
        try c.encode(pdfCompress, forKey: .pdfCompress)
    }

    /// As stored: every key, in the order above, written out here rather
    /// than left to JSONEncoder's ordering, so the text is the Android
    /// twin's character for character — whole numbers without ".0".
    var json: String {
        let edge = longEdge.map { String($0) } ?? "null"
        let fields: [String] = [
            "\"format\":" + Self.quoted(format),
            "\"scale\":" + Self.number(scale),
            "\"longEdge\":" + edge,
            "\"jpegQuality\":" + Self.number(jpegQuality),
            "\"transparent\":" + String(transparent),
            "\"pages\":" + Self.quoted(pages),
            "\"pdfNotes\":" + String(pdfNotes),
            "\"pdfCompress\":" + String(pdfCompress),
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// A number as JSON writes it: 2 rather than 2.0, 0.85 as it is.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }

    /// A string as JSON writes it, quotes and backslashes escaped.
    static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    /// The stored text read back; nil for none, or for text that is not
    /// one.
    static func read(_ text: String) -> ExportLast? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ExportLast.self, from: data)
    }
}
