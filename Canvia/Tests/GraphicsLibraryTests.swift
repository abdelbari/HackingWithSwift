// The illustrated graphics pack, as the Android twin's GraphicsLibraryTest
// has it: the shared file byte for byte, its thirteen categories, each
// graphic's fills, each going on a page as an SVG graphic does — grouped,
// naming it — and found by Add's search and kept in Recently used.

import XCTest
import CryptoKit
@testable import Canvia

final class GraphicsLibraryTests: XCTestCase {

    func testThePackIsTheSharedFileByteForByte() throws {
        // The Android twin's GraphicsLibraryTest hashes its copy to the same.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Graphics", withExtension: "json"))
        let hash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hash, "b3cb188dcabd476ca77dffac73b877ff2c74e8f4dc74b142818b5e4373934416")
    }

    func testAboutTwoHundredAndSixtyGraphicsInThirteenCategoriesEachIdOnce() {
        XCTAssertEqual(GraphicsLibrary.categories, [
            "Doodle arrows", "Underlines & circles", "Sparkles", "Starbursts & badges", "Ribbons", "Blobs",
            "Confetti", "Dividers", "Speech bubbles", "Hand-drawn frames", "Scribbles", "Patterns", "Animated",
        ])
        XCTAssertEqual(GraphicsLibrary.graphics.count, 262)
        XCTAssertEqual(Set(GraphicsLibrary.graphics.map(\.id)).count, GraphicsLibrary.graphics.count)
        XCTAssertEqual(Set(GraphicsLibrary.graphics.map(\.category)), Set(GraphicsLibrary.categories))
        for c in GraphicsLibrary.categories where c != GraphicsLibrary.animated {
            XCTAssertTrue((16...17).contains(GraphicsLibrary.inCategory(c).count), c)
        }
        // The moving ones are a category of their own, and only they move.
        XCTAssertEqual(GraphicsLibrary.inCategory(GraphicsLibrary.animated).count, 60)
        XCTAssertTrue(GraphicsLibrary.graphics.allSatisfy { ($0.motion != nil) == ($0.category == GraphicsLibrary.animated) })
        XCTAssertEqual(GraphicsLibrary.graphic("arrow-01")?.name, "Curved arrow")
        XCTAssertNil(GraphicsLibrary.graphic("no-such-graphic"))
    }

    func testEachListsItsFillsInTheOrderFirstUsedAtMostFourLowerCase() throws {
        // A drawn line is stroked, with no fill; everything else is filled.
        let fill = try NSRegularExpression(pattern: #"(?:fill|stroke)="(#[0-9a-f]{6})""#)
        for g in GraphicsLibrary.graphics {
            let text = g.svg as NSString
            var fills: [String] = []
            for match in fill.matches(in: g.svg, range: NSRange(location: 0, length: text.length)) {
                let hex = text.substring(with: match.range(at: 1))
                if !fills.contains(hex) { fills.append(hex) }
            }
            XCTAssertEqual(fills, g.colours, g.id)
            XCTAssertTrue((1...4).contains(g.colours.count), g.id)
            XCTAssertTrue(!g.tags.isEmpty && g.tags.allSatisfy { $0 == $0.lowercased() }, g.id)
            XCTAssertFalse(g.svg.contains("<text"), g.id)
            XCTAssertEqual(g.motion == "draw", g.svg.contains("stroke"), g.id)
        }
    }

    func testEveryGraphicGoesOnAPageAsAnSVGGraphicItsShapesGroupedAndNamingIt() throws {
        for g in GraphicsLibrary.graphics {
            let els = GraphicsLibrary.elements(g, pageWidth: 1080, pageHeight: 1080)
            XCTAssertFalse(els.isEmpty, g.id)
            XCTAssertTrue(els.allSatisfy { $0.type == .shape && GraphicsLibrary.graphic(of: $0) == g }, g.id)
            XCTAssertEqual(Set(ColourSwap.colours(els)), Set(g.colours), g.id)
            if els.count > 1 {
                XCTAssertTrue(els.allSatisfy { $0.group != nil && $0.group == els[0].group }, g.id)
            }
        }
        let one = GraphicsLibrary.elements(try XCTUnwrap(GraphicsLibrary.graphic("sparkle-03")),
                                           pageWidth: 1080, pageHeight: 1080)
        XCTAssertEqual(one.count, 3)
        // Fitted to 0.4 of the page's shorter side, centred, as any SVG is.
        let maxX = one.map { $0.x + $0.w }.max() ?? 0
        let minX = one.map(\.x).min() ?? 0
        XCTAssertLessThanOrEqual(maxX - minX, 432.01)
        // Each part is named for the graphic, in Layers and aloud.
        let arrow = GraphicsLibrary.elements(try XCTUnwrap(GraphicsLibrary.graphic("arrow-01")),
                                             pageWidth: 1080, pageHeight: 1080)
        XCTAssertEqual(ElementNames.name(of: try XCTUnwrap(arrow.first)), "Curved arrow graphic")
        // Its id goes into the file with each part, and comes back.
        let written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(one[0])) as? [String: Any]
        XCTAssertEqual(written?["graphicId"] as? String, "sparkle-03")
        let read = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(one[0]))
        XCTAssertEqual(read.graphicId, "sparkle-03")
    }

    func testASearchReadsNamesIdsAndTagsWithinACategory() {
        XCTAssertEqual(GraphicsLibrary.search("confetti").count, 16)
        XCTAssertFalse(GraphicsLibrary.search("hand drawn").isEmpty)
        XCTAssertEqual(GraphicsLibrary.search("thought").map(\.id), ["bubble-03", "bubble-08", "bubble-13"])
        XCTAssertEqual(GraphicsLibrary.search("thought", in: "Sparkles"), [])
        XCTAssertEqual(GraphicsLibrary.search(" ", in: "Blobs").count, 17)
    }

    func testAddsSearchFindsGraphicsByTheirTagsAndRecentlyUsedKeepsThem() throws {
        let hits = ElementSearch.results("confetti")
        XCTAssertEqual(hits.first?.kind, .sticker)
        XCTAssertEqual(hits.filter { $0.kind == .graphic }.prefix(3).map(\.id), ["confetti-01", "confetti-02", "confetti-03"])
        XCTAssertTrue(ElementSearch.sections(ElementSearch.results("ribbon")).contains { $0.section == .graphics })
        let hit = try XCTUnwrap(ElementSearch.hit(.graphic, "blob-02"))
        let kept = ElementSearch.encode(ElementSearch.remembered([], hit))
        XCTAssertEqual(kept, #"[{"kind":"graphic","id":"blob-02"}]"#)
        XCTAssertEqual(ElementSearch.decode(kept), [hit])
    }
}
