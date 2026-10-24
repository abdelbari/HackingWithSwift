// Lists from the keyboard and from a paste — the shared rows the Android
// twin's TextListsTest runs too.

import XCTest
@testable import Canvia

final class ListTypingTests: XCTestCase {

    func testATypedPrefixAndSpaceStartsAList() {
        XCTAssertEqual(TextLists.autoStart("- ", caret: 2), "bullet")
        XCTAssertEqual(TextLists.autoStart("* ", caret: 2), "bullet")
        XCTAssertEqual(TextLists.autoStart("• ", caret: 2), "bullet")
        XCTAssertEqual(TextLists.autoStart("1. ", caret: 3), "number")
        XCTAssertEqual(TextLists.autoStart("12) ", caret: 4), "number")
        XCTAssertEqual(TextLists.autoStart("a) ", caret: 3), "letter")
        XCTAssertEqual(TextLists.autoStart("b. milk", caret: 3), "letter", "words after the caret do not matter")
        XCTAssertNil(TextLists.autoStart("-x ", caret: 3))
        XCTAssertNil(TextLists.autoStart("A. ", caret: 3))
        XCTAssertNil(TextLists.autoStart("x - ", caret: 4))
        XCTAssertNil(TextLists.autoStart("- ", caret: 1))
    }

    /// Shared: '- ' then 'milk' is a bullet item reading 'milk'.
    func testDashSpaceThenWordsIsABulletItem() {
        let started = TextLists.autoStarted(Element.text("- "), line: 0, prefix: 2, list: "bullet")
        XCTAssertEqual(started.text, "")
        var el = started
        el.setText("milk")
        XCTAssertEqual(RichText.strip(el.text ?? ""), "milk")
        XCTAssertEqual(TextLists.lines(el), [TextParagraph(list: "bullet")])
        // On a later line, only that line.
        let second = TextLists.autoStarted(Element.text("Shop\n1. "), line: 1, prefix: 3, list: "number")
        XCTAssertEqual(second.text, "Shop\n")
        XCTAssertEqual(TextLists.lines(second).map(\.list), ["none", "number"])
    }

    /// Shared: Backspace at the start of a level-1 item makes it level 0,
    /// then takes it out of the list; the lines are never joined.
    func testBackspaceAtAnItemsStartStepsOutOfTheList() throws {
        var el = Element.text("Shop\nmilk")
        el.setLines([TextParagraph(), TextParagraph(list: "bullet", level: 1)])
        let once = try XCTUnwrap(TextLists.backspaceAtItemStart(el, line: 1))
        XCTAssertEqual(TextLists.lines(once)[1], TextParagraph(list: "bullet", level: 0))
        XCTAssertEqual(once.text, "Shop\nmilk")
        let twice = try XCTUnwrap(TextLists.backspaceAtItemStart(once, line: 1))
        XCTAssertEqual(TextLists.lines(twice)[1], TextParagraph())
        XCTAssertNil(TextLists.backspaceAtItemStart(twice, line: 1), "a plain line joins as ever")
        XCTAssertNil(TextLists.backspaceAtItemStart(el, line: 0))
    }

    /// Shared: '1. a\n2. b' pasted is number items 'a' and 'b'.
    func testPastedNumberedLinesAreAList() {
        let pasted = TextLists.fromPasted("1. a\n2. b")
        XCTAssertEqual(pasted.text, "a\nb")
        XCTAssertEqual(pasted.paragraphs, [TextParagraph(list: "number"), TextParagraph(list: "number")])
        let nested = TextLists.fromPasted("- a\n\t- b\n    • c\nplain - line")
        XCTAssertEqual(nested.text, "a\nb\nc\nplain - line")
        XCTAssertEqual(nested.paragraphs, [TextParagraph(list: "bullet"), TextParagraph(list: "bullet", level: 1),
                                           TextParagraph(list: "bullet", level: 2), TextParagraph()])
        let el = RichClipboard.paste(Element.text(""), at: 0, removed: 0, plainText: "1. a\n2. b")
        XCTAssertEqual(RichText.strip(el.text ?? ""), "a\nb")
        XCTAssertEqual(TextLists.lines(el), [TextParagraph(list: "number"), TextParagraph(list: "number")])
    }

    /// The setting travels in a backup's settings.json, on by default.
    func testTheAutoListsSettingTravelsInABackup() {
        XCTAssertEqual(TextLists.autoListsKey, "canvia.autoLists")
        XCTAssertEqual(Backup.decodeSettings(Backup.encodeSettings(autoLists: false, use: nil)), false)
        XCTAssertEqual(Backup.decodeSettings(Data("{\"autoLists\":true}".utf8)), true)
        XCTAssertNil(Backup.decodeSettings(Data("{}".utf8)))
        XCTAssertNil(Backup.decodeSettings(nil))
    }
}
