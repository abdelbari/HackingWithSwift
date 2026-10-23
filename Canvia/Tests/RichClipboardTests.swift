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

    /// A part of the fixture as JSON data again, for a decoder.
    private func data(_ object: Any?) throws -> Data {
        try JSONSerialization.data(withJSONObject: try XCTUnwrap(object), options: [.fragmentsAllowed])
    }

    /// A box from the fixture: its words, spans and lines.
    private func box(_ object: [String: Any]) throws -> Element {
        var el = Element.text(try XCTUnwrap(object["text"] as? String))
        if let spans = object["spans"] {
            el.setSpans(try JSONDecoder().decode([TextSpan].self, from: data(spans)))
        }
        if let lines = object["paragraphs"] {
            el.setLines(try JSONDecoder().decode([TextParagraph].self, from: data(lines)))
        }
        return el
    }

    /// Shared fixture, the Android twin's fixtures/rich-clip.json byte for
    /// byte: the box copied gives the same clip as the JSON either phone
    /// puts on the clipboard, which reads back the same; and each paste row
    /// — a clip, or another app's words — leaves the box as it says.
    func testTheSharedClipFixture() throws {
        let shared = try XCTUnwrap(JSONSerialization.jsonObject(with: try fixture("rich-clip")) as? [String: Any])
        let el = try box(try XCTUnwrap(shared["box"] as? [String: Any]))
        for row in try XCTUnwrap(shared["cases"] as? [[String: Any]]) {
            let name = row["name"] as? String ?? ""
            let clip = RichClipboard.copy(el, start: row["start"] as? Int ?? 0, end: row["end"] as? Int ?? 0)
            XCTAssertEqual(clip.plain, row["plain"] as? String, name)
            XCTAssertEqual(RichClipboard.decode(try data(row["clip"])), clip, name)
            XCTAssertEqual(RichClipboard.decode(RichClipboard.json(clip)), clip, name)
        }
        for row in try XCTUnwrap(shared["pastes"] as? [[String: Any]]) {
            let name = row["name"] as? String ?? ""
            let into = try box(try XCTUnwrap(row["into"] as? [String: Any]))
            let at = row["at"] as? Int ?? 0
            let pasted: Element
            if let clip = row["clip"] {
                let read = try XCTUnwrap(RichClipboard.decode(try data(clip)), name)
                pasted = RichClipboard.paste(into, at: at, removed: 0, clip: read)
            } else {
                pasted = RichClipboard.paste(into, at: at, removed: 0, plainText: row["plain"] as? String ?? "")
            }
            XCTAssertEqual(pasted.text, row["text"] as? String, name)
            XCTAssertEqual(pasted.liveSpans, try JSONDecoder().decode([TextSpan].self, from: data(row["spans"])), name)
            XCTAssertEqual(TextLists.lines(pasted),
                           try JSONDecoder().decode([TextParagraph].self, from: data(row["paragraphs"])), name)
        }
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
        // A plain line pasted at a bullet's start keeps the bullet; a
        // bullet line pasted at a line's start makes one.
        var bullet = Element.text("milk")
        bullet.setLines([TextParagraph(list: "bullet")])
        let plainWord = RichClipboard.copy(Element.text("Big sale"), start: 0, end: 3)
        XCTAssertEqual(TextLists.lines(RichClipboard.paste(bullet, at: 0, removed: 0, clip: plainWord)),
                       [TextParagraph(list: "bullet")])
        let listed = RichClipboard.paste(Element.text("Tea"), at: 0, removed: 0,
                                         clip: RichClipboard.copy(source, start: 5, end: 9))
        XCTAssertEqual(TextLists.lines(listed), [TextParagraph(list: "bullet")])
        // Another app's bullet: a list item at a line's start, its words as
        // typed within a line.
        let empty = RichClipboard.paste(Element.text(""), at: 0, removed: 0, plainText: "- milk")
        XCTAssertEqual(empty.text, "milk")
        XCTAssertEqual(TextLists.lines(empty), [TextParagraph(list: "bullet")])
        XCTAssertEqual(RichClipboard.paste(Element.text("Buy "), at: 4, removed: 0, plainText: "- milk").text,
                       "Buy - milk")
    }
}
