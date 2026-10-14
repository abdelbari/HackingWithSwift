// Lists set paragraph by paragraph — `paragraphs` — over the Android twin's
// TextListsTest rows, row for row.

import XCTest
@testable import Canvia

final class TextParagraphsTests: XCTestCase {

    private let none = TextParagraph()
    private func bullet(_ level: Int = 0) -> TextParagraph { TextParagraph(list: "bullet", level: level) }
    private func number(_ level: Int = 0) -> TextParagraph { TextParagraph(list: "number", level: level) }
    private func letter(_ level: Int = 0) -> TextParagraph { TextParagraph(list: "letter", level: level) }

    private func box(_ text: String, _ lines: [TextParagraph]) -> Element {
        var el = Element.text(text)
        el.setLines(lines)
        return el
    }

    /// Shared rows: each line's marker, numbered across levels.
    func testNumbersGoOneAIByLevelAndStartAgainAfterAPlainLineOrAShallowerItem() {
        // text, paragraphs, markers
        let rows: [(String, [TextParagraph], [String?])] = [
            ("A\nB\nC", [number(), number(1), number(1)], ["1.  ", "a.  ", "b.  "]),
            ("A\nB\nC\nD", [number(), number(1), number(), number(1)], ["1.  ", "a.  ", "2.  ", "a.  "]),
            ("A\nB\nC", [number(), number(1), number(2)], ["1.  ", "a.  ", "i.  "]),
            ("A\nB\nC\nD", [number(2), number(2), number(2), number(2)], ["i.  ", "ii.  ", "iii.  ", "iv.  "]),
            ("A\nHead\nB", [number(), none, number()], ["1.  ", nil, "1.  "]),
            ("A\n\nB", [number(), number(), number()], ["1.  ", nil, "2.  "]),
            ("A\nB\nC", [bullet(), bullet(1), bullet(2)], ["•  ", "◦  ", "▪  "]),
            ("A\nB", [bullet(3), bullet(4)], ["•  ", "◦  "]),
            ("A\nB\nC", [letter(), letter(1), letter(2)], ["a.  ", "i.  ", "1.  "]),
            ("A\nB\nC", [bullet(), number(), number()], ["•  ", "1.  ", "2.  "]),
            ("A\nB\nC", [number(), bullet(), number()], ["1.  ", "•  ", "1.  "]),
            ("Head\nA\nB", [none, bullet(), bullet()], [nil, "•  ", "•  "]),
        ]
        for (text, lines, markers) in rows {
            XCTAssertEqual(TextLists.markers(box(text, lines)), markers, "\(text) \(lines)")
        }
        let heading = box("Plan\nShop\nCook", [none, bullet(), bullet()])
        XCTAssertEqual(FontLibrary.displayText(for: heading), "Plan\n•  Shop\n•  Cook")
        XCTAssertEqual(TextLists.roman(9), "ix")
        XCTAssertEqual(TextLists.roman(44), "xliv")
    }

    /// Shared rows: paragraphs moved by a line diff as the words change.
    func testParagraphsFollowTheirLinesThroughAnEdit() {
        let a = bullet(), b = number(1), c = none
        // before, after, paragraphs, expected
        let rows: [(String, String, [TextParagraph], [TextParagraph])] = [
            // Return at the end of a line: the new line copies it.
            ("One\nTwo", "One\n\nTwo", [a, c], [a, a, c]),
            // Split in the middle: both halves take the line split.
            ("One\nTwo", "On\ne\nTwo", [b, c], [b, b, c]),
            // Return at the very start: the new line copies the one after.
            ("One\nTwo", "\nOne\nTwo", [a, c], [a, a, c]),
            // A line typed in keeps its own.
            ("One\nTwo\nSix", "One\nTwos\nSix", [a, b, c], [a, b, c]),
            // Two lines joined: the first's.
            ("One\nTwo\nSix", "OneTwo\nSix", [b, a, c], [b, c]),
            // A line taken away.
            ("One\nTwo\nSix", "One\nSix", [a, b, c], [a, c]),
            // Lines pasted in after the last.
            ("One", "One\nTwo\nSix", [b], [b, b, b]),
        ]
        for (before, after, lines, expected) in rows {
            XCTAssertEqual(TextLists.remap(before, after, lines), expected, "\(before) → \(after)")
        }
        // Through the words changing on a box, style markers aside.
        var typed = box("Plan\nShop", [none, bullet()])
        typed.setText("Plan\nShop\n**Cook**")
        XCTAssertEqual(TextLists.paragraphsOf(typed), [none, bullet(), bullet()])
        XCTAssertEqual(typed.paragraphsText, "Plan\nShop\nCook")
        // And through a page number filled in.
        var page = box("Plan\nPage {page}", [none, bullet()])
        page.fillPageTokens(number: 3, count: 4)
        XCTAssertEqual(TextLists.paragraphsOf(page), [none, bullet()])
    }

