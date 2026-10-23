// What an exported PDF says about itself — its title, maker, language,
// bookmarks and alt texts — and the update that writes it: the same cases
// as the Android twin's PdfMetadataTest, with its shared fixture
// Fixtures/pdf-metadata.json.

import XCTest
import PDFKit
@testable import Canvia

final class PDFMetadataTests: XCTestCase {

    private struct Fixture: Decodable {
        var version: String
        var appLanguage: String
        var info: [String: String]
        var infoKeys: [String]
        var lang: String
        var outline: [String]
        var figures: [[String]]
        var displayDocTitle: Bool
        var design: Design
    }

    private func fixture(file: StaticString = #filePath) throws -> Fixture {
        let data: Data
        if let url = Bundle(for: PDFMetadataTests.self).url(forResource: "pdf-metadata", withExtension: "json") {
            data = try Data(contentsOf: url)
        } else {
            let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            data = try Data(contentsOf: here.appendingPathComponent("Fixtures/pdf-metadata.json"))
        }
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    /// The small PDF the Android twin's test lays out: a classic
    /// cross-reference table and trailer, as Core Graphics writes one —
    /// `linked`, with a link on the first page in an annotations array of
    /// its own, as Core Graphics writes a page's links.
    private func plainPDF(pages: Int, lang: String? = nil, linked: Bool = false) -> Data {
        var objects: [String] = []
        objects.append("<</Producer (Quartz PDFContext)>>")
        objects.append("<</Type /Catalog\n/Pages 3 0 R" + (lang.map { "\n/Lang (\($0))" } ?? "") + ">>")
        let kids = (0..<pages).map { "\(4 + $0 * 2) 0 R" }.joined(separator: " ")
        objects.append("<</Type /Pages\n/Count \(pages)\n/Kids [\(kids)]>>")
        for p in 0..<pages {
            let content = "0 0 1 rg\n10 10 100 100 re f\n"
            let annots = linked && p == 0 ? "/Annots \(4 + pages * 2) 0 R\n" : ""
            objects.append("<</Type /Page\n/Resources <</ProcSet [/PDF /Text]>>\n/MediaBox [0 0 1440 810]\n"
                           + annots + "/Contents \(5 + p * 2) 0 R\n/Parent 3 0 R>>")
            objects.append("<</Length \(content.utf8.count)>> stream\n\(content)endstream")
        }
        if linked {
            objects.append("[\(5 + pages * 2) 0 R]")
            objects.append("<</Type /Annot /Subtype /Link /Rect [0 0 100 100] /A <</S /URI /URI (https://example.com)>>>>")
        }
        var text = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(text.utf8.count)
            text += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xrefAt = text.utf8.count
        text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { text += String(format: "%010d 00000 n \n", o) }
        text += "trailer\n<</Size \(objects.count + 1)\n/Root 2 0 R\n/Info 1 0 R>>\nstartxref\n\(xrefAt)\n%%EOF"
        return Data(text.utf8)
    }

    /// A PDF text string as written: "<FEFF…>" read back.
    private func words(_ hex: String) -> String {
        let digits = Array(hex.dropFirst(5).dropLast())
        var units: [UInt16] = []
        var i = 0
        while i + 4 <= digits.count {
            units.append(UInt16(String(digits[i..<i + 4]), radix: 16) ?? 0)
            i += 4
        }
        return String(decoding: units, as: UTF16.self)
    }

    private func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) else { return nil }
        return (text as NSString).substring(with: m.range(at: m.numberOfRanges > 1 ? 1 : 0))
    }

    /// The objects of the update after `from` bytes, by number.
    private func objects(_ pdf: Data, from: Int) -> [Int: String] {
        let tail = String(decoding: pdf[from...], as: UTF8.self)
        guard let regex = try? NSRegularExpression(pattern: #"(\d+) 0 obj\n(.*?)\nendobj"#, options: [.dotMatchesLineSeparators])
        else { return [:] }
        let ns = tail as NSString
        var out: [Int: String] = [:]
        for m in regex.matches(in: tail, range: NSRange(location: 0, length: ns.length)) {
            out[Int(ns.substring(with: m.range(at: 1))) ?? -1] = ns.substring(with: m.range(at: 2))
        }
        return out
    }

    // MARK: the shared fixture

    /// Shared: a 3-page design with what its PDF must say — the
    /// information keys, the language, the outline's titles and each
    /// page's alt texts — the same on both phones.
    func testTheSharedDesignsPDFSaysWhatTheFixtureLists() throws {
        let f = try fixture()
        let info = PDFMetadata.info(f.design, version: f.version)
        XCTAssertEqual(info.map(\.key), f.infoKeys)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: info.map { ($0.key, $0.value) }), f.info)
        XCTAssertEqual(PDFMetadata.language(f.design, appLanguage: f.appLanguage), f.lang)
        XCTAssertEqual(PDFMetadata.bookmarks(f.design, indices: Array(f.design.pages.indices)), f.outline)
        XCTAssertEqual(f.design.pages.map { page in PDFMetadata.figures(f.design, page: page).map(\.alt) }, f.figures)
        XCTAssertTrue(f.displayDocTitle)
    }

    func testTheLanguageIsTheDesignsElseTheAppsAndTheProducerNamesTheVersion() {
        var design = Design(title: "Flyer", width: 100, height: 100)
        XCTAssertEqual(PDFMetadata.language(design, appLanguage: "en-GB"), "en-GB")
        XCTAssertEqual(PDFMetadata.language(design, appLanguage: " "), "en")
        design.language = "de-DE"
        XCTAssertEqual(PDFMetadata.language(design, appLanguage: "en-GB"), "de-DE")
        XCTAssertEqual(PDFMetadata.producer("1.2"), "Canvia 1.2")
        XCTAssertEqual(PDFMetadata.creator, "Canvia")
        // A page's own title, else its number in the design, hidden or not.
        var cover = Page()
        cover.title = "Cover"
        design.pages = [cover, Page(), Page()]
        XCTAssertEqual(PDFMetadata.bookmarks(design, indices: [0, 2]), ["Cover", "Page 3"])
    }

    func testFiguresAreThePicturesWithAltTextThatAreNotDecorativeInReadingOrder() {
        let design = Design(title: "Order", width: 1000, height: 1000)
        func image(_ src: String, x: Double, y: Double, alt: String?) -> Element {
            var el = Element.image(src, w: 100, h: 100)
            el.x = x
            el.y = y
            el.altText = alt
            return el
        }
        let top = image("media:a", x: 600, y: 0, alt: "Top right")
        let left = image("media:b", x: 0, y: 20, alt: "Top left")
        var lower = Element.sticker("star")
        lower.y = 500
        lower.altText = "Star"
        let mute = image("media:c", x: 0, y: 800, alt: nil)
        var hidden = image("media:d", x: 0, y: 0, alt: "Gone")
        hidden.hidden = true
        var decorative = image("media:e", x: 0, y: 0, alt: "Pattern")
        decorative.decorative = true
        let page = Page(elements: [lower, top, mute, left, hidden, decorative])
        let figures = PDFMetadata.figures(design, page: page)
        XCTAssertEqual(figures.map(\.alt), ["Top left", "Top right", "Star"])
        XCTAssertEqual(figures[2], PDFMetadata.Figure(x: 0, y: 500, w: 160, h: 160, alt: "Star"))
    }

    // MARK: the update

    func testTheUpdateWritesTheInformationTheCatalogTheOutlineAndTheAltTexts() throws {
        let f = try fixture()
        let design = f.design
        let pdf = plainPDF(pages: 3, lang: "en-US")
        let figures = design.pages.map { page in
            PDFMetadata.figures(design, page: page).map { g in
                PDFUpdate.Picture(left: g.x * 0.75, bottom: (1080 - g.y - g.h) * 0.75, right: (g.x + g.w) * 0.75,
                                 top: (1080 - g.y) * 0.75, alt: g.alt)
            }
        }
        let metadata = PDFUpdate.Metadata(info: PDFMetadata.info(design, version: "0.1.0"), lang: "fr-FR",
                                          bookmarks: PDFMetadata.bookmarks(design, indices: [0, 1, 2]), figures: figures)
        let out = PDFUpdate.annotated(pdf, metadata: metadata)
        XCTAssertGreaterThan(out.count, pdf.count)
        XCTAssertEqual(out.prefix(pdf.count), pdf)
        let objs = objects(out, from: pdf.count)
        let whole = String(decoding: out, as: UTF8.self)
        let trailer = String(whole[try XCTUnwrap(whole.range(of: "trailer", options: .backwards)).lowerBound...])
        // The trailer points at the new information dictionary, the title
        // in UTF-16 so any language's goes in.
        let info = try XCTUnwrap(first(#"/Info (\d+) 0 R"#, in: trailer).flatMap { Int($0) })
        let infoDict = try XCTUnwrap(objs[info])
        XCTAssertEqual(words(try XCTUnwrap(first(#"/Title (<[0-9A-F]+>)"#, in: infoDict))), "Quarterly review")
        XCTAssertEqual(words(try XCTUnwrap(first(#"/Creator (<[0-9A-F]+>)"#, in: infoDict))), "Canvia")
        XCTAssertEqual(words(try XCTUnwrap(first(#"/Producer (<[0-9A-F]+>)"#, in: infoDict))), "Canvia 0.1.0")
        // The catalog again: the new language in place of the old one, the
        // outline, and the title shown.
        let catalog = try XCTUnwrap(objs[2])
        XCTAssertTrue(catalog.contains("/Type /Catalog"), catalog)
        XCTAssertTrue(catalog.contains("/Lang (fr-FR)"), catalog)
        XCTAssertFalse(catalog.contains("en-US"), catalog)
        XCTAssertTrue(catalog.contains("/ViewerPreferences << /DisplayDocTitle true >>"), catalog)
        let outlines = try XCTUnwrap(first(#"/Outlines (\d+) 0 R"#, in: catalog).flatMap { Int($0) })
        let root = try XCTUnwrap(objs[outlines])
        XCTAssertTrue(root.contains("/Type /Outlines") && root.contains("/Count 3"), root)
        // One entry a page, chained, each to the top of its page.
        var item = first(#"/First (\d+) 0 R"#, in: root).flatMap { Int($0) }
        var titles: [String] = []
        var dests: [String] = []
        while let number = item, let dict = objs[number] {
            titles.append(words(first(#"/Title (<[0-9A-F]+>)"#, in: dict) ?? ""))
            dests.append(first(#"/Dest (\[[^\]]*\])"#, in: dict) ?? "")
            XCTAssertTrue(dict.contains("/Parent \(outlines) 0 R"), dict)
            item = first(#"/Next (\d+) 0 R"#, in: dict).flatMap { Int($0) }
        }
        XCTAssertEqual(titles, ["Intro", "Page 2", "Closing"])
        XCTAssertEqual(dests, ["[4 0 R /XYZ 0 810.00 null]", "[6 0 R /XYZ 0 810.00 null]", "[8 0 R /XYZ 0 810.00 null]"])
        // Each picture's alt text, an annotation over it on its page; the
        // decorative one left out, a page with none not written again.
        let page1 = try XCTUnwrap(objs[4])
        XCTAssertNotNil(objs[6])
        XCTAssertNil(objs[8])
        let widget = try XCTUnwrap(first(#"/Annots \[(\d+) 0 R"#, in: page1).flatMap { Int($0) }.flatMap { objs[$0] })
        XCTAssertTrue(widget.contains("/Subtype /Widget") && widget.contains("/Rect [75.00 435.00 525.00 735.00]"), widget)
        XCTAssertFalse(widget.contains("/A "), widget)
        XCTAssertEqual(words(first(#"/Contents (<[0-9A-F]+>)"#, in: widget) ?? ""), "A red bicycle leaning on a wall")
        // Every offset in the new cross-reference section points at its
        // object.
        let xrefAt = try XCTUnwrap(first(#"startxref\s+(\d+)\s+%%EOF\s*$"#, in: whole).flatMap { Int($0) })
        let bytes = [UInt8](out)
        let section = String(decoding: bytes[xrefAt...], as: UTF8.self).components(separatedBy: "trailer")[0]
        var number = 0
        for line in section.components(separatedBy: "\n").dropFirst() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = line.split(separator: " ")
            if parts.count == 2 { number = Int(parts[0]) ?? 0; continue }
            if parts.count >= 3, parts[2] == "n", let at = Int(parts[0]) {
                XCTAssertTrue(String(decoding: bytes[at...].prefix(16), as: UTF8.self).hasPrefix("\(number) 0 obj"), "object \(number)")
            }
            number += 1
        }
    }

    /// A page's links, which Core Graphics writes in an array of their
    /// own, are kept with its alt texts when the page is written again.
    func testAPagesOwnLinksAreKeptWithItsAltTexts() throws {
        let pdf = plainPDF(pages: 1, linked: true)
        let alt = PDFUpdate.Picture(left: 0, bottom: 0, right: 10, top: 10, alt: "A dog")
        let metadata = PDFUpdate.Metadata(info: [("Title", "Poster")], lang: "en", figures: [[alt]])
        let out = PDFUpdate.annotated(pdf, metadata: metadata)
        let page = try XCTUnwrap(objects(out, from: pdf.count)[4])
        // The array was object 6, holding the link, object 7.
        XCTAssertNotNil(first(#"/Annots \[7 0 R \d+ 0 R\]"#, in: page), page)
        XCTAssertFalse(page.contains("/Annots 6 0 R"), page)
    }

    func testNoBookmarksIsNoOutlineAndAFileItCannotReadIsLeftAlone() {
        let pdf = plainPDF(pages: 2)
        let metadata = PDFUpdate.Metadata(info: [("Title", "Poster")], lang: "en", bookmarks: [nil, "Page 2"])
        // A page with none — a notes page after its page — is passed over.
        let gapped = String(decoding: PDFUpdate.annotated(pdf, metadata: metadata).dropFirst(pdf.count), as: UTF8.self)
        XCTAssertTrue(gapped.contains("/Count 1") && gapped.contains("/Dest [6 0 R /XYZ 0 810.00 null]"), gapped)
        var none = metadata
        none.bookmarks = []
        let plain = String(decoding: PDFUpdate.annotated(pdf, metadata: none), as: UTF8.self)
        XCTAssertFalse(plain.contains("/Outlines"))
        XCTAssertTrue(plain.contains("/Lang (en)") && plain.contains("/DisplayDocTitle true"))
        let junk = Data("not a pdf".utf8)
        XCTAssertEqual(PDFUpdate.annotated(junk, metadata: metadata), junk)
        XCTAssertEqual(PDFUpdate.literal("en-GB"), "(en-GB)")
        XCTAssertEqual(PDFUpdate.textString("Hé"), "<FEFF004800E9>")
    }

    // MARK: the export

    /// The PDF the export writes, read back by PDFKit: its title, maker
    /// and outline; its language and viewer preferences in the file.
    @MainActor
    func testTheExportedPDFCarriesItsTitleOutlineAndLanguage() async throws {
        let f = try fixture()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("meta-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        try await DesignExporter.exportPDF(design: f.design, to: url)
        let document = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(document.pageCount, 3)
        let attributes = document.documentAttributes ?? [:]
        XCTAssertEqual(attributes[PDFDocumentAttribute.titleAttribute] as? String, "Quarterly review")
        XCTAssertEqual(attributes[PDFDocumentAttribute.creatorAttribute] as? String, "Canvia")
        let outline = try XCTUnwrap(document.outlineRoot)
        XCTAssertEqual((0..<outline.numberOfChildren).compactMap { outline.child(at: $0)?.label }, f.outline)
        XCTAssertEqual(outline.child(at: 2)?.destination?.page, document.page(at: 2))
        let raw = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        XCTAssertTrue(raw.contains("/Lang (fr-FR)"))
        XCTAssertTrue(raw.contains("/DisplayDocTitle true"))
        // Bookmarks off: the rest is still said.
        try await DesignExporter.exportPDF(design: f.design, bookmarks: false, to: url)
        XCTAssertNil(PDFDocument(url: url)?.outlineRoot?.child(at: 0))
    }
}
