// The bar over the keyboard while a box is typed in: Bold, Italic, Underline
// and Strikethrough put the rich-text markers round the words chosen, hard
// against them and a line at a time, or take them off when every word
// chosen has the style already — as the Android twin's typing row does.

import XCTest
@testable import Canvia

final class TypingBarTests: XCTestCase {

    private func chosen(_ part: String, in text: String) -> NSRange {
        (text as NSString).range(of: part)
    }

    private func toggled(_ mark: RichText.Mark, _ text: String, choosing part: String) -> String? {
        RichText.toggling(mark, in: text, selection: chosen(part, in: text))?.text
    }

    /// Each stretch of the words with its styles, as the parser reads them.
    private func styles(_ text: String) -> [(String, RichText.Style)] {
        let p = RichText.parse(text)
        let ns = p.plain as NSString
        return p.runs.map { (ns.substring(with: $0.range), $0.style) }
    }

    func testMarkersGoHardAgainstTheWordsAndTheWordsStayChosen() throws {
        let text = "Big sale today"
        let result = try XCTUnwrap(RichText.toggling(.bold, in: text, selection: chosen(" sale ", in: text)))
        XCTAssertEqual(result.text, "Big **sale** today", "the spaces chosen are left outside")
        let exact = try XCTUnwrap(RichText.toggling(.bold, in: text, selection: chosen("sale", in: text)))
        XCTAssertEqual(exact.text, "Big **sale** today")
        XCTAssertEqual((exact.text as NSString).substring(with: exact.selection), "sale")
    }

    func testEachStyleHasItsMarker() {
        XCTAssertEqual(toggled(.italic, "Big sale today", choosing: "sale"), "Big *sale* today")
        XCTAssertEqual(toggled(.underline, "Big sale today", choosing: "sale"), "Big __sale__ today")
        XCTAssertEqual(toggled(.strike, "Was £40 now £30", choosing: "Was £40"), "~~Was £40~~ now £30")
    }

    func testAStyleEveryWordHasIsTakenOff() {
        XCTAssertEqual(toggled(.bold, "Big **sale** today", choosing: "sale"), "Big sale today")
        XCTAssertEqual(toggled(.bold, "**big sale today**", choosing: "sale"), "**big** sale **today**",
                       "a word taken out of a run splits it")
    }

    func testAMarkedWordInTheChoiceJoinsTheRun() {
        XCTAssertEqual(toggled(.bold, "**big** sale", choosing: "big** sale"), "**big sale**")
        XCTAssertEqual(toggled(.bold, "a **b** c", choosing: "a **b** c"), "**a b c**")
        XCTAssertEqual(toggled(.bold, "**abc** def", choosing: "c** de"), "**abc de**f")
    }

    func testEachLineIsMarkedOnItsOwn() {
        XCTAssertEqual(toggled(.underline, "one\ntwo", choosing: "one\ntwo"), "__one__\n__two__")
        XCTAssertEqual(toggled(.underline, "__one__\n__two__", choosing: "one__\n__two"), "one\ntwo")
    }

    func testItalicsTakeWholeWords() {
        // A single star cannot open or close inside a word, so the word is
        // taken whole.
        XCTAssertEqual(toggled(.italic, "hello world", choosing: "ell"), "*hello* world")
        XCTAssertEqual(toggled(.italic, "*hello* world", choosing: "ell"), "hello world")
        // Doubles can sit inside a word, as the parser reads "he**llo**".
        XCTAssertEqual(toggled(.bold, "hello", choosing: "ll"), "he**ll**o")
    }

    func testOtherStylesAreLeftAsTheyWere() throws {
        let text = "*soft* words"
        let bold = try XCTUnwrap(toggled(.bold, text, choosing: "soft* words"))
        let read = styles(bold)
        XCTAssertEqual(read.map(\.0), ["soft", " words"])
        XCTAssertEqual(read[0].1, RichText.Style(bold: true, italic: true))
        XCTAssertEqual(read[1].1, RichText.Style(bold: true))
        XCTAssertEqual(RichText.strip(bold), "soft words")
        XCTAssertEqual(toggled(.bold, bold, choosing: "soft* words"), text, "and back again")
    }

    func testUTF16Offsets() throws {
        let text = "😀 wow"
        let result = try XCTUnwrap(RichText.toggling(.bold, in: text, selection: NSRange(location: 3, length: 3)))
        XCTAssertEqual(result.text, "😀 **wow**")
        XCTAssertEqual(result.selection, NSRange(location: 5, length: 3))
    }

    func testNothingToSayOrNoWayToSayItIsRefused() {
        XCTAssertNil(toggled(.bold, "a   ", choosing: "   "), "only spaces chosen")
        XCTAssertNil(RichText.toggling(.bold, in: "abc", selection: NSRange(location: 1, length: 0)))
        // An unclosed ** earlier would take the new marker as its close and
        // show its stars: refused rather than left looking broken.
        XCTAssertNil(toggled(.bold, "x **y and z", choosing: "z"))
    }

    func testWhatTheButtonsShow() {
        let text = "Big **sale** today"
        XCTAssertTrue(RichText.selectionHas(.bold, in: text, selection: chosen("sale", in: text)))
        XCTAssertTrue(RichText.selectionHas(.bold, in: text, selection: chosen(" **sale** ", in: text)),
                      "spaces around the words do not count")
        XCTAssertFalse(RichText.selectionHas(.bold, in: text, selection: chosen("sale** today", in: text)))
        XCTAssertFalse(RichText.selectionHas(.italic, in: text, selection: chosen("sale", in: text)))
        XCTAssertFalse(RichText.selectionHas(.bold, in: text, selection: NSRange(location: 0, length: 0)))
    }

    func testTheCaretStaysBeforeItsLetter() {
        XCTAssertEqual(RichText.caret(at: 4, from: "abc def", to: "~~abc def~~"), 6, "before the d")
        XCTAssertEqual(RichText.caret(at: 0, from: "abc def", to: "~~abc def~~"), 2, "before the a")
        XCTAssertEqual(RichText.caret(at: 7, from: "abc def", to: "~~abc def~~"), 11, "the end stays the end")
        XCTAssertEqual(RichText.caret(at: 3, from: "abc def", to: "abc ~~def~~"), 3)
    }

    func testTheBoxWideSwitchesMatchTheMarks() {
        XCTAssertEqual(TextToggle(.bold), .bold)
        XCTAssertEqual(TextToggle(.italic), .italic)
        XCTAssertEqual(TextToggle(.underline), .underline)
        XCTAssertNil(TextToggle(.strike), "no box is struck through as a whole")
    }

    @MainActor
    func testAShapesWordsHaveNoWordColourOrSizes() {
        func labels(_ field: InlineTextField) -> [String] {
            (field.makeCoordinator().typingBar().items ?? []).compactMap { $0.accessibilityLabel }
        }
        let box = InlineTextField(element: .text("Big sale"), onChange: { _ in }, onDone: {})
        XCTAssertTrue(labels(box).contains("Larger"), "a text box's bar has A+")
        let shape = InlineTextField(element: ShapeText.textElement(for: .shape("rect")),
                                    onChange: { _ in }, onDone: {}, wordStyles: false)
        let shown = labels(shape)
        XCTAssertTrue(shown.contains("Bold"))
        for gone in ["Colour of the selected words", "Smaller", "Larger"] {
            XCTAssertFalse(shown.contains(gone), "\(gone) is not on a shape's bar, as on the Android twin")
        }
    }
}
