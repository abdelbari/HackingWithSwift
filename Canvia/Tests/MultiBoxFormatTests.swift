// Round 34's format for several text boxes at once, and for the words in a
// shape: what a change of each property reaches (TextSelection.applied), the
// readouts that say "Mixed" where the boxes differ — the shared fixture
// Fixtures/multi-text.json — one undo step for each change, letter spacing
// kept as a share of each box's own size, and a shape's lists and spacing
// written to a text box's keys and drawn through its words' box — the
// shared fixture Fixtures/shape-lists.json. The Android twin's tests hold
// the same rows.

import XCTest
@testable import Canvia

@MainActor
final class MultiBoxFormatTests: XCTestCase {

    private func boxes() throws -> (elements: [Element], root: [String: Any]) {
        let root = try SharedFixture.object("multi-text")
        let elements = try JSONDecoder().decode([Element].self, from: SharedFixture.encoded(root["boxes"] ?? [Any]()))
        return (elements, root)
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "several", width: 1000, height: 1000)
        design.pages[0].elements = elements
        let s = DesignStore(design: design)
        s.selection = Set(elements.map(\.id))
        return s
    }

    private static let kinds: [String: TextSelection.Property] = [
        "effect": .effect, "curve": .curve, "spacing": .spacing, "list": .list, "opacity": .opacity,
    ]

    // MARK: the shared fixture

    func testEachChangeReachesTheBoxesTheFixtureNames() throws {
        let (elements, root) = try boxes()
        let reaches = try XCTUnwrap(root["reaches"] as? [String: [String]])
        for (name, ids) in reaches {
            let property = try XCTUnwrap(Self.kinds[name])
            let changed = TextSelection.applied(elements, property) { $0.text = "changed" }
            XCTAssertEqual(changed.filter { $0.text == "changed" }.map(\.id), ids, name)
        }
    }

    func testTheReadoutsSayMixedWhereTheBoxesDiffer() throws {
        let (elements, root) = try boxes()
        let readouts = try XCTUnwrap(root["readouts"] as? [String: Any])
        func number(_ key: String) -> Double? { readouts[key] as? Double }
        XCTAssertEqual(TextSelection.effect(elements)?.rawValue, readouts["effect"] as? String)
        XCTAssertEqual(TextSelection.effectValue(elements, .offset), number("offset"))
        XCTAssertEqual(TextSelection.effectValue(elements, .blur), number("blur"))
        XCTAssertEqual(TextSelection.effectValue(elements, .direction), number("direction"))
        XCTAssertEqual(TextSelection.sharedLetterPercent(elements), number("letterPercent"))
        XCTAssertEqual(TextSelection.lineHeight(elements), number("lineHeight"))
        XCTAssertEqual(TextSelection.paragraphSpacing(elements), number("paragraphSpacing"))
        XCTAssertEqual(TextSelection.list(elements), readouts["list"] as? String)
        XCTAssertEqual(TextSelection.curve(elements), number("curve"))
        XCTAssertEqual(TextSelection.opacity(elements), number("opacity"))
    }

    func testEveryBoxLockedIsStillRead() throws {
        var locked = try boxes().elements.filter { $0.type == .text }
        for i in locked.indices { locked[i].locked = true }
        // a, b and c all read now, and they differ.
        XCTAssertNil(TextSelection.effect(locked))
        XCTAssertNil(TextSelection.lineHeight(locked))
    }

    // MARK: through the store

    func testAnEffectTileSetsEveryTextBoxInOneStep() throws {
        let s = store(try boxes().elements)
        s.setTextEffect(.neon)
        let page = s.page.elements
        XCTAssertEqual(page.first { $0.id == "a" }?.effect?.type, "neon")
        XCTAssertEqual(page.first { $0.id == "b" }?.effect?.type, "neon")
        XCTAssertNil(page.first { $0.id == "d" }?.effect, "a shape's words take no effect")
        s.undo()
        XCTAssertEqual(s.page.elements.first { $0.id == "a" }?.effect?.type, "shadow")
        XCTAssertEqual(s.page.elements.first { $0.id == "b" }?.effect?.type, "shadow")
    }

    func testLetterSpacingIsAShareOfEachBoxsOwnSize() throws {
        let s = store(try boxes().elements)
        s.setLetterPercentLive(10)
        s.commit()
        let page = s.page.elements
        XCTAssertEqual(page.first { $0.id == "a" }?.letterSpacing ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(page.first { $0.id == "b" }?.letterSpacing ?? 0, 5, accuracy: 1e-9)
        XCTAssertEqual(page.first { $0.id == "d" }?.letterSpacing ?? 0, 3, accuracy: 1e-9)
        XCTAssertEqual(page.first { $0.id == "c" }?.letterSpacing, 5, "a locked box is left be")
        XCTAssertEqual(TextSelection.sharedLetterPercent(page), 10)
    }

    func testAListAndAnIndentReachEveryParagraph() throws {
        var a = Element.text("One\nTwo"), b = Element.text("Three")
        a.id = "a"; b.id = "b"
        let s = store([a, b])
        s.setTextList("number")
        XCTAssertEqual(TextSelection.list(s.page.elements), "number")
        s.indentTexts(by: 1)
        XCTAssertEqual(TextSelection.levels(s.page.elements).shallowest, 1)
        s.setTextList("none")
        XCTAssertEqual(TextSelection.list(s.page.elements), "none")
    }

    // MARK: words in shapes

    private func shapes() throws -> (design: Design, markers: [String: [String?]]) {
        let root = try SharedFixture.object("shape-lists")
        let design = try JSONDecoder().decode(Design.self, from: SharedFixture.data("shape-lists"))
        let raw = try XCTUnwrap(root["markers"] as? [String: [Any]])
        let markers = raw.mapValues { row in row.map { $0 as? String } }
        return (design, markers)
    }

    func testAShapesNestedListIsDrawnAsATextBoxsWouldBe() throws {
        let (design, markers) = try shapes()
        for el in design.pages[0].elements {
            let words = ShapeText.textElement(for: el)
            XCTAssertEqual(TextLists.markers(words), markers[el.id], el.id)
            XCTAssertEqual(words.lineHeight, el.lineHeight, el.id)
            XCTAssertEqual(words.letterSpacing, el.letterSpacing, el.id)
            XCTAssertEqual(words.paragraphSpacing, el.paragraphSpacing, el.id)
        }
    }

    func testAShapesListAndSpacingKeepTheTextBoxKeys() throws {
        let (design, _) = try shapes()
        let star = try XCTUnwrap(design.pages[0].elements.first { $0.id == "star" })
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(star)) as? [String: Any])
        for key in ["lineHeight", "letterSpacing", "paragraphSpacing", "paragraphs", "paragraphsText"] {
            XCTAssertNotNil(object[key], key)
        }
    }

    func testIndentInAShapeIsOneStepAndTheShapeNeverShrinks() throws {
        let (design, _) = try shapes()
        let s = DesignStore(design: design)
        s.selection = ["card"]
        let before = try XCTUnwrap(s.element("card"))
        s.indentTexts(by: 1)
        let after = try XCTUnwrap(s.element("card"))
        XCTAssertEqual(TextLists.lines(after).map(\.level), [1, 1, 1, 2])
        XCTAssertGreaterThanOrEqual(after.h, before.h)
        s.undo()
        XCTAssertEqual(s.element("card").map { TextLists.lines($0).map(\.level) }, [0, 0, 0, 1])
    }

    func testTypedListKeysWorkInAShape() throws {
        let (design, _) = try shapes()
        let s = DesignStore(design: design)
        s.selection = ["card"]
        let changed = s.changeLines("card", covering: NSRange(location: 0, length: 0)) { $0.list = "bullet" }
        XCTAssertTrue(changed)
        XCTAssertEqual(s.element("card").flatMap { TextLists.lines($0).first?.list }, "bullet")
    }
}
