// Colours and sizes on chosen words: the spans move with every edit by the
// same rules as on the Android twin — one table of test vectors, run on both
// phones — are written to the file and read back, are drawn, measured and
// exported, and each press of the typing bar is a step of its own.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class WordSpansTests: XCTestCase {

    private let red = "#ff0000"
    private let blue = "#0000ff"

    private func span(_ start: Int, _ end: Int, _ color: String? = nil, scale: Double? = nil) -> TextSpan {
        TextSpan(start: start, end: end, color: color, scale: scale)
    }

    // MARK: the shared test vectors

    /// One row of the table the Android twin runs too, row for row: spans
    /// made for `spansText`, the words edited from `old` to `new`, and the
    /// spans Spans.remap gives over the box's live spans, as every edit runs
    /// them. A row whose words do not change is the spans tidied.
    private struct Vector {
        var name: String
        var spansText: String
        var old: String
        var new: String
        var spans: [TextSpan]
        var expected: [TextSpan]
    }

    private func r(_ start: Int, _ end: Int) -> TextSpan { span(start, end, red) }
    private func b(_ start: Int, _ end: Int) -> TextSpan { span(start, end, blue) }

    // The same rows, strings, spans and expected spans as the Android twin's
    // SpansTest table, in the same order. Typed in, words take a span only
    // strictly inside it; typed over letters all in one span, they take it,
    // its ends included (Canva keeps the colour of a word typed over).
    private var vectors: [Vector] {
        let many = String(repeating: "x", count: 300)
        return [
            Vector(name: "typing inside a span extends it", spansText: "big sale today", old: "big sale today", new: "big saale today",
                   spans: [r(4, 8)], expected: [r(4, 9)]),
            Vector(name: "typing at a span's end does not extend it", spansText: "big sale today", old: "big sale today", new: "big sales today",
                   spans: [r(4, 8)], expected: [r(4, 8)]),
            Vector(name: "typing at a span's start does not extend it", spansText: "big sale", old: "big sale", new: "big Xsale",
                   spans: [r(4, 8)], expected: [r(5, 9)]),
            Vector(name: "typing before a span shifts it", spansText: "big sale", old: "big sale", new: "a big sale",
                   spans: [r(4, 8)], expected: [r(6, 10)]),
            Vector(name: "typing after a span leaves it", spansText: "red car", old: "red car", new: "red cars",
                   spans: [r(0, 3)], expected: [r(0, 3)]),
            Vector(name: "deleting inside a span shrinks it", spansText: "crimson", old: "crimson", new: "crson",
                   spans: [r(0, 7)], expected: [r(0, 5)]),
            Vector(name: "deleting across a span's start clips it", spansText: "big sale today", old: "big sale today", new: "bile today",
                   spans: [r(4, 8)], expected: [r(2, 4)]),
            Vector(name: "deleting across a span's end clips it", spansText: "red car", old: "red car", new: "rar",
                   spans: [r(0, 3)], expected: [r(0, 1)]),
            Vector(name: "deleting a whole span removes it", spansText: "big sale today", old: "big sale today", new: "big  today",
                   spans: [r(4, 8)], expected: []),
            Vector(name: "replacing letters strictly inside a span keeps it", spansText: "big sale today", old: "big sale today", new: "big sole today",
                   spans: [r(4, 8)], expected: [r(4, 8)]),
            Vector(name: "replacing letters up to a span's end keeps it", spansText: "big red sale", old: "big red sale", new: "big rose sale",
                   spans: [r(4, 7)], expected: [r(4, 8)]),
            Vector(name: "a misspelling corrected at a span's start keeps it", spansText: "teh car", old: "teh car", new: "the car",
                   spans: [r(0, 3)], expected: [r(0, 3)]),
            Vector(name: "words typed over a whole span take it", spansText: "red car", old: "red car", new: "blue car",
                   spans: [r(0, 3)], expected: [r(0, 4)]),
            Vector(name: "replacing text across two spans clips both", spansText: "red blue", old: "red blue", new: "reXue",
                   spans: [r(0, 3), b(4, 8)], expected: [r(0, 2), b(3, 5)]),
            Vector(name: "spans past the end are cut to it", spansText: "red car", old: "red car", new: "red",
                   spans: [r(0, 7)], expected: [r(0, 3)]),
            Vector(name: "adjacent identical spans merge", spansText: "abcdef", old: "abcdef", new: "abcdef",
                   spans: [r(0, 2), r(2, 4)], expected: [r(0, 4)]),
            Vector(name: "overlapping input is resolved last-wins", spansText: "abcdef", old: "abcdef", new: "abcdef",
                   spans: [r(0, 5), b(2, 4)], expected: [r(0, 2), b(2, 4), r(4, 5)]),
            Vector(name: "more than 100 spans are truncated", spansText: many, old: many, new: many,
                   spans: (0..<150).map { r(2 * $0, 2 * $0 + 1) }, expected: (0..<100).map { r(2 * $0, 2 * $0 + 1) }),
            Vector(name: "spans made for other words are ignored", spansText: "old words", old: "new words", new: "new words!",
                   spans: [r(0, 3)], expected: []),
            Vector(name: "a size of 1, a blank colour and an empty stretch say nothing", spansText: "abcdef", old: "abcdef", new: "abcdef",
                   spans: [span(0, 2, scale: 1), span(2, 3, ""), r(4, 4)], expected: []),
            Vector(name: "a size is held between 0.3 and 4", spansText: "abcdef", old: "abcdef", new: "abcdef",
                   spans: [span(0, 2, scale: 9), span(2, 4, scale: 0.1)],
                   expected: [span(0, 2, scale: 4), span(2, 4, scale: 0.3)]),
            Vector(name: "a size and a colour are kept apart", spansText: "big sale", old: "big sale", new: "big sale",
                   spans: [span(0, 3, scale: 1.25), span(4, 8, red, scale: 0.8)],
                   expected: [span(0, 3, scale: 1.25), span(4, 8, red, scale: 0.8)]),
            Vector(name: "offsets are UTF-16 units", spansText: "\u{1F600} ok", old: "\u{1F600} ok", new: "a\u{1F600} ok",
                   spans: [r(0, 2)], expected: [r(1, 3)]),
            Vector(name: "a face typed before a coloured face stays plain",
                   spansText: "\u{1F600}", old: "\u{1F600}", new: "\u{1F603}\u{1F600}",
                   spans: [r(0, 2)], expected: [r(2, 4)]),
            Vector(name: "a face retyped with the letter after it never leaves half a face coloured",
                   spansText: "a\u{1F600}bc", old: "a\u{1F600}bc", new: "a\u{1F603}xc",
                   spans: [r(0, 3), b(4, 5)], expected: [r(0, 1), b(4, 5)]),
            Vector(name: "a face changed in its first half never leaves half a face coloured",
                   spansText: "a\u{1F514}c", old: "a\u{1F514}c", new: "x\u{1F914}c",
                   spans: [b(1, 4)], expected: [b(3, 4)]),
            Vector(name: "a face typed inside a run of faces takes its colour",
                   spansText: "\u{1F600}\u{1F600}", old: "\u{1F600}\u{1F600}", new: "\u{1F600}\u{1F603}\u{1F600}",
                   spans: [r(0, 4)], expected: [r(0, 6)]),
        ]
    }

    func testTheSharedVectors() {
        XCTAssertEqual(vectors.count, 27)
        for v in vectors {
            let live = Spans.live(v.spans, madeFor: v.spansText, plain: v.old)
            XCTAssertEqual(Spans.remap(v.old, v.new, live), v.expected, v.name)
        }
    }

    func testMoreThanAHundredSpansKeepTheFirstHundred() {
        let words = String(repeating: "a", count: 300)
        let many = (0..<150).map { $0 % 2 == 0 ? r(2 * $0, 2 * $0 + 1) : b(2 * $0, 2 * $0 + 1) }
        let kept = Spans.remap(words, words, many)
        XCTAssertEqual(kept.count, Spans.maxCount)
        XCTAssertEqual(kept.last?.start, 198)
        XCTAssertEqual(Spans.normalised(many).count, Spans.maxCount)
    }

    func testSpansMadeForOtherWordsAreIgnored() {
        XCTAssertEqual(Spans.live([r(0, 3)], madeFor: "old words", plain: "new words"), [])
        XCTAssertEqual(Spans.live([r(0, 3)], madeFor: "new words", plain: "new words"), [r(0, 3)])
    }

    func testAPlusAndAMinusMultiplyTheSizeAndBackAt1ThereIsNone() {
        let sale = NSRange(location: 4, length: 4)
        let bigger = Spans.scaling([], range: sale, by: Spans.larger)
        XCTAssertEqual(bigger, [span(4, 8, scale: 1.25)])
        let twice = Spans.scaling(bigger, range: sale, by: Spans.larger)
        XCTAssertEqual(twice, [span(4, 8, scale: 1.5625)])
        // To four places, so three steps down undo three steps up.
        let thrice = Spans.scaling(twice, range: sale, by: Spans.larger)
        XCTAssertEqual(thrice, [span(4, 8, scale: 1.9531)])
        var back = thrice
        for _ in 0..<3 { back = Spans.scaling(back, range: sale, by: Spans.smaller) }
        XCTAssertEqual(back, [])
        // Held at the ends.
        var big: [TextSpan] = []
        for _ in 0..<10 { big = Spans.scaling(big, range: NSRange(location: 0, length: 3), by: Spans.larger) }
        XCTAssertEqual(big.first?.scale, Spans.scaleRange.upperBound)
    }

    // MARK: the file

    func testTheKeysRoundTripAndAreOptional() throws {
        let json = ##"{"type":"text","text":"Big **sale**","spans":[{"start":4,"end":8,"color":"#ff0000","scale":1.25}],"spansText":"Big sale"}"##
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertEqual(el.spans, [span(4, 8, red, scale: 1.25)], "offsets are into the words as they read")
        XCTAssertEqual(el.spansText, "Big sale")
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.spans, el.spans)
        XCTAssertEqual(back.spansText, "Big sale")

        let old = try JSONDecoder().decode(Element.self, from: Data(#"{"type":"text","text":"Sale"}"#.utf8))
        XCTAssertNil(old.spans)
        let oldJSON = try XCTUnwrap(String(data: JSONEncoder().encode(old), encoding: .utf8))
        XCTAssertFalse(oldJSON.contains("spans"), "an old design is written back without the keys")
    }

    func testSpansMadeForOtherWordsAreDroppedOnTheNextSave() throws {
        // The words changed by a build that does not know spans.
        let json = ##"{"type":"text","text":"Big deal","spans":[{"start":4,"end":8,"color":"#ff0000"}],"spansText":"Big sale"}"##
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertNil(el.spans)
        XCTAssertNil(el.spansText)
        let written = try XCTUnwrap(String(data: JSONEncoder().encode(el), encoding: .utf8))
        XCTAssertFalse(written.contains("spans"))
    }

    func testAColourOnlySpanWritesNoScale() throws {
        var el = Element.text("Big sale")
        el.setSpans([span(4, 8, red)])
        let written = try XCTUnwrap(String(data: JSONEncoder().encode(el), encoding: .utf8))
        XCTAssertTrue(written.contains(#""spansText":"Big sale""#), written)
        XCTAssertFalse(written.contains("scale"), written)
    }

    // MARK: editing

    func testEveryEditCarriesTheSpansAlong() {
        var el = Element.text("Big sale")
        el.setSpans([span(4, 8, red)])
        el.setText("A big sale")
        XCTAssertEqual(el.spans, [span(6, 10, red)])
        XCTAssertEqual(el.spansText, "A big sale", "written down against the new words")
        // Markers put round words leave the words as they read alone.
        el.setText("A **big** sale")
        XCTAssertEqual(el.liveSpans, [span(6, 10, red)])
        el.setText("A **big**")
        XCTAssertNil(el.spans, "the coloured word deleted, nothing is kept")
        XCTAssertNil(el.spansText)
    }

    func testFindAndReplaceKeepsTheWordsBetweenInTheirColours() {
        var text = Element.text("red and blue and red")
        text.setSpans([span(8, 12, blue)])
        var design = Design(title: "replace", width: 1000, height: 1000)
        design.pages[0].elements = [text]
        let s = DesignStore(design: design)
        XCTAssertEqual(s.replaceAll("red", with: "green"), 2)
        let after = s.element(text.id)
        XCTAssertEqual(after?.text, "green and blue and green")
        XCTAssertEqual(after?.liveSpans, [span(10, 14, blue)])
    }

    func testDictationCarriesTheSpansAlong() {
        var text = Element.text("Big sale")
        text.setSpans([span(4, 8, red)])
        let s = store([text])
        s.select(text.id)
        s.dictationTarget = text.id
        XCTAssertTrue(s.dictate("Big sale now"))
        XCTAssertEqual(s.element(text.id)?.liveSpans, [span(4, 8, red)])
    }

    func testTheTypingBarsChoiceIsReadInTheWordsAsTheyRead() {
        let typed = "a **b** c"
        XCTAssertEqual(RichText.typedUnits(typed), [0, 1, 4, 7, 8])
        XCTAssertEqual(RichText.plainRange(of: NSRange(location: 2, length: 5), in: typed),
                       NSRange(location: 2, length: 1), "the markers chosen with the word are not counted")
        XCTAssertNil(RichText.plainRange(of: NSRange(location: 2, length: 2), in: typed), "only markers")
        XCTAssertEqual(RichText.typedRanges(of: NSRange(location: 0, length: 5), units: RichText.typedUnits(typed)),
                       [NSRange(location: 0, length: 2), NSRange(location: 4, length: 1), NSRange(location: 7, length: 2)])
    }

    // MARK: steps

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "spans", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    func testEachSizePressIsAStepOfItsOwnBetweenTheTyping() {
        let text = Element.text("Big sale")
        let s = store([text])
        s.select(text.id)
        s.beginGesture()
        s.editingTextId = text.id
        s.design.pages[0].elements[0].setText("Big sale now")
        let before = s.element(text.id)?.h ?? 0
        s.scaleWords(text.id, range: NSRange(location: 4, length: 4), by: Spans.larger)
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, scale: 1.25)])
        XCTAssertGreaterThanOrEqual(s.element(text.id)?.h ?? 0, before, "the box is measured again")
        s.scaleWords(text.id, range: NSRange(location: 4, length: 4), by: Spans.smaller)
        XCTAssertNil(s.element(text.id)?.spans, "back to the box's own size, no size is kept")

        s.undo()
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, scale: 1.25)])
        s.undo()
        XCTAssertNil(s.element(text.id)?.spans)
        XCTAssertEqual(s.element(text.id)?.text, "Big sale now", "the typing is a step of its own")
        s.undo()
        XCTAssertEqual(s.element(text.id)?.text, "Big sale")
    }

    func testAColourPickedForTheWordsIsOneStep() {
        let text = Element.text("Big sale")
        let s = store([text])
        s.select(text.id)
        s.chooseWordColour(text.id, range: NSRange(location: 4, length: 4))
        XCTAssertEqual(s.wordColourTarget, WordRange(id: text.id, range: NSRange(location: 4, length: 4)))
        XCTAssertEqual(s.wordColour, "#1f2430", "the box's own, before")
        s.colourWords(red)
        XCTAssertEqual(s.element(text.id)?.spans, [span(4, 8, red)])
        XCTAssertEqual(s.wordColour, red)
        s.undo()
        XCTAssertNil(s.element(text.id)?.spans)
    }

    func testTheBoxsOwnColourGivesTheWordsBackToIt() {
        var text = Element.text("Big sale")
        text.setSpans([span(4, 8, red)])
        let s = store([text])
        s.select(text.id)
        s.chooseWordColour(text.id, range: NSRange(location: 4, length: 4))
        s.colourWords("#1F2430")
        XCTAssertNil(s.element(text.id)?.spans, "no colour of their own, so they follow the box")
    }

    func testGradientLettersExplainRatherThanColourWords() {
        var text = Element.text("Big sale")
        text.textFill = Paint(kind: "gradient", color: nil, angle: 90,
                              stops: [GradientStop(offset: 0, color: "#000000"), GradientStop(offset: 1, color: "#ffffff")])
        let s = store([text])
        s.select(text.id)
        s.chooseWordColour(text.id, range: NSRange(location: 4, length: 4))
        XCTAssertNil(s.wordColourTarget)
        XCTAssertEqual(s.announcement, DesignStore.gradientWordsNote)
    }

    func testClearingWordColoursAndSizesIsOneStep() {
        var text = Element.text("Big sale")
        text.setSpans([span(0, 3, blue), span(4, 8, red, scale: 2)])
        let s = store([text])
        s.select(text.id)
        s.clearWordStyles()
        XCTAssertNil(s.element(text.id)?.spans)
        XCTAssertNil(s.element(text.id)?.spansText)
        s.undo()
        XCTAssertEqual(s.element(text.id)?.spans?.count, 2)
    }

    func testCopyStyleAndSavedStylesDoNotCarrySpans() {
        var styled = Element.text("Big sale")
        styled.setSpans([span(4, 8, red)])
        var other = Element.text("Other words")
        DesignStore.apply(DesignStore.style(of: styled), to: &other)
        XCTAssertNil(other.spans)
        XCTAssertNil(other.spansText)
    }

    // MARK: drawing

    func testTheWordsAreDrawnInTheirColourAndSize() throws {
        var el = Element.text("Big sale", fontSize: 40)
        el.setSpans([span(4, 8, red, scale: 2)])
        let drawn = FontLibrary.attributedString(for: el)
        XCTAssertEqual(drawn.string, "Big sale")
        let colour = try XCTUnwrap(drawn.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? UIColor)
        XCTAssertEqual(colour.hexString, red)
        let font = try XCTUnwrap(drawn.attribute(.font, at: 5, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, 80, accuracy: 0.01)
        let plain = try XCTUnwrap(drawn.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(plain.pointSize, 40, accuracy: 0.01)
    }

    func testABoldWordSetLargerStaysBold() throws {
        var el = Element.text("Big **sale**", fontSize: 40)
        el.setSpans([span(4, 8, scale: 1.25)])
        let font = try XCTUnwrap(FontLibrary.attributedString(for: el).attribute(.font, at: 5, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, 50, accuracy: 0.01)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    func testCapitalsMoveTheSpansAsTheRunsMove() {
        let caps = RichText.inCapitals(RichText.Parsed(plain: "straße tag", runs: []), spans: [span(7, 10, red)])
        XCTAssertEqual(caps.parsed.plain, "STRASSE TAG")
        XCTAssertEqual(caps.spans, [span(8, 11, red)])

        var el = Element.text("straße tag")
        el.uppercase = true
        el.setSpans([span(7, 10, red)])
        let drawn = FontLibrary.attributedString(for: el)
        XCTAssertEqual(drawn.string, "STRASSE TAG")
        XCTAssertEqual((drawn.attribute(.foregroundColor, at: 8, effectiveRange: nil) as? UIColor)?.hexString, red)
        XCTAssertNotEqual((drawn.attribute(.foregroundColor, at: 6, effectiveRange: nil) as? UIColor)?.hexString, red)
    }

    func testAListsMarkersAreNotColoured() {
        var el = Element.text("one\ntwo")
        el.listStyle = "bullet"
        el.setSpans([span(4, 7, red)])
        let drawn = FontLibrary.attributedString(for: el)
        XCTAssertEqual(drawn.string, "•  one\n•  two")
        XCTAssertEqual((drawn.attribute(.foregroundColor, at: 10, effectiveRange: nil) as? UIColor)?.hexString, red)
        XCTAssertNotEqual((drawn.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? UIColor)?.hexString, red)
    }

    func testGradientLettersIgnoreWordColoursButKeepSizes() throws {
        var el = Element.text("Big sale", fontSize: 40)
        el.textFill = Paint(kind: "gradient", color: nil, angle: 90,
                            stops: [GradientStop(offset: 0, color: "#000000"), GradientStop(offset: 1, color: "#ffffff")])
        el.setSpans([span(4, 8, red, scale: 2)])
        let drawn = FontLibrary.attributedString(for: el)
        XCTAssertNotEqual((drawn.attribute(.foregroundColor, at: 5, effectiveRange: nil) as? UIColor)?.hexString, red)
        let font = try XCTUnwrap(drawn.attribute(.font, at: 5, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, 80, accuracy: 0.01)
    }

    func testLargerWordsAreMeasured() {
        var el = Element.text("Big sale today and tomorrow", fontSize: 30, w: 200)
        let plain = FontLibrary.measuredHeight(for: el)
        el.setSpans([span(4, 8, scale: 3)])
        XCTAssertGreaterThan(FontLibrary.measuredHeight(for: el), plain, "a new key, and a taller box")
        XCTAssertGreaterThan(FontLibrary.naturalWidth(for: el), 0)
    }

    func testLargerWordsKeepTheLinePitchAsOnAndroid() {
        // Set tighter than the face's own lines: none of them grows.
        var el = Element.text("Big sale\nsoon", fontSize: 40, w: 1000)
        el.lineHeight = 0.9
        let plain = FontLibrary.measuredHeight(for: el)
        el.setSpans([span(4, 8, scale: Spans.larger)])
        XCTAssertEqual(FontLibrary.measuredHeight(for: el), plain, accuracy: 0.5, "every line still 36 apart")
    }

    func testADropCapKeepsTheWordsColoursAndSizes() throws {
        var el = Element.text("Sale on now", fontSize: 40, w: 400)
        el.dropCap = true
        el.setSpans([span(0, 4, red), span(8, 11, blue, scale: 2)])
        let layout = try XCTUnwrap(FontLibrary.dropCapLayout(for: el))
        let text = FontLibrary.dropCapText(for: el, layout)
        XCTAssertEqual(text.body.string, "ale on now", "past the cap's letter")
        XCTAssertEqual(text.capColour?.hexString, red, "the cap in the colour of the word it starts")
        XCTAssertEqual((text.body.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)?.hexString, red)
        let font = try XCTUnwrap(text.body.attribute(.font, at: 7, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(font.pointSize, 80, accuracy: 0.01)
        XCTAssertEqual((text.body.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? UIColor)?.hexString, blue)
    }

    func testAPageTokensColourStaysOnItsNumber() {
        var el = Element.text("Page {page} of {pages}")
        el.setSpans([span(5, 11, red)])
        el.fillPageTokens(number: 3, count: 12)
        XCTAssertEqual(el.text, "Page 3 of 12")
        XCTAssertEqual(el.liveSpans, [span(5, 6, red)])
    }

    func testOutlinesComeApartByColour() throws {
        var el = Element.text("Big sale", fontSize: 40, w: 400)
        el.setSpans([span(4, 8, red)])
        let outlines = try XCTUnwrap(TextOutliner.inkedPaths(for: el))
        XCTAssertEqual(outlines.parts.map(\.color), [nil, red], "the box's own colour first")

        var curved = el
        curved.curve = 120
        let bent = try XCTUnwrap(TextOutliner.inkedPaths(for: curved))
        XCTAssertEqual(bent.parts.map(\.color), [nil, red], "a curve keeps the colours")
    }

    func testTheSVGWritesEachColour() {
        var el = Element.text("Big sale", fontSize: 40, w: 400)
        el.setSpans([span(4, 8, red)])
        var design = Design(title: "svg", width: 800, height: 600)
        design.pages[0].elements = [el]
        let svg = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertTrue(svg.contains(##"fill="#ff0000""##), svg)
        XCTAssertTrue(svg.contains(##"fill="#1f2430""##), svg)
    }
}
