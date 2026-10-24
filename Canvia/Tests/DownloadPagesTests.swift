// Download: choose which pages go out — by id, in the design's order, a
// hidden page only when ticked — for every format, the video and GIF
// included; remember the last export's settings as the shared JSON; the
// video's 720p / 1080p / 4K; and a PDF flattened to 300-dpi pictures.

import XCTest
import CoreGraphics
@testable import Canvia

final class DownloadPagesTests: XCTestCase {

    private var written: [URL] = []

    override func tearDown() {
        for url in written { try? FileManager.default.removeItem(at: url) }
        written = []
        ExportChoices.chosenByDesign = [:]
        super.tearDown()
    }

    /// `hidden[i]` hides page i; each page a coloured square.
    private func design(_ hidden: [Bool], width: Double = 200, height: Double = 120) -> Design {
        var d = Design(title: "Deck", width: width, height: height)
        d.pages = hidden.enumerated().map { i, isHidden in
            var page = Page(background: .color(i.isMultiple(of: 2) ? "#ff0000" : "#0000ff"),
                            elements: [Element.shape("rect", w: 40, h: 40)])
            page.hidden = isHidden ? true : nil
            return page
        }
        return d
    }

    private func destination(_ ext: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pages-\(UUID().uuidString).\(ext)")
        written.append(url)
        return url
    }

    // MARK: choosing

    /// By id, in the design's order however they were ticked; a hidden page
    /// goes when it was ticked.
    func testChosenPagesAreByIdInTheDesignsOrder() {
        let d = design([false, true, false, false])
        let ids = d.pages.map(\.id)
        let range = DesignExporter.PageRange.chosen([ids[3], ids[1], "gone"])
        XCTAssertEqual(range.indices(in: d, current: 0), [1, 3])
        XCTAssertEqual(DesignExporter.PageRange.chosen([]).indices(in: d, current: 0), [])
    }

    /// Hidden pages start unticked; a toggle keeps the design's order; the
    /// choice is the design's own for the session.
    func testTheChoiceStartsWithTheShownPagesAndIsKeptPerDesign() {
        let d = design([false, true, false])
        let ids = d.pages.map(\.id)
        XCTAssertEqual(ExportChoices.chosen(for: d), [ids[0], ids[2]])
        let picked = ExportChoices.toggled([ids[2]], ids[0], in: d)
        XCTAssertEqual(picked, [ids[0], ids[2]])
        XCTAssertEqual(ExportChoices.toggled(picked, ids[2], in: d), [ids[0]])
        ExportChoices.remember([ids[2], ids[1]], for: d)
        XCTAssertEqual(ExportChoices.chosen(for: d), [ids[1], ids[2]])
        XCTAssertEqual(ExportChoices.chosen(for: design([false])).count, 1, "another design starts afresh")
    }

    /// A one-page design is that page, even hidden or with nothing ticked;
    /// more pages keep the choice as made.
    func testAOnePageDesignIsThatPage() {
        let lone = design([true])
        for picked in [DesignExporter.PageRange.all, .current, .chosen([])] {
            let taken = ExportChoices.exportRange(picked, in: lone)
            XCTAssertEqual(taken, .current)
            XCTAssertEqual(taken.indices(in: lone, current: 0), [0])
        }
        let deck = design([false, true, false])
        XCTAssertEqual(ExportChoices.exportRange(.all, in: deck), .all)
        XCTAssertEqual(ExportChoices.exportRange(.chosen([]), in: deck), .chosen([]))
    }

    func testTheRowsSayHowManyOfHowMany() {
        XCTAssertEqual(ExportChoices.countText(3, of: 8), "3 of 8 pages")
        XCTAssertEqual(ExportChoices.countText(1, of: 8), "1 of 8 pages")
        XCTAssertEqual(ExportChoices.countText(1, of: 1), "1 of 1 page")
    }

    // MARK: the video plays only those

    func testTheVideoPlaysTheChosenPagesInOrderWithTheirOwnHolds() {
        var d = design([false, false, true, false])
        d.pages[3].holdSeconds = 4
        let ids = d.pages.map(\.id)
        let settings = MovieExporter.Settings()
        XCTAssertEqual(MovieExporter.playedPages(design: d, range: .all, current: 0), [0, 1, 3])
        XCTAssertEqual(MovieExporter.playedPages(design: d, range: .current, current: 2), [2])
        let chosen = DesignExporter.PageRange.chosen([ids[3], ids[2]])
        XCTAssertEqual(MovieExporter.playedPages(design: d, range: chosen, current: 0), [2, 3])
        // 2.5 s for page 3, its own 4 s for page 4.
        XCTAssertEqual(MovieExporter.seconds(design: d, settings: settings, range: chosen, current: 0), 6.5, accuracy: 0.05)
        XCTAssertEqual(MovieExporter.seconds(design: d, settings: settings, range: .all, current: 0),
                       MovieExporter.seconds(design: d, settings: settings), accuracy: 1e-9)
    }

