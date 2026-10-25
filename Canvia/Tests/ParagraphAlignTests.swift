// Alignment a paragraph at a time — an "align" on each entry of
// `paragraphs` — over the shared Fixtures/paragraph-align.json, which the
// Android twin's TextListsTest reads row for row.

import XCTest
@testable import Canvia

final class ParagraphAlignTests: XCTestCase {

    private func element(_ value: Any?) throws -> Element {
        try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(XCTUnwrap(value)))
    }

    private func paragraphs(_ value: Any?) throws -> [TextParagraph]? {
        guard let value, !(value is NSNull) else { return nil }
        return try JSONDecoder().decode([TextParagraph].self, from: SharedFixture.encoded(value))
    }

    /// Shared: each line's alignment as both phones read it.
    func testEachLineReadsItsOwnAlignElseTheBoxs() throws {
        let fixture = try SharedFixture.object("paragraph-align")
        let rows = try XCTUnwrap(fixture["reads"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let name = row["name"] as? String ?? ""
            let el = try element(row["element"])
            XCTAssertEqual(TextLists.alignments(el), row["aligns"] as? [String], name)
            if let markers = row["markers"] as? [Any] {
                XCTAssertEqual(TextLists.markers(el), markers.map { $0 as? String }, name)
            }
        }
    }

    /// Shared: lines aligned while typing (withAlign) and every line at once
    /// (setAlign), and what the box keeps after.
    func testAligningLinesKeepsOnlyTheAlignsThatDifferFromTheBox() throws {
        let fixture = try SharedFixture.object("paragraph-align")
        let rows = try XCTUnwrap(fixture["aligned"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let name = row["name"] as? String ?? ""
            var el = try element(row["element"])
            let align = try XCTUnwrap(row["align"] as? String)
            if row["box"] as? Bool == true {
                el.setAlign(align)
            } else {
                let lines = try XCTUnwrap(row["lines"] as? [Int])
                el = TextLists.withAlign(el, lines[0]...lines[1], align)
            }
            XCTAssertEqual(el.align, row["boxAlign"] as? String, name)
            XCTAssertEqual(el.paragraphs, try paragraphs(row["paragraphs"]), name)
        }
    }

    func testAnAlignIsWrittenOnlyWhenALineHasOneOfItsOwn() throws {
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TextParagraph())) as? [String: Any]
        XCTAssertEqual(plain?.count, 0)
        let own = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TextParagraph(list: "bullet", align: "right")))
            as? [String: Any]
        XCTAssertEqual(own?["align"] as? String, "right")
        XCTAssertEqual(own?["list"] as? String, "bullet")
        // Through a whole element and back.
        var el = Element.text("Head\nBody")
        el.align = "left"
        el = TextLists.withAlign(el, 0...0, "center")
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(TextLists.alignments(back), ["center", "left"])
    }

    /// The words moved through an edit keep each line's alignment.
    func testTypingKeepsEachLinesAlign() {
        var el = Element.text("Head\nBody")
        el.align = "left"
        el = TextLists.withAlign(el, 0...0, "center")
        el.setText("Head\nBody\nMore")
        XCTAssertEqual(TextLists.alignments(el), ["center", "left", "left"])
        XCTAssertEqual(TextLists.sharedAlign(el, lines: 0...1), nil)
        XCTAssertEqual(TextLists.sharedAlign(el, lines: 1...2), "left")
    }

    /// Each line is set in its own paragraph style's alignment.
    func testEachLineIsDrawnInItsOwnAlignment() throws {
        let fixture = try SharedFixture.object("paragraph-align")
        let el = try element((fixture["reads"] as? [[String: Any]])?.first?["element"])
        let drawn = FontLibrary.attributedString(for: el)
        let ns = drawn.string as NSString
        let starts = [0, ns.range(of: "Body one").location, ns.range(of: "Body two").location]
        let aligns = starts.map { (drawn.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle)?.alignment }
        XCTAssertEqual(aligns, [.center, .left, .left])
    }

    /// Shared: PowerPoint gets each paragraph's algn.
    func testPowerPointWritesEachParagraphsAlgn() throws {
        let fixture = try SharedFixture.object("paragraph-align")
        let pptx = try XCTUnwrap(fixture["pptx"] as? [String: Any])
        let el = try element(pptx["element"])
        let expected = try XCTUnwrap(pptx["algn"] as? [Any])
        let written = PptxExporter.paragraphProperties(el, em: 32, design: nil)
        XCTAssertEqual(written.count, expected.count)
        for (properties, algn) in zip(written, expected) {
            if let algn = algn as? String {
                XCTAssertTrue(properties.contains("algn=\"\(algn)\""), properties)
            } else {
                XCTAssertFalse(properties.contains("algn="), properties)
            }
        }
    }

    /// Design to Doc: a box with lines aligned on their own is a block a
    /// line, each aligned as its line is.
    func testADocGetsABlockALineAlignedAsItIs() throws {
        let fixture = try SharedFixture.object("paragraph-align")
        var el = try element((fixture["reads"] as? [[String: Any]])?.first?["element"])
        // Body type, so the box heads nothing.
        el.fontSize = 20
        var design = Design(title: "Doc", width: 800, height: 600)
        design.pages = [Page(elements: [el])]
        let blocks = Docs.blocks(Docs.fromDesign(design)).filter { Docs.textTypes.contains($0.type) }
        XCTAssertEqual(blocks.map { RichText.strip($0.text) }, ["Title", "Body one", "Body two"])
        XCTAssertEqual(blocks.map(\.align), ["center", nil, nil])
    }
}
