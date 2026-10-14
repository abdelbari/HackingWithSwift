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
    /// Android twin writes them.
    func testTheSettingsJSONIsTheSharedText() {
        let plain = ExportLast(format: "png", scale: 2, longEdge: nil, jpegQuality: 0.85, transparent: false, pages: "all")
        XCTAssertEqual(plain.json,
                       #"{"format":"png","scale":2,"longEdge":null,"jpegQuality":0.85,"transparent":false,"pages":"all","pdfNotes":false,"pdfCompress":false}"#)
        let pdf = ExportLast(format: "pdf", scale: 3, longEdge: 1080, jpegQuality: 0.92, transparent: true,
                             pages: "chosen", pdfNotes: true, pdfCompress: true)
        XCTAssertEqual(pdf.json,
                       #"{"format":"pdf","scale":3,"longEdge":1080,"jpegQuality":0.92,"transparent":true,"pages":"chosen","pdfNotes":true,"pdfCompress":true}"#)
        XCTAssertEqual(ExportLast.read(pdf.json), pdf)
        XCTAssertEqual(ExportLast.read(plain.json), plain)
    }

    /// Missing, or not a true or false, is off.
    func testTheNewKeysReadLeniently() throws {
        let old = try XCTUnwrap(ExportLast.read(#"{"format":"pdf","scale":2,"pages":"all"}"#))
        XCTAssertFalse(old.pdfNotes)
        XCTAssertFalse(old.pdfCompress)
        let odd = try XCTUnwrap(ExportLast.read(#"{"format":"pdf","pdfNotes":"yes","pdfCompress":1}"#))
        XCTAssertFalse(odd.pdfNotes)
        XCTAssertFalse(odd.pdfCompress)
        let on = try XCTUnwrap(ExportLast.read(#"{"format":"pdf","pdfNotes":true,"pdfCompress":true}"#))
        XCTAssertTrue(on.pdfNotes)
        XCTAssertTrue(on.pdfCompress)
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

    // MARK: compress

    /// 150 for each inch a photo prints across: a 4000 × 3000 photo in a box
    /// of 400 × 300 px at 96 dpi prints 4.17 in wide, so keeps 625 × 469
    /// (468.75, to the nearest); a crop zoomed in 1.6 times keeps 1.6 times as many;
    /// never more than it has.
    func testACompressedPhotoKeeps150DotsAnInch() {
        let points = Units.pointsPerPixel(dpi: 96)
        let photo = CGSize(width: 4000, height: 3000)
        XCTAssertEqual(ExportChoices.compressedPixels(natural: photo, box: CGSize(width: 400, height: 300),
                                                      cropScale: 1, pointsPerPixel: points),
                       CGSize(width: 625, height: 469))
        XCTAssertEqual(ExportChoices.compressedPixels(natural: photo, box: CGSize(width: 400, height: 300),
                                                      cropScale: 1.6, pointsPerPixel: points),
                       CGSize(width: 1000, height: 750))
        XCTAssertEqual(ExportChoices.compressedPixels(natural: CGSize(width: 100, height: 50),
                                                      box: CGSize(width: 400, height: 200),
                                                      cropScale: 1, pointsPerPixel: points),
                       CGSize(width: 100, height: 50), "never more than it has")
        // An A4 page at 300 dpi: a 2480 px photo across it prints 8.27 in.
        XCTAssertEqual(ExportChoices.compressedPixels(natural: CGSize(width: 4000, height: 4000),
                                                      box: CGSize(width: 2480, height: 2480),
                                                      cropScale: 1, pointsPerPixel: Units.pointsPerPixel(dpi: 300)),
                       CGSize(width: 1240, height: 1240))
    }

    func testTheSizeIsSaidAsAFileIs() {
        XCTAssertEqual(ExportChoices.sizeText(3_200_000), "About 3.2 MB")
        XCTAssertEqual(ExportChoices.sizeText(1_000_000), "About 1.0 MB")
        XCTAssertEqual(ExportChoices.sizeText(450_000), "About 450 KB")
        XCTAssertEqual(ExportChoices.sizeText(90), "About 1 KB")
    }

    /// 30 KB a sheet, notes pages counted, and each photo as a JPEG at 0.75
    /// of the pixels it keeps.
    func testTheEstimate() {
        let d = notedDesign()
        XCTAssertEqual(ExportChoices.estimatedPDFBytes(design: d, indices: [0, 1, 2], notes: true, compress: false) { _ in nil },
                       5 * 30_000)
        var photo = Design(title: "Photo", width: 800, height: 600)
        photo.pages = [Page(elements: [Element.image("media:fixture", w: 400, h: 300)])]
        let size: (String) -> CGSize? = { _ in CGSize(width: 4000, height: 3000) }
        let full = ExportChoices.estimatedPDFBytes(design: photo, indices: [0], notes: false, compress: false, pixelSize: size)
        let small = ExportChoices.estimatedPDFBytes(design: photo, indices: [0], notes: false, compress: true, pixelSize: size)
        XCTAssertEqual(full, 30_000 + DesignExporter.jpegBytes(pixels: 12_000_000, quality: 0.75))
        XCTAssertEqual(small, 30_000 + DesignExporter.jpegBytes(pixels: 625 * 469, quality: 0.75))
        XCTAssertLessThan(small, full)
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
    func testTheStandInIsThePixelsKept() throws {
        let src = try noisyPhoto(width: 4000, height: 3000)
        var d = Design(title: "Photo", width: 800, height: 600)
        d.pages = [Page(elements: [Element.image(src, w: 400, h: 300), Element.text("Caption")])]
        let staged = DesignExporter.compressedForPDF(d, indices: [0])
        defer { CompressedPhotos.clear() }
        let stand = try XCTUnwrap(staged.pages[0].elements[0].src)
        XCTAssertTrue(stand.hasPrefix(CompressedPhotos.prefix))
        let copy = try XCTUnwrap(PhotoLibrary.resolve(stand))
        XCTAssertEqual(copy.size.width * copy.scale, 625)
        XCTAssertEqual(copy.size.height * copy.scale, 469)
        XCTAssertEqual(staged.pages[0].elements[1], d.pages[0].elements[1])
    }
}
