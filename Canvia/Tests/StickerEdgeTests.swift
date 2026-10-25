// A sticker's or a graphic's outline or glow — the photo's edge reused
// (PhotoEffects.takesDrawnEdge) — and the shared fixture sticker-edge.json
// the Android twin's StickerEdgeTest reads too.

import XCTest
@testable import Canvia

final class StickerEdgeTests: XCTestCase {

    private func fixture() throws -> [String: Any] {
        try SharedFixture.object("sticker-edge")
    }

    private func parts(_ id: String, edge: PhotoEdge) throws -> [Element] {
        let graphic = try XCTUnwrap(GraphicsLibrary.graphic(id))
        return GraphicsLibrary.elements(graphic, pageWidth: 1080, pageHeight: 1080).map { el in
            var edged = el
            edged.edge = edge
            return edged
        }
    }

    func testTheSharedFixturesStickerKeepsItsOutlineAndShadowBothWays() throws {
        let element = try XCTUnwrap(try fixture()["element"] as? [String: Any])
        let sticker = try JSONDecoder().decode(Element.self, from: SharedFixture.encoded(element))
        XCTAssertEqual(sticker.edge, PhotoEdge(kind: "outline", color: "#ffffff", width: 30))
        XCTAssertEqual(sticker.shadow?.opacity, 0.35)
        XCTAssertTrue(PhotoEffects.hasDrawnEdge(sticker))
        let reach = try XCTUnwrap(try fixture()["reach"] as? NSNumber).doubleValue
        XCTAssertEqual(PhotoEffects.reach(sticker.edge), reach)
        let back = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(sticker)) as? [String: Any])
        let edge = try XCTUnwrap(back["edge"] as? [String: Any])
        XCTAssertEqual(edge["kind"] as? String, "outline")
        XCTAssertEqual(edge["color"] as? String, "#ffffff")
        XCTAssertEqual((edge["width"] as? NSNumber)?.doubleValue, 30)
        XCTAssertEqual(back["glyph"] as? String, "🎉")
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(sticker)), sticker)
        // Its picture in an SVG reaches out to the outline.
        XCTAssertEqual(SVGExporter.overflow(sticker), 6)
    }

    func testAStickerAndAPackGraphicsShapesTakeADrawnEdgeAPhotoAndAPlainShapeDoNot() throws {
        let graphic = try parts("sticker-heart-01", edge: PhotoEdge())
        XCTAssertTrue(graphic.allSatisfy(PhotoEffects.takesDrawnEdge))
        XCTAssertTrue(PhotoEffects.takesDrawnEdge(.sticker("🎉")))
        XCTAssertFalse(PhotoEffects.takesDrawnEdge(.shape("rect")))
        XCTAssertFalse(PhotoEffects.takesDrawnEdge(.image("media:1")))
        // No width, no edge.
        var thin = Element.sticker("🎉")
        thin.edge = PhotoEdge(width: 0)
        XCTAssertFalse(PhotoEffects.hasDrawnEdge(thin))
    }

    func testAGroupsShapeEdgesGoDownTogetherBeforeItsFirstElement() throws {
        let face = try parts("sticker-face-01", edge: PhotoEdge(kind: "outline", color: "#ff0000", width: 20))
        var loose = Element.sticker("🎉")
        loose.id = "loose"
        loose.edge = PhotoEdge()
        let drawn = [loose] + face
        let edges = PhotoEffects.groupEdges(drawn)
        XCTAssertEqual(Set(edges.keys), [face[0].id])
        XCTAssertEqual(edges[face[0].id]?.map(\.id), face.map(\.id))
        // Each then draws without its own; a sticker keeps its own.
        XCTAssertTrue(face.map(PhotoEffects.afterGroupEdge).allSatisfy { $0.edge == nil })
        XCTAssertEqual(PhotoEffects.afterGroupEdge(loose), loose)
        var grouped = loose
        grouped.group = "g"
        XCTAssertEqual(PhotoEffects.afterGroupEdge(grouped), grouped)
        // As drawn: the edges alone, no shadow, before the group's first
        // part, then the parts without theirs.
        let laid = PhotoEffects.withGroupEdges(drawn)
        XCTAssertEqual(laid.count, drawn.count + face.count)
        XCTAssertEqual(laid[0], loose)
        XCTAssertTrue(laid[1...face.count].allSatisfy { $0.edgeOnly && $0.shadow == nil && $0.edge != nil })
        XCTAssertEqual(laid[1...face.count].map(\.id), face.map { $0.id + "#edge" })
        XCTAssertTrue(laid.suffix(face.count).allSatisfy { !$0.edgeOnly && $0.edge == nil })
        // Never in the file.
        let written = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(laid[1])) as? [String: Any])
        XCTAssertNil(written["edgeOnly"])
    }

    @MainActor
    func testSVGStrokesAGraphicsOutlineAsAnOutsetPathOnceForTheWholeGroup() throws {
        let arrow = try parts("sticker-arrow-01", edge: PhotoEdge(kind: "outline", color: "#ff0000", width: 20))
        var d = Design(title: "Stickers", width: 1080, height: 1080)
        d.pages = [Page(background: .color("#ffffff"), elements: arrow)]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        // 20 wide is 4 thick, stroked 8 across, in the outline's colour.
        let pattern = try NSRegularExpression(pattern: ##"fill="#ff0000" stroke="#ff0000" stroke-width="8""##)
        XCTAssertEqual(pattern.numberOfMatches(in: svg, range: NSRange(svg.startIndex..., in: svg)), arrow.count)
        // A glow is blurred by its def.
        var glow = arrow[0]
        glow.group = nil
        glow.edge = PhotoEdge(kind: "glow", color: "#ffe066", width: 20)
        d.pages = [Page(background: .color("#ffffff"), elements: [glow])]
        let glowing = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(glowing.contains("<filter id=\"edge0\""), glowing)
        XCTAssertTrue(glowing.contains("filter=\"url(#edge0)\""), glowing)
        XCTAssertNil(PhotoEffects.groupEdges([glow])[glow.id])
    }

    func testPowerPointLaysAGraphicsEdgeAsAPictureUnderItsShapes() throws {
        let heart = try parts("sticker-heart-01", edge: PhotoEdge())
        var d = Design(title: "Stickers", width: 1080, height: 1080)
        d.pages = [Page(background: .color("#ffffff"), elements: heart)]
        let drawn = PptxExporter.drawnElements(design: d, page: d.pages[0])
        XCTAssertEqual(drawn.count, heart.count * 2)
        XCTAssertTrue(drawn.prefix(heart.count).allSatisfy { PptxExporter.form(of: $0) == .picture })
        XCTAssertTrue(drawn.suffix(heart.count).allSatisfy { PptxExporter.form(of: $0) != .picture || $0.edge == nil })
    }
}
