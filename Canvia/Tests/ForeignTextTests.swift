// Styled words pasted from other apps: HTML read by the tag walker and RTF
// by the system, both through one builder, into the clip the typing field
// pastes. The HTML rows are the Android twin's ForeignTextTest rows: the
// same snippet gives the same text, spans and paragraphs on both phones.

import XCTest
import UIKit
@testable import Canvia

final class ForeignTextTests: XCTestCase {

    func testBoldItalicUnderlineAndStrikeBecomeMarkers() {
        let clip = ForeignText.fromHtml("<p>Big <b>sale</b> <i>today</i></p>")
        XCTAssertEqual(clip.plain, "Big sale today")
        XCTAssertEqual(clip.text, "Big **sale** *today*")
        XCTAssertEqual(clip.spans, [])
        XCTAssertEqual(clip.paragraphs, [], "no list, no paragraphs")
        XCTAssertEqual(ForeignText.fromHtml("<u>under</u> <s>gone</s>").text, "__under__ ~~gone~~")
        XCTAssertEqual(ForeignText.fromHtml("<strong>A</strong><em>b</em><del>c</del>").plain, "Abc")
    }

    func testAnInlineWeightOverridesTheTagAsDocsWritesIt() {
        let html = #"<b style="font-weight:normal;" id="docs-internal-guid-1"><span style="font-weight:700;">Bold</span><span style="font-weight:400;"> plain</span></b>"#
        let clip = ForeignText.fromHtml(html)
        XCTAssertEqual(clip.text, "**Bold** plain")
    }

    func testLinksColoursAndSizesBecomeSpans() {
        let html = #"<a href="https://example.com">Shop</a> <span style="color:#FF0000;font-size:24px">now</span> <span style="font-size:12pt;color:rgb(0, 128, 255)">ok</span>"#
        let clip = ForeignText.fromHtml(html)
        XCTAssertEqual(clip.plain, "Shop now ok")
        XCTAssertEqual(clip.spans, [TextSpan(start: 0, end: 4, link: "https://example.com"),
                                    TextSpan(start: 5, end: 8, color: "#ff0000", scale: 1.5),
                                    TextSpan(start: 9, end: 11, color: "#0080ff")],
                       "12pt is 16px, the box's own size")
    }

    func testListsBecomeParagraphsAtTheirDepth() {
        let html = "<ul><li>Milk</li><li>Eggs<ul><li>Brown</li></ul></li></ul><ol><li>One</li></ol>"
        let clip = ForeignText.fromHtml(html)
        XCTAssertEqual(clip.plain, "Milk\nEggs\nBrown\nOne")
        XCTAssertEqual(clip.paragraphs, [TextParagraph(list: "bullet"), TextParagraph(list: "bullet"),
                                         TextParagraph(list: "bullet", level: 1), TextParagraph(list: "number")])
        // Docs puts each item's words in a paragraph of their own.
        let docs = ForeignText.fromHtml("<ul><li><p><span>A</span></p></li><li><p>B</p></li></ul>")
        XCTAssertEqual(docs.plain, "A\nB")
        XCTAssertEqual(docs.paragraphs, [TextParagraph(list: "bullet"), TextParagraph(list: "bullet")])
    }

    func testBreaksBlocksSpacesEntitiesAndWhatIsDropped() {
        XCTAssertEqual(ForeignText.fromHtml("<div>One<br>Two</div><div>Three</div>").plain, "One\nTwo\nThree")
        let html = "<style>p{color:red}</style><p>Fish &amp; chips&nbsp;&lt;3 &#8364;5</p><script>alert(1)</script>"
        XCTAssertEqual(ForeignText.fromHtml(html).plain, "Fish & chips <3 €5")
        XCTAssertEqual(ForeignText.fromHtml("<p>  lots \n\t of   space  </p><!-- note --><p>x</p>").plain,
                       "lots of space\nx")
        XCTAssertEqual(ForeignText.fromHtml("2 * 3 &amp; a_b").text, RichText.escapeLiteral("2 * 3 & a_b"),
                       "stars and underscores that came in are stars and underscores")
    }

    func testAFontIsKeptOnlyWhenTheLibraryHasIt() {
        let known = FontLibrary.all[0]
        let html = "<span style=\"font-family: '\(known.name)', serif\">A</span><span style=\"font-family: Nowhere Sans\">B</span>"
        XCTAssertEqual(ForeignText.fromHtml(html).spans, [TextSpan(start: 0, end: 1, font: known.id)])
    }

    func testRtfGoesThroughTheSameBuilder() throws {
        let rtf = #"{\rtf1\ansi{\fonttbl\f0 Helvetica;}{\colortbl;\red255\green0\blue0;}\f0\fs24 Plain \b Bold\b0  \cf1 Red\cf0\par Next}"#
        let clip = try XCTUnwrap(ForeignText.fromRtf(text: rtf))
        XCTAssertEqual(clip.plain, "Plain Bold Red\nNext")
        XCTAssertTrue(clip.text.contains("**Bold**"), clip.text)
        let red = clip.spans.first { $0.start <= 11 && $0.end >= 14 && $0.color != nil }
        let ink = UIColor(hex: try XCTUnwrap(red?.color, "\(clip.spans)")).srgbComponents
        XCTAssertGreaterThan(ink.r, 0.9)
        XCTAssertLessThan(ink.g, 0.1)
    }

    func testAPasteOntoThePageIsATextBoxInItsStyles() {
        let clip = ForeignText.fromHtml(#"<p><b>Hello</b> <span style="color:#00ff00">world</span></p>"#)
        let el = ForeignText.element(clip, fontSize: 40, maxWidth: 600)
        XCTAssertEqual(el.text, "**Hello** world")
        XCTAssertEqual(el.liveSpans, [TextSpan(start: 6, end: 11, color: "#00ff00")])
        XCTAssertLessThanOrEqual(el.w, 600)
        XCTAssertGreaterThan(el.h, 0)
    }
}