    func testParagraphsAreWrittenTheirDefaultsLeftOutAndGuardedByTheirWords() throws {
        let el = box("Plan\nShop\nCook", [none, bullet(), number(2)])
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        let written = try XCTUnwrap(json["paragraphs"] as? [[String: Any]])
        XCTAssertEqual(written.count, 3)
        XCTAssertTrue(written[0].isEmpty)
        XCTAssertEqual(written[1]["list"] as? String, "bullet")
        XCTAssertNil(written[1]["level"])
        XCTAssertEqual(written[2]["list"] as? String, "number")
        XCTAssertEqual(written[2]["level"] as? Int, 2)
        XCTAssertEqual(json["paragraphsText"] as? String, "Plan\nShop\nCook")
        XCTAssertNil(json["listStyle"])
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back, el)
        // Words changed by a build that knows nothing of them: the box-wide
        // keys again, and the stale ones dropped as the design is read.
        var stale = el
        stale.text = "Plan\nShop"
        XCTAssertNil(TextLists.paragraphsOf(stale))
        XCTAssertFalse(TextLists.isList(stale))
        let reread = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(stale))
        XCTAssertFalse(TextLists.stored(reread))
        // Made for the words as they read, style markers out.
        let bold = box("**Plan**\nShop", [none, bullet()])
        XCTAssertEqual(bold.paragraphsText, "Plan\nShop")
        XCTAssertEqual(TextLists.paragraphsOf(bold), [none, bullet()])
        // As the Android twin writes them: an unknown list is none, a level
        // past the deepest the deepest.
        let android = #"{"type":"text","text":"A\nB","paragraphs":[{"list":"star"},{"list":"bullet","level":9}],"paragraphsText":"A\nB"}"#
        let read = try JSONDecoder().decode(Element.self, from: Data(android.utf8))
        XCTAssertEqual(TextLists.paragraphsOf(read), [none, bullet(4)])
    }

    /// Shared rows: a style copied from a box with its own lines carries its
    /// first listed line as the whole box's list and indent; pasted, it
    /// sets every line, the box's own lines gone.
    func testAStyleCopiedAndPastedCarriesAListForTheWholeBox() {
        let headed = box("Plan\nShop\nCook", [none, bullet(1), bullet(1)])
        let bullets = box("A\nB", [bullet(), bullet()])
        var onBullets = bullets
        DesignStore.apply(DesignStore.style(of: headed), to: &onBullets)
        XCTAssertEqual(TextLists.lines(onBullets), [bullet(1), bullet(1)])
        var onHeaded = headed
        DesignStore.apply(DesignStore.style(of: bullets), to: &onHeaded)
        XCTAssertNil(TextLists.paragraphsOf(onHeaded))
        XCTAssertEqual(TextLists.lines(onHeaded), [bullet(), bullet(), bullet()])
        var plain = headed
        DesignStore.apply(DesignStore.style(of: Element.text("Hi")), to: &plain)
        XCTAssertEqual(TextLists.lines(plain), [none, none, none])
    }

    /// Shared rows: a linked text style updated from a heading-and-bullets
    /// box leaves every follower's own lines as they are, and gives a
    /// follower with no list none.
    func testUpdatingALinkedStyleKeepsEachFollowersLines() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("styles-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var source = box("Plan\nShop\nCook", [none, bullet(), bullet()])
        let style = TextStyles.add(named: "Notes", from: source, url: url)
        source.textStyleId = style.id
        var follower = box("Plan\nShop\nCook", [none, bullet(), bullet()])
        TextStyles.apply(style, to: &follower)
        var plain = Element.text("Hi")
        TextStyles.apply(style, to: &plain)
        source.color = "#ff0000"
        TextStyles.update(style.id, from: source, url: url)
        let newer = try XCTUnwrap(TextStyles.load(from: url).first { $0.id == style.id })
        TextStyles.apply(newer, to: &follower)
        TextStyles.apply(newer, to: &plain)
        XCTAssertEqual(follower.color, "#ff0000")
        XCTAssertEqual(TextLists.lines(follower), [none, bullet(), bullet()])
        XCTAssertEqual(TextLists.lines(plain), [none])
        XCTAssertEqual(plain.color, "#ff0000")
    }

    func testLinesAllAlikeAreTheBoxWideKeysWhenTheyReadTheSame() {
        let bullets = box("A\nB", [bullet(), bullet()])
        XCTAssertEqual(bullets.listStyle, "bullet")
        XCTAssertFalse(TextLists.stored(bullets))
        let pushed = box("A\nB", [TextParagraph(level: 2), TextParagraph(level: 2)])
        XCTAssertEqual(pushed.indent, 2)
        XCTAssertFalse(TextLists.stored(pushed))
        let plain = box("A\nB", [none, none])
        XCTAssertNil(plain.listStyle)
        XCTAssertNil(plain.indent)
        XCTAssertFalse(TextLists.stored(plain))
        // A deeper list keeps its own: box-wide, its marker would be •.
        let deep = box("A\nB", [bullet(1), bullet(1)])
        XCTAssertTrue(TextLists.stored(deep))
        XCTAssertEqual(TextLists.markers(deep), ["◦  ", "◦  "])
        // A box with no paragraphs reads as it always has: every line at the
        // box's indent, the first level's marker whatever the indent.
        var old = Element.text("A\n\nB")
        old.listStyle = "number"
        old.indent = 1
        XCTAssertEqual(TextLists.lines(old), [number(1), number(1), number(1)])
        XCTAssertEqual(TextLists.markers(old), ["1.  ", nil, "2.  "])
    }

    func testThePanelActsOnEveryLineAndTheTypingBarOnTheLinesChosen() {
        let el = box("Plan\nShop\nCook", [none, bullet(), bullet(1)])
        // Every line numbered, levels kept.
        var numbered = el
        numbered.setListStyle("number")
        XCTAssertEqual(TextLists.lines(numbered), [number(), number(), number(1)])
        // Every line a level deeper, held at the deepest.
        var deeper = el
        deeper.stepIndent(by: 1)
        XCTAssertEqual(TextLists.lines(deeper), [TextParagraph(level: 1), bullet(1), bullet(2)])
        var shallower = el
        shallower.stepIndent(by: -1)
        XCTAssertEqual(TextLists.lines(shallower), [none, bullet(), bullet()])
        // Box-wide, the box-wide keys.
        var wide = Element.text("A")
        wide.indent = 2
        wide.stepIndent(by: 1)
        XCTAssertEqual(wide.indent, 3)
        // The lines a choice covers.
        XCTAssertEqual(TextLists.lineRange("Plan\nShop\nCook", NSRange(location: 2, length: 0)), 0...0)
        XCTAssertEqual(TextLists.lineRange("Plan\nShop\nCook", NSRange(location: 6, length: 5)), 1...2)
        XCTAssertEqual(TextLists.lineRange("Plan\nShop\nCook", NSRange(location: 5, length: 0)), 1...1)
        var nested = el
        nested.changeLines(2...2) { $0.level += 1 }
        XCTAssertEqual(TextLists.lines(nested), [none, bullet(), bullet(2)])
        // List goes none → bullets → numbers → none.
        XCTAssertEqual(TextLists.nextList("none"), "bullet")
        XCTAssertEqual(TextLists.nextList("bullet"), "number")
        XCTAssertEqual(TextLists.nextList("number"), "none")
        XCTAssertEqual(TextLists.nextList("letter"), "none")
    }

    func testDrawnSpansStepPastEachLinesOwnMarker() {
        var el = box("Plan\nShop", [none, bullet()])
        el.setSpans([TextSpan(start: 5, end: 9, color: "#ff0000")])
        let marked = FontLibrary.markedDisplayText(for: el, pageNumber: nil, pageCount: nil)
        XCTAssertEqual(marked, "Plan\n•  Shop")
        let span = FontLibrary.displaySpans(for: el, marked: marked).first
        XCTAssertEqual(span.map { (marked as NSString).substring(with: $0.range) }, "Shop")
    }

    /// The typing bar's List and Indent act on the lines the choice covers,
    /// each a step of its own that Undo while typing takes back.
    @MainActor
    func testTheTypingBarsListIsAStepOfItsOwn() throws {
        let el = Element.text("Plan\nShop\nCook")
        var design = Design(title: "lists", width: 1000, height: 1000)
        design.pages[0].elements = [el]
        let s = DesignStore(design: design)
        s.startTyping(el.id)
        XCTAssertTrue(s.changeLines(el.id, covering: NSRange(location: 6, length: 5)) { $0.list = "bullet" })
        XCTAssertEqual(TextLists.lines(try XCTUnwrap(s.element(el.id))), [none, bullet(), bullet()])
        XCTAssertFalse(s.changeLines(el.id, covering: NSRange(location: 0, length: 0)) {
            $0.level = max(0, $0.level - 1)
        }, "a line already at the edge does not move")
        s.undo()
        XCTAssertFalse(TextLists.isList(try XCTUnwrap(s.element(el.id))))
        XCTAssertEqual(s.editingTextId, el.id, "the typing stays open")
    }

    /// A text box's bar has List, Outdent and Indent; a shape's words have
    /// no lists.
    @MainActor
    func testATextBoxsBarHasListAndIndentsAndAShapesHasNot() {
        let box = labels(InlineTextField(element: .text("Big sale"), onChange: { _ in }, onDone: {}))
        XCTAssertTrue(["List", "Outdent", "Indent"].allSatisfy { box.contains($0) }, "\(box)")
        let shape = labels(InlineTextField(element: ShapeText.textElement(for: .shape("rect")),
                                           onChange: { _ in }, onDone: {}, wordStyles: false))
        XCTAssertFalse(shape.contains("List"))
    }

    /// What the buttons on a field's bar are called.
    @MainActor
    private func labels(_ field: InlineTextField) -> [String] {
        (field.makeCoordinator().typingBar().items ?? []).compactMap { $0.accessibilityLabel }
    }

    /// Each paragraph at its own level, a list item hanging its marker — the
    /// canvas's paragraph styles, a line at a time.
    func testEachLineIsIndentedAtItsOwnLevel() throws {
        var el = box("Plan\nShop\nCook", [none, bullet(), number(2)])
        el.fontSize = 20
        let drawn = FontLibrary.attributedString(for: el)
        let ns = drawn.string as NSString
        func style(at line: String) throws -> NSParagraphStyle {
            let at = ns.range(of: line).location
            return try XCTUnwrap(drawn.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)
        }
        XCTAssertEqual(try style(at: "Plan").firstLineHeadIndent, 0)
        XCTAssertEqual(try style(at: "Plan").headIndent, 0)
        XCTAssertEqual(try style(at: "Shop").firstLineHeadIndent, 0)
        XCTAssertEqual(try style(at: "Shop").headIndent, 20 * FontLibrary.markerEm, accuracy: 0.001)
        XCTAssertEqual(try style(at: "Cook").firstLineHeadIndent, 2 * 20 * FontLibrary.indentEm, accuracy: 0.001)
        XCTAssertEqual(try style(at: "Cook").headIndent, 20 * (2 * FontLibrary.indentEm + FontLibrary.markerEm),
                       accuracy: 0.001)
    }

    /// A larger word in a listed line keeps the room it was given: the
    /// line's own indents go over that style, not over the box's.
    func testALargerWordInAListedLineKeepsItsRoom() throws {
        var el = box("Plan\nShop", [none, bullet()])
        el.fontSize = 20
        el.lineHeight = 1.25
        el.setSpans([TextSpan(start: 5, end: 9, scale: 2)])
        let drawn = FontLibrary.attributedString(for: el)
        let at = (drawn.string as NSString).range(of: "Shop").location
        let style = try XCTUnwrap(drawn.attribute(.paragraphStyle, at: at, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.maximumLineHeight, 20 * 1.25 * 2, accuracy: 0.001)
        XCTAssertEqual(style.headIndent, 20 * FontLibrary.markerEm, accuracy: 0.001)
        let plan = try XCTUnwrap(drawn.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(plan.maximumLineHeight, 20 * 1.25, accuracy: 0.001)
    }
}
