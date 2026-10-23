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
        tr("%d of %@", chosen, trn("%d page|%d pages", total))
    }

    // MARK: in the background — the Android twin's ExportPlan words

    /// Asked when the sheet is closed with an export running; Keep is the
    /// default.
    static let keepQuestion = tr("Keep exporting in the background?")
    static let keep = tr("Keep")
    static let stop = tr("Stop")

    /// The pill while an export runs: "Rendering the video 42%".
    static func pillText(label: String, fraction: Double) -> String {
        "\(label) \(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    /// "1 more waiting", under the progress while others wait their turn.
    static func waitingText(_ count: Int) -> String {
        trn("%d more waiting|%d more waiting", count)
    }

    /// The notifications: done, with Share and Open; failed; paused.
    static let readyTitle = tr("Your export is ready")
    static let failedTitle = tr("Export failed")
    static let pausedTitle = tr("Export paused")
    static let paused = tr("Paused — return to Canvia to finish")
    static let shareAction = tr("Share")
    static let openAction = tr("Open")

    /// "Export failed: <why>", in the sheet or the pill.
    static func failedText(_ reason: String) -> String {
        tr("Export failed: %@", reason)
    }

    /// Said when a video's music could not be mixed in.
    static let musicLost = tr("Couldn't add the music, so it has none.")

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
    /// wrapped, in #1f2430 — laid out by the Android twin's PdfNotes
    /// numbers, so the same design is the same file on either phone.
    static let notesFamily = "sans"
    static let notesPointSize = 14.0
    static let notesColor = "#1f2430"

    /// The margin round a notes page: a twelfth of its shorter side.
    static func notesMargin(_ size: CGSize) -> Double {
        Double(min(size.width, size.height)) / 12
    }

    /// Where the page's picture goes on its notes page of `size`: fitted
    /// into the top third inside the margin — (m, m) to the third — at the
    /// top of it, centred across.
    static func notesThumbnail(_ size: CGSize) -> CGRect {
        let m = notesMargin(size)
        let w = Double(size.width), h = Double(size.height)
        guard w > 0, h > 0 else { return .zero }
        let boxW = w - 2 * m, boxH = h / 3 - m
        let scale = max(0, min(boxW / w, boxH / h))
        let fitted = CGSize(width: w * scale, height: h * scale)
        return CGRect(x: m + boxW / 2 - Double(fitted.width) / 2, y: m,
                      width: Double(fitted.width), height: Double(fitted.height))
    }

    /// The notes' box: across the page inside the margin, from half a
    /// margin under the top third down to the bottom margin.
    static func notesTextBox(_ size: CGSize) -> CGRect {
        let m = notesMargin(size)
        let w = Double(size.width), h = Double(size.height)
        let top = h / 3 + m / 2
        return CGRect(x: m, y: top, width: w - 2 * m, height: max(1, h - m - top))
    }

    /// "Compress": every photo at 150 dpi of the size it prints at, as JPEG
    /// at 0.75; nothing else is flattened.
    static let compressDPI = 150.0
    static let compressQuality = 0.75
    /// What a PDF sheet costs before its photos, in the size estimate.
    static let pdfSheetBytes = 30_000

    /// Said where the Compress switch is, on the print-ready PDF.
    static let printKeepsQuality = tr("Print-ready PDFs keep full quality")

    /// The pixels a photo of `natural` pixels keeps in a compressed PDF:
    /// 150 for each inch it prints across at its largest use in `uses` —
    /// its natural shape scaled to cover the box (page pixels), as it is
    /// drawn and cropped, and zoomed by its crop — at the design's `dpi`;
    /// never more than it has. Each side to the nearest pixel, a half up.
    /// The Android twin's ExportPlan.compressedPixels, sum for sum: a
    /// 4000 × 3000 photo in an 800 × 800 frame at 96 dpi keeps 1667 × 1250.
    static func compressedPixels(natural: CGSize, uses: [PDFPhoto], dpi: Double) -> CGSize {
        let nw = Double(natural.width), nh = Double(natural.height)
        guard nw > 0, nh > 0, dpi > 0 else { return natural }
        let covers = uses.map { max(Double($0.box.width) / nw, Double($0.box.height) / nh) * max($0.cropScale, 1) }
        guard let cover = covers.max() else { return natural }
        let keep = min(1, compressDPI / dpi * cover)
        return CGSize(width: max(1, (nw * keep).rounded()), height: max(1, (nh * keep).rounded()))
    }

    /// A photo the PDF draws: the box it fills in page pixels — a frame,
    /// or the page for one behind it — and its crop's zoom.
    struct PDFPhoto: Equatable {
        var box: CGSize
        var cropScale: Double = 1
    }

    /// Whether a picture source is a photo that compressing re-encodes: one
    /// of the library's or your uploads, not a clip, an animated picture or
    /// a code drawn on the fly.
    static func isPhoto(_ src: String?) -> Bool {
        guard let src, src.hasPrefix("media:") || src.hasPrefix("asset:") else { return false }
        return !VideoStore.isVideo(src) && !AnimStore.isAnim(src)
    }

    /// Every photo the pages of `indices` draw, by source in the order first
    /// met, with each box it fills there: a page's background photo, then
    /// each photo on it, the master's behind it first. By source, so a
    /// photo used twice is kept once, as a PDF holds it.
    static func pdfPhotos(design: Design, indices: [Int]) -> [(src: String, uses: [PDFPhoto])] {
        var order: [String] = []
        var uses: [String: [PDFPhoto]] = [:]
        func add(_ src: String, _ photo: PDFPhoto) {
            if uses[src] == nil { order.append(src) }
            uses[src, default: []].append(photo)
        }
        for index in indices where design.pages.indices.contains(index) {
            let page = design.pages[index]
            if case .image(let src) = page.background, isPhoto(src) {
                add(src, PDFPhoto(box: design.size(for: page)))
            }
            for el in design.drawnElements(on: page) where el.type == .image && isPhoto(el.src) {
                add(el.src ?? "", PDFPhoto(box: CGSize(width: el.w, height: el.h), cropScale: el.cropScale ?? 1))
            }
        }
        return order.map { (src: $0, uses: uses[$0] ?? []) }
    }

    /// A JPEG's bits a pixel at compressQuality, as the estimate counts
    /// them on both phones.
    static let compressedBitsPerPixel = 0.15 + 2.6 * compressQuality * compressQuality

    /// The PDF's size, roughly, by the Android twin's
    /// ExportPlan.estimatedPdfBytes rule, byte for byte: 30 KB a sheet,
    /// notes pages counted, and each photo once, by source — compressed,
    /// its kept pixels (compressedPixels) as a JPEG at 0.75, at
    /// compressedBitsPerPixel; else all its pixels, three bytes each, as a
    /// PDF writer is handed them; no floor. `pixelSize` gives a photo's
    /// pixels, nil for one not on this phone, which is not counted.
    static func estimatedPDFBytes(design: Design, indices: [Int], notes: Bool, compress: Bool,
                                  pixelSize: (String) -> CGSize?) -> Int {
        var bytes = pdfSheets(design: design, indices: indices, notes: notes).count * pdfSheetBytes
        for photo in pdfPhotos(design: design, indices: indices) {
            guard let natural = pixelSize(photo.src), natural.width > 0, natural.height > 0 else { continue }
            if compress {
                let kept = compressedPixels(natural: natural, uses: photo.uses, dpi: design.effectiveDPI)
                bytes += Int(Double(kept.width) * Double(kept.height) * compressedBitsPerPixel / 8)
            } else {
                bytes += Int(natural.width) * Int(natural.height) * 3
            }
        }
        return bytes
    }

    /// A photo's pixels as the size estimate wants them, from its file's
    /// header alone — no decode — so the Export sheet can ask off the main
    /// thread: an upload's as stored, a library picture's PhotoLibrary.size.
    static func photoPixelSize(_ src: String) -> CGSize? {
        if src.hasPrefix("media:") { return MediaStore.pixelSize(String(src.dropFirst("media:".count))) }
        if src.hasPrefix("asset:") { return PhotoLibrary.size }
        return nil
    }

    /// "About 3.2 MB", or "About 450 KB" under a megabyte — decimal, as a
    /// file's size is said.
    static func sizeText(_ bytes: Int) -> String {
        if bytes >= 1_000_000 { return tr("About %@ MB", String(format: "%.1f", Double(bytes) / 1_000_000)) }
        return tr("About %d KB", max(1, Int((Double(bytes) / 1000).rounded())))
    }
}

