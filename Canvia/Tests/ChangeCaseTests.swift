// Change case and capitals on chosen words, over the shared
// Fixtures/change-case.json the Android twin's TextCaseTest reads row for
// row.

import XCTest
@testable import Canvia

final class ChangeCaseTests: XCTestCase {

    /// Shared rows: each transform over the words, or a range of them, in
    /// the design's language.
    func testEachTransformCasesTheWordsInTheDesignsLanguage() throws {
        let fixture = try SharedFixture.object("change-case")
        let rows = try XCTUnwrap(fixture["rows"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let text = try XCTUnwrap(row["text"] as? String)
            let locale = ChangeCase.locale(row["language"] as? String)
            let range = (row["range"] as? [Int]).map { NSRange(location: $0[0], length: $0[1] - $0[0]) }
            for kind in ChangeCase.Casing.allCases {
                let expected = try XCTUnwrap(row[kind.rawValue] as? String)
                XCTAssertEqual(ChangeCase.transformed(text, kind, range: range, locale: locale), expected,
                               "\(text) \(kind.rawValue)")
            }
        }
    }

    /// Shared rows: a box's stored words, markers and spans and all,
    /// changed over the stretch selected (all of them for none).
    func testEachTransformChangesTheStoredWordsAndMovesTheSpans() throws {
        let fixture = try SharedFixture.object("change-case")
        let rows = try XCTUnwrap(fixture["changed"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let name = row["name"] as? String ?? ""
            var el = Element.text(try XCTUnwrap(row["text"] as? String))
            if let spans = row["spans"] {
                el.setSpans(try JSONDecoder().decode([TextSpan].self, from: SharedFixture.encoded(spans)))
            }
            let start = try XCTUnwrap(row["start"] as? Int)
            let end = try XCTUnwrap(row["end"] as? Int)
            let kind = try XCTUnwrap(ChangeCase.Casing(rawValue: try XCTUnwrap(row["case"] as? String)))
            let locale = ChangeCase.locale(row["language"] as? String)
            let selection = start == end ? nil : NSRange(location: start, length: end - start)
            let out = ChangeCase.changed(el, selection: selection, kind, locale: locale) ?? el
            XCTAssertEqual(out.text, row["out"] as? String, name)
            if let spans = row["outSpans"] {
                XCTAssertEqual(out.liveSpans, try JSONDecoder().decode([TextSpan].self, from: SharedFixture.encoded(spans)), name)
            }
        }
    }

    /// Shared rows: words with capitals of their own drawn in them.
    func testWordsWithCapsAreDrawnInCapitals() throws {
        let fixture = try SharedFixture.object("change-case")
        let rows = try XCTUnwrap(fixture["caps"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let el = try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(XCTUnwrap(row["element"])))
            let shown = try XCTUnwrap(row["shown"] as? String)
            XCTAssertEqual(FontLibrary.displayText(for: el), shown)
            XCTAssertEqual(FontLibrary.attributedString(for: el).string, shown)
        }
    }

    func testCapsIsWrittenOnlyWhenTrueAndMovesWithTheWords() throws {
        let on = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TextSpan(start: 0, end: 3, caps: true)))
            as? [String: Any]
        XCTAssertEqual(on?["caps"] as? Bool, true)
        let off = try JSONDecoder().decode(TextSpan.self, from: Data("{\"start\":0,\"end\":3,\"caps\":false}".utf8))
        XCTAssertNil(off.caps)
        // A span of nothing but caps: false is no span at all.
        XCTAssertTrue(Spans.normalised([off]).isEmpty)
        var el = Element.text("Big sale")
        el.setSpans(Spans.toggledCaps([], range: NSRange(location: 4, length: 4)))
        XCTAssertEqual(el.liveSpans, [TextSpan(start: 4, end: 8, caps: true)])
        el.setText("A big sale")
        XCTAssertEqual(el.liveSpans, [TextSpan(start: 6, end: 10, caps: true)])
        // Toggled again over the same words: as typed.
        el.setSpans(Spans.toggledCaps(el.liveSpans, range: NSRange(location: 6, length: 4)))
        XCTAssertNil(el.spans)
        // The field types the words as they are kept.
        el.setSpans([TextSpan(start: 2, end: 5, caps: true)])
        XCTAssertEqual(FontLibrary.typedAttributedString(for: el).string, "A big sale")
        XCTAssertEqual(FontLibrary.displayText(for: el), "A BIG sale")
    }

    /// PowerPoint: a run in capitals of its own says cap="all".
    func testARunInCapitalsIsWrittenSo() {
        var el = Element.text("Big sale")
        el.setSpans([TextSpan(start: 4, end: 8, caps: true)])
        let runs = PptxExporter.paragraphs(of: el).flatMap { $0 }
        XCTAssertEqual(runs.map(\.text), ["Big ", "sale"])
        XCTAssertEqual(runs.map(\.caps), [nil, true])
    }

    /// Changing the words keeps their markers on the same letters, their
    /// spans on the same words and each line its list.
    func testChangingCaseKeepsMarkersSpansAndLines() throws {
        var el = Element.text("**hello** world\nnext line")
        el.setSpans([TextSpan(start: 6, end: 11, color: "#ff0000")])
        el.changeLines(1...1) { $0.list = "bullet" }
        let en = ChangeCase.locale("en")
        let title = try XCTUnwrap(ChangeCase.changed(el, selection: nil, .title, locale: en))
        XCTAssertEqual(title.text, "**Hello** World\nNext Line")
        XCTAssertEqual(title.liveSpans, [TextSpan(start: 6, end: 11, color: "#ff0000")])
        XCTAssertEqual(TextLists.lines(title).map(\.list), ["none", "bullet"])
        // A choice in the stored words, its markers counted: only "world".
        let chosen = NSRange(location: 10, length: 5)
        let upper = try XCTUnwrap(ChangeCase.changed(el, selection: chosen, .upper, locale: en))
        XCTAssertEqual(upper.text, "**hello** WORLD\nnext line")
        // A letter that grows takes its span with it.
        var street = Element.text("die straße hier")
        street.setSpans([TextSpan(start: 11, end: 15, color: "#00ff00")])
        let shouted = try XCTUnwrap(ChangeCase.changed(street, selection: nil, .upper, locale: ChangeCase.locale("de")))
        XCTAssertEqual(shouted.text, "DIE STRASSE HIER")
        XCTAssertEqual(shouted.liveSpans, [TextSpan(start: 12, end: 16, color: "#00ff00")])
        // Nothing to change is nil.
        XCTAssertNil(ChangeCase.changed(Element.text("ALL"), selection: nil, .upper, locale: en))
    }
}
