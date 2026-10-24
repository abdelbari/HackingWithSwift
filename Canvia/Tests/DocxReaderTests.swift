// Word documents opened as Docs, and Docs written to Word and read back —
// held to the fixture both phones share (Fixtures/word.docx, from
// Tools/generate_docx_fixture.py, read into Fixtures/word-blocks.json), as
// the Android twin's DocxReaderTest.

import XCTest
@testable import Canvia

final class DocxReaderTests: XCTestCase {

    /// Each block as its JSON, without its id.
    private func withoutIds(_ blocks: [DocBlock]) throws -> [NSDictionary] {
        try blocks.map { b in
            let object = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(b))
            var dict = try XCTUnwrap(object as? [String: Any])
            dict["id"] = nil
            return dict as NSDictionary
        }
    }

    /// Shared with the Android twin's DocxReaderTest.
    func testTheFixtureReadsIntoTheSharedBlocks() throws {
        let golden = try SharedFixture.object("word-blocks")
        let read = try XCTUnwrap(DocxReader.read(try SharedFixture.data("word", ext: "docx"),
                                                 title: DocxReader.title(fromFile: "Café menu.docx")))
        XCTAssertEqual(read.design.title, "Café menu")
        XCTAssertTrue(Docs.isDoc(read.design))
        let want = try XCTUnwrap(golden["blocks"] as? [[String: Any]]).map { $0 as NSDictionary }
        let got = try withoutIds(Docs.blocks(read.design))
        XCTAssertEqual(got.count, want.count)
        for (g, w) in zip(got, want) { XCTAssertEqual(g, w) }
        let page = try XCTUnwrap(golden["docPage"] as? [String: Any])
        XCTAssertEqual(read.design.docPage?.size, page["size"] as? String)
        XCTAssertEqual(read.design.docPage?.margins ?? 0, (page["margins"] as? Double) ?? -1, accuracy: 1e-9)
        XCTAssertEqual(read.design.width, 794, accuracy: 1e-9)
        XCTAssertEqual(read.media, ["image1.png": "word/media/image1.png"])
    }

    func testPicturesGoWhereThePhoneStoredThemOrAreLeftOut() throws {
        let read = try XCTUnwrap(DocxReader.read(try SharedFixture.data("word", ext: "docx"), title: "Menu"))
        let placed = DocxReader.placed(read, stored: ["image1.png": "media:img_1"])
        XCTAssertEqual(Docs.blocks(placed.design).filter { $0.type == Docs.image }.map(\.src), ["media:img_1"])
        let missing = DocxReader.placed(read, stored: [:])
        XCTAssertFalse(Docs.blocks(missing.design).contains { $0.type == Docs.image })
    }

    func testWhatIsNotAWordDocumentReadsAsNothing() throws {
        XCTAssertNil(DocxReader.read(Data("plain words".utf8), title: "x"))
        XCTAssertNil(DocxReader.read(try SharedFixture.data("deck", ext: "pptx"), title: "x"))
    }

    /// The same blocks as the Android twin's round trip: every kind
    /// DocxWriter writes as words, with levels, spans and both kinds of
    /// table.
    func testADocWrittenToWordReadsBackAsTheSameBlocks() throws {
        let blocks = [
            DocBlock(id: "a", type: Docs.title, text: "Annual report"),
            DocBlock(id: "b", type: Docs.h1, text: "Summary"),
            DocBlock(id: "c", type: Docs.h2, text: "Numbers"),
            DocBlock(id: "d", type: Docs.h3, text: "Small print"),
            Docs.withSpans(DocBlock(id: "e", type: Docs.p, text: "We **grew** *fast* and __far__, ~~not~~ slow."), [
                TextSpan(start: 0, end: 2, color: "#c00000"),
                TextSpan(start: 15, end: 18, highlight: "#ffff00"),
                TextSpan(start: 20, end: 23, link: "https://example.com/a?b=1&c=2"),
            ]),
            DocBlock(id: "f", type: Docs.bullet, text: "Toast"),
            DocBlock(id: "g", type: Docs.bullet, text: "Butter", level: 1),
            DocBlock(id: "h", type: Docs.number, text: "First"),
            DocBlock(id: "i", type: Docs.number, text: "Inner", level: 2),
            DocBlock(id: "j", type: Docs.checklist, text: "Done", checked: true),
            DocBlock(id: "k", type: Docs.checklist, text: "To do", checked: false),
            DocBlock(id: "l", type: Docs.quote, text: "Good food, good mood."),
            DocBlock(id: "m", type: Docs.divider),
            DocBlock(id: "n", type: Docs.pagebreak),
            DocBlock(id: "o", type: Docs.table, table: DocTable(rows: [["Item", "Price"], ["Tea, hot", "2 * 3"]], header: true)),
            DocBlock(id: "p", type: Docs.table, table: DocTable(rows: [["a", "b"]], header: false)),
            DocBlock(id: "q", type: Docs.image, src: "media:photo1", alt: "A cup"),
            DocBlock(id: "r", type: Docs.caption, text: "Figure 1"),
        ]
        let setup = DocPage(size: Docs.a4, margins: 54)
        let doc = Docs.withPageSetup(Docs.withBlocks(Docs.started("Report", setup: setup), blocks), setup)
        var out = Data()
        try DocxWriter.write(doc, png: { _ in Data() }, sink: { out.append($0) })
        let read = try XCTUnwrap(DocxReader.read(out, title: "Report"))
        let placed = DocxReader.placed(read, stored: ["image1.png": "media:photo1"])
        XCTAssertEqual(try withoutIds(Docs.blocks(placed.design)), try withoutIds(blocks))
        XCTAssertEqual(Docs.pageSetup(placed.design), setup)
    }

    func testABlocksLevelAndSpansAreWrittenOnlyWhenItHasThem() throws {
        let plain = try withoutIds([DocBlock(type: Docs.bullet, text: "a")])[0]
        XCTAssertNil(plain["level"])
        XCTAssertNil(plain["spans"])
        XCTAssertNil(plain["spansText"])
        let red = [TextSpan(start: 0, end: 1, color: "#ff0000")]
        let deep = try withoutIds([Docs.withSpans(DocBlock(type: Docs.bullet, text: "a", level: 2), red)])[0]
        XCTAssertEqual(deep["level"] as? Int, 2)
        XCTAssertEqual((deep["spans"] as? [Any])?.count, 1)
        // Spans are written with the words they were made for, as a text
        // box's (the shared rule of rich Docs).
        XCTAssertEqual(deep["spansText"] as? String, "a")
        // A span moves with typing, as in a text box: it stays when markers
        // change and when words are added after it.
        let styled = Docs.withSpans(DocBlock(type: Docs.p, text: "ab"), red)
        XCTAssertEqual(Docs.spansOf(Docs.withText(styled, "**ab**")).count, 1)
        XCTAssertEqual(Docs.spansOf(Docs.withText(styled, "abc")), red)
    }

    /// A link DocxWriter writes in the Hyperlink character style reads back
    /// as the link alone; a link with its own colour keeps it.
    func testALinksOwnLookReadsBackAsTheLinkAlone() throws {
        let spans = [
            TextSpan(start: 4, end: 8, link: "https://example.com/1"),
            TextSpan(start: 13, end: 18, color: "#c00000", link: "https://example.com/2"),
        ]
        let blocks = [Docs.withSpans(DocBlock(id: "a", type: Docs.p, text: "see here and there"), spans)]
        var out = Data()
        try DocxWriter.write(Docs.withBlocks(Docs.started("Links"), blocks), png: { _ in Data() }, sink: { out.append($0) })
        let read = try XCTUnwrap(DocxReader.read(out, title: "Links"))
        XCTAssertEqual(try withoutIds(Docs.blocks(read.design)), try withoutIds(blocks))
    }
}
