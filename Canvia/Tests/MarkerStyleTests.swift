// List markers in the look of their item's first letter, over the shared
// Fixtures/list-markers.json the Android twin's TextListsTest reads.

import XCTest
@testable import Canvia

final class MarkerStyleTests: XCTestCase {

    private func fixture() throws -> (el: Element, markers: [Any]) {
        let fixture = try SharedFixture.object("list-markers")
        let el = try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(XCTUnwrap(fixture["element"])))
        return (el, try XCTUnwrap(fixture["markers"] as? [Any]))
    }

    /// Shared: a red, 1.5× word at the start of item 2 gives item 2 a red,
    /// 1.5× marker, and the others keep the box's own.
    func testAMarkerTakesTheLookOfItsItemsFirstLetter() throws {
        let (el, markers) = try fixture()
        for (line, expected) in markers.enumerated() {
            let look = TextLists.markerStyle(el, line)
            guard let expected = expected as? [String: Any] else {
                XCTAssertNil(look, "line \(line)")
                continue
            }
            XCTAssertEqual(look?.color, expected["color"] as? String, "line \(line)")
            XCTAssertEqual(look?.scale, expected["scale"] as? Double, "line \(line)")
            XCTAssertNil(look?.link)
            XCTAssertNil(look?.highlight)
        }
    }

    /// Drawn: the marker of item 2 in red at 1.5×, the others in the box's
    /// own colour and size; the hang under item 2 at the marker's size.
    func testTheMarkerIsDrawnInItsLook() throws {
        let (el, _) = try fixture()
        let drawn = FontLibrary.attributedString(for: el)
        let ns = drawn.string as NSString
        let second = ns.range(of: "•  ", options: [], range: NSRange(location: 1, length: ns.length - 1)).location
        XCTAssertNotEqual(second, NSNotFound)
        XCTAssertEqual(drawn.attribute(Spans.colourKey, at: second, effectiveRange: nil) as? String, "#ff0000")
        XCTAssertNil(drawn.attribute(Spans.colourKey, at: 0, effectiveRange: nil))
        let big = (drawn.attribute(.font, at: second, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        let plain = (drawn.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.pointSize ?? 0
        XCTAssertEqual(Double(big), Double(plain) * 1.5, accuracy: 0.01)
        let hang = (drawn.attribute(.paragraphStyle, at: second, effectiveRange: nil) as? NSParagraphStyle)?.headIndent ?? 0
        XCTAssertEqual(Double(hang), 40 * FontLibrary.markerEm * 1.5, accuracy: 0.01)
    }

    /// PowerPoint: buClr and buSzPct on item 2's paragraph only.
    func testPowerPointWritesTheMarkersLook() throws {
        let (el, _) = try fixture()
        let props = PptxExporter.paragraphProperties(el, em: 40, design: nil)
        XCTAssertFalse(props[0].contains("buClr"))
        XCTAssertTrue(props[1].contains("<a:buClr><a:srgbClr val=\"FF0000\"/></a:buClr><a:buSzPct val=\"150000\"/>"), props[1])
        XCTAssertFalse(props[2].contains("buClr"))
    }
}
