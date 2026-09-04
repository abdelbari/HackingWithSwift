// Relative SVG paths and imports, gradient kinds, per-corner radii, drop
// caps, and the uploads listing.

import XCTest
import UIKit
@testable import Canvia

final class ShapeExtrasTests: XCTestCase {

    // MARK: svg parsing

    func testRelativeCommandsLandWhereAbsoluteOnesDo() {
        let absolute = SVGPath.path("M10 10 L60 10 L60 60 Z").boundingBox
        let relative = SVGPath.path("m10 10 l50 0 l0 50 z").boundingBox
        XCTAssertEqual(absolute, relative)
        let hv = SVGPath.path("m10 10 h50 v50 h-50 z").boundingBox
        XCTAssertEqual(hv, CGRect(x: 10, y: 10, width: 50, height: 50))
        let curve = SVGPath.path("M0 0 c10 20 30 20 40 0 s30 -20 40 0").boundingBox
        XCTAssertEqual(curve.maxX, 80, accuracy: 0.001)
        XCTAssertGreaterThan(curve.height, 5, "the smooth curve has a bulge")
    }

    func testAnImportedPathIsFittedIntoTheHundredBox() throws {
        let svg = ##"<svg viewBox="0 0 300 200"><path fill="red" d="M100 50 l 100 0 l 0 60 l -100 0 z"/></svg>"##
        let d = try XCTUnwrap(SVGPath.importFirstPath(fromSVG: svg))
        let box = SVGPath.path(d).boundingBox
        XCTAssertEqual(box.width, 100, accuracy: 0.05, "the long side fills the box")
        XCTAssertEqual(box.height, 60, accuracy: 0.05, "the aspect is kept")
        XCTAssertEqual(box.midX, 50, accuracy: 0.05); XCTAssertEqual(box.midY, 50, accuracy: 0.05)
        XCTAssertNil(SVGPath.importFirstPath(fromSVG: "<svg><rect width='10' height='10'/></svg>"), "no <path>, nothing")
    }

    // MARK: gradients

    func testGradientKindsRoundTripAndTheSVGKnowsRadial() throws {
        var paint = Paint(kind: "gradient", color: nil, angle: 0,
                          stops: [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 1, color: "#0000ff")])
        paint.gradientKind = "radial"
        let back = try JSONDecoder().decode(Paint.self, from: JSONEncoder().encode(paint))
        XCTAssertEqual(back.gradientKind, "radial")
        let old = try JSONDecoder().decode(Paint.self, from: Data(##"{"kind":"gradient","angle":90,"stops":[]}"##.utf8))
        XCTAssertNil(old.gradientKind, "older documents are linear")
    }

    @MainActor
    func testTheSVGEmitsARadialGradientAndBitmapsAnAngularOne() {
        var d = Design(title: "g", width: 200, height: 200)
        var el = Element.shape("rect")
        var paint = Paint(kind: "gradient", color: nil, angle: 0,
                          stops: [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 1, color: "#0000ff")])
        paint.gradientKind = "radial"
        el.fill = paint
        d.pages[0].elements = [el]
        XCTAssertTrue(SVGExporter.svg(design: d, page: d.pages[0]).contains("<radialGradient"))
        paint.gradientKind = "angular"
        d.pages[0].elements[0].fill = paint
        let angular = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertFalse(angular.contains("Gradient id"), "no SVG conic gradient exists")
        XCTAssertTrue(angular.contains("<image"), angular.prefix(300).description)
    }

    /// Rendered: a radial red-to-blue fill is red in the middle and blue at
    /// the corner; a linear one at 90° is red on the left and blue on the
    /// right.
    @MainActor
    func testRadialIsRedInTheMiddleAndBlueAtTheEdge() throws {
        var el = Element.shape("rect", w: 100, h: 100)
        var paint = Paint(kind: "gradient", color: nil, angle: 90,
                          stops: [GradientStop(offset: 0, color: "#ff0000"), GradientStop(offset: 1, color: "#0000ff")])
        paint.gradientKind = "radial"
        el.fill = paint
        let radial = try render(el)
        XCTAssertGreaterThan(try rgb(radial, 50, 50).r, 200)
        XCTAssertGreaterThan(try rgb(radial, 3, 3).b, 150)
        paint.gradientKind = nil
        el.fill = paint
        let linear = try render(el)
        XCTAssertGreaterThan(try rgb(linear, 3, 50).r, 200)
        XCTAssertGreaterThan(try rgb(linear, 96, 50).b, 200)
    }

    // MARK: corners

