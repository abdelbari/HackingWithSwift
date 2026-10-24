// The Doc type (Docs): its blocks, pagination, Word export and slides,
// over the Android twin's DocsTest rows and the shared fixtures
// Fixtures/doc.json and Fixtures/doc-document.xml.

import XCTest
@testable import Canvia

final class DocsTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("doc") }

    private func design() throws -> Design {
        try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture()["design"])))
    }

    /// A stand-in for the text layout: 1.35 lines of the size per line, 60
    /// characters a line — the twin's.
    private func measure(_ el: Element) -> Double {
        guard el.type == .text else { return el.h }
        let lines = RichText.strip(el.text ?? "").components(separatedBy: "\n")
            .map { max(1, ($0.count + 59) / 60) }.reduce(0, +)
        return Double(lines) * (el.fontSize ?? 16) * 1.35
    }

    /// Shared: the same units and the same page breaks on both phones.
    func testTheSharedDocBreaksWhereTheFixtureSays() throws {
        let d = try design()
        XCTAssertTrue(Docs.isDoc(d))
        let blocks = Docs.blocks(d)
        XCTAssertEqual(blocks.count, 17)
        let units = try XCTUnwrap(fixture()["units"] as? [[Int]])
        XCTAssertEqual(Docs.units(blocks).map { Array($0) }, units)
        let heights = try XCTUnwrap(fixture()["unitHeights"] as? [Double])
        let content = try XCTUnwrap(fixture()["contentHeight"] as? Double)
        let setup = Docs.pageSetup(d)
        XCTAssertEqual(Double(Docs.pageSize(setup).height) - 2 * Docs.margin(setup), content)
        XCTAssertEqual(Docs.paginate(blocks, heights: heights, contentHeight: content),
                       try XCTUnwrap(fixture()["breaks"] as? [Int]))
    }

    /// Shared: document.xml byte for byte.
    func testTheSharedDocsDocumentXmlIsTheGoldenOne() throws {
        XCTAssertEqual(DocxWriter.documentXml(try design()), try SharedFixture.text("doc-document", ext: "xml"))
    }

    func testPaginationKeepsAHeadingWithWhatFollowsAndHonoursPageBreaks() {
        func b(_ type: String) -> DocBlock { DocBlock(type: type) }
        // A heading that would end a page goes over with its paragraph.
        XCTAssertEqual(Docs.paginate([b(Docs.p), b(Docs.h2), b(Docs.p)], heights: [500, 40, 400], contentHeight: 864), [1])
        // Alone on its page it stays, and the paragraph goes over.
        XCTAssertEqual(Docs.paginate([b(Docs.h1), b(Docs.p)], heights: [40, 900], contentHeight: 864), [1])
        // A page break on an empty page breaks nothing; a tall block has a page of its own.
        XCTAssertEqual(Docs.paginate([b(Docs.pagebreak), b(Docs.p)], heights: [0, 10], contentHeight: 864), [])
        XCTAssertEqual(Docs.paginate([b(Docs.p), b(Docs.image), b(Docs.p)], heights: [10, 1000, 10], contentHeight: 864), [1, 2])
    }

    func testADocsKeysSurviveTheDesignFileAndBlocksWriteOnlyWhatTheyHave() throws {
        let d = try design()
        let round = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(Docs.blocks(round), Docs.blocks(d))
        XCTAssertEqual(Docs.pageSetup(round), DocPage(size: "letter", margins: 72))
        func keys(_ block: DocBlock) throws -> [String: Any] {
            try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? [String: Any])
        }
        XCTAssertEqual(Set(try keys(DocBlock(id: "x", type: Docs.divider)).keys), ["id", "type"])
        let check = try keys(DocBlock(id: "x", type: Docs.checklist, text: "Hi", checked: false))
        XCTAssertEqual(Set(check.keys), ["id", "type", "text", "checked"])
        XCTAssertEqual(check["checked"] as? Bool, false)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
        XCTAssertEqual(json["kind"] as? String, "doc")
        XCTAssertEqual((json["blocks"] as? [Any])?.count, 17)
        // A design that is no Doc writes none of the keys.
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Design())) as? [String: Any])
        XCTAssertNil(plain["kind"])
        XCTAssertNil(plain["blocks"])
        XCTAssertNil(plain["docPage"])
    }

    func testTheDocTypeStartsADocAndHomeTypesItAsOne() throws {
        let made = try XCTUnwrap(SizePreset.byId(Docs.presetId)).makeDesign()
        XCTAssertTrue(Docs.isDoc(made))
        XCTAssertEqual(Docs.blocks(made).map(\.type), [Docs.h1, Docs.p])
        XCTAssertEqual(made.width, 816)
        XCTAssertEqual(made.height, 1056)
        XCTAssertEqual(DesignLibrary.typeOf(made), Docs.presetId)
        // A plain page of the same size is no Doc.
        XCTAssertNotEqual(DesignLibrary.typeOf(Design(width: 816, height: 1056)), Docs.presetId)
        let item = RecentDesign(id: "a", title: "Doc", width: 816, height: 1056, pages: 1, updatedAt: 0, type: Docs.presetId)
        XCTAssertTrue(DesignLibrary.TypeFilter.docs.admits(item))
        XCTAssertFalse(DesignLibrary.TypeFilter.documents.admits(item))
        XCTAssertEqual(ExportSuggestion.suggest(made), "pdf")
        XCTAssertTrue(DesignLibrary.searchText(try design()).lowercased().contains("annual report"))
    }

    func testSixDocTemplatesOpenAsDocs() throws {
        XCTAssertEqual(Docs.templates.map(\.id),
                       ["doc-report", "doc-resume", "doc-letter", "doc-meeting-notes", "doc-proposal", "doc-newsletter"])
        for t in Docs.templates {
            let d = Docs.fromTemplate(t)
            XCTAssertTrue(Docs.isDoc(d), t.id)
            XCTAssertFalse(Docs.blocks(d).isEmpty, t.id)
        }
        let report = Docs.fromTemplate(try XCTUnwrap(Docs.templates.first))
        XCTAssertEqual(report.width, 794)
        XCTAssertEqual(report.height, 1123)
    }

    func testLaidOutOnPagesEachBlockIsSetInItsRole() throws {
        let d = try design()
        let pages = Docs.paginated(d, heightFor: measure)
        XCTAssertFalse(Docs.isDoc(pages))
        XCTAssertGreaterThanOrEqual(pages.pages.count, 2)
        let texts = pages.pages.flatMap(\.elements).filter { $0.type == .text && $0.table == nil }
        XCTAssertEqual(texts.first.flatMap(TextRoles.stored), "h1")
        // The two bullets one list box, the two numbers another.
        XCTAssertEqual(texts.filter { $0.text == "Revenue up 12%\nTwo new markets" && TextLists.isList($0) }.count, 1)
        // Every element inside the margins across.
        let margin = Docs.margin(Docs.pageSetup(d))
        XCTAssertTrue(pages.pages.flatMap(\.elements).allSatisfy { $0.x >= margin - 1e-6 && $0.x + $0.w <= 816 - margin + 1e-6 })
        // The tagged PDF sees headings and a figure.
        let outline = PdfTags.outline(pages)
        XCTAssertTrue(outline.contains("  H1"))
        XCTAssertTrue(outline.contains("  Figure"))
    }

    func testTurnIntoPresentationMakesASlideAFirstLevelHeading() throws {
        let blocks = [
            DocBlock(id: "a", type: Docs.p, text: "Intro"),
            DocBlock(id: "b", type: Docs.h1, text: "One"),
            DocBlock(id: "c", type: Docs.bullet, text: "x"),
            DocBlock(id: "d", type: Docs.h1, text: "Two"),
            DocBlock(id: "e", type: Docs.image, src: "media:p", alt: "A photo"),
        ]
        let slides = Docs.presentation(Docs.withBlocks(try design(), blocks), heightFor: measure)
        XCTAssertEqual(slides.width, 1920)
        XCTAssertEqual(slides.height, 1080)
        XCTAssertEqual(slides.pages.count, 3)
        XCTAssertEqual(slides.pages[0].elements[0].text, "Annual report")
        XCTAssertEqual(slides.pages[1].elements[0].text, "One")
        XCTAssertTrue(TextLists.isList(slides.pages[1].elements[1]))
        XCTAssertEqual(slides.pages[2].elements.last?.altText, "A photo")
        XCTAssertFalse(Docs.isDoc(slides))
    }

    func testTheDocxHoldsItsPartsAPictureEach() throws {
        let d = try design()
        var bytes = Data()
        try DocxWriter.write(d, png: { _ in nil }, sink: { bytes.append($0) })
        let zip = try ZipStore.Reader(data: bytes)
        XCTAssertEqual(Set(zip.entries.keys), [
            "[Content_Types].xml", "_rels/.rels", "docProps/core.xml", "word/document.xml", "word/styles.xml",
            "word/numbering.xml", "word/_rels/document.xml.rels", "word/media/image1.png", "word/media/image2.png",
        ])
        XCTAssertEqual(DocxWriter.pictures(d).count, 2)
        XCTAssertNotNil(Docs.blocks(d)[14].chart)
        XCTAssertTrue(ExportLast.formats.contains("docx"))
    }

    /// Shared: a chart of a kind this build does not know is no picture,
    /// so the pictures after it keep their numbers on both phones.
    func testAChartOfAnUnknownKindIsNoPicture() throws {
        var blocks = Docs.blocks(try design())
        blocks[14].chart?.kind = "hologram"
        let d = Docs.withBlocks(try design(), blocks)
        XCTAssertNil(Docs.chartSpec(blocks[14]))
        XCTAssertEqual(DocxWriter.pictures(d).count, 1)
        XCTAssertEqual(DocxWriter.documentXml(d).components(separatedBy: "<w:drawing>").count - 1, 1)
    }

    @MainActor
    func testABlockTurnedIntoAnotherKeepsItsWords() {
        let typed = DocBlock(id: "x", type: Docs.p, text: "/Plan")
        XCTAssertEqual(DocEditorView.turned(typed, into: Docs.h2).text, "Plan")
        XCTAssertEqual(DocEditorView.turned(typed, into: Docs.checklist).checked, false)
        XCTAssertEqual(DocEditorView.turned(typed, into: Docs.table).table?.rows, [["", ""], ["", ""]])
        XCTAssertEqual(DocEditorView.turned(typed, into: Docs.chart).chart?.kind, "column")
        XCTAssertEqual(DocEditorView.turned(typed, into: Docs.divider).text, "")
        XCTAssertEqual(DocEditorView.typeName(Docs.number), "Numbered list")
    }
}