    @MainActor
    func testAGIFOfChosenPagesHasOnlyTheirFrames() async throws {
        let d = design([false, false, false])
        let one = DesignExporter.PageRange.chosen([d.pages[1].id])
        let url = destination("gif")
        try await MovieExporter.exportGIF(design: d, range: one, to: url)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let plan = MovieExporter.gifPlan(design: d, settings: MovieExporter.Settings(), range: one)
        var settings = MovieExporter.Settings()
        settings.fps = plan.fps
        let frames = MovieExporter.timeline(design: d, pages: [1], settings: settings).last?.end ?? 0
        XCTAssertEqual(CGImageSourceGetCount(source), frames)
    }

    // MARK: video size

    /// The same frame maths on both phones: the design fitted under the
    /// long edge, never enlarged, in even pixels.
    func testTheVideoSizes() {
        XCTAssertEqual(MovieExporter.Resolution.allCases.map(\.rawValue), ["720p", "1080p", "4K"])
        XCTAssertEqual(MovieExporter.Resolution.standard, .fullHD)
        XCTAssertEqual(MovieExporter.Resolution.hd.maxEdge, 1280)
        XCTAssertEqual(MovieExporter.Resolution.fullHD.maxEdge, 1920)
        XCTAssertEqual(MovieExporter.Resolution.uhd.maxEdge, 3840)
        let deck = Design(title: "d", width: 3840, height: 2160)
        XCTAssertEqual(MovieExporter.videoSize(for: deck, maxEdge: MovieExporter.Resolution.hd.maxEdge),
                       CGSize(width: 1280, height: 720))
        XCTAssertEqual(MovieExporter.videoSize(for: deck, maxEdge: MovieExporter.Resolution.uhd.maxEdge),
                       CGSize(width: 3840, height: 2160))
        let post = Design(title: "p", width: 1080, height: 1080)
        XCTAssertEqual(MovieExporter.videoSize(for: post, maxEdge: MovieExporter.Resolution.uhd.maxEdge),
                       CGSize(width: 1080, height: 1080), "never enlarged")
        XCTAssertTrue(MovieExporter.resolutions(for: deck).contains(.fullHD))
        XCTAssertEqual(MovieExporter.resolutions(for: deck).contains(.uhd), MovieExporter.supports4K(for: deck))
        // 4K is asked of the design's own size: a tall A3 poster is 2716 × 3840.
        let a3 = Design(title: "a3", width: 3508, height: 4961)
        XCTAssertEqual(MovieExporter.videoSize(for: a3, maxEdge: MovieExporter.Resolution.uhd.maxEdge),
                       CGSize(width: 2716, height: 3840))
        XCTAssertEqual(MovieExporter.supports4K(for: a3),
                       MovieExporter.encoderTakes(CGSize(width: 2716, height: 3840)))
    }

    // MARK: every format follows the pages

    @MainActor
    func testPicturesAndSVGsAreAFileAPageNumberedOnlyWhenSeveral() async throws {
        let d = design([false, true, false])
        let chosen = DesignExporter.PageRange.chosen([d.pages[0].id, d.pages[1].id])
        let pngs = try await DesignExporter.exportPages(design: d, range: chosen, current: 0, format: .png, scale: 1)
        written += pngs
        XCTAssertEqual(pngs.map(\.lastPathComponent), ["Deck-1.png", "Deck-2.png"])
        let svgs = try DesignExporter.exportSVGs(design: d, range: chosen, current: 0)
        written += svgs
        XCTAssertEqual(svgs.map(\.lastPathComponent), ["Deck-1.svg", "Deck-2.svg"])
        let one = try DesignExporter.exportSVGs(design: d, range: .chosen([d.pages[2].id]), current: 0)
        written += one
        XCTAssertEqual(one.map(\.lastPathComponent), ["Deck.svg"])
    }

