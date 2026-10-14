// Inline styles: **bold**, *italic*, __underline__, ~~strike~~ inside one text.

import XCTest
import UIKit
@testable import Canvia

final class RichTextTests: XCTestCase {

    private func styles(_ text: String) -> [(String, RichText.Style)] {
        let p = RichText.parse(text)
        let ns = p.plain as NSString
        return p.runs.map { (ns.substring(with: $0.range), $0.style) }
    }

    func testMarkersAreStrippedAndStyledWords() {
        let p = RichText.parse("Big **Summer** sale, *today* only")
        XCTAssertEqual(p.plain, "Big Summer sale, today only")
        let s = styles("Big **Summer** sale, *today* only")
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].0, "Summer"); XCTAssertTrue(s[0].1.bold); XCTAssertFalse(s[0].1.italic)
        XCTAssertEqual(s[1].0, "today"); XCTAssertTrue(s[1].1.italic)
    }

    func testUnderlineStrikeAndUnderscoreItalic() {
        let s = styles("__under__ and ~~gone~~ and _soft_")
        XCTAssertEqual(s.map(\.0), ["under", "gone", "soft"])
        XCTAssertTrue(s[0].1.underline)
        XCTAssertTrue(s[1].1.strike)
        XCTAssertTrue(s[2].1.italic)
        XCTAssertEqual(RichText.strip("__under__ and ~~gone~~ and _soft_"), "under and gone and soft")
    }

    func testStylesNest() {
        let s = styles("**bold and *both* here**")
        XCTAssertEqual(s.map(\.0), ["bold and ", "both", " here"])
        XCTAssertEqual(s[1].1, RichText.Style(bold: true, italic: true))
        XCTAssertEqual(s[0].1, RichText.Style(bold: true))
    }

    func testLoneAndInWordMarkersStayLiteral() {
        XCTAssertEqual(RichText.strip("2*3 = 6"), "2*3 = 6")
        XCTAssertEqual(RichText.strip("snake_case_name"), "snake_case_name")
        XCTAssertEqual(RichText.strip("5 * 3 * 2"), "5 * 3 * 2")
        XCTAssertEqual(RichText.strip("**unclosed"), "**unclosed")
        XCTAssertEqual(RichText.strip("no markup"), "no markup")
        XCTAssertEqual(RichText.strip("~ one tilde ~"), "~ one tilde ~")
        XCTAssertTrue(RichText.parse("plain").runs.isEmpty)
    }

    func testRangesAreUTF16Offsets() {
        let p = RichText.parse("😀 **wow** ✨")
        XCTAssertEqual(p.plain, "😀 wow ✨")
        XCTAssertEqual(p.runs.count, 1)
        XCTAssertEqual((p.plain as NSString).substring(with: p.runs[0].range), "wow")
    }

    @MainActor
    func testDisplayTextIsPlainAndTheAttributedStringCarriesTheRuns() {
        let el = Element.text("Try **bold** and *italic*", fontSize: 30)
        XCTAssertEqual(FontLibrary.displayText(for: el), "Try bold and italic")
        let attributed = FontLibrary.attributedString(for: el)
        XCTAssertEqual(attributed.string, "Try bold and italic")
        let baseFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let boldFont = attributed.attribute(.font, at: 4, effectiveRange: nil) as? UIFont
        let italicFont = attributed.attribute(.font, at: 13, effectiveRange: nil) as? UIFont
        XCTAssertNotNil(baseFont)
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true, boldFont?.fontName ?? "nil")
        XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true, italicFont?.fontName ?? "nil")
        XCTAssertFalse(baseFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        // A plain element takes the fast path and is byte-identical to before.
        let plain = Element.text("Hello", fontSize: 30)
        XCTAssertEqual(FontLibrary.attributedString(for: plain).string, "Hello")
    }

    @MainActor
    func testMeasurementIgnoresTheMarkers() {
        let marked = Element.text("**Summer** sale", fontSize: 30, w: 400)
        let plain = Element.text("Summer sale", fontSize: 30, w: 400)
        XCTAssertEqual(FontLibrary.lineWidth(for: marked), FontLibrary.lineWidth(for: plain))
        XCTAssertEqual(FontLibrary.measuredHeight(for: marked), FontLibrary.measuredHeight(for: plain))
    }

    @MainActor
    func testTheOutlineOfABoldWordIsWiderThanThePlainOne() throws {
        var bold = Element.text("**WIDE** word", fontSize: 40, w: 600); bold.align = "left"
        var plain = Element.text("WIDE word", fontSize: 40, w: 600); plain.align = "left"
        let b = try XCTUnwrap(TextOutliner.path(for: bold)).boundingBoxOfPath
        let p = try XCTUnwrap(TextOutliner.path(for: plain)).boundingBoxOfPath
        XCTAssertGreaterThan(b.width, p.width)
    }

    func testARevealCountsTheWordsAsTheyReadAndKeepsTheirStyle() {
        // Every step of a typewriter on bold, italic and plain words reads as
        // the words shown so far, styled, with no marker in sight — as the
        // Android twin's test checks the same function.
        let text = "**Sale** today, *only* __here__ ~~now~~"
        let full = RichText.parse(text)
        let plain = Array(full.plain)
        for n in 0...plain.count {
            let shown = RichText.revealed(text, count: n)
            let parsed = RichText.parse(shown)
            XCTAssertEqual(parsed.plain, String(plain.prefix(n)), "step \(n)")
        }
        XCTAssertEqual(RichText.revealed("**Sale** today", count: 2), "**Sa**")
        XCTAssertEqual(RichText.revealed(text, count: plain.count), text)
        XCTAssertEqual(RichText.revealed(text, count: 0), "")
        XCTAssertEqual(RichText.revealed("\u{1F44B} hi", count: 1), "\u{1F44B}")
        let bold = RichText.parse(RichText.revealed("**Sale** today", count: 3))
        XCTAssertEqual(bold.runs.first?.style.bold, true)
    }

    // MARK: typing the words as they read

    /// The caret rows the Android twin's RichTextTest runs too: a caret
    /// among the words as they read, and where it stands among the stored
    /// characters — just after the letter before it, so inside its style.
    func testTheCaretMapsBetweenTheWordsAsTheyReadAndAsStored() {
        let text = "**Sale** today"
        XCTAssertEqual(RichText.rawCaret(0, in: text), 2)
        XCTAssertEqual(RichText.rawCaret(4, in: text), 6, "inside the bold")
        XCTAssertEqual(RichText.rawCaret(5, in: text), 9)
        XCTAssertEqual(RichText.rawCaret(10, in: text), 14, "the end")
        XCTAssertEqual(RichText.plainCaret(2, in: text), 0)
        XCTAssertEqual(RichText.plainCaret(6, in: text), 4)
        XCTAssertEqual(RichText.plainCaret(8, in: text), 4, "past the closing marker, still just after Sale")
        XCTAssertEqual(RichText.plainCaret(9, in: text), 5)
        XCTAssertEqual(RichText.rawCaret(0, in: ""), 0)
        XCTAssertEqual(RichText.rawCaret(3, in: "abc"), 3)
    }

    /// Typed at the end of a styled word, a letter goes inside its closing
    /// marker and the style carries on — the Android twin's row.
    func testTypingAtTheEndOfAStyledWordCarriesItsStyleOn() {
        let text = "**Sale** today"
        let typed = RichText.typing("s", over: NSRange(location: RichText.rawCaret(4, in: text), length: 0), in: text, pending: nil)
        XCTAssertEqual(typed.text, "**Sales** today")
        XCTAssertEqual(typed.caret, 7)
        XCTAssertNil(typed.pending)
        let start = RichText.typing("S", over: NSRange(location: RichText.rawCaret(0, in: text), length: 0), in: text, pending: nil)
        XCTAssertEqual(start.text, "**SSale** today", "at the start, the first letter's style")
        let after = RichText.typing("x", over: NSRange(location: 9, length: 0), in: text, pending: nil)
        XCTAssertEqual(after.text, "**Sale** xtoday", "after a space, the space's")
    }

    /// A backspace just after hidden markers takes the letter before them,
    /// never a marker.
    func testABackspaceAfterHiddenMarkersTakesTheLetterBeforeThem() {
        let typed = RichText.typing("", over: NSRange(location: 7, length: 1), in: "**Sale** today", pending: nil)
        XCTAssertEqual(typed.text, "**Sal** today")
        XCTAssertEqual(typed.caret, 5)
        let last = RichText.typing("", over: NSRange(location: 2, length: 1), in: "**S** x", pending: nil)
        XCTAssertEqual(last.text, " x", "the markers of a word deleted whole go with it")
    }

    /// Words typed over chosen ones take the style of the first of them.
    func testTypingOverChosenWordsKeepsTheirStyle() {
        let typed = RichText.typing("Huge", over: NSRange(location: 2, length: 3), in: "**Big** sale", pending: nil)
        XCTAssertEqual(typed.text, "**Huge** sale")
        XCTAssertEqual(typed.caret, 6)
    }

    /// A space typed after a bold word cannot be inside its markers, so the
    /// bold waits, and the next word takes it with the space.
    func testASpaceAfterABoldWordWaitsForTheNextWord() {
        let space = RichText.typing(" ", over: NSRange(location: 5, length: 0), in: "**Big**", pending: nil)
        XCTAssertEqual(space.text, "**Big** ")
        XCTAssertEqual(space.caret, 8)
        XCTAssertEqual(space.pending, RichText.Pending(style: RichText.Style(bold: true), from: 3))
        let word = RichText.typing("s", over: NSRange(location: space.caret, length: 0), in: space.text,
                                   pending: space.pending)
        XCTAssertEqual(word.text, "**Big s**")
        XCTAssertEqual(word.caret, 7)
        XCTAssertNil(word.pending)
        // A second space waits on from the first; plain words carry nothing.
        let again = RichText.typing(" ", over: NSRange(location: 8, length: 0), in: "**Big** ", pending: space.pending)
        XCTAssertEqual(again.pending, RichText.Pending(style: RichText.Style(bold: true), from: 3))
        XCTAssertNil(RichText.typing(" ", over: NSRange(location: 3, length: 0), in: "Big", pending: nil).pending)
    }

    /// Bold armed on an empty box stays on across the spaces typed — the
    /// Android twin's row.
    func testBoldArmedOnAnEmptyBoxStaysOnAcrossSpaces() {
        var words = ""
        var caret = 0
        var pending: RichText.Pending? = RichText.Pending(style: RichText.Style(bold: true), from: 0)
        for key in "Big sale" {
            let typed = RichText.typing(String(key), over: NSRange(location: caret, length: 0), in: words,
                                        pending: pending)
            words = typed.text
            caret = typed.caret
            pending = typed.pending
        }
        XCTAssertEqual(words, "**Big sale**")
        XCTAssertEqual(caret, 10)
    }

    /// Bold pressed with nothing chosen wraps what is typed next.
    func testAStyleArmedWithNothingChosenWrapsWhatIsTypedNext() {
        let armed = RichText.Pending(style: RichText.Style(bold: true), from: 4)
        let typed = RichText.typing("B", over: NSRange(location: 4, length: 0), in: "Big ", pending: armed)
        XCTAssertEqual(typed.text, "Big **B**")
        XCTAssertEqual(typed.caret, 7)
        let next = RichText.typing("e", over: NSRange(location: typed.caret, length: 0), in: typed.text, pending: nil)
        XCTAssertEqual(next.text, "Big **Be**", "then the style carries on")
    }

    func testTheCaretAndChoiceKeepOffTheMarkers() {
        let text = "**Sale** today"
        XCTAssertEqual(RichText.snapped(NSRange(location: 8, length: 0), in: text, was: nil),
                       NSRange(location: 6, length: 0))
        XCTAssertEqual(RichText.snapped(NSRange(location: 0, length: 0), in: text, was: nil),
                       NSRange(location: 2, length: 0))
        // The right arrow from the end of Sale steps over the markers.
        XCTAssertEqual(RichText.snapped(NSRange(location: 7, length: 0), in: text, was: NSRange(location: 6, length: 0)),
                       NSRange(location: 9, length: 0))
        XCTAssertEqual(RichText.snapped(NSRange(location: 0, length: 8), in: text, was: nil),
                       NSRange(location: 2, length: 4))
        XCTAssertEqual(RichText.snapped(NSRange(location: 6, length: 2), in: text, was: nil),
                       NSRange(location: 6, length: 0), "only markers chosen: a caret")
    }

    /// The field keeps the markers in its words but draws them as nothing,
    /// and the bold word bold.
    @MainActor
    func testTheFieldShowsStyledWordsAndNoMarkers() throws {
        let words = "**Sale** today"
        let el = Element.text(words, fontSize: 30)
        let attrs = FontLibrary.attributes(for: el)
        let storage = NSTextStorage(string: words, attributes: attrs)
        InlineTextField.paint(storage, words: words, spans: [], attrs: attrs, runFont: InlineTextField.runFont(for: el))
        XCTAssertEqual(storage.string, words, "the stored words keep their markers")
        let marker = try XCTUnwrap(storage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        XCTAssertLessThan(marker.pointSize, 0.1)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 7, effectiveRange: nil) as? UIColor, UIColor.clear)
        let bold = try XCTUnwrap(storage.attribute(.font, at: 2, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(bold.fontDescriptor.symbolicTraits.contains(.traitBold), bold.fontName)
        let plain = try XCTUnwrap(storage.attribute(.font, at: 9, effectiveRange: nil) as? UIFont)
        XCTAssertEqual(plain.pointSize, 30)
        XCTAssertFalse(plain.fontDescriptor.symbolicTraits.contains(.traitBold))
    }
}
