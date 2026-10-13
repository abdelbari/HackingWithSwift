// Fonts and links on chosen words: the span keys `font` and `link` are
// written only when set and read back alike on both phones — the same rows
// as the Android twin's — move with every edit as colours and sizes do, are
// drawn, measured and outlined in the word's own face, linked words
// underlined in the link colour, and a link is clickable over the lines its
// words are set on: a link that wraps is two rectangles.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class WordFontsAndLinksTests: XCTestCase {

    private let lora = "lora"
    private let site = "https://canvia.app"

    private func span(_ start: Int, _ end: Int, color: String? = nil, scale: Double? = nil,
                      font: String? = nil, link: String? = nil) -> TextSpan {
        TextSpan(start: start, end: end, color: color, scale: scale, font: font, link: link)
    }

    private func keys(_ span: TextSpan) throws -> [String: Any] {
        let data = try JSONEncoder().encode(span)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: the file — the shared rows

    /// One row of the span JSON both phones read and write alike: the JSON
    /// read, the span it reads as, and the keys it is written back with.
    private struct SpanRow {
        var json: String
        var expected: TextSpan
        var written: [String]
    }

    private var rows: [SpanRow] {
        [
            SpanRow(json: #"{"start":0,"end":3,"font":"lora"}"#,
                expected: span(0, 3, font: "lora"), written: ["end", "font", "start"]),
            SpanRow(json: #"{"start":4,"end":8,"link":"https://canvia.app"}"#,
                expected: span(4, 8, link: "https://canvia.app"), written: ["end", "link", "start"]),
            SpanRow(json: ##"{"start":0,"end":5,"color":"#ff0000","scale":1.25,"font":"custom:0123456789ab","link":"mailto:hi@canvia.app"}"##,
                expected: span(0, 5, color: "#ff0000", scale: 1.25, font: "custom:0123456789ab", link: "mailto:hi@canvia.app"),
                written: ["color", "end", "font", "link", "scale", "start"]),
            SpanRow(json: ##"{"start":2,"end":4,"color":"#00ff00"}"##,
                expected: span(2, 4, color: "#00ff00"), written: ["color", "end", "start"]),
        ]
    }

    func testTheSharedJSONRows() throws {
        for row in rows {
            let read = try JSONDecoder().decode(TextSpan.self, from: Data(row.json.utf8))
            XCTAssertEqual(read, row.expected, row.json)
            XCTAssertEqual(try keys(read).keys.sorted(), row.written, row.json)
            let back = try JSONDecoder().decode(TextSpan.self, from: JSONEncoder().encode(read))
            XCTAssertEqual(back, read, row.json)
        }
    }

    func testFontsAndLinksSurviveTheDesignFile() throws {
        var el = Element.text("Visit our shop")
        el.setSpans([span(0, 5, font: lora), span(10, 14, link: site)])
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.liveSpans, [span(0, 5, font: lora), span(10, 14, link: site)])
        XCTAssertEqual(back.spansText, "Visit our shop")
    }

    // MARK: tidying

    func testABlankFontAndAnUnreadableLinkSayNothing() {
        XCTAssertEqual(Spans.normalised([span(0, 2, font: "  "), span(2, 4, link: "javascript:alert(1)")]), [])
        XCTAssertEqual(Spans.normalised([span(0, 2, font: " lora ")]), [span(0, 2, font: "lora")])
        XCTAssertEqual(Spans.normalised([span(0, 2, link: "HTTPS://canvia.app")]), [span(0, 2, link: "https://canvia.app")])
    }

    func testARunSplitsWhereAnyOfTheFourDiffers() {
        XCTAssertEqual(Spans.normalised([span(0, 2, font: lora), span(2, 4, font: lora)]), [span(0, 4, font: lora)])
        XCTAssertEqual(Spans.normalised([span(0, 2, font: lora), span(2, 4, font: "oswald")]),
                       [span(0, 2, font: lora), span(2, 4, font: "oswald")])
        XCTAssertEqual(Spans.normalised([span(0, 2, color: "#ff0000"), span(2, 4, color: "#ff0000", link: site)]),
                       [span(0, 2, color: "#ff0000"), span(2, 4, color: "#ff0000", link: site)])
    }

    func testAFaceOverWordsKeepsTheirColourAndLink() {
        let spans = [span(0, 4, color: "#ff0000"), span(4, 8, link: site)]
        XCTAssertEqual(Spans.fonting(spans, range: NSRange(location: 2, length: 4), font: lora),
                       [span(0, 2, color: "#ff0000"), span(2, 4, color: "#ff0000", font: lora),
                        span(4, 6, font: lora, link: site), span(6, 8, link: site)])
        XCTAssertEqual(Spans.linking([span(0, 4, link: site)], range: NSRange(location: 0, length: 4), link: nil), [])
    }

    // MARK: editing moves them

    func testRemapKeepsFontAndLinkSpansOnTheirWords() {
        // Typed inside: the word keeps its face.
        XCTAssertEqual(Spans.remap("big sale today", "big saale today", [span(4, 8, font: lora)]), [span(4, 9, font: lora)])
        // Typed at its end: not taken in.
        XCTAssertEqual(Spans.remap("big sale today", "big sales today", [span(4, 8, link: site)]), [span(4, 8, link: site)])
        // Deleted before: moved back.
        XCTAssertEqual(Spans.remap("a big sale", "big sale", [span(6, 10, font: lora)]), [span(4, 8, font: lora)])
        // Deleted inside: shrunk.
        XCTAssertEqual(Spans.remap("crimson", "crson", [span(0, 7, font: lora, link: site)]),
                       [span(0, 5, font: lora, link: site)])
        // Deleted whole: gone.
        XCTAssertEqual(Spans.remap("big sale today", "big  today", [span(4, 8, font: lora)]), [])
    }

    // MARK: the store

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "words", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    func testAFacePickedForTheWordsIsOneStepAndTheBoxsOwnGivesThemBack() {
        let text = Element.text("Big sale")
        let s = store([text])
        s.select(text.id)
        s.chooseWordFont(text.id, range: NSRange(location: 4, length: 4))
        XCTAssertEqual(s.wordFontTarget, WordRange(id: text.id, range: NSRange(location: 4, length: 4)))
        XCTAssertEqual(s.wordFont, "sans", "the box's own, before")
        s.fontWords(lora)
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, font: lora)])
        XCTAssertEqual(s.wordFont, lora)
        s.fontWords("sans-serif")
        XCTAssertNil(s.element(text.id)?.spans, "an old name for the box's own face is the box's own")
        s.undo()
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, font: lora)])
        s.undo()
        XCTAssertNil(s.element(text.id)?.spans)
    }

    func testAWholeBoxFaceTakesTheWordsFacesAway() {
        var el = Element.text("Big sale")
        el.setSpans([span(0, 3, color: "#ff0000", font: lora), span(4, 8, font: "oswald")])
        el.setFontFamily("roboto")
        XCTAssertEqual(el.fontFamily, "roboto")
        XCTAssertEqual(el.liveSpans, [span(0, 3, color: "#ff0000")], "colours stay, faces go")
    }

    func testClearingWordStylesTakesFacesAndLeavesLinks() {
        var text = Element.text("Big sale")
        text.setSpans([span(0, 3, color: "#ff0000", font: lora), span(4, 8, scale: 2, link: site)])
        let s = store([text])
        s.select(text.id)
        XCTAssertTrue(Spans.hasStyles(text.liveSpans))
        s.clearWordStyles()
        XCTAssertEqual(s.element(text.id)?.liveSpans, [span(4, 8, link: site)])
        XCTAssertFalse(Spans.hasStyles(s.element(text.id)?.liveSpans ?? []), "nothing left for Clear to take")
    }

    func testLinkingTheWordsIsOneStep() {
        let text = Element.text("Read the terms")
        let s = store([text])
        s.select(text.id)
        let words = WordRange(id: text.id, range: NSRange(location: 9, length: 5))
        s.chooseWordLink(text.id, range: words.range)
        XCTAssertEqual(s.wordLinkTarget, words)
        XCTAssertNil(s.sharedLink(of: words))
        s.linkWords("canvia.app/terms", in: words)
        XCTAssertEqual(s.element(text.id)?.spans, [span(9, 14, link: "https://canvia.app/terms")],
                       "read as the element's link prompt reads it")
        XCTAssertEqual(s.sharedLink(of: words), "https://canvia.app/terms")
        s.linkWords(nil, in: words)
        XCTAssertNil(s.element(text.id)?.spans)
        s.undo()
        XCTAssertEqual(s.sharedLink(of: words), "https://canvia.app/terms")
    }

    func testTheDesignsFontsOfYourOwnTakeInTheWords() {
        var el = Element.text("Big sale")
        el.setSpans([span(4, 8, font: "custom:0123456789ab")])
        var design = Design(title: "own", width: 500, height: 500)
        design.pages[0].elements = [el]
        XCTAssertEqual(el.fontKeys, ["sans", "custom:0123456789ab"])
        XCTAssertEqual(CustomFonts.used(in: design), ["0123456789ab"])
        XCTAssertTrue(FontLibrary.usedIn(design).contains("custom:0123456789ab"))
    }

    // MARK: drawing and measuring

    func testAWordIsDrawnInItsFaceBoldStillBoldAndSized() throws {
        var el = Element.text("Big **sale** now", fontSize: 40)
        el.setSpans([span(4, 12, scale: 1.5, font: lora)])
        let drawn = FontLibrary.attributedString(for: el)
        XCTAssertEqual(drawn.string, "Big sale now")
        let bold = try XCTUnwrap(drawn.attribute(.font, at: 5, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(bold.fontName, FontLibrary.uiFont(family: lora, size: 40, weight: 700, italic: false).fontName)
        XCTAssertEqual(bold.pointSize, 60, accuracy: 0.01)
        let plain = try XCTUnwrap(drawn.attribute(.font, at: 10, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(plain.fontName, FontLibrary.uiFont(family: lora, size: 40, weight: 400, italic: false).fontName)
        let box = try XCTUnwrap(drawn.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(box.fontName, FontLibrary.uiFont(family: "sans", size: 40, weight: 400, italic: false).fontName)
        XCTAssertEqual(FontLibrary.resolveWeight(400, bold: true), 700)
        XCTAssertEqual(FontLibrary.resolveWeight(700, bold: true), 900)
        XCTAssertEqual(FontLibrary.resolveWeight(300, bold: false), 300)
    }

    func testAWordInAnotherFaceIsMeasured() {
        var el = Element.text("Big sale", fontSize: 40, w: 1000)
        let width = FontLibrary.lineWidth(for: el)
        el.setSpans([span(0, 8, font: "anton")])
        XCTAssertTrue(FontLibrary.hasSizedWords(el))
        XCTAssertNotEqual(FontLibrary.lineWidth(for: el), width, "measured in the word's face")
    }

    func testLinkedWordsAreUnderlinedInTheLinkColourUnlessColoured() throws {
        var el = Element.text("Go here or there", fontSize: 40)
        el.setSpans([span(3, 7, link: site), span(11, 16, color: "#ff0000", link: site)])
        let drawn = FontLibrary.attributedString(for: el)
        XCTAssertEqual((drawn.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? UIColor)?.hexString, Spans.linkColour)
        XCTAssertEqual(drawn.attribute(.underlineStyle, at: 4, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertEqual(drawn.attribute(Spans.linkKey, at: 4, effectiveRange: nil) as? String, site)
        XCTAssertEqual((drawn.attribute(.foregroundColor, at: 12, effectiveRange: nil) as? UIColor)?.hexString, "#ff0000")
        XCTAssertEqual(drawn.attribute(.underlineStyle, at: 12, effectiveRange: nil) as? Int, NSUnderlineStyle.single.rawValue)
        XCTAssertNil(drawn.attribute(.underlineStyle, at: 0, effectiveRange: nil))
        XCTAssertEqual(Spans.linkColour, "#2563eb")
    }

    // MARK: where a link is clicked

    func testALinkWrappingOverTwoLinesIsTwoRects() throws {
        let font = UIFont.systemFont(ofSize: 20)
        let text = NSMutableAttributedString(string: "aaaa bbbb", attributes: [.font: font])
        text.addAttribute(Spans.linkKey, value: site, range: NSRange(location: 0, length: 9))
        let oneLine = WordLinks.lineRects(text, width: 1000)
        XCTAssertEqual(oneLine.count, 1)
        let lines = WordLinks.lineRects(text, width: 70)
        XCTAssertEqual(lines.count, 2)
        let first = try XCTUnwrap(lines.first), second = try XCTUnwrap(lines.last)
        XCTAssertEqual(first.url, site)
        XCTAssertEqual(second.url, site)
        XCTAssertGreaterThan(second.rect.minY, first.rect.minY, "the second line below the first")
        XCTAssertEqual(first.rect.minX, 0, accuracy: 0.5)
        XCTAssertLessThan(first.rect.width, 70, "the space at the line's end is left off")
        XCTAssertGreaterThan(first.rect.height, 0)
    }

    func testOnlyTheLinkedWordsAreLinkedTheBoxsOwnLinkElsewhere() throws {
        var el = Element.text("Go here now", fontSize: 40, w: 600)
        el.x = 100
        el.y = 50
        el.link = site
        el.setSpans([span(3, 7, link: "https://canvia.app/here")])
        var design = Design(title: "links", width: 1000, height: 1000)
        design.pages[0].elements = [el]
        let page = design.pages[0]
        let words = try XCTUnwrap(WordLinks.areas(of: el).first)
        XCTAssertEqual(WordLinks.areas(of: el).count, 1)
        let onWords = CGPoint(x: words.rect.midX, y: words.rect.midY)
        XCTAssertEqual(Links.at(design: design, page: page, point: onWords), "https://canvia.app/here")
        XCTAssertEqual(Links.at(design: design, page: page, point: CGPoint(x: 105, y: 55)), site,
                       "the box's own link away from the words")
        let areas = Links.areas(design: design, page: page)
        XCTAssertEqual(areas.map(\.url), [site, "https://canvia.app/here"])
        let svg = SVGExporter.svg(design: design, page: page)
        XCTAssertTrue(svg.contains("href=\"https://canvia.app/here\""), svg)
        XCTAssertTrue(svg.contains("fill-opacity=\"0\""))
    }

    func testATurnedBoxsLinkedWordsTurnWithIt() throws {
        var el = Element.text("Go here now", fontSize: 40, w: 600)
        el.x = 100
        el.y = 300
        el.rotation = 90
        el.setSpans([span(3, 7, link: site)])
        var design = Design(title: "turned", width: 1000, height: 1000)
        design.pages[0].elements = [el]
        let words = try XCTUnwrap(WordLinks.areas(of: el).first)
        XCTAssertGreaterThan(words.rect.height, words.rect.width, "upright words lie across a turned box")
        XCTAssertEqual(Links.at(design: design, page: design.pages[0], point: CGPoint(x: words.rect.midX, y: words.rect.midY)),
                       site)
    }
}