    @MainActor
    func testThePDFHasOnlyTheChosenPages() async throws {
        let d = design([false, false, false, false])
        let url = destination("pdf")
        try await DesignExporter.exportPDF(design: d, range: .chosen([d.pages[3].id, d.pages[0].id]), to: url)
        XCTAssertEqual(CGPDFDocument(url as CFURL)?.numberOfPages, 2)
        let print = destination("pdf")
        try await DesignExporter.exportPrintPDF(design: d, range: .chosen([d.pages[1].id]),
                                                options: PrintLayout.Options(), to: print)
        XCTAssertEqual(CGPDFDocument(print as CFURL)?.numberOfPages, 1)
    }

    // MARK: flatten

    /// 300 dpi from the design's own: 3.125× for a design in pixels, 1× for
    /// one already at 300.
    func testFlattenRendersAt300Dpi() throws {
        XCTAssertEqual(DesignExporter.flattenScale(Design(title: "p")), 3.125, accuracy: 1e-12)
        let a4 = try XCTUnwrap(SizePreset.byId("a4")).makeDesign()
        XCTAssertEqual(DesignExporter.flattenScale(a4), 1, accuracy: 1e-12)
    }

    /// A flattened page is the same size, drawn as a picture: it carries an
    /// image where the vector page has none.
    @MainActor
    func testAFlattenedPDFPageIsAPictureOfTheSameSize() async throws {
        let d = design([false], width: 200, height: 120)
        let vector = destination("pdf"), flat = destination("pdf")
        try await DesignExporter.exportPDF(design: d, to: vector)
        try await DesignExporter.exportPDF(design: d, flatten: true, to: flat)
        let a = try XCTUnwrap(CGPDFDocument(vector as CFURL)?.page(at: 1))
        let b = try XCTUnwrap(CGPDFDocument(flat as CFURL)?.page(at: 1))
        XCTAssertEqual(a.getBoxRect(.mediaBox), b.getBoxRect(.mediaBox))
        XCTAssertFalse(hasImage(a))
        XCTAssertTrue(hasImage(b))
    }

    /// Whether the page's resources hold an image XObject, as
    /// DesignExporterTests counts them.
    private func hasImage(_ page: CGPDFPage) -> Bool {
        guard let pageDict = page.dictionary else { return false }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(pageDict, "Resources", &resources),
              let resources else { return false }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects),
              let xobjects else { return false }
        var count = 0
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
        return count > 0
    }

    // MARK: remember these settings

    /// The shared keys, every one written, the long edge as null when none.
    func testTheLastExportIsTheSharedJSON() throws {
        let last = ExportLast(format: "png", scale: 2, longEdge: nil, jpegQuality: 0.85,
                              transparent: false, pages: "all")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(last.json.utf8)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["format", "scale", "longEdge", "jpegQuality", "transparent", "pages",
                                          "pdfNotes", "pdfCompress", "pptxStyledText",
                                          "suggested", "pdfBookmarks", "colourProfile", "html", "zip", "pngCompress",
                                          "pdfTagged", "audioVoice", "audioClips", "split"])
        XCTAssertTrue(object["longEdge"] is NSNull)
        XCTAssertEqual(object["format"] as? String, "png")
        XCTAssertEqual(object["scale"] as? Double, 2)
        XCTAssertEqual(object["jpegQuality"] as? Double, 0.85)
        XCTAssertEqual(object["transparent"] as? Bool, false)
        XCTAssertEqual(object["pages"] as? String, "all")
        XCTAssertEqual(ExportLast.read(last.json), last)
        XCTAssertEqual(ExportLast.key, "exportLast")
    }

    /// As the Android twin writes it reads here; what does not read takes
    /// the sheet's own default; nothing stored is nothing remembered.
    func testTheLastExportReadsLeniently() throws {
        let android = #"{"format":"jpg","scale":3,"longEdge":1080,"jpegQuality":0.7,"transparent":true,"pages":"chosen"}"#
        let read = try XCTUnwrap(ExportLast.read(android))
        // Written before "pdfTagged": untagged.
        XCTAssertEqual(read, ExportLast(format: "jpg", scale: 3, longEdge: 1080, jpegQuality: 0.7,
                                        transparent: true, pages: "chosen", pdfTagged: false))
        let odd = try XCTUnwrap(ExportLast.read(#"{"format":"webp","scale":9,"pages":"some"}"#))
        XCTAssertEqual(odd.format, "png")
        XCTAssertEqual(odd.scale, 3)
        XCTAssertNil(odd.longEdge)
        XCTAssertEqual(odd.pages, "all")
        XCTAssertNil(ExportLast.read(""))
        XCTAssertNil(ExportLast.read("not json"))
    }
}
