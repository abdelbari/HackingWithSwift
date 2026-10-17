// A weight and a slant on chosen words: the span keys `weight` and `italic`
// are written only when set and read back alike on both phones — the same
// rows as the Android twin's SpansTest and TextPathsTest — move with every
// edit as a font does, are set from the font sheet opened for the words
// with Mixed where they differ, cleared with the colours and sizes, and
// drawn in the word's own cut, **bold** over a word's own weight by the
// rule both phones share (FontLibrary.boldWeight).

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class WordWeightsTests: XCTestCase {

    private func span(_ start: Int, _ end: Int, font: String? = nil, link: String? = nil,
                      weight: Int? = nil, italic: Bool? = nil) -> TextSpan {
        TextSpan(start: start, end: end, font: font, link: link, weight: weight, italic: italic)
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "words", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    // MARK: the file — the shared rows

    /// Shared: "weight" an Int and "italic" a Bool, each written only when
    /// set; over, remap and tidy treat them as a font — a weight held to
    /// 100…900.
    func testAWordsOwnWeightAndSlantAreSpanKeysAndGoToAndroidAsTheyAre() throws {
        var el = Element.text("Big sale today")
        el.setSpans([span(4, 8, weight: 300, italic: true), span(9, 14, weight: 950)])
        XCTAssertEqual(el.spans, [span(4, 8, weight: 300, italic: true), span(9, 14, weight: 900)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try XCTUnwrap(el.spans?.first)
        XCTAssertEqual(String(decoding: try encoder.encode(first), as: UTF8.self),
                       ##"{"end":8,"italic":true,"start":4,"weight":300}"##)
        let data = try encoder.encode(el)
        let back = try JSONDecoder().decode(Element.self, from: data)
        XCTAssertEqual(back.liveSpans, el.liveSpans)
        // A weight the keys hold as words is none.
        let odd = try JSONDecoder().decode(TextSpan.self, from: Data(##"{"start":0,"end":3,"weight":"700"}"##.utf8))
        XCTAssertNil(odd.weight)
        XCTAssertFalse(odd.says)
        XCTAssertEqual(Spans.normalised([odd]), [])
        // Moved with their words as a font is.
        el.setText("A Big sale today")
        XCTAssertEqual(el.liveSpans, [span(6, 10, weight: 300, italic: true), span(11, 16, weight: 900)])
        // Neighbours alike are one span.
        XCTAssertEqual(Spans.normalised([span(0, 4, weight: 700), span(4, 8, weight: 700)]), [span(0, 8, weight: 700)])
        XCTAssertFalse(span(0, 4, weight: 700).looksLike(span(0, 4, weight: 600)))
        XCTAssertFalse(span(0, 4, italic: true).looksLike(span(0, 4)))
    }

    func testSelectedWordsTakeAWeightAndASlantAndMixedWhenTheyDiffer() {
        var text = Element.text("Big sale today")
        text.fontFamily = "roboto"
        text.fontWeight = 400
        let s = store([text])
        s.select(text.id)
        s.chooseWordFont(text.id, range: NSRange(location: 0, length: 14))
        XCTAssertEqual(s.wordWeight, 400)
        XCTAssertEqual(s.wordItalic, false)
        s.chooseWordFont(text.id, range: NSRange(location: 4, length: 4))
        s.weightWords(300)
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, weight: 300)])
        XCTAssertEqual(s.wordWeight, 300)
        s.wordFontTarget = WordRange(id: text.id, range: NSRange(location: 0, length: 8))
        XCTAssertNil(s.wordWeight, "Mixed")
        s.wordFontTarget = WordRange(id: text.id, range: NSRange(location: 0, length: 3))
        XCTAssertEqual(s.wordWeight, 400)
        // The box's own weight takes the words' own away.
        s.wordFontTarget = WordRange(id: text.id, range: NSRange(location: 4, length: 4))
        s.weightWords(400)
        XCTAssertNil(s.element(text.id)?.spans)
        s.undo()
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, weight: 300)])
        s.italicWords(true)
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, weight: 300, italic: true)])
        XCTAssertEqual(s.wordItalic, true)
        s.wordFontTarget = WordRange(id: text.id, range: NSRange(location: 0, length: 14))
        XCTAssertNil(s.wordItalic, "Mixed")
        s.wordFontTarget = WordRange(id: text.id, range: NSRange(location: 4, length: 4))
        s.italicWords(false)
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, weight: 300)])
        s.undo()
        // Styled, and cleared with the colours and sizes; the link stays.
        XCTAssertTrue(Spans.hasStyles(s.element(text.id)?.liveSpans ?? []))
        s.linkWords("https://x.com", in: WordRange(id: text.id, range: NSRange(location: 4, length: 4)))
        s.clearWordStyles()
        XCTAssertEqual(s.element(text.id)?.liveSpans, [span(4, 8, link: "https://x.com")])
    }

    // MARK: drawing — the shared rows

    /// Shared: **bold** over a word with a weight of its own is 700 when
    /// that is lighter, else the next heavier cut the font has, else its
    /// own; the box's own weight bolded is 700, or 900 in type already bold.
    func testBoldOverAWordsOwnWeightIs700OrTheNextHeavierCut() throws {
        let rows: [(String, Int, Int)] = [
            ("roboto", 400, 700), ("roboto", 300, 700), ("roboto", 700, 800), ("roboto", 800, 900),
            ("roboto", 900, 900), ("lora", 700, 700), ("sans", 300, 700), ("sans", 700, 700), ("montserrat", 600, 700),
        ]
        for (font, weight, bold) in rows {
            XCTAssertEqual(FontLibrary.boldWeight(font, weight), bold, "\(font) \(weight)")
        }
        var el = Element.text("Big **sale** now", fontSize: 40)
        el.fontFamily = "roboto"
        el.setSpans([span(0, 3, weight: 300, italic: true), span(4, 8, weight: 700)])
        let drawn = FontLibrary.attributedString(for: el)
        XCTAssertEqual(drawn.string, "Big sale now")
        func name(_ at: Int) -> String? { (drawn.attribute(.font, at: at, effectiveRange: nil) as? UIFont)?.fontName }
        XCTAssertEqual(name(0), FontLibrary.uiFont(family: "roboto", size: 40, weight: 300, italic: true).fontName)
        XCTAssertEqual(name(5), FontLibrary.uiFont(family: "roboto", size: 40, weight: 800, italic: false).fontName,
                       "bold over the word's own 700 is Roboto's 800")
        XCTAssertEqual(name(10), FontLibrary.uiFont(family: "roboto", size: 40, weight: 400, italic: false).fontName)
        XCTAssertTrue(FontLibrary.hasSizedWords(el), "measured in the words' own cuts")
        // A word upright in an italic box is upright; one in a font of its own at its own weight.
        var slanted = Element.text("a b", fontSize: 40)
        slanted.italic = true
        slanted.setSpans([span(2, 3, font: "lora", italic: false, weight: 700)])
        let upright = FontLibrary.attributedString(for: slanted)
        XCTAssertEqual((upright.attribute(.font, at: 2, effectiveRange: nil) as? UIFont)?.fontName,
                       FontLibrary.uiFont(family: "lora", size: 40, weight: 700, italic: false).fontName)
        XCTAssertEqual((upright.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.fontName,
                       FontLibrary.uiFont(family: "sans", size: 40, weight: 400, italic: true).fontName)
        // Round a curve the outlines take the words' own cuts in too.
        var curved = el
        curved.curve = 60
        curved.w = 400
        curved.h = 300
        XCTAssertNotNil(TextOutliner.path(for: curved))
    }
}