    @MainActor
    func testPerCornerRadiiRoundOnlyTheCornersAsked() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let topOnly = LibraryShape.roundedRect(rect, corners: [30, 30, 0, 0])
        XCTAssertFalse(topOnly.contains(CGPoint(x: 1, y: 1)), "top-left is cut")
        XCTAssertFalse(topOnly.contains(CGPoint(x: 99, y: 1)), "top-right is cut")
        XCTAssertTrue(topOnly.contains(CGPoint(x: 1, y: 99)), "bottom-left is square")
        XCTAssertTrue(topOnly.contains(CGPoint(x: 99, y: 99)), "bottom-right is square")
        let huge = LibraryShape.roundedRect(rect, corners: [500, 500, 500, 500])
        XCTAssertTrue(huge.contains(CGPoint(x: 50, y: 50)), "radii clamp to half the side, not to nothing")
    }

    @MainActor
    func testCornersReachTheSVG() {
        var d = Design(title: "c", width: 200, height: 100)
        var el = Element.shape("rect", w: 200, h: 100)
        el.radius = 20
        el.corners = [20, 0, 0, 0]
        d.pages[0].elements = [el]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        // A single rounded corner: one curve, three sharp corners.
        let curves = svg.components(separatedBy: "C").count - 1 + svg.components(separatedBy: "Q").count - 1
        XCTAssertGreaterThan(curves, 0)
        XCTAssertTrue(svg.contains("L100 100") || svg.contains("100 100"), svg)
    }

    // MARK: drop caps

    func testADropCapIsThreeLinesTallAndTakesTheFirstLetterOnly() throws {
        var el = Element.text("Once upon a time there was a very long paragraph of text that wraps.", fontSize: 20, w: 300)
        el.align = "left"
        XCTAssertNil(FontLibrary.dropCapLayout(for: el))
        el.dropCap = true
        let layout = try XCTUnwrap(FontLibrary.dropCapLayout(for: el))
        XCTAssertEqual(layout.letter, "O")
        XCTAssertTrue(layout.rest.hasPrefix("nce upon"))
        XCTAssertEqual(layout.capRect.height, 20 * 1.25 * 3, accuracy: 0.001)
        XCTAssertGreaterThan(layout.capRect.width, 20)
        XCTAssertGreaterThanOrEqual(FontLibrary.measuredHeight(for: el), layout.capRect.height)
        var short = el; short.text = "Hi"
        XCTAssertEqual(FontLibrary.measuredHeight(for: short), layout.capRect.height, accuracy: 0.001,
                       "a one-word paragraph is still as tall as its cap")
        var list = el; list.listStyle = "bullet"
        XCTAssertNil(FontLibrary.dropCapLayout(for: list), "a list has no drop cap")
    }

    @MainActor
    func testTheCapIsDrawnTallerThanALine() throws {
        var el = Element.text("Wonderful things happen when the first letter is large and the rest wraps around.", fontSize: 20, w: 320)
        el.align = "left"; el.color = "#000000"; el.dropCap = true
        el.h = FontLibrary.layoutHeight(for: el)
        let image = try render(el)
        // Ink in the leftmost 12 px should span well past one line (25px).
        var top = Int.max, bottom = 0
        for y in 0..<Int(image.height) {
            for x in 0..<12 where try rgb(image, x, y).r < 100 {
                top = min(top, y); bottom = max(bottom, y)
            }
        }
        XCTAssertGreaterThan(bottom - top, 40, "the cap's ink spans \(bottom - top)px — not tall")
    }

    // MARK: uploads

    func testUploadsAreListedNewestFirstAndDeletable() throws {
        let id = try XCTUnwrap(MediaStore.storeOpaque(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in })
            .map { String($0.dropFirst(6)) })
        XCTAssertEqual(MediaStore.all().first, id)
        MediaStore.delete(id)
        XCTAssertFalse(MediaStore.all().contains(id))
        XCTAssertNil(MediaStore.load(id))
    }

    // MARK: helpers

    @MainActor
    private func render(_ el: Element) throws -> CGImage {
        var d = Design(title: "r", width: el.w, height: el.h)
        d.pages[0].elements = [el]
        return try XCTUnwrap(DesignExporter.render(design: d, page: d.pages[0], scale: 1))
    }

    private func rgb(_ cg: CGImage, _ x: Int, _ y: Int) throws -> (r: Double, g: Double, b: Double) {
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(cg, in: CGRect(x: -x, y: -(cg.height - 1 - y), width: cg.width, height: cg.height))
        }
        return (Double(pixel[0]), Double(pixel[1]), Double(pixel[2]))
    }
}
