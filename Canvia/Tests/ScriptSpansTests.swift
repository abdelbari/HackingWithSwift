// Raised and lowered words: a span's "script" ("super" or "sub"), moved
// with the words, toggled by x² and x₂ (⌘. and ⌘,), drawn at 0.62 of the
// run's size with the baseline 0.33 em up or 0.12 em down, and carried
// through PowerPoint (a:rPr baseline), Word (w:vertAlign) and a paste of
// HTML (<sup>, <sub>, vertical-align) or RTF. The remap, toggle and layout
// rows (Fixtures/spans-script.json) are shared with the Android twin.

import XCTest
import UIKit
@testable import Canvia

final class ScriptSpansTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("spans-script") }

    private func spans(_ value: Any?) throws -> [TextSpan] {
        try JSONDecoder().decode([TextSpan].self, from: SharedFixture.encoded(value ?? [Any]()))
    }

    func testAScriptReadsAndWritesAsBothPhonesDo() throws {
        let json = ##"{"end":2,"script":"sub","start":1}"##
        let span = try JSONDecoder().decode(TextSpan.self, from: Data(json.utf8))
        XCTAssertEqual(span, TextSpan(start: 1, end: 2, script: "sub"))
        XCTAssertTrue(span.says, "a script alone is something to keep")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(span), as: UTF8.self), json)
        let plain = try JSONDecoder().decode(TextSpan.self, from: Data(##"{"start":0,"end":3,"color":"#ff0000"}"##.utf8))
        XCTAssertNil(plain.script, "on the line: no key at all")
        XCTAssertFalse(String(decoding: try encoder.encode(plain), as: UTF8.self).contains("script"))
        XCTAssertTrue(Spans.hasStyles([TextSpan(start: 0, end: 1, script: "super")]))
        XCTAssertEqual(Spans.linksOnly([TextSpan(start: 0, end: 1, script: "super")]), [])
    }

    /// Shared: the spans move with the words as every other look does.
    func testTheScriptsMoveWithTheWords() throws {
        let rows = try XCTUnwrap(try fixture()["remap"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 6)
        for row in rows {
            let old = try XCTUnwrap(row["old"] as? String), new = try XCTUnwrap(row["new"] as? String)
            XCTAssertEqual(Spans.remap(old, new, try spans(row["spans"])), try spans(row["out"]), "\(old) → \(new)")
        }
    }

    /// Shared: x² or x₂ raises or lowers every word chosen unless all of
    /// them already are, then puts them back on the line.
    func testTheButtonsToggleTheScript() throws {
        let rows = try XCTUnwrap(try fixture()["toggle"] as? [[String: Any]])
        for (n, row) in rows.enumerated() {
            let range = try XCTUnwrap(row["range"] as? [Int])
            let script = try XCTUnwrap(row["script"] as? String)
            let out = Spans.toggledScript(try spans(row["spans"]), range: NSRange(location: range[0], length: range[1]),
                                          script: script)
            XCTAssertEqual(out, try spans(row["out"]), "row \(n)")
        }
        let mixed = [TextSpan(start: 0, end: 1, script: "super"), TextSpan(start: 1, end: 2, script: "sub")]
        XCTAssertFalse(Spans.script(of: mixed, in: NSRange(location: 0, length: 2)).shared)
        XCTAssertEqual(Spans.script(of: mixed, in: NSRange(location: 1, length: 1)).script, "sub")
    }

    /// Shared: the size and baseline raised and lowered letters are drawn
    /// at; the line keeps its height.
    func testRaisedAndLoweredLettersAreSmallerAndMoved() throws {
        let layout = try XCTUnwrap(try fixture()["layout"] as? [String: Any])
        for row in try XCTUnwrap(layout["rows"] as? [[Any]]) {
            let size = try XCTUnwrap(row[0] as? Double)
            let script = row[1] as? String
            XCTAssertEqual(Spans.scriptedSize(size, script: script), try XCTUnwrap(row[2] as? Double),
                           accuracy: 1e-9, "\(size) \(script ?? "none")")
            XCTAssertEqual(Spans.scriptOffset(size, script: script), try XCTUnwrap(row[3] as? Double),
                           accuracy: 1e-9, "\(size) \(script ?? "none")")
        }
        // As drawn: the letters' font and baseline.
        let base: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 40)]
        let scripted = [TextSpan(start: 1, end: 2, script: "super"), TextSpan(start: 4, end: 5, script: "sub")]
        let drawn = RichText.attributed("m2 H2O", base: base, spans: scripted, face: nil,
                                        font: { _, _ in UIFont.systemFont(ofSize: 40) })
        let raised = drawn.attributes(at: 1, effectiveRange: nil)
        XCTAssertEqual(Double((raised[.font] as? UIFont)?.pointSize ?? 0), 24.8, accuracy: 0.001)
        XCTAssertEqual((raised[.baselineOffset] as? Double) ?? 0, 13.2, accuracy: 0.001)
        let lowered = drawn.attributes(at: 4, effectiveRange: nil)
        XCTAssertEqual((lowered[.baselineOffset] as? Double) ?? 0, -4.8, accuracy: 0.001)
        XCTAssertNil(drawn.attributes(at: 0, effectiveRange: nil)[.baselineOffset])
        XCTAssertEqual(drawn.string, "m2 H2O", "the letters themselves are unchanged for Find, spelling and reading")
    }

    func testPowerPointWritesAndReadsTheBaseline() {
        var el = Element.text("m2 H2O")
        el.setSpans([TextSpan(start: 1, end: 2, script: "super"), TextSpan(start: 4, end: 5, script: "sub")])
        let runs = PptxExporter.paragraphs(of: el)
        XCTAssertEqual(runs.first?.map(\.script), [nil, "super", nil, "sub", nil])
        XCTAssertEqual(PptxExporter.baseline("super"), "30000")
        XCTAssertEqual(PptxExporter.baseline("sub"), "-25000")
        XCTAssertNil(PptxExporter.baseline(nil))
        XCTAssertEqual(PptxReader.script(baseline: "30000"), "super")
        XCTAssertEqual(PptxReader.script(baseline: "-25000"), "sub")
        XCTAssertEqual(PptxReader.script(baseline: "8000"), "super")
        XCTAssertNil(PptxReader.script(baseline: "0"))
        XCTAssertNil(PptxReader.script(baseline: nil))
    }

    func testWordWritesAndReadsVertAlign() throws {
        let json = ##"""
        {"id":"d-script","title":"Notes","width":816,"height":1056,"createdAt":0,"updatedAt":0,"kind":"doc",
         "docPage":{"size":"letter","margins":72},
         "blocks":[{"id":"s1","type":"p","text":"H2O and m2",
                    "spans":[{"start":1,"end":2,"script":"sub"},{"start":9,"end":10,"script":"super"}],
                    "spansText":"H2O and m2"}],
         "pages":[]}
        """##
        let d = try JSONDecoder().decode(Design.self, from: Data(json.utf8))
        let xml = DocxWriter.documentXml(d)
        XCTAssertTrue(xml.contains("<w:rPr><w:vertAlign w:val=\"subscript\"/></w:rPr><w:t xml:space=\"preserve\">2</w:t>"), xml)
        XCTAssertTrue(xml.contains("<w:rPr><w:vertAlign w:val=\"superscript\"/></w:rPr><w:t xml:space=\"preserve\">2</w:t>"), xml)
        XCTAssertEqual(DocxReader.script("superscript"), "super")
        XCTAssertEqual(DocxReader.script("subscript"), "sub")
        XCTAssertNil(DocxReader.script("baseline"))
        XCTAssertNil(DocxReader.script(nil))
    }

    func testAPasteKeepsRaisedAndLoweredWords() {
        let clip = ForeignText.fromHtml("<p>m<sup>2</sup> H<sub>2</sub>O <span style=\"vertical-align: super\">st</span></p>")
        XCTAssertEqual(clip.plain, "m2 H2O st")
        XCTAssertEqual(clip.spans, [TextSpan(start: 1, end: 2, script: "super"), TextSpan(start: 4, end: 5, script: "sub"),
                                    TextSpan(start: 7, end: 9, script: "super")])
        let back = ForeignText.fromHtml("<sup>a<span style=\"vertical-align: baseline\">b</span></sup>")
        XCTAssertEqual(back.spans, [TextSpan(start: 0, end: 1, script: "super")])
        // RTF's \super and \sub, as the system hands them over.
        XCTAssertEqual(ForeignText.look(of: [.baselineOffset: 4.0]).script, "super")
        XCTAssertEqual(ForeignText.look(of: [NSAttributedString.Key("NSSuperScript"): -1]).script, "sub")
        XCTAssertNil(ForeignText.look(of: [:]).script)
    }

    func testTheClipboardCarriesTheScript() throws {
        var el = Element.text("E = mc2")
        el.setSpans([TextSpan(start: 6, end: 7, script: "super")])
        let clip = RichClipboard.copy(el, start: 4, end: 7)
        let back = try XCTUnwrap(RichClipboard.decode(RichClipboard.json(clip)))
        XCTAssertEqual(back.spans, [TextSpan(start: 2, end: 3, script: "super")])
    }

    func testTheKeysRaiseAndLower() {
        XCTAssertEqual(TextKeys.action(for: ".", shift: false), .raise)
        XCTAssertEqual(TextKeys.action(for: ",", shift: false), .lower)
        XCTAssertEqual(TextKeys.action(for: ".", shift: true), .larger)
        XCTAssertEqual(TextKeys.action(for: ",", shift: true), .smaller)
        XCTAssertEqual(TextKeys.keyName(.raise), "Superscript")
        XCTAssertEqual(TextKeys.keyName(.lower), "Subscript")
    }
}
