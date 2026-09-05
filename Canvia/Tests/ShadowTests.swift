// Element shadows.
//
// A shadow is visible in exactly one way: pixels beside the element that were
// the background's colour are darker (or, for a glow, lighter) than they
// were. That is what gets asserted — rendered, not inferred from the model.

import XCTest
import SwiftUI
import UIKit
@testable import Canvia

final class ShadowTests: XCTestCase {

    private func design(_ shadow: Shadow?) -> Design {
        var d = Design(title: "shadow", width: 200, height: 200)
        var box = Element.shape("rect", w: 60, h: 60)
        box.x = 70; box.y = 70
        box.fill = .solid("#2244aa")
        box.shadow = shadow
        d.pages = [Page(background: .color("#ffffff"), elements: [box])]
        return d
    }

    @MainActor
    private func render(_ d: Design) throws -> CGImage {
        let renderer = ImageRenderer(content: PageRenderView(design: d, page: d.pages[0]))
        renderer.scale = 1
        renderer.isOpaque = true
        return try XCTUnwrap(renderer.cgImage)
    }

    private func luma(_ image: CGImage, x: Int, y: Int) throws -> Double {
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                       width: image.width, height: image.height))
        }
        return 0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])
    }

    // MARK: rendering

    /// A downward shadow darkens the page just below the element and leaves
    /// the page just above it alone.
    @MainActor
    func testADownwardShadowDarkensBelowNotAbove() throws {
        let plain = try render(design(nil))
        let shadowed = try render(design(Shadow(color: "#000000", opacity: 0.6, blur: 6,
                                                offsetX: 0, offsetY: 12)))
        let belowBefore = try luma(plain, x: 100, y: 136)
        let belowAfter = try luma(shadowed, x: 100, y: 136)
        XCTAssertLessThan(belowAfter, belowBefore - 15, "nothing darkened below the element")
        let aboveBefore = try luma(plain, x: 100, y: 60)
        let aboveAfter = try luma(shadowed, x: 100, y: 60)
        XCTAssertEqual(aboveAfter, aboveBefore, accuracy: 6, "the shadow reached above the element")
    }

    /// A glow is a shadow with no offset: it surrounds the element evenly.
    @MainActor
    func testAGlowSurroundsTheElementEvenly() throws {
        let plain = try render(design(nil))
        let glowing = try render(design(Shadow(color: "#000000", opacity: 0.7, blur: 10,
                                               offsetX: 0, offsetY: 0)))
        let left = try luma(plain, x: 64, y: 100) - luma(glowing, x: 64, y: 100)
        let right = try luma(plain, x: 136, y: 100) - luma(glowing, x: 136, y: 100)
        let above = try luma(plain, x: 100, y: 64) - luma(glowing, x: 100, y: 64)
        XCTAssertGreaterThan(left, 8)
        XCTAssertEqual(left, right, accuracy: 10, "the glow is lopsided")
        XCTAssertEqual(left, above, accuracy: 10)
    }

    @MainActor
    func testNoShadowChangesNothing() throws {
        let plain = try render(design(nil))
        XCTAssertEqual(try luma(plain, x: 100, y: 136), 255, accuracy: 1)
    }

    /// The shadow turns with the element. Rotated a quarter turn, a downward
    /// shadow falls to the side — applied after rotation it would still fall
    /// straight down, which is not how light works.
    @MainActor
    func testTheShadowRotatesWithTheElement() throws {
        var d = design(Shadow(color: "#000000", opacity: 0.7, blur: 4, offsetX: 0, offsetY: 16))
        d.pages[0].elements[0].rotation = 90
        let plain = try render(design(nil))
        let rotated = try render(d)
        // With a 90° rotation the shadow's downward offset points along +x or
        // -x; whichever side, one of them darkens and directly below does not.
        let below = try luma(plain, x: 100, y: 140) - luma(rotated, x: 100, y: 140)
        let left = try luma(plain, x: 60, y: 100) - luma(rotated, x: 60, y: 100)
        let right = try luma(plain, x: 140, y: 100) - luma(rotated, x: 140, y: 100)
        XCTAssertGreaterThan(max(left, right), 12, "the shadow did not move to a side")
        XCTAssertLessThan(below, 6, "the shadow still falls straight down")
    }

    // MARK: export

    @MainActor
    func testShadowsReachTheSVGAsAFilter() {
        let d = design(Shadow(color: "#112233", opacity: 0.4, blur: 8, offsetX: 3, offsetY: 5))
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<filter id=\"shadow0\""))
        XCTAssertTrue(svg.contains("<feDropShadow"))
        XCTAssertTrue(svg.contains("flood-color=\"#112233\""))
        XCTAssertTrue(svg.contains("filter=\"url(#shadow0)\""))
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())
    }

    @MainActor
    func testAnUnshadowedElementGetsNoFilter() {
        let svg = SVGExporter.svg(design: design(nil), page: design(nil).pages[0])
        XCTAssertFalse(svg.contains("<filter"))
    }

    // MARK: model

    func testShadowRoundTripsAndOlderDocumentsHaveNone() throws {
        var el = Element.shape("rect", w: 10, h: 10)
        el.shadow = Shadow(color: "#abcdef", opacity: 0.5, blur: 3, offsetX: 1, offsetY: 2)
        let restored = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(restored, el)
        let old = #"{"id":"el_1","type":"shape","shapeId":"rect","w":10,"h":10}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(old.utf8)).shadow)
    }

    /// A shadow written by a build with more fields still decodes here with
    /// the defaults filled in, rather than being dropped whole.
    func testAPartialShadowDecodesWithDefaults() throws {
        // Double-hash delimiters: the "#ff0000" inside would otherwise end a
        // single-hash raw string at its "# sequence.
        let json = ##"{"id":"el_1","type":"shape","shapeId":"rect","w":10,"h":10,"shadow":{"color":"#ff0000"}}"##
        let el = try JSONDecoder().decode(Element.self, from: Data(json.utf8))
        XCTAssertEqual(el.shadow?.color, "#ff0000")
        XCTAssertEqual(el.shadow?.blur, 12)
    }

    func testStyleCopyCarriesTheShadow() {
        var source = Element.shape("rect", w: 10, h: 10)
        source.shadow = Shadow.presets[0].shadow
        var target = Element.text("Hi", fontSize: 20, w: 100)
        DesignStore.apply(DesignStore.style(of: source), to: &target)
        XCTAssertEqual(target.shadow, Shadow.presets[0].shadow, "shadow is universal and should cross kinds")
    }
}
