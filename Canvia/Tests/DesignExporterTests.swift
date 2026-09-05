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

// MARK: - page ranges and transparency

@MainActor
final class ExportRangeTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        super.tearDown()
    }

    private func design(pages: Int) -> Design {
        var d = Design(title: "range", width: 120, height: 90)
        d.pages = (0..<pages).map { _ in
            Page(background: .color("#3355ff"), elements: [Element.shape("rect", w: 40, h: 30)])
        }
        return d
    }

    // MARK: which pages

    func testCurrentIsOnlyThePageYouAreOn() {
        let d = design(pages: 5)
        XCTAssertEqual(DesignExporter.PageRange.current.indices(in: d, current: 2), [2])
    }

    func testAllIsEveryPage() {
        let d = design(pages: 4)
        XCTAssertEqual(DesignExporter.PageRange.all.indices(in: d, current: 0), [0, 1, 2, 3])
    }

    /// A range given backwards is still a range — the alternative is an empty
    /// export and no explanation.
    func testAReversedRangeIsNormalised() {
        let d = design(pages: 5)
        XCTAssertEqual(DesignExporter.PageRange.range(3, 1).indices(in: d, current: 0), [1, 2, 3])
    }

    /// Indices out of the document's range are clamped rather than crashing —
    /// a saved range outliving the pages it referred to is ordinary.
    func testOutOfRangeIndicesAreClamped() {
        let d = design(pages: 3)
        XCTAssertEqual(DesignExporter.PageRange.range(-4, 99).indices(in: d, current: 0), [0, 1, 2])
        XCTAssertEqual(DesignExporter.PageRange.current.indices(in: d, current: 99), [2])
    }

    func testAnEmptyDocumentYieldsNoPages() {
        var d = design(pages: 1)
        d.pages = []
        XCTAssertTrue(DesignExporter.PageRange.all.indices(in: d, current: 0).isEmpty)
    }

    // MARK: files

    /// One file per page, numbered — the point of a range is that each page
    /// can be sent on its own.
    func testAllPagesProducesOneNumberedFileEach() throws {
        let urls = try DesignExporter.exportPages(design: design(pages: 3), range: .all,
                                                  current: 0, format: .png, scale: 1)
        written = urls
        XCTAssertEqual(urls.count, 3)
        XCTAssertEqual(Set(urls.map(\.lastPathComponent)).count, 3, "two pages shared a filename")
        for (index, url) in urls.enumerated() {
            XCTAssertTrue(url.lastPathComponent.contains("-\(index + 1)."), url.lastPathComponent)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testARangeReportsAPageAtATime() throws {
        var seen: [Double] = []
        let urls = try DesignExporter.exportPages(design: design(pages: 4), range: .all,
                                                  current: 0, format: .png, scale: 1,
                                                  progress: { seen.append($0) })
        written = urls
        XCTAssertEqual(seen, [0.25, 0.5, 0.75, 1])
    }

    /// A single page keeps the plain name: "poster.png", not "poster-1.png".
    func testASinglePageIsNotNumbered() throws {
        let urls = try DesignExporter.exportPages(design: design(pages: 3), range: .current,
                                                  current: 1, format: .png, scale: 1)
        written = urls
        XCTAssertEqual(urls.count, 1)
        XCTAssertFalse(urls[0].lastPathComponent.contains("-"), urls[0].lastPathComponent)
    }

    func testThePDFCoversOnlyTheChosenRange() throws {
        let url = DesignExporter.fileURL(for: design(pages: 4), ext: "pdf")
        written = [url]
        try DesignExporter.exportPDF(design: design(pages: 4), range: .current, current: 2, to: url)
        let pdf = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 1)
    }

    // MARK: exact sizes

    func testALongEdgeResolvesToTheScaleThatProducesIt() {
        let wide = Design(title: "wide", width: 1600, height: 900)
        let scale = DesignExporter.scale(forLongEdge: 3840, design: wide)
        XCTAssertEqual(DesignExporter.longEdge(design: wide, requested: scale), 3840, accuracy: 0.5)
        let tall = Design(title: "tall", width: 900, height: 1600)
        XCTAssertEqual(DesignExporter.outputSize(design: tall,
                                                 requested: DesignExporter.scale(forLongEdge: 1920, design: tall)),
                       CGSize(width: 1080, height: 1920))
    }

    func testAFractionalScaleRendersAtThatSize() throws {
        let d = Design(title: "half", width: 200, height: 100)
        let url = DesignExporter.fileURL(for: d, ext: "png", suffix: "-half")
        written = [url]
        try DesignExporter.exportRaster(design: d, page: d.pages[0], format: .png,
                                        scale: 0.5, to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 100)
        XCTAssertEqual(image.height, 50)
    }

    // MARK: resolution guard

    func testAPhotoStretchedPastItsPixelsIsFlagged() {
        var big = Element.image("media:big", w: 1000, h: 600)
        big.id = "big"
        var small = Element.image("media:small", w: 100, h: 60)
        small.id = "small"
        var zoomed = Element.image("media:small", w: 100, h: 60)
        zoomed.id = "zoomed"
        zoomed.cropScale = 3
        let page = Page(elements: [big, small, zoomed, Element.shape("rect")])
        let sizes = ["media:big": CGSize(width: 800, height: 480),
                     "media:small": CGSize(width: 200, height: 120)]
        let flagged = DesignExporter.upscaledImages(page: page, scale: 1, pixelSize: { sizes[$0] })
        XCTAssertEqual(flagged, ["big", "zoomed"],
                       "the big photo lacks pixels; the small one has spare, unless it is cropped in 3x")
        XCTAssertEqual(DesignExporter.upscaledImages(page: page, scale: 3, pixelSize: { sizes[$0] }),
                       ["big", "small", "zoomed"])
        XCTAssertTrue(DesignExporter.upscaledImages(page: page, scale: 3, pixelSize: { _ in nil }).isEmpty,
                      "an unknown source is not flagged")
    }

    // MARK: selection

    func testASelectionExportsAsAPageOfItsOwnSize() throws {
        var a = Element.shape("rect", w: 40, h: 30); a.x = 100; a.y = 50; a.id = "a"
        var b = Element.shape("circle", w: 20, h: 20); b.x = 160; b.y = 90; b.id = "b"
        var far = Element.shape("rect", w: 300, h: 300); far.x = 500; far.y = 500; far.id = "far"
        let page = Page(background: .color("#123456"), elements: [a, b, far])
        var d = Design(title: "sel", width: 1000, height: 1000)
        d.pages = [page]

        let cropped = try XCTUnwrap(DesignExporter.selectionDesign(design: d, page: page, ids: ["a", "b"]))
        XCTAssertEqual(cropped.width, 80)   // 100…180
        XCTAssertEqual(cropped.height, 60)  // 50…110
        XCTAssertEqual(cropped.pages.count, 1)
        XCTAssertEqual(cropped.pages[0].elements.map(\.id), ["a", "b"], "the unselected element came along")
        XCTAssertEqual(cropped.pages[0].elements[0].x, 0)
        XCTAssertEqual(cropped.pages[0].elements[1].x, 60)
        XCTAssertEqual(cropped.pages[0].elements[1].y, 40)
        XCTAssertEqual(cropped.pages[0].background, .color("#123456"), "the background stays")
        XCTAssertNil(DesignExporter.selectionDesign(design: d, page: page, ids: []))
    }

    // MARK: transparency

    /// The corner of a transparent export has to be actually transparent, not
    /// an opaque white square with an alpha channel bolted on.
    func testATransparentPNGHasNothingBehindIt() throws {
        let url = DesignExporter.fileURL(for: design(pages: 1), ext: "png", suffix: "-clear")
        written = [url]
        var d = design(pages: 1)
        // An element small enough, and far enough from the corner being
        // sampled, that the corner is background only.
        var rect = Element.shape("rect", w: 20, h: 20)
        rect.x = 50
        rect.y = 35
        d.pages[0].elements = [rect]
        try DesignExporter.exportRaster(design: d, page: d.pages[0], format: .png,
                                        scale: 1, transparent: true, to: url)
        XCTAssertEqual(try alpha(at: CGPoint(x: 2, y: 2), of: url), 0,
                       "the background survived a transparent export")
    }

    func testAnOpaqueExportIsStillOpaque() throws {
        let url = DesignExporter.fileURL(for: design(pages: 1), ext: "png", suffix: "-solid")
        written = [url]
        let d = design(pages: 1)
        try DesignExporter.exportRaster(design: d, page: d.pages[0], format: .png,
                                        scale: 1, transparent: false, to: url)
        XCTAssertEqual(try alpha(at: CGPoint(x: 2, y: 2), of: url), 255)
    }

    private func alpha(at point: CGPoint, of url: URL) throws -> UInt8 {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: -point.x, y: -(Double(image.height) - 1 - point.y),
                                       width: Double(image.width), height: Double(image.height)))
        }
        return pixel[3]
    }
}
