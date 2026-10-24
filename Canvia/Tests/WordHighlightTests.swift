// Highlight colour on chosen words: a marker behind them, kept on each span
// as "highlight" ("#rrggbb" or "#rrggbbaa"), its rects on a drawn line, and
// carried through the clipboard, the PowerPoint writer and reader, and the
// contrast audit. The span JSON and rect rows are shared with the Android
// twin's WordHighlightTest.

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

    /// The shared rect rows: a line holding letters 0..<10, 0 to 50 down,
    /// each letter 10 wide, type 40 high — a pad of 3.2 each side and
    /// corners of 6.
    func testTheMarksOnALineAreTheSameRectsOnBothPhones() {
        let spans = [TextSpan(start: 2, end: 5, highlight: "#FFF176"),
                     TextSpan(start: 5, end: 7, color: "#ff0000"),
                     TextSpan(start: 8, end: 14, highlight: "#90CAF9")]
        let rects = Spans.highlightRects(spans, start: 0, end: 10, top: 0, bottom: 50, em: 40) { Double($0) * 10 }
        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].x, 16.8, accuracy: 1e-9)
        XCTAssertEqual(rects[0].w, 36.4, accuracy: 1e-9)
        XCTAssertEqual(rects[0].y, 0)
        XCTAssertEqual(rects[0].h, 50)
        XCTAssertEqual(rects[0].radius, 6, accuracy: 1e-9)
        XCTAssertEqual(rects[0].color, "#FFF176")
        XCTAssertEqual(rects[1].x, 76.8, accuracy: 1e-9, "cut at the line's end")
        XCTAssertEqual(rects[1].w, 26.4, accuracy: 1e-9)
        XCTAssertEqual(rects[1].color, "#90CAF9")
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