/// The last export, as "Remember these settings" keeps it:
/// {"format":"png","scale":2.0,"longEdge":null,"jpegQuality":0.85,
///  "transparent":false,"pages":"all","pdfNotes":false,"pdfCompress":false,
///  "pptxStyledText":"editable","suggested":false,"pdfBookmarks":true}.
/// A missing "pptxStyledText" is "editable".
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
    /// The PowerPoint's "Styled text": "editable" (the closest DrawingML
    /// match, PptxExporter's styled text) or "picture" (the exact look).
    var pptxStyledText = ExportLast.styledEditable
    /// Whether the format was the sheet's Suggested one, taken as offered
    /// (ExportSuggestion) — so a remembered choice can go back to being
    /// suggested — rather than picked by hand.
    var suggested = false
    /// The PDF's bookmarks: an outline entry for each page, titled by the
    /// page's title or "Page N" (PDFMetadata). On unless turned off.
    var pdfBookmarks = true

    static let key = "exportLast"
    static let formats: Set<String> = ["png", "jpg", "pdf", "print", "svg", "pptx", "mp4", "gif"]
    /// The export sheet's file types, in the order its picker lists them —
    /// the Android twin's ExportSettings.formats.
    static let fileTypes = ["png", "jpg", "pdf", "print", "svg", "pptx", "mp4", "gif"]
    static let pageChoices: Set<String> = ["all", "current", "chosen"]

    static let styledEditable = "editable"
    static let styledPicture = "picture"
    static let styledTextChoices: [String] = [styledEditable, styledPicture]

    private enum CodingKeys: String, CodingKey {
        case format, scale, longEdge, jpegQuality, transparent, pages, pdfNotes, pdfCompress, pptxStyledText,
             suggested, pdfBookmarks
    }

    init(format: String, scale: Double, longEdge: Int?, jpegQuality: Double, transparent: Bool, pages: String,
         pdfNotes: Bool = false, pdfCompress: Bool = false, pptxStyledText: String = ExportLast.styledEditable,
         suggested: Bool = false, pdfBookmarks: Bool = true) {
        self.format = format
        self.scale = scale
        self.longEdge = longEdge
        self.jpegQuality = jpegQuality
        self.transparent = transparent
        self.pages = pages
        self.pdfNotes = pdfNotes
        self.pdfCompress = pdfCompress
        self.pptxStyledText = pptxStyledText
        self.suggested = suggested
        self.pdfBookmarks = pdfBookmarks
    }

    /// Whether styled text goes out editable, as the setting says.
    var styledTextEditable: Bool { pptxStyledText != ExportLast.styledPicture }

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
        // "editable" or "picture"; anything else, or none, is editable.
        let styled = (try? c.decode(String.self, forKey: .pptxStyledText)) ?? Self.styledEditable
        pptxStyledText = Self.styledTextChoices.contains(styled) ? styled : Self.styledEditable
        // Missing, the format was picked by hand and the bookmarks are on.
        suggested = (try? c.decode(Bool.self, forKey: .suggested)) ?? false
        pdfBookmarks = (try? c.decode(Bool.self, forKey: .pdfBookmarks)) ?? true
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
        try c.encode(pptxStyledText, forKey: .pptxStyledText)
        try c.encode(suggested, forKey: .suggested)
        try c.encode(pdfBookmarks, forKey: .pdfBookmarks)
    }

    /// As stored: every key, in the order above, written out here rather
    /// than left to JSONEncoder's ordering, so the text is the Android
    /// twin's character for character — a whole number with ".0", as
    /// Kotlin writes a Double.
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
            "\"pptxStyledText\":" + Self.quoted(pptxStyledText),
            "\"suggested\":" + String(suggested),
            "\"pdfBookmarks\":" + String(pdfBookmarks),
        ]
        return "{" + fields.joined(separator: ",") + "}"
    }

    /// A number as the Android twin's kotlinx.serialization writes a
    /// Double: 2.0 and 1.0 with their ".0", 0.85 as it is. (Kotlin turns to
    /// an exponent from 10 million up and under 0.001, which no setting
    /// here reaches.)
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "0.0" }
        if value == value.rounded(), abs(value) < 1e7 { return String(Int(value)) + ".0" }
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
