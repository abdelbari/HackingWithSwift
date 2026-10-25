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
        let elements = try JSONDecoder().decode([Element].self, from: SharedFixture.encoded(root["elements"] ?? [Any]()))
        return (elements, root)
    }

    private func picked(_ elements: [Element], _ ids: [String]) -> [Element] {
        ids.compactMap { id in elements.first { $0.id == id } }
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
        let chosen = picked(elements, try XCTUnwrap(reaches["boxes"]))
        for (name, ids) in reaches where name != "boxes" {
            let property = try XCTUnwrap(Self.kinds[name])
            let changed = TextSelection.applied(chosen, property) { $0.text = "changed" }
            XCTAssertEqual(changed.filter { $0.text == "changed" }.map(\.id), ids, name)
        }
    }

    func testTheReadoutsSayMixedWhereTheBoxesDiffer() throws {
        let (elements, root) = try boxes()
        let cases = try XCTUnwrap(root["cases"] as? [[String: Any]])
        for row in cases {
            let ids = try XCTUnwrap(row["boxes"] as? [String])
            let chosen = picked(elements, ids)
            XCTAssertEqual(chosen.count, ids.count)
            let name = ids.joined(separator: "+")
            func number(_ key: String) -> Double? { row[key] as? Double }
            XCTAssertEqual(TextSelection.effect(chosen)?.rawValue, row["effect"] as? String, "\(name) effect")
            XCTAssertEqual(TextSelection.effectValue(chosen, .offset), number("offset"), "\(name) offset")
            XCTAssertEqual(TextSelection.sharedLetterPercent(chosen), number("letterPercent"), "\(name) letters")
            XCTAssertEqual(TextSelection.lineHeight(chosen), number("lineHeight"), "\(name) lines")
            XCTAssertEqual(TextSelection.paragraphSpacing(chosen), number("paragraphSpacing"), "\(name) paragraphs")
            XCTAssertEqual(TextSelection.list(chosen), row["list"] as? String, "\(name) list")
            XCTAssertEqual(TextSelection.curve(chosen), number("curve"), "\(name) curve")
            XCTAssertEqual(TextSelection.opacity(chosen).map { ($0 * 100).rounded() }, number("opacityPercent"), "\(name) opacity")
        }
    }

    func testEveryBoxLockedIsStillRead() throws {
        var locked = picked(try boxes().elements, ["a", "c"])
        for i in locked.indices { locked[i].locked = true }
        // Both read now, and they differ.
        XCTAssertNil(TextSelection.lineHeight(locked))
        XCTAssertEqual(TextSelection.effect(locked), .shadow)
    }

    // MARK: through the store

    func testAnEffectTileSetsEveryTextBoxInOneStep() throws {
        let s = store(picked(try boxes().elements, ["a", "b", "d", "s"]))
        s.setTextEffect(.neon)
        let page = s.page.elements
        XCTAssertEqual(page.first { $0.id == "a" }?.effect?.type, "neon")
        XCTAssertEqual(page.first { $0.id == "b" }?.effect?.type, "neon")
        XCTAssertNil(page.first { $0.id == "s" }?.effect, "a shape's words take no effect")
        s.undo()
        XCTAssertEqual(s.page.elements.first { $0.id == "a" }?.effect?.type, "shadow")
        XCTAssertEqual(s.page.elements.first { $0.id == "b" }?.effect?.type, "shadow")
    }

    func testLetterSpacingIsAShareOfEachBoxsOwnSize() throws {
        let s = store(picked(try boxes().elements, ["a", "b", "d", "s", "blank"]))
        s.setLetterPercentLive(10)
        s.commit()
        let page = s.page.elements
        XCTAssertEqual(page.first { $0.id == "a" }?.letterSpacing ?? 0, 4, accuracy: 1e-9)
        XCTAssertEqual(page.first { $0.id == "b" }?.letterSpacing ?? 0, 2, accuracy: 1e-9)
        XCTAssertEqual(page.first { $0.id == "s" }?.letterSpacing ?? 0, 3, accuracy: 1e-9)
        XCTAssertNil(page.first { $0.id == "d" }?.letterSpacing, "a locked box is left be")
        XCTAssertNil(page.first { $0.id == "blank" }?.letterSpacing, "a shape with no words has no spacing")
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

    private func shapes() throws -> (design: Design, boxes: [String: [String: Any]]) {
        let root = try SharedFixture.object("shape-lists")
        let elements = try JSONDecoder().decode([Element].self, from: SharedFixture.encoded(root["elements"] ?? [Any]()))
        var design = Design(title: "shape lists", width: 1080, height: 1080)
        design.pages = [Page(id: "p1", elements: elements)]
        return (design, try XCTUnwrap(root["boxes"] as? [String: [String: Any]]))
    }

    func testAShapesNestedListIsDrawnAsATextBoxsWouldBe() throws {
        let (design, boxes) = try shapes()
        for el in design.pages[0].elements {
            let want = try XCTUnwrap(boxes[el.id], el.id)
            let words = ShapeText.textElement(for: el)
            for (key, value) in [("x", words.x), ("y", words.y), ("w", words.w), ("h", words.h)] {
                XCTAssertEqual(value, try XCTUnwrap(want[key] as? Double), accuracy: 1e-9, "\(el.id) \(key)")
            }
            XCTAssertEqual(words.letterSpacing, want["letterSpacing"] as? Double, el.id)
            XCTAssertEqual(words.lineHeight, want["lineHeight"] as? Double, el.id)
            XCTAssertEqual(words.paragraphSpacing ?? 0, try XCTUnwrap(want["paragraphSpacing"] as? Double), accuracy: 1e-9, el.id)
            let markers = try XCTUnwrap(want["markers"] as? [Any]).map { $0 as? String }
            XCTAssertEqual(TextLists.markers(words), markers, el.id)
            XCTAssertEqual(TextLists.lines(words).map(\.level), want["levels"] as? [Int], el.id)
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
