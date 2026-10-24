// The PDF's two switches: "Include notes", a notes page after each page
// that has notes, and "Compress", every photo at 150 dpi of its printed
// size as JPEG 0.75 — with the size the PDF row says it will come to, and
// both remembered in the shared export JSON as "pdfNotes" and "pdfCompress".
// The rows are the Android twin's ExportPlan tests.

import XCTest
import CoreGraphics
import CoreImage
import UIKit
@testable import Canvia

final class PDFOptionsTests: XCTestCase {

    private var written: [URL] = []
    private var stored: [String] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        for id in stored { MediaStore.delete(id) }
        written = []
        stored = []
        super.tearDown()
    }

    private func destination() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-options-\(UUID().uuidString).pdf")
        written.append(url)
        return url
    }

    private func notedDesign() -> Design {
        var d = Design(title: "Talk", width: 400, height: 225)
        d.pages = (0..<3).map { _ in Page(elements: [Element.text("Slide", fontSize: 40, w: 300)]) }
        d.pages[0].notes = "Open with the story about the harbour."
        d.pages[1].notes = "   \n"
        d.pages[2].notes = "Ask for questions."
        return d
    }

    // MARK: settings

    /// The shared JSON, character for character, every key in the order the
    /// Android twin writes them — a whole number with ".0", as
    /// kotlinx.serialization writes a Double.
    func testTheSettingsJSONIsTheSharedText() {
        let plain = ExportLast(format: "png", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false, pages: "all")
        XCTAssertEqual(plain.json,
                       #"{"format":"png","scale":2.0,"longEdge":null,"jpegQuality":0.85,"transparent":false,"pages":"all","pdfNotes":false,"pdfCompress":false,"pptxStyledText":"editable","suggested":false,"pdfBookmarks":true,"colourProfile":"rgb","html":{"nav":true,"mobileStack":true,"embedMedia":true,"layout":"scroll","autoplay":0.0,"loop":false},"zip":false,"pngCompress":false,"pdfTagged":true}"#)
        let pdf = ExportLast(format: "pdf", scale: 3, longEdge: 1080, jpegQuality: 1, transparent: true,
                             pages: "chosen", pdfNotes: true, pdfCompress: true)
        XCTAssertEqual(pdf.json,
                       #"{"format":"pdf","scale":3.0,"longEdge":1080,"jpegQuality":1.0,"transparent":true,"pages":"chosen","pdfNotes":true,"pdfCompress":true,"pptxStyledText":"editable","suggested":false,"pdfBookmarks":true,"colourProfile":"rgb","html":{"nav":true,"mobileStack":true,"embedMedia":true,"layout":"scroll","autoplay":0.0,"loop":false},"zip":false,"pngCompress":false,"pdfTagged":true}"#)
        // The Android twin's PdfOptionsTest row.
        let shared = ExportLast(format: "pdf", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                                pages: "all", pdfNotes: true, pdfCompress: true)
        XCTAssertEqual(shared.json,
                       #"{"format":"pdf","scale":2.0,"longEdge":null,"jpegQuality":0.85,"transparent":false,"pages":"all","pdfNotes":true,"pdfCompress":true,"pptxStyledText":"editable","suggested":false,"pdfBookmarks":true,"colourProfile":"rgb","html":{"nav":true,"mobileStack":true,"embedMedia":true,"layout":"scroll","autoplay":0.0,"loop":false},"zip":false,"pngCompress":false,"pdfTagged":true}"#)
        XCTAssertEqual(ExportLast.read(pdf.json), pdf)
        XCTAssertEqual(ExportLast.read(plain.json), plain)
        XCTAssertEqual(ExportLast.number(1.5), "1.5")
    }

    /// Missing, or not a true or false, is off.
    func testTheNewKeysReadLeniently() throws {
        let old = try XCTUnwrap(ExportLast.read(#"{"format":"pdf","scale":2,"pages":"all"}"#))
        XCTAssertFalse(old.pdfNotes)
        XCTAssertFalse(old.pdfCompress)
        // A setting from before the tagged PDF stays untagged; a fresh sheet
        // tags, as on the Android twin.
        XCTAssertFalse(old.pdfTagged)
        XCTAssertTrue(ExportLast(format: "pdf", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                                 pages: "all").pdfTagged)
        let odd = try XCTUnwrap(ExportLast.read(#"{"format":"pdf","pdfNotes":"yes","pdfCompress":1}"#))
        XCTAssertFalse(odd.pdfNotes)
        XCTAssertFalse(odd.pdfCompress)
        let on = try XCTUnwrap(ExportLast.read(#"{"format":"pdf","pdfNotes":true,"pdfCompress":true,"suggested":false,"pdfBookmarks":true}"#))
        XCTAssertTrue(on.pdfNotes)
        XCTAssertTrue(on.pdfCompress)
        // Shared: "pptxStyledText" is "editable" (the default) or "picture"; anything else is the default.
        XCTAssertEqual(old.pptxStyledText, "editable")
        XCTAssertTrue(old.styledTextEditable)
        let picture = ExportLast(format: "pptx", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                                 pages: "all", pptxStyledText: "picture")
        XCTAssertTrue(picture.json.hasSuffix(#""pdfCompress":false,"pptxStyledText":"picture","suggested":false,"pdfBookmarks":true,"colourProfile":"rgb","html":{"nav":true,"mobileStack":true,"embedMedia":true,"layout":"scroll","autoplay":0.0,"loop":false},"zip":false,"pngCompress":false,"pdfTagged":true}"#))
        XCTAssertEqual(ExportLast.read(picture.json)?.pptxStyledText, "picture")
        XCTAssertFalse(try XCTUnwrap(ExportLast.read(picture.json)).styledTextEditable)
        XCTAssertEqual(ExportLast.read(#"{"format":"pptx","pptxStyledText":"vector"}"#)?.pptxStyledText, "editable")
        // Missing, the format was picked by hand and the bookmarks are on.
        XCTAssertFalse(old.suggested)
        XCTAssertTrue(old.pdfBookmarks)
        let round = ExportLast(format: "mp4", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false,
                               pages: "all", suggested: true, pdfBookmarks: false)
        XCTAssertEqual(ExportLast.read(round.json), round)
        XCTAssertTrue(round.json.hasSuffix(#""pdfCompress":false,"pptxStyledText":"editable","suggested":true,"pdfBookmarks":false,"colourProfile":"rgb","html":{"nav":true,"mobileStack":true,"embedMedia":true,"layout":"scroll","autoplay":0.0,"loop":false},"zip":false,"pngCompress":false,"pdfTagged":true}"#))
    }

    // MARK: notes pages

    /// A notes page straight after each page with notes — spaces are not
    /// notes — and none without the switch.
    func testANotesPageFollowsEachPageWithNotes() {
        let d = notedDesign()
        XCTAssertEqual(ExportChoices.pdfSheets(design: d, indices: [0, 1, 2], notes: true),
                       [.page(0), .notes(0), .page(1), .page(2), .notes(2)])
        XCTAssertEqual(ExportChoices.pdfSheets(design: d, indices: [0, 1, 2], notes: false),
                       [.page(0), .page(1), .page(2)])
        XCTAssertEqual(ExportChoices.pdfSheets(design: d, indices: [1, 2], notes: true), [.page(1), .page(2), .notes(2)])
    }

    /// The PDF itself: its page count is the pages plus the pages with
    /// notes, each notes page the size of its page — flattened or not.
    @MainActor
    func testTheNotesPageCountIsThePagesWithNotes() async throws {
        let d = notedDesign()
        let withNotes = d.pages.filter(ExportChoices.hasNotes).count
        for flatten in [false, true] {
            let url = destination()
            try await DesignExporter.exportPDF(design: d, flatten: flatten, notes: true, to: url)
            let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
            XCTAssertEqual(pdf.numberOfPages, d.pages.count + withNotes, "flatten \(flatten)")
            let notesBox = try XCTUnwrap(pdf.page(at: 2)).getBoxRect(.mediaBox)
            XCTAssertEqual(notesBox.width, 300, accuracy: 0.5)
            XCTAssertEqual(notesBox.height, 168.75, accuracy: 0.5)
        }
        let url = destination()
        try await DesignExporter.exportPDF(design: d, to: url)
        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, d.pages.count)
    }

    // MARK: notes page layout

    /// The Android twin's PdfNotes numbers: a twelfth of the shorter side
    /// round it, the page fitted in the top third, the notes from half a
    /// margin under it to the bottom margin.
    func testTheNotesPageIsLaidOutByTheSharedNumbers() {
        let size = CGSize(width: 1920, height: 1080)
        XCTAssertEqual(ExportChoices.notesMargin(size), 90, accuracy: 1e-9)
        let thumb = ExportChoices.notesThumbnail(size)
        XCTAssertEqual(thumb.minY, 90, accuracy: 1e-9)
        XCTAssertEqual(thumb.maxY, 360, accuracy: 1e-9)
        XCTAssertEqual(thumb.width, 480, accuracy: 1e-9)
        XCTAssertEqual(thumb.midX, 960, accuracy: 1e-9)
        let box = ExportChoices.notesTextBox(size)
        XCTAssertEqual(box.minY, 405, accuracy: 1e-9)
        XCTAssertEqual(box.maxY, 990, accuracy: 1e-9)
        XCTAssertEqual(box.minX, 90, accuracy: 1e-9)
        XCTAssertEqual(ExportChoices.notesColor, "#1f2430")
        XCTAssertEqual(ExportChoices.notesPointSize, 14)
    }

    // MARK: compress

    private typealias Use = ExportChoices.PDFPhoto

    /// 150 for each inch a photo prints across, the photo cover-fitted to
    /// its box as it is drawn — the rows the Android twin's PdfOptionsTest
    /// shares: a 4000 × 3000 photo in an 800 × 600 frame at 96 dpi keeps
    /// 1250 × 938 (937.5, a half up); in an 800 × 800 frame, cropped to it,
    /// 1667 × 1250; behind a 1920 × 1080 page 3000 × 2250; a crop zoomed
    /// in twice keeps twice as many; used twice, its largest use; never
    /// more than it has.
    func testACompressedPhotoKeeps150DotsAnInch() {
        let photo = CGSize(width: 4000, height: 3000)
        XCTAssertEqual(ExportChoices.compressedPixels(natural: photo, uses: [Use(box: CGSize(width: 800, height: 600))], dpi: 96),
                       CGSize(width: 1250, height: 938))
        XCTAssertEqual(ExportChoices.compressedPixels(natural: photo, uses: [Use(box: CGSize(width: 800, height: 800))], dpi: 96),
                       CGSize(width: 1667, height: 1250))
        XCTAssertEqual(ExportChoices.compressedPixels(natural: photo, uses: [Use(box: CGSize(width: 1920, height: 1080))], dpi: 96),
                       CGSize(width: 3000, height: 2250))
        XCTAssertEqual(ExportChoices.compressedPixels(natural: photo, uses: [Use(box: CGSize(width: 800, height: 600), cropScale: 2)],
                                                      dpi: 96),
                       CGSize(width: 2500, height: 1875))
        let twice = [Use(box: CGSize(width: 400, height: 300)), Use(box: CGSize(width: 800, height: 600))]
        XCTAssertEqual(ExportChoices.compressedPixels(natural: photo, uses: twice, dpi: 96), CGSize(width: 1250, height: 938))
        XCTAssertEqual(ExportChoices.compressedPixels(natural: CGSize(width: 100, height: 50),
                                                      uses: [Use(box: CGSize(width: 400, height: 200))], dpi: 96),
                       CGSize(width: 100, height: 50), "never more than it has")
        // An A4 page at 300 dpi: a 2480 px photo across it prints 8.27 in.
        XCTAssertEqual(ExportChoices.compressedPixels(natural: CGSize(width: 4000, height: 4000),
                                                      uses: [Use(box: CGSize(width: 2480, height: 2480))], dpi: 300),
                       CGSize(width: 1240, height: 1240))
    }

    func testTheSizeIsSaidAsAFileIs() {
        XCTAssertEqual(ExportChoices.sizeText(3_200_000), "About 3.2 MB")
        XCTAssertEqual(ExportChoices.sizeText(1_000_000), "About 1.0 MB")
        XCTAssertEqual(ExportChoices.sizeText(450_000), "About 450 KB")
        XCTAssertEqual(ExportChoices.sizeText(90), "About 1 KB")
    }

    /// The Android twin's ExportPlan.estimatedPdfBytes rows, byte for byte:
    /// 30 KB a sheet, notes pages counted, and each photo once by source —
    /// compressed at 1.6125 bits a pixel of what it keeps, else three bytes
    /// a pixel of all it has — with no floor.
    func testTheEstimate() {
        let d = notedDesign()
        XCTAssertEqual(ExportChoices.estimatedPDFBytes(design: d, indices: [0, 1, 2], notes: true, compress: false) { _ in nil },
                       5 * 30_000)
        var photo = Design(title: "Photo", width: 1920, height: 1080)
        photo.pages = [Page(elements: [Element.image("media:big", w: 800, h: 600)])]
        let size: (String) -> CGSize? = { _ in CGSize(width: 4000, height: 3000) }
        let full = ExportChoices.estimatedPDFBytes(design: photo, indices: [0], notes: false, compress: false, pixelSize: size)
        let small = ExportChoices.estimatedPDFBytes(design: photo, indices: [0], notes: false, compress: true, pixelSize: size)
        XCTAssertEqual(full, 36_030_000)
        XCTAssertEqual(small, 266_332)
        XCTAssertLessThan(small, full)
        XCTAssertEqual(ExportChoices.sizeText(full), "About 36.0 MB")
        XCTAssertEqual(ExportChoices.sizeText(small), "About 266 KB")
        var square = Design(title: "Square", width: 1920, height: 1080)
        square.pages = [Page(elements: [Element.image("media:big", w: 800, h: 800)])]
        XCTAssertEqual(ExportChoices.estimatedPDFBytes(design: square, indices: [0], notes: false, compress: true, pixelSize: size),
                       450_005)
        var twice = Design(title: "Twice", width: 1920, height: 1080)
        twice.pages = [Page(elements: [Element.image("media:big", w: 400, h: 300), Element.image("media:big", w: 800, h: 600)])]
        XCTAssertEqual(ExportChoices.estimatedPDFBytes(design: twice, indices: [0], notes: false, compress: true, pixelSize: size),
                       266_332)
        XCTAssertEqual(ExportChoices.estimatedPDFBytes(design: twice, indices: [0], notes: false, compress: false, pixelSize: size),
                       36_030_000)
    }

    /// A 4000 px photo noisy enough not to squash: random pixels as a JPEG,
    /// kept whole among the uploads.
    private func noisyPhoto(width: Int, height: Int) throws -> String {
        let noise = try XCTUnwrap(CIFilter(name: "CIRandomGenerator")?.outputImage)
        let cropped = noise.cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let cg = try XCTUnwrap(CIContext().createCGImage(cropped, from: cropped.extent))
        let data = try XCTUnwrap(UIImage(cgImage: cg).jpegData(compressionQuality: 0.9))
        let prepared = try XCTUnwrap(ImageDownsampler.prepare(data, maxEdge: CGFloat(max(width, height))))
        let src = try XCTUnwrap(MediaStore.store(prepared))
        stored.append(String(src.dropFirst("media:".count)))
        return src
    }

    private func bytes(_ url: URL) throws -> Int {
        try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
    }

    /// Compressing a PDF with a 4000 px photo on it makes it smaller, the
    /// page and its text as they were, and lets the stand-ins go after.
    @MainActor
    func testCompressingLowersTheByteSize() async throws {
        let src = try noisyPhoto(width: 4000, height: 3000)
        var d = Design(title: "Photo", width: 800, height: 600)
        d.pages = [Page(elements: [Element.image(src, w: 400, h: 300), Element.text("Caption", fontSize: 30, w: 300)])]
        let plain = destination()
        try await DesignExporter.exportPDF(design: d, to: plain)
        let compressed = destination()
        try await DesignExporter.exportPDF(design: d, compress: true, to: compressed)
        XCTAssertLessThan(try bytes(compressed), try bytes(plain))
        XCTAssertEqual(CGPDFDocument(compressed as CFURL)?.numberOfPages, 1)
        XCTAssertTrue(CompressedPhotos.staged.isEmpty, "the stand-ins are let go")
        // The design itself keeps its own photo.
        XCTAssertEqual(d.pages[0].elements[0].src, src)
    }

    /// The stand-in design: the photo drawn from a copy of the pixels it
    /// keeps; a text left alone.
    @MainActor
    func testTheStandInIsThePixelsKept() async throws {
        let src = try noisyPhoto(width: 4000, height: 3000)
        var d = Design(title: "Photo", width: 800, height: 600)
        d.pages = [Page(elements: [Element.image(src, w: 400, h: 300), Element.text("Caption")])]
        let staged = try await DesignExporter.compressedForPDF(d, indices: [0])
        defer { CompressedPhotos.clear() }
        let stand = try XCTUnwrap(staged.pages[0].elements[0].src)
        XCTAssertTrue(stand.hasPrefix(CompressedPhotos.prefix))
        let copy = try XCTUnwrap(PhotoLibrary.resolve(stand))
        XCTAssertEqual(copy.size.width * copy.scale, 625)
        XCTAssertEqual(copy.size.height * copy.scale, 469)
        XCTAssertEqual(staged.pages[0].elements[1], d.pages[0].elements[1])
    }
}
