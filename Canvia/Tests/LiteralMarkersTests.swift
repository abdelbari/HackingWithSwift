// A backslash before a marker character is that character, as typed: the
// shared rows the Android twin's RichTextTest runs too.

import XCTest
@testable import Canvia

final class LiteralMarkersTests: XCTestCase {

    /// Types `keys` one at a time into `words`, as the typing field does.
    private func typed(_ keys: String, into words: String = "") -> String {
        var text = words
        var caret = (words as NSString).length
        for key in keys {
            let step = RichText.typing(String(key), over: NSRange(location: caret, length: 0), in: text, pending: nil)
            text = step.text
            caret = step.caret
        }
        return text
    }

    /// Shared: an escaped star is a star, and nothing is styled.
    func testAnEscapedMarkerReadsAsItselfUnstyled() {
        let parsed = RichText.parse("a \\*b\\* c")
        XCTAssertEqual(parsed.plain, "a *b* c")
        XCTAssertTrue(parsed.runs.isEmpty)
        XCTAssertEqual(RichText.strip("\\_\\_init\\_\\_"), "__init__")
        XCTAssertEqual(RichText.strip("\\~\\~50\\~\\~"), "~~50~~")
        XCTAssertEqual(RichText.strip("C:\\\\temp"), "C:\\temp", "a doubled backslash is one")
        XCTAssertEqual(RichText.strip("a\\b"), "a\\b", "a backslash before anything else stays")
        // An escaped star never closes a run, and a real one still does.
        let bold = RichText.parse("**5\\*** off")
        XCTAssertEqual(bold.plain, "5* off")
        XCTAssertEqual(bold.runs.map(\.range), [NSRange(location: 0, length: 2)])
        XCTAssertTrue(bold.runs[0].style.bold)
    }

    /// Shared: typed into an empty box, '__init__' is stored escaped and
    /// reads as typed; Bold still writes its markers.
    func testTypedMarkersAreLiteralAndTheBoldButtonStillWritesStars() {
        let words = typed("__init__")
        XCTAssertEqual(words, "\\_\\_init\\_\\_")
        XCTAssertEqual(RichText.strip(words), "__init__")
        XCTAssertTrue(RichText.parse(words).runs.isEmpty)
        XCTAssertEqual(RichText.strip(typed("*Terms apply*")), "*Terms apply*")
        XCTAssertTrue(RichText.parse(typed("*Terms apply*")).runs.isEmpty)
        let bold = RichText.toggling(.bold, in: "abc", selection: NSRange(location: 0, length: 3))
        XCTAssertEqual(bold?.text, "**abc**")
    }

    func testEscapeLiteralEscapesEveryMarkerCharacterAndBackslash() {
        XCTAssertEqual(RichText.escapeLiteral("a*b_c~d\\e"), "a\\*b\\_c\\~d\\\\e")
        XCTAssertEqual(RichText.escapeLiteral("plain words"), "plain words")
        for words in ["a*b", "__init__", "~~50~~", "C:\\temp", "2*3 = 6", "**bold**"] {
            XCTAssertEqual(RichText.strip(RichText.escapeLiteral(words)), words, words)
        }
    }

    /// Older files have no backslash and read as they always have.
    func testAFileWithNoBackslashReadsAsBefore() {
        XCTAssertEqual(RichText.strip("**Big** sale"), "Big sale")
        XCTAssertEqual(RichText.strip("snake_case_name"), "snake_case_name")
        XCTAssertTrue(RichText.parse("**Big** sale").runs.first?.style.bold == true)
    }

    /// The caret keeps off an escape as it keeps off a marker, and nothing
    /// typed or found ever lands between a backslash and its character.
    func testTheCaretAndRangesKeepTheBackslashWithItsCharacter() {
        let text = "\\*x"
        XCTAssertEqual(RichText.rawCaret(0, in: text), 0)
        XCTAssertEqual(RichText.snapped(NSRange(location: 1, length: 0), in: text, was: nil),
                       NSRange(location: 0, length: 0))
        XCTAssertEqual(RichText.storedRange(of: NSRange(location: 0, length: 1), in: text),
                       NSRange(location: 0, length: 2))
        XCTAssertEqual(RichText.storedRange(of: NSRange(location: 1, length: 1), in: "a\\*"),
                       NSRange(location: 1, length: 2))
        let start = RichText.typing("y", over: NSRange(location: 0, length: 0), in: text, pending: nil)
        XCTAssertEqual(start.text, "y\\*x")
        XCTAssertEqual(RichText.strip(start.text), "y*x")
    }

    /// Find and replace's new words, and a spelling fix, read as typed.
    func testReplacementsAreLiteral() {
        let replaced = FindReplace.replacing(NSRange(location: 2, length: 1), in: "a b", with: "*x*")
        XCTAssertEqual(replaced, "a \\*x\\*")
        XCTAssertEqual(RichText.strip(replaced), "a *x*")
        let bold = FindReplace.replacing(NSRange(location: 0, length: 3), in: "**Big** sale", with: "5*")
        XCTAssertEqual(RichText.strip(bold), "5* sale")
        XCTAssertTrue(RichText.parse(bold).runs.first?.style.bold == true)
    }
}
