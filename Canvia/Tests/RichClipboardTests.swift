// Words copied and pasted inside the typing field keep their styles, and
// another app's text is pasted as it reads — the rows the Android twin's
// RichClipboardTest runs over the same shared fixture.

import XCTest
@testable import Canvia

final class RichClipboardTests: XCTestCase {

    private func fixture(_ name: String, file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: RichClipboardTests.self).url(forResource: name, withExtension: "json") {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).json"))
    }

    /// Shared: the bold word copied on its own is "**Big**", and the plain
    /// words for another app are "Big".
    func testACopyIsThePlainWordsAndTheWordsAsKept() {
        let clip = RichClipboard.copy(Element.text("**Big** sale"), start: 0, end: 3)
        XCTAssertEqual(clip.plain, "Big")
        XCTAssertEqual(clip.text, "**Big**")
        // A run cut by the copy is closed inside it.
        let cut = RichClipboard.copy(Element.text("**Big sale** now"), start: 4, end: 8)
        XCTAssertEqual(cut.plain, "sale")
        XCTAssertEqual(cut.text, "**sale**")
    }

    /// Shared: pasted into 'x', the copied bold word stays bold, and a
    /// colour on it comes along.
    func testAPasteKeepsTheBoldAndTheColour() throws {
        var source = Element.text("**Big** sale")
        source.setSpans([TextSpan(start: 0, end: 3, color: "#ff0000")])
        let clip = RichClipboard.copy(source, start: 0, end: 3)
        XCTAssertEqual(clip.spans, [TextSpan(start: 0, end: 3, color: "#ff0000")])
        let pasted = RichClipboard.paste(Element.text("x"), at: 1, removed: 0, clip: clip)
        XCTAssertEqual(pasted.text, "x**Big**")
        let run = try XCTUnwrap(RichText.parse(pasted.text ?? "").runs.first)
        XCTAssertTrue(run.style.bold)
        XCTAssertEqual(run.range, NSRange(location: 1, length: 3))
        XCTAssertEqual(pasted.liveSpans, [TextSpan(start: 1, end: 4, color: "#ff0000")])
    }

    /// Shared: another app's 'a**b**c' shows its stars.
    func testOutsideTextShowsItsStars() {
        let pasted = RichClipboard.paste(Element.text(""), at: 0, removed: 0, plainText: "a**b**c")
        XCTAssertEqual(RichText.strip(pasted.text ?? ""), "a**b**c")
        XCTAssertTrue(RichText.parse(pasted.text ?? "").runs.isEmpty)
        // Over chosen words, in the style of the first of them.
        let over = RichClipboard.paste(Element.text("**Big** sale"), at: 0, removed: 3, plainText: "Huge")
        XCTAssertEqual(over.text, "**Huge** sale")
    }

    /// Shared fixture: the JSON either phone puts on the clipboard reads the
    /// same here, and pasted into an empty box keeps its words, bold, colour
    /// and lists.
    func testTheSharedClipFixture() throws {
        let clip = try XCTUnwrap(RichClipboard.decode(try fixture("rich-clip")))
        XCTAssertEqual(clip.plain, "Big sale\nnow *50*")
        XCTAssertEqual(clip.spans, [TextSpan(start: 0, end: 3, color: "#ff0000")])
        XCTAssertEqual(clip.paragraphs, [TextParagraph(list: "bullet"), TextParagraph(list: "bullet", level: 1)])
        let pasted = RichClipboard.paste(Element.text(""), at: 0, removed: 0, clip: clip)
        XCTAssertEqual(RichText.strip(pasted.text ?? ""), "Big sale\nnow *50*")
        XCTAssertEqual(TextLists.lines(pasted), clip.paragraphs)
        XCTAssertEqual(pasted.liveSpans, clip.spans)
        // And back to JSON and again, unchanged.
        XCTAssertEqual(RichClipboard.decode(RichClipboard.json(clip)), clip)
        XCTAssertNil(RichClipboard.decode(Data("{\"canviaText\":2,\"text\":\"x\"}".utf8)))
        XCTAssertNil(RichClipboard.decode(Data("not json".utf8)))
    }

    /// A copy of whole listed lines carries their lists; one word pasted
    /// into a line leaves the lines' lists alone.
    func testListsComeWithWholeLines() {
        var source = Element.text("Shop\nmilk\neggs")
        source.setLines([TextParagraph(), TextParagraph(list: "bullet"), TextParagraph(list: "bullet")])
        let clip = RichClipboard.copy(source, start: 5, end: 14)
        XCTAssertEqual(clip.plain, "milk\neggs")
        XCTAssertEqual(clip.paragraphs, [TextParagraph(list: "bullet"), TextParagraph(list: "bullet")])
        let into = RichClipboard.paste(Element.text("List\n"), at: 5, removed: 0, clip: clip)
        XCTAssertEqual(RichText.strip(into.text ?? ""), "List\nmilk\neggs")
        XCTAssertEqual(TextLists.lines(into).map(\.list), ["none", "bullet", "bullet"])
        let word = RichClipboard.paste(Element.text("Tea"), at: 3, removed: 0,
                                       clip: RichClipboard.copy(source, start: 5, end: 9))
        XCTAssertEqual(RichText.strip(word.text ?? ""), "Teamilk")
        XCTAssertFalse(TextLists.isList(word))
    }
}
