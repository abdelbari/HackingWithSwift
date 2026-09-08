// Inline styles: **bold**, *italic*, __underline__, ~~strike~~ inside one text.

import XCTest
import UIKit
@testable import Canvia

final class RichTextTests: XCTestCase {

    private func styles(_ text: String) -> [(String, RichText.Style)] {
        let p = RichText.parse(text)
        let ns = p.plain as NSString
        return p.runs.map { (ns.substring(with: $0.range), $0.style) }
    }

    func testMarkersAreStrippedAndStyledWords() {
        let p = RichText.parse("Big **Summer** sale, *today* only")
        XCTAssertEqual(p.plain, "Big Summer sale, today only")
        let s = styles("Big **Summer** sale, *today* only")
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].0, "Summer"); XCTAssertTrue(s[0].1.bold); XCTAssertFalse(s[0].1.italic)
        XCTAssertEqual(s[1].0, "today"); XCTAssertTrue(s[1].1.italic)
    }

    func testUnderlineStrikeAndUnderscoreItalic() {
        let s = styles("__under__ and ~~gone~~ and _soft_")
        XCTAssertEqual(s.map(\.0), ["under", "gone", "soft"])
        XCTAssertTrue(s[0].1.underline)
        XCTAssertTrue(s[1].1.strike)
        XCTAssertTrue(s[2].1.italic)
        XCTAssertEqual(RichText.strip("__under__ and ~~gone~~ and _soft_"), "under and gone and soft")
    }

    func testStylesNest() {
        let s = styles("**bold and *both* here**")
        XCTAssertEqual(s.map(\.0), ["bold and ", "both", " here"])
        XCTAssertEqual(s[1].1, RichText.Style(bold: true, italic: true))
        XCTAssertEqual(s[0].1, RichText.Style(bold: true))
    }

    func testLoneAndInWordMarkersStayLiteral() {
        XCTAssertEqual(RichText.strip("2*3 = 6"), "2*3 = 6")
        XCTAssertEqual(RichText.strip("snake_case_name"), "snake_case_name")
        XCTAssertEqual(RichText.strip("5 * 3 * 2"), "5 * 3 * 2")
        XCTAssertEqual(RichText.strip("**unclosed"), "**unclosed")
        XCTAssertEqual(RichText.strip("no markup"), "no markup")
        XCTAssertEqual(RichText.strip("~ one tilde ~"), "~ one tilde ~")
        XCTAssertTrue(RichText.parse("plain").runs.isEmpty)
    }

    func testRangesAreUTF16Offsets() {
        let p = RichText.parse("😀 **wow** ✨")
        XCTAssertEqual(p.plain, "😀 wow ✨")
        XCTAssertEqual(p.runs.count, 1)
        XCTAssertEqual((p.plain as NSString).substring(with: p.runs[0].range), "wow")
    }

    @MainActor
    func testDisplayTextIsPlainAndTheAttributedStringCarriesTheRuns() {
        let el = Element.text("Try **bold** and *italic*", fontSize: 30)
        XCTAssertEqual(FontLibrary.displayText(for: el), "Try bold and italic")
        let attributed = FontLibrary.attributedString(for: el)
        XCTAssertEqual(attributed.string, "Try bold and italic")
        let baseFont = attributed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let boldFont = attributed.attribute(.font, at: 4, effectiveRange: nil) as? UIFont
        let italicFont = attributed.attribute(.font, at: 13, effectiveRange: nil) as? UIFont
        XCTAssertNotNil(baseFont)
        XCTAssertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true, boldFont?.fontName ?? "nil")
        XCTAssertTrue(italicFont?.fontDescriptor.symbolicTraits.contains(.traitItalic) == true, italicFont?.fontName ?? "nil")
        XCTAssertFalse(baseFont?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
        // A plain element takes the fast path and is byte-identical to before.
        let plain = Element.text("Hello", fontSize: 30)
        XCTAssertEqual(FontLibrary.attributedString(for: plain).string, "Hello")
    }

    @MainActor
    func testMeasurementIgnoresTheMarkers() {
        let marked = Element.text("**Summer** sale", fontSize: 30, w: 400)
        let plain = Element.text("Summer sale", fontSize: 30, w: 400)
        XCTAssertEqual(FontLibrary.lineWidth(for: marked), FontLibrary.lineWidth(for: plain))
        XCTAssertEqual(FontLibrary.measuredHeight(for: marked), FontLibrary.measuredHeight(for: plain))
    }

    @MainActor
    func testTheOutlineOfABoldWordIsWiderThanThePlainOne() throws {
        var bold = Element.text("**WIDE** word", fontSize: 40, w: 600); bold.align = "left"
        var plain = Element.text("WIDE word", fontSize: 40, w: 600); plain.align = "left"
        let b = try XCTUnwrap(TextOutliner.path(for: bold)).boundingBoxOfPath
        let p = try XCTUnwrap(TextOutliner.path(for: plain)).boundingBoxOfPath
        XCTAssertGreaterThan(b.width, p.width)
    }
}
