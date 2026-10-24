// Highlight colour on chosen words: a marker behind them, kept on each span
// as "highlight" ("#rrggbb" or "#rrggbbaa"), its rects on a drawn line, and
// carried through the clipboard, the PowerPoint writer and reader, and the
// contrast audit. The span JSON and rect rows (Fixtures/word-highlights.json)
// are shared with the Android twin's WordHighlightsTest.

import XCTest
@testable import Canvia

final class WordHighlightTests: XCTestCase {

    /// One span with a marker, as both phones write it.
    static let spanJSON = ##"{"end":5,"highlight":"#FFF17680","start":2}"##

    func testASpansHighlightReadsAndWritesAsBothPhonesDo() throws {
        let span = try JSONDecoder().decode(TextSpan.self, from: Data(Self.spanJSON.utf8))
        XCTAssertEqual(span, TextSpan(start: 2, end: 5, highlight: "#FFF17680"))
        XCTAssertTrue(span.says, "a highlight alone is something to keep")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(span), as: UTF8.self), Self.spanJSON)
        let old = try JSONDecoder().decode(TextSpan.self, from: Data(##"{"start":0,"end":3,"color":"#ff0000"}"##.utf8))
        XCTAssertNil(old.highlight, "a span from before highlights has none")
    }

    func testHighlightingWordsKeepsTheirOtherLooksAndReadsMixed() {
        let spans = [TextSpan(start: 0, end: 4, color: "#ff0000")]
        let marked = Spans.highlighting(spans, range: NSRange(location: 2, length: 4), highlight: "#A5D6A7")
        XCTAssertEqual(marked, [TextSpan(start: 0, end: 2, color: "#ff0000"),
                                TextSpan(start: 2, end: 4, color: "#ff0000", highlight: "#A5D6A7"),
                                TextSpan(start: 4, end: 6, highlight: "#A5D6A7")])
        let shared = Spans.highlight(of: marked, in: NSRange(location: 2, length: 4))
        XCTAssertEqual(shared.highlight, "#A5D6A7")
        XCTAssertTrue(shared.shared)
        XCTAssertFalse(Spans.highlight(of: marked, in: NSRange(location: 0, length: 4)).shared, "Mixed")
        XCTAssertEqual(Spans.highlighting(marked, range: NSRange(location: 0, length: 6), highlight: nil),
                       [TextSpan(start: 0, end: 4, color: "#ff0000")])
        XCTAssertTrue(Spans.hasStyles([TextSpan(start: 0, end: 1, highlight: "#FFF176")]))
        XCTAssertEqual(Spans.highlightPresets, ["#FFF176", "#A5D6A7", "#90CAF9", "#F48FB1", "#FFCC80"])
    }

    /// The shared rect rows (Fixtures/word-highlights.json, the Android
    /// twin's byte for byte): each case's spans over its lines, the edge
    /// before letter o at x0 + (o − start) × advance — a pad of 0.08 em at
    /// each side, the line's full height, corners of 0.15 em.
    func testTheMarksOnALineAreTheSameRectsOnBothPhones() throws {
        let fixture = try SharedFixture.object("word-highlights")
        let em = try XCTUnwrap(fixture["fontSize"] as? Double)
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        XCTAssertEqual(cases.count, 4)
        for item in cases {
            let spans = try JSONDecoder().decode([TextSpan].self, from: SharedFixture.encoded(try XCTUnwrap(item["spans"])))
            let lines = try XCTUnwrap(item["lines"] as? [[String: Double]])
            let rects = lines.flatMap { line -> [Spans.HighlightRect] in
                let start = Int(line["start"] ?? 0), x0 = line["x0"] ?? 0, advance = line["advance"] ?? 0
                return Spans.highlightRects(spans, start: start, end: Int(line["end"] ?? 0), top: line["top"] ?? 0,
                                            bottom: line["bottom"] ?? 0, em: em) { x0 + Double($0 - start) * advance }
            }
            let want = try XCTUnwrap(item["rects"] as? [[Any]])
            XCTAssertEqual(rects.count, want.count, "\(item)")
            for (got, row) in zip(rects, want) {
                let n = try row.prefix(5).map { try XCTUnwrap($0 as? Double) }
                XCTAssertEqual(got.x, n[0], accuracy: 1e-9)
                XCTAssertEqual(got.y, n[1], accuracy: 1e-9)
                XCTAssertEqual(got.w, n[2], accuracy: 1e-9)
                XCTAssertEqual(got.h, n[3], accuracy: 1e-9)
                XCTAssertEqual(got.radius, n[4], accuracy: 1e-9)
                XCTAssertEqual(got.color, row[5] as? String)
            }
        }
    }

    func testTheClipboardCarriesTheMarker() throws {
        var el = Element.text("Big sale today")
        el.setSpans([TextSpan(start: 4, end: 8, highlight: "#FFCC80")])
        let clip = RichClipboard.copy(el, start: 4, end: 14)
        let back = try XCTUnwrap(RichClipboard.decode(RichClipboard.json(clip)))
        XCTAssertEqual(back.spans, [TextSpan(start: 0, end: 4, highlight: "#FFCC80")])
    }

    func testPowerPointWritesAndReadsTheMarkerOnTheRun() {
        var el = Element.text("Big sale")
        el.setSpans([TextSpan(start: 4, end: 8, highlight: "#FFF176")])
        let runs = PptxExporter.paragraphs(of: el)
        XCTAssertEqual(runs.first?.map(\.highlight), [nil, "#FFF176"])
    }

    func testTheContrastAuditChecksWordsAgainstTheirMarker() {
        var el = Element.text("Pale words", fontSize: 16)
        el.color = "#ffffff"
        el.setSpans([TextSpan(start: 0, end: 4, highlight: "#FFF176")])
        var design = Design(title: "c", width: 800, height: 600)
        design.pages[0] = Page(background: .color("#000000"), elements: [el])
        let findings = ContrastAudit.audit(design)
        XCTAssertEqual(findings.map(\.text), ["Pale"], "white on a yellow marker falls short")
        XCTAssertEqual(findings.first?.backdrop, "#FFF176")
        design.pages[0].elements[0].setSpans([])
        XCTAssertTrue(ContrastAudit.audit(design).isEmpty, "white on black passes")
    }
}
