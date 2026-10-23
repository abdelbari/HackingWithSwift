// Shadow styles beyond the offset copy: the `style` key and its settings
// as the file carries them, the silhouettes ShadowShapes gives each style
// (the same rows as the Android twin's ShadowShapesTest), the projective
// transform the angle style leans on, what the renderer and the SVG draw
// for them, and the four new cards.

import XCTest
import SwiftUI
import UIKit
@testable import Canvia

final class ShadowStylesTests: XCTestCase {

    private func json(_ shadow: Shadow) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shadow)) as? [String: Any])
    }

    // MARK: the file

    func testAStyleAndItsSettingsRoundTripAndADropShadowWritesNone() throws {
        let plain = try json(Shadow())
        XCTAssertNil(plain["style"])
        XCTAssertNil(plain["curve"])
        XCTAssertNil(plain["angle"])
        XCTAssertNil(plain["distance"])

        let angled = Shadow(color: "#000000", opacity: 0.3, blur: 8, offsetX: 0, offsetY: 0,
                            style: "angle", angle: -20, distance: 40)
        let written = try json(angled)
        XCTAssertEqual(written["style"] as? String, "angle")
        XCTAssertEqual(written["angle"] as? Double, -20)
        XCTAssertEqual(written["distance"] as? Double, 40)
        XCTAssertNil(written["curve"], "a setting not set is not written")
        XCTAssertEqual(try JSONDecoder().decode(Shadow.self, from: JSONEncoder().encode(angled)), angled)

        let curved = Shadow(style: "curved", curve: 0.8)
        XCTAssertEqual(try JSONDecoder().decode(Shadow.self, from: JSONEncoder().encode(curved)), curved)
    }

    /// A style this build does not know is kept as written and drawn as a
    /// drop shadow; "drop" itself is the key's absence.
    func testAnUnknownStyleReadsAsDropAndIsKept() throws {
        let odd = ##"{"color":"#000000","style":"glowRing","curve":"x","distance":12}"##
        let shadow = try JSONDecoder().decode(Shadow.self, from: Data(odd.utf8))
        XCTAssertEqual(shadow.style, "glowRing")
        XCTAssertEqual(ShadowShapes.style(of: shadow), "drop")
        XCTAssertFalse(ShadowShapes.isStyled(shadow))
        XCTAssertNil(ShadowShapes.path(for: shadow, w: 100, h: 50))
        XCTAssertNil(shadow.curve, "a setting that is no number is none")
        XCTAssertEqual(shadow.distance, 12)
        XCTAssertEqual(try json(shadow)["style"] as? String, "glowRing")

        let drop = try JSONDecoder().decode(Shadow.self, from: Data(#"{"style":"drop"}"#.utf8))
        XCTAssertNil(drop.style)
        XCTAssertEqual(drop, Shadow())
    }

    func testTheDialsReadTheirDefaultsUntilSet() {
        var shadow = Shadow(style: "curved")
        XCTAssertEqual(shadow.curveDial, ShadowShapes.defaultCurve)
        XCTAssertEqual(shadow.angleDial, 30)
        XCTAssertEqual(shadow.distanceDial, 40)
        shadow.curveDial = 0.2
        XCTAssertEqual(shadow.curve, 0.2)
        // Held to their tracks, and a setting that is no number is its default.
        XCTAssertEqual(ShadowShapes.angle(Shadow(style: "angle", angle: 90)), 60)
        XCTAssertEqual(ShadowShapes.curve(Shadow(style: "curved", curve: 4)), 1)
        XCTAssertEqual(ShadowShapes.distance(Shadow(style: "angle", distance: .nan)), 40)
    }

    // MARK: the silhouettes

    /// The Android twin's rows: a 100 × 50 box at half a curve bows 1.5
    /// down and draws its top corners in by 4.
    func testACurvedShadowBowsItsBottomEdgeAndDrawsItsTopCornersIn() {
        let path = ShadowShapes.curved(w: 100, h: 50, curve: 0.5)
        let box = path.boundingBoxOfPath
        XCTAssertEqual(box.minY, 0, accuracy: 1e-9)
        XCTAssertEqual(box.maxY, 51.5, accuracy: 0.01)
        XCTAssertEqual(box.minX, 0, accuracy: 1e-9)
        XCTAssertEqual(box.maxX, 100, accuracy: 1e-9)
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 0.5)), "the top corners are drawn in")
        XCTAssertTrue(path.contains(CGPoint(x: 6, y: 0.5)))
        XCTAssertTrue(path.contains(CGPoint(x: 50, y: 51)), "the middle of the bottom edge bows down")
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 50.5)), "the corners do not")
        XCTAssertEqual(ShadowShapes.reach(of: Shadow(style: "curved", curve: 0.5), w: 100, h: 50), 1.5, accuracy: 1e-9)
        // A full curve bows 6% and tapers 8%; none is the box itself.
        let full = ShadowShapes.curved(w: 200, h: 100, curve: 1).boundingBoxOfPath
        XCTAssertEqual(full.maxY, 106, accuracy: 0.01)
        XCTAssertFalse(ShadowShapes.curved(w: 200, h: 100, curve: 1).contains(CGPoint(x: 15, y: 0.5)))
        XCTAssertEqual(ShadowShapes.curved(w: 200, h: 100, curve: 0).boundingBoxOfPath, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    /// Two wedges up the sides from the lower corners, inside the box, so
    /// only their blur shows past it.
    func testAPageLiftIsTwoWedgesAtTheLowerCorners() {
        let path = ShadowShapes.pageLift(w: 100, h: 50, curve: 0.5)
        let box = path.boundingBoxOfPath
        XCTAssertEqual(box.minY, 37.5, accuracy: 1e-9)
        XCTAssertEqual(box.maxY, 50, accuracy: 1e-9)
        XCTAssertTrue(path.contains(CGPoint(x: 2, y: 48)), "at the left corner")
        XCTAssertTrue(path.contains(CGPoint(x: 98, y: 48)), "at the right corner")
        XCTAssertFalse(path.contains(CGPoint(x: 50, y: 48)), "nothing in the middle")
        XCTAssertFalse(path.contains(CGPoint(x: 2, y: 30)), "nothing above the wedge")
        XCTAssertEqual(ShadowShapes.reach(of: Shadow(style: "pageLift"), w: 100, h: 50), 0)
    }

    func testABackdropIsTheBoxMovedByItsDistance() {
        XCTAssertEqual(ShadowShapes.backdrop(w: 200, h: 100, distance: 12).boundingBoxOfPath,
                       CGRect(x: 12, y: 12, width: 200, height: 100))
        XCTAssertEqual(ShadowShapes.backdrop(w: 200, h: 100, distance: 500).boundingBoxOfPath.minX, 100)
        XCTAssertEqual(ShadowShapes.backdrop(w: 100, h: 50, distance: 16).boundingBoxOfPath, CGRect(x: 16, y: 16, width: 100, height: 50))
        XCTAssertEqual(ShadowShapes.blur(of: Shadow(blur: 20, style: "backdrop")), 0, "never blurred")
        XCTAssertEqual(ShadowShapes.blur(of: Shadow(blur: 20, style: "curved")), 20)
    }

    /// The Android twin's rows: a 100 × 50 box at 30° and distance 40
    /// keeps its base, lifts its far edge 20 up, pushed 11.547 sideways and
    /// narrowed to 80 wide.
    func testAnAngleShadowKeepsItsBaseAndLeansAwayFromIt() throws {
        let corners = ShadowShapes.angleCorners(w: 100, h: 50, angle: 30, distance: 40)
        XCTAssertEqual(corners[0].x, 21.547, accuracy: 1e-3)
        XCTAssertEqual(corners[0].y, 30, accuracy: 1e-9)
        XCTAssertEqual(corners[1].x, 101.547, accuracy: 1e-3)
        XCTAssertEqual(corners[1].y, 30, accuracy: 1e-9)
        XCTAssertEqual(corners[2], CGPoint(x: 100, y: 50))
        XCTAssertEqual(corners[3], CGPoint(x: 0, y: 50))
        // Leaning the other way, and flat on its base at no distance.
        XCTAssertEqual(ShadowShapes.angleCorners(w: 100, h: 50, angle: -30, distance: 40)[0].x, -1.547, accuracy: 1e-3)
        XCTAssertEqual(ShadowShapes.angleCorners(w: 100, h: 50, angle: 30, distance: 0)[0], CGPoint(x: 10, y: 50))
        let cast = try XCTUnwrap(ShadowShapes.angle(w: 100, h: 50, angle: 30, distance: 40))
        // The transform takes the box's corners onto the silhouette's.
        for (from, to) in zip(ShadowShapes.corners(w: 100, h: 50), corners) {
            let mapped = ShadowShapes.taken(from, through: cast.matrix)
            XCTAssertEqual(mapped.x, to.x, accuracy: 1e-6)
            XCTAssertEqual(mapped.y, to.y, accuracy: 1e-6)
        }
        XCTAssertTrue(cast.path.contains(CGPoint(x: 60, y: 45)))
        XCTAssertFalse(cast.path.contains(CGPoint(x: 5, y: 32)))
        // No distance is no silhouette: four points on one line.
        XCTAssertNil(ShadowShapes.angle(w: 100, h: 50, angle: 30, distance: 0))
        XCTAssertEqual(ShadowShapes.reach(of: Shadow(style: "angle"), w: 100, h: 50), 1.547, accuracy: 1e-3)
    }

    /// The transform is the Android twin's Deskew.homography: a square's
    /// corners to a trapezium, straight lines kept straight.
    func testTheHomographyTakesFourPointsToFourAndRefusesALine() throws {
        let from = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let to = [CGPoint(x: 0.25, y: 0), CGPoint(x: 0.75, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]
        let m = try XCTUnwrap(ShadowShapes.homography(from: from, to: to))
        XCTAssertEqual(m.count, 9)
        XCTAssertEqual(m[8], 1)
        let mid = ShadowShapes.taken(CGPoint(x: 0.5, y: 0.5), through: m)
        XCTAssertEqual(mid.x, 0.5, accuracy: 1e-9, "the middle stays in the middle")
        XCTAssertGreaterThan(mid.y, 0.5, "and nearer the wide end, as perspective has it")
        let identity = try XCTUnwrap(ShadowShapes.homography(from: from, to: from))
        XCTAssertEqual(identity[0], 1, accuracy: 1e-9)
        XCTAssertEqual(identity[1], 0, accuracy: 1e-9)
        XCTAssertNil(ShadowShapes.homography(from: from, to: [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1),
                                                              CGPoint(x: 2, y: 1), CGPoint(x: 0, y: 2)]))
    }

    func testTheReachIsHowFarTheSilhouettePassesTheBox() {
        XCTAssertEqual(ShadowShapes.reach(of: Shadow(style: "backdrop", distance: 12), w: 200, h: 100), 12)
        XCTAssertEqual(ShadowShapes.reach(of: Shadow(style: "curved", curve: 1), w: 200, h: 100), 6, accuracy: 0.01)
        XCTAssertEqual(ShadowShapes.reach(of: Shadow(), w: 200, h: 100), 0)
        XCTAssertEqual(ShadowShapes.reach(of: Shadow(style: "teapot"), w: 200, h: 100), 0)
    }

    // MARK: drawn

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

    /// A backdrop is a hard block of the shadow's colour, down and right of
    /// the element, and nothing up and left of it.
    @MainActor
    func testABackdropDrawsABlockDownAndRight() throws {
        let plain = try render(design(nil))
        let backed = try render(design(Shadow(color: "#000000", opacity: 1, blur: 0, offsetX: 0, offsetY: 0,
                                              style: "backdrop", distance: 12)))
        XCTAssertLessThan(try luma(backed, x: 136, y: 136), 20, "the block, past the element's corner")
        XCTAssertEqual(try luma(backed, x: 136, y: 136), try luma(backed, x: 100, y: 138), accuracy: 2, "hard edged")
        XCTAssertEqual(try luma(backed, x: 64, y: 64), try luma(plain, x: 64, y: 64), accuracy: 2)
        XCTAssertEqual(try luma(backed, x: 100, y: 64), 255, accuracy: 2, "nothing above")
    }

    /// A page lift, offset down, darkens below the lower corners more than
    /// below the middle of the bottom edge.
    @MainActor
    func testAPageLiftShadowsTheLowerCornersMost() throws {
        let lifted = try render(design(Shadow(color: "#000000", opacity: 0.9, blur: 6, offsetX: 0, offsetY: 8,
                                              style: "pageLift", curve: 1)))
        let left = try luma(lifted, x: 72, y: 134)
        let right = try luma(lifted, x: 128, y: 134)
        let middle = try luma(lifted, x: 100, y: 134)
        XCTAssertLessThan(left, 200, "under the left corner")
        XCTAssertLessThan(right, 200, "under the right corner")
        XCTAssertGreaterThan(middle, left + 20, "lighter under the middle")
        XCTAssertGreaterThan(try luma(lifted, x: 100, y: 64), 250, "nothing above")
    }

    /// An angle shadow leans out to one side of the element and not the
    /// other.
    @MainActor
    func testAnAngleShadowLeansToOneSide() throws {
        let plain = try render(design(nil))
        let leaning = try render(design(Shadow(color: "#000000", opacity: 0.8, blur: 2, offsetX: 0, offsetY: 0,
                                               style: "angle", angle: 45, distance: 80)))
        let right = try luma(plain, x: 140, y: 100) - luma(leaning, x: 140, y: 100)
        let left = try luma(plain, x: 60, y: 100) - luma(leaning, x: 60, y: 100)
        XCTAssertGreaterThan(right, 30, "the shadow leans out to the right")
        XCTAssertLessThan(left, 6, "and not to the left")
    }

    // MARK: export

    @MainActor
    func testAStyledShadowReachesTheSVGAsABlurredPath() {
        let d = design(Shadow(color: "#112233", opacity: 0.4, blur: 8, offsetX: 0, offsetY: 6, style: "curved", curve: 0.5))
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("<feGaussianBlur stdDeviation=\"4\"/>"))
        XCTAssertFalse(svg.contains("<feDropShadow"))
        XCTAssertTrue(svg.contains("<path d=\"M72.4 76L127.6 76L130 136Q100 139.6 70 136Z\" fill=\"#112233\" fill-opacity=\"0.4\" filter=\"url(#shadow0)\"/>"), svg)
        XCTAssertTrue(XMLParser(data: Data(svg.utf8)).parse())

        let backed = design(Shadow(color: "#5a31f4", opacity: 1, blur: 0, style: "backdrop", distance: 10))
        let block = SVGExporter.svg(design: backed, page: backed.pages[0])
        XCTAssertTrue(block.contains("<path d=\"M80 86L140 86L140 146L80 146Z\" fill=\"#5a31f4\" fill-opacity=\"1\"/>"),
                      "a backdrop has no filter: \(block)")
        XCTAssertFalse(block.contains("<filter"))
    }

    func testPowerPointPadsAPictureForTheSilhouettesReach() {
        var el = Element.shape("rect", w: 200, h: 100)
        el.shadow = Shadow(blur: 0, offsetX: 0, offsetY: 0, style: "backdrop", distance: 12)
        XCTAssertEqual(PptxExporter.margin(el), SVGExporter.overflow(el) + 12, accuracy: 1e-9)
    }

    // MARK: the cards

    func testTheFourStyledCardsFollowTheSix() {
        let names = Shadow.presets.map(\.name)
        XCTAssertEqual(names.count, 10)
        XCTAssertEqual(Array(names.suffix(4)), [tr("Curved"), tr("Page lift"), tr("Angle"), tr("Backdrop")])
        XCTAssertEqual(Shadow.presets.suffix(4).map { ShadowShapes.style(of: $0.shadow) },
                       ["curved", "pageLift", "angle", "backdrop"])
        XCTAssertTrue(Shadow.presets.prefix(6).allSatisfy { !ShadowShapes.isStyled($0.shadow) })
    }
}
