// A Doc's words styled as a text box's: spans, alignment, Find, the word
// count and the Word document, over the shared Fixtures/docs_rich.json —
// the Android twin's DocsRichTest, row for row.

import XCTest
@testable import Canvia

final class DocsRichTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("docs_rich") }

    private func design() throws -> Design {
        try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture()["design"])))
    }

    private func json(_ block: DocBlock) throws -> NSDictionary {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(block)) as? NSDictionary)
    }

    /// Shared: every block read and written back key for key.
    func testTheRichBlocksRoundTripKeyForKey() throws {
        let given = try XCTUnwrap((try fixture()["design"] as? [String: Any])?["blocks"] as? [NSDictionary])
        let d = try design()
        let blocks = Docs.blocks(d)
        XCTAssertEqual(blocks.count, given.count)
        for (block, want) in zip(blocks, given) {
            XCTAssertEqual(try json(block), want, block.id)
        }
        let round = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(Docs.blocks(round), blocks)
        XCTAssertEqual(blocks[0].align, "center")
        XCTAssertEqual(blocks[2].align, "justify")
        XCTAssertEqual(Docs.spansOf(blocks[1]), [TextSpan(start: 4, end: 7, color: "#e11d48"),
                                                 TextSpan(start: 21, end: 24, highlight: "#fde68a")])
        XCTAssertEqual(Docs.spansOf(blocks[2]).first?.link, "https://example.com/brief")
    }

    func testLeftIsNoKeyAndSpansMadeForOtherWordsAreDropped() throws {
        let left = try json(DocBlock(id: "x", type: Docs.p, text: "Hi", align: "left"))
        XCTAssertEqual(left, ["id": "x", "type": "p", "text": "Hi"] as NSDictionary)
        let rich = Docs.blocks(try design())[1]
        let stale = DocBlock(id: "x", type: Docs.p, text: "Hi there", spans: rich.spans, spansText: "Other words")
        XCTAssertTrue(Docs.spansOf(stale).isEmpty)
        XCTAssertNil(Docs.withText(stale, "Hi").spans)
    }

    func testTypingInABlockMovesItsSpansWithTheWords() throws {
        let block = Docs.blocks(try design())[1]
        // "Our **big** launch" with "really " typed before "big".
        let typed = Docs.withText(block, "Our really **big** launch is in May.")
        XCTAssertEqual(Docs.spansOf(typed), [TextSpan(start: 11, end: 14, color: "#e11d48"),
                                             TextSpan(start: 28, end: 31, highlight: "#fde68a")])
        XCTAssertEqual(typed.spansText, "Our really big launch is in May.")
        // Linking the words as they read, as the format bar does.
        var el = Docs.asElement(block)
        DesignStore.restyleWords(&el, NSRange(location: 8, length: 6)) { Spans.linking($0, range: $1, link: "https://example.com") }
        let linked = Docs.withElement(block, el)
        XCTAssertEqual(Docs.spansOf(linked).first { $0.start == 8 }?.link, "https://example.com")
        var right = Docs.asElement(block)
        right.align = "right"
        XCTAssertEqual(Docs.withElement(block, right).align, "right")
    }

    func testLaidOutABlocksWordsKeepTheirSpansAndAlignment() throws {
        let d = try design()
        let blocks = Docs.blocks(d)
        func laid(_ i: Int) -> Element? {
            Docs.elements(blocks, unit: i...i, x: 0, y: 0, width: 500, styles: Docs.Styles()) { _ in 20 }.first
        }
        XCTAssertEqual(laid(0)?.align, "center")
        XCTAssertEqual(laid(1)?.liveSpans, Docs.spansOf(blocks[1]))
        XCTAssertEqual(laid(2)?.align, "justify")
        XCTAssertEqual(laid(3)?.align, "right")
        // A checklist's spans move past its box.
        XCTAssertEqual(laid(5)?.liveSpans, [TextSpan(start: 11, end: 17, color: "#2563eb")])
        // Paginated, the PDF and the web page draw them so.
        let page = try XCTUnwrap(Docs.paginated(d) { _ in 20 }.pages.first)
        XCTAssertTrue(page.elements.contains { $0.liveSpans.contains { $0.link == "https://example.com/brief" } })
    }

    func testTheWordDocumentColoursHighlightsLinksAndAligns() throws {
        let d = try design()
        let xml = DocxWriter.documentXml(d)
        XCTAssertTrue(xml.contains("<w:pPr><w:pStyle w:val=\"Heading1\"/><w:jc w:val=\"center\"/></w:pPr>"), xml)
        XCTAssertTrue(xml.contains("<w:r><w:rPr><w:b/><w:color w:val=\"E11D48\"/></w:rPr><w:t xml:space=\"preserve\">big</w:t></w:r>"))
        XCTAssertTrue(xml.contains("<w:r><w:rPr><w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"FDE68A\"/></w:rPr>"
                                   + "<w:t xml:space=\"preserve\">May</w:t></w:r>"))
        XCTAssertTrue(xml.contains("<w:hyperlink r:id=\"rId3\"><w:r><w:rPr><w:color w:val=\"2563EB\"/><w:u w:val=\"single\"/></w:rPr>"
                                   + "<w:t xml:space=\"preserve\">brief</w:t></w:r></w:hyperlink>"))
        XCTAssertTrue(xml.contains("<w:jc w:val=\"both\"/>"))
        XCTAssertTrue(xml.contains("<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"1\"/></w:numPr><w:jc w:val=\"right\"/>"))
        XCTAssertEqual(DocxWriter.links(d), ["https://example.com/brief": "rId3"])
    }

    /// Shared: Find goes through a Doc's blocks and cells, in order.
    @MainActor
    func testFindSearchesEveryBlockAndCellAndReplacesInPlace() throws {
        let d = try design()
        let found = DesignStore.matches(in: d, for: "launch", caseSensitive: false, wholeWord: false)
        let want = try XCTUnwrap(fixture()["launchMatches"] as? [[String: Any]])
        XCTAssertEqual(found.count, want.count)
        for (m, w) in zip(found, want) {
            XCTAssertEqual(m.kind, .doc)
            XCTAssertEqual(m.blockId, w["blockId"] as? String)
            XCTAssertEqual(m.row, w["row"] as? Int)
            XCTAssertEqual(m.col, w["col"] as? Int)
            XCTAssertEqual(m.range.location, w["start"] as? Int)
            XCTAssertEqual(NSMaxRange(m.range), w["end"] as? Int)
        }
        // One replaced: in a styled block, the spans after it move along.
        let one = try XCTUnwrap(DesignStore.replacingOne(d, found[1], with: "release"))
        let block = Docs.blocks(one)[1]
        XCTAssertEqual(block.text, "Our **big** release is in May.")
        XCTAssertEqual(Docs.spansOf(block).last, TextSpan(start: 22, end: 25, highlight: "#fde68a"))
        // In a cell, as plain text.
        let cell = try XCTUnwrap(DesignStore.replacingOne(d, found[3], with: "Open"))
        XCTAssertEqual(Docs.tableRows(Docs.blocks(cell)[4]).rows[1], ["Open the site", "Ana"])
        // All at once, as one step.
        let store = DesignStore(design: d)
        XCTAssertEqual(store.replaceAll("launch", with: "release"), 5)
        XCTAssertTrue(store.matches(for: "launch").isEmpty)
        XCTAssertEqual(Docs.blocks(store.design)[5].text, "Book the release venue")
        store.undo()
        XCTAssertEqual(store.matches(for: "launch").count, 5)
        // The next match after a replacement is the one after it.
        let now = DesignStore.matches(in: one, for: "launch", caseSensitive: false, wholeWord: false)
        XCTAssertEqual(DesignStore.matchAfter(replacing: found[1], at: 1, length: 7, in: now), 1)
    }

    /// Shared: the More menu's word count.
    func testTheWordCountReadsTheBlocksAndTheCells() throws {
        let d = try design()
        XCTAssertEqual(Docs.wordCount(d), try XCTUnwrap(fixture()["words"] as? Int))
        XCTAssertEqual(Docs.wordCountLine(Docs.wordCount(d)), try XCTUnwrap(fixture()["wordCountLine"] as? String))
        XCTAssertEqual(Docs.wordCountLine(1234), "1,234 words · 6 min read")
        XCTAssertEqual(Docs.wordCountLine(1), "1 word · 1 min read")
        XCTAssertEqual(Docs.readingMinutes(0), 1)
        XCTAssertEqual(Docs.readingMinutes(300), 2)
        // Any Unicode space parts words, and a word needs a letter or a
        // number — the same on both phones.
        let rows = try XCTUnwrap(fixture()["wordRows"] as? [[String: Any]])
        for row in rows {
            let text = try XCTUnwrap(row["text"] as? String)
            XCTAssertEqual(Docs.countWords(text), row["words"] as? Int, text)
        }
        let nbsp = Docs.withBlocks(d, [DocBlock(id: "n", type: Docs.p, text: "deux\u{a0}mots")])
        XCTAssertEqual(Docs.wordCount(nbsp), 2)
    }
}
