// Export: the size budget, and that each format actually lands on disk in the
// shape it claims.
//
// The budget checks are pure arithmetic and cheap. The file checks render for
// real, so every design here is deliberately tiny — the point is the plumbing,
// not the pixel count, and a test suite that allocates a 128 MB bitmap to
// prove a 128 MB bitmap is possible is not a good trade.

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Canvia

final class DesignExporterTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func design(title: String = "Test design",
                        width: Double = 200, height: Double = 120,
                        pages: Int = 1) -> Design {
        var d = Design(title: title, width: width, height: height)
        d.pages = (0..<pages).map { i in
            Page(background: .color(i.isMultiple(of: 2) ? "#ff0000" : "#0000ff"),
                 elements: [Element.shape("rect", w: width / 2, h: height / 2)])
        }
        return d
    }

    private func destination(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-test-\(UUID().uuidString).\(ext)")
        written.append(url)
        return url
    }

    // MARK: the budget

    func testScaleIsHonouredWhenTheRenderFits() {
        let d = design(width: 1080, height: 1080)   // 3x is 10.5 megapixels
        for requested in 1...3 {
            XCTAssertEqual(DesignExporter.effectiveScale(design: d, requested: requested),
                           Double(requested), accuracy: 0.0001)
            XCTAssertFalse(DesignExporter.isClamped(design: d, requested: requested))
        }
    }

    /// The custom-size sheet allows 4000x4000. At 3x that is 144 megapixels —
    /// 576 MB of bitmap, which is not an export, it is a crash.
    func testScaleIsClampedWhenTheRenderWouldNotFit() {
        let d = design(width: 4000, height: 4000)
        XCTAssertFalse(DesignExporter.isClamped(design: d, requested: 1))
        XCTAssertTrue(DesignExporter.isClamped(design: d, requested: 3))
        XCTAssertLessThan(DesignExporter.effectiveScale(design: d, requested: 3), 3)
    }

    func testOutputNeverExceedsTheBudget() {
        for width in [40.0, 1080, 2000, 4000] {
            for height in [40.0, 1080, 2000, 4000] {
                for requested in 1...3 {
                    let size = DesignExporter.outputSize(design: design(width: width, height: height),
                                                         requested: requested)
                    XCTAssertLessThanOrEqual(size.width * size.height,
                                             DesignExporter.pixelBudget * 1.001,
                                             "\(width)x\(height) @\(requested)x")
                }
            }
        }
    }

    /// Clamping must only ever reduce. An export that silently came back
    /// *larger* than asked for would defeat the whole point of the cap.
    func testClampingNeverIncreasesTheScale() {
        for width in [40.0, 1080, 4000] {
            for requested in 1...3 {
                let d = design(width: width, height: width)
                XCTAssertLessThanOrEqual(DesignExporter.effectiveScale(design: d, requested: requested),
                                         Double(requested))
            }
        }
    }

    func testOutputSizeMatchesTheEffectiveScale() {
        let d = design(width: 800, height: 600)
        let size = DesignExporter.outputSize(design: d, requested: 2)
        XCTAssertEqual(size, CGSize(width: 1600, height: 1200))
    }

    // MARK: files

    @MainActor
    func testExportsPNGAtTheChosenScale() throws {
        let url = destination("png")
        try DesignExporter.exportRaster(design: design(), page: design().pages[0],
                                        format: .png, scale: 2, to: url)
        let (type, size) = try inspect(url)
        XCTAssertEqual(type, UTType.png.identifier)
        XCTAssertEqual(size, CGSize(width: 400, height: 240))
    }

    @MainActor
    func testExportsJPEG() throws {
        let url = destination("jpg")
        try DesignExporter.exportRaster(design: design(), page: design().pages[0],
                                        format: .jpeg, scale: 1, to: url)
        let (type, size) = try inspect(url)
        XCTAssertEqual(type, UTType.jpeg.identifier)
        XCTAssertEqual(size, CGSize(width: 200, height: 120))
    }

    /// Overwriting matters: the file is named after the design, so exporting
    /// twice in a row reuses the same path and the second result must be the
    /// one that survives.
    @MainActor
    func testExportingTwiceOverwrites() throws {
        let url = destination("png")
        try DesignExporter.exportRaster(design: design(), page: design().pages[0],
                                        format: .png, scale: 1, to: url)
        try DesignExporter.exportRaster(design: design(), page: design().pages[0],
                                        format: .png, scale: 2, to: url)
        let (_, size) = try inspect(url)
        XCTAssertEqual(size, CGSize(width: 400, height: 240))
    }

    @MainActor
    func testExportsEveryPageToThePDF() throws {
        let url = destination("pdf")
        try DesignExporter.exportPDF(design: design(pages: 3), to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 3)
    }

    /// Page units are pixels at 96dpi and PDF works in points at 72, so a
    /// 200x120 design is a 150x90pt page. Getting this wrong prints at the
    /// wrong physical size, which is the one thing a PDF is for.
    @MainActor
    func testPDFPageUsesPointsNotPixels() throws {
        let url = destination("pdf")
        try DesignExporter.exportPDF(design: design(width: 200, height: 120), to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let box = try XCTUnwrap(pdf.page(at: 1)).getBoxRect(.mediaBox)
        XCTAssertEqual(box.width, 150, accuracy: 0.5)
        XCTAssertEqual(box.height, 90, accuracy: 0.5)
    }

    /// The claim the export sheet now makes out loud: PDF pages are drawing
    /// commands, not a page-sized picture. Checked at the file's own level —
    /// a rasterised page has to place its bitmap as an image XObject, so if
    /// there are none, nothing was rasterised. A file-size heuristic would not
    /// do: this page is mostly flat colour, which compresses small enough as a
    /// bitmap to pass a size check while being exactly what the test is
    /// supposed to catch.
    @MainActor
    func testPDFPagesAreDrawnAsVectors() throws {
        let url = destination("pdf")
        try DesignExporter.exportPDF(design: design(width: 2000, height: 1200), to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(pdf.page(at: 1))
        XCTAssertEqual(imageCount(in: page), 0)
    }

    /// Images placed on a page still travel as images, so the check above is
    /// measuring something rather than always returning zero.
    @MainActor
    func testPDFCarriesRealImagesAsImages() throws {
        let photo = try XCTUnwrap(PhotoLibrary.photos.first)
        var d = design(width: 400, height: 300)
        d.pages[0].background = .image("asset:\(photo.id)")
        let url = destination("pdf")
        try DesignExporter.exportPDF(design: d, to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(pdf.page(at: 1))
        XCTAssertGreaterThan(imageCount(in: page), 0)
    }

    // MARK: naming

    func testFileURLUsesTheDesignTitle() {
        let url = DesignExporter.fileURL(for: design(title: "My Poster"), ext: "png")
        XCTAssertEqual(url.lastPathComponent, "My-Poster.png")
    }

    func testFileURLStripsCharactersAPathCannotHold() {
        let url = DesignExporter.fileURL(for: design(title: "Q3/Q4: report *final*"), ext: "pdf")
        XCTAssertEqual(url.lastPathComponent, "Q3Q4-report-final.pdf")
        XCTAssertFalse(url.lastPathComponent.contains("/"))
    }

    func testFileURLFallsBackWhenTheTitleHasNothingUsable() {
        let url = DesignExporter.fileURL(for: design(title: "///"), ext: "png")
        XCTAssertEqual(url.lastPathComponent, "design.png")
    }

    // MARK: helpers

    /// How many image XObjects the page's resources hold.
    private func imageCount(in page: CGPDFPage) -> Int {
        guard let pageDict = page.dictionary else { return 0 }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
              let resources else { return 0 }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects),
              let xobjects else { return 0 }
        var count = 0
        // The callback is a C function pointer, so the counter has to travel
        // through the untyped info pointer rather than being captured.
        withUnsafeMutablePointer(to: &count) { box in
            CGPDFDictionaryApplyFunction(xobjects, { _, object, info in
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(object, .stream, &stream),
                      let stream,
                      let streamDict = CGPDFStreamGetDictionary(stream) else { return }
                var subtype: UnsafePointer<CChar>?
                guard CGPDFDictionaryGetName(streamDict, "Subtype", &subtype),
                      let subtype,
                      String(cString: subtype) == "Image" else { return }
                info?.assumingMemoryBound(to: Int.self).pointee += 1
            }, box)
        }
        return count
    }

    private func inspect(_ url: URL) throws -> (type: String, size: CGSize) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let type = try XCTUnwrap(CGImageSourceGetType(source)) as String
        let props = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let width = try XCTUnwrap(props[kCGImagePropertyPixelWidth] as? Double)
        let height = try XCTUnwrap(props[kCGImagePropertyPixelHeight] as? Double)
        return (type, CGSize(width: width, height: height))
    }
}
