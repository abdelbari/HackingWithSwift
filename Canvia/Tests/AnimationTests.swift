// Entrances, text reveals, Ken Burns and equal-spacing hints.

import XCTest
import SwiftUI
@testable import Canvia

final class AnimationTests: XCTestCase {

    // MARK: evaluator

    func testProgressIsZeroBeforeTheDelayOneAfterAndEasedBetween() {
        let a = ElementAnimation(kind: "fade", delay: 1, duration: 2)
        XCTAssertEqual(a.progress(at: 0), 0); XCTAssertEqual(a.progress(at: 1), 0)
        XCTAssertEqual(a.progress(at: 3), 1); XCTAssertEqual(a.progress(at: 99), 1)
        let mid = a.progress(at: 2)
        XCTAssertGreaterThan(mid, 0.5, "ease-out is past halfway at half time")
        XCTAssertLessThan(mid, 1)
        XCTAssertEqual(a.end, 3)
        XCTAssertEqual(ElementAnimation(kind: "fade", delay: 0.5, duration: 0).progress(at: 0.4), 0)
        XCTAssertEqual(ElementAnimation(kind: "fade", delay: 0.5, duration: 0).progress(at: 0.5), 1)
    }

    func testEachKindMovesTheRightThing() {
        let size = 200.0
        XCTAssertEqual(ElementAnimation(kind: "fade").state(at: 0, size: size).opacity, 0)
        XCTAssertEqual(ElementAnimation(kind: "rise").state(at: 0, size: size).offset.height, 60, accuracy: 0.001)
        XCTAssertEqual(ElementAnimation(kind: "pop").state(at: 0, size: size).scale, 0.4, accuracy: 0.001)
        XCTAssertEqual(ElementAnimation(kind: "slideLeft").state(at: 0, size: size).offset.width, 200, accuracy: 0.001)
        XCTAssertEqual(ElementAnimation(kind: "slideRight").state(at: 0, size: size).offset.width, -200, accuracy: 0.001)
        for kind in ElementAnimation.kinds where !ElementAnimation.loopKinds.contains(kind) {
            XCTAssertEqual(ElementAnimation(kind: kind).state(at: 10, text: "Hello there", size: size), .settled, kind)
        }
        for kind in ElementAnimation.loopKinds {
            XCTAssertTrue(ElementAnimation(kind: kind).loops, kind)
        }
    }

    func testTextRevealsCountCharactersOrWholeWords() {
        let type = ElementAnimation(kind: "typewriter", delay: 0, duration: 1)
        XCTAssertEqual(type.state(at: 0, text: "abcdefghij").visibleCharacters, 0)
        XCTAssertEqual(type.state(at: 0.5, text: "abcdefghij").visibleCharacters, 5)
        XCTAssertNil(type.state(at: 1, text: "abcdefghij").visibleCharacters, "settled shows everything")
        let words = ElementAnimation(kind: "words", delay: 0, duration: 1)
        let half = words.state(at: 0.5, text: "one two three four").visibleCharacters
        XCTAssertEqual(half, "one two".count, "half the time, half the words, whole")
        XCTAssertEqual(words.state(at: 0.01, text: "one two").visibleCharacters, 3, "the first word comes whole")
    }

    // MARK: ken burns

    func testKenBurnsDriftsTheCropOverTheHold() {
        var el = Element.image("asset:x")
        el.cropScale = 1.2; el.cropX = 0.3; el.cropY = 0.5
        var drift = KenBurns(); drift.zoom = 1.5; drift.toX = 0.7
        let start = drift.crop(from: el, fraction: 0)
        XCTAssertEqual(start.scale, 1.2, accuracy: 0.001); XCTAssertEqual(start.x, 0.3, accuracy: 0.001)
        let end = drift.crop(from: el, fraction: 1)
        XCTAssertEqual(end.scale, 1.8, accuracy: 0.001)
        XCTAssertEqual(end.x, 0.7, accuracy: 0.001)
        XCTAssertEqual(end.y, 0.5, accuracy: 0.001, "no target: the focus stays")
        XCTAssertEqual(drift.crop(from: el, fraction: 7).scale, 1.8, accuracy: 0.001, "clamped")
    }

    // MARK: rendered

    /// A fading red square over white: white at the start, red once settled.
    @MainActor
    func testAFadingElementIsInvisibleAtTheStartAndThereAtTheEnd() throws {
        var d = Design(title: "a", width: 100, height: 100)
        var el = Element.shape("rect", w: 100, h: 100)
        el.fill = .solid("#ff0000")
        el.animation = ElementAnimation(kind: "fade", delay: 0, duration: 1)
        d.pages[0].elements = [el]
        func centre(at time: Double?) throws -> (r: Double, g: Double) {
            let renderer = ImageRenderer(content: PageRenderView(design: d, page: d.pages[0])
                .environment(\.animationTime, time.map { ($0, 2.0) }))
            renderer.scale = 1
            renderer.isOpaque = true
            let cg = try XCTUnwrap(renderer.cgImage)
            var px: [UInt8] = [0, 0, 0, 0]
            try px.withUnsafeMutableBytes { raw in
                let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                ctx.draw(cg, in: CGRect(x: -50, y: -49, width: 100, height: 100))
            }
            return (Double(px[0]), Double(px[1]))
        }
        let start = try centre(at: 0)
        XCTAssertGreaterThan(start.g, 200, "at t=0 the square has not appeared: \(start)")
        let settled = try centre(at: 5)
        XCTAssertLessThan(settled.g, 60, "settled, the square is red: \(settled)")
        let rest = try centre(at: nil)
        XCTAssertLessThan(rest.g, 60, "with no clock the editor shows everything: \(rest)")
        XCTAssertTrue(MovieExporter.isAnimated(d.pages[0]))
        XCTAssertFalse(MovieExporter.isAnimated(Page()))
    }

    // MARK: equal spacing

    func testEqualSpacingSnapsBetweenTwoNeighbours() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 100)
        let right = CGRect(x: 400, y: 0, width: 100, height: 100)
        // Gaps 90 and 110: off by 20, within a 12 threshold (×2).
        let moving = CGRect(x: 190, y: 10, width: 100, height: 50)
        let even = Geometry.equalGap(moving: moving, siblings: [left, right], threshold: 12)
        XCTAssertEqual(even.dx, 10, accuracy: 0.001)
        XCTAssertEqual(even.gapX, 100)
        XCTAssertNil(even.gapY)
        // Far off: nothing.
        let far = Geometry.equalGap(moving: CGRect(x: 120, y: 10, width: 100, height: 50), siblings: [left, right], threshold: 12)
        XCTAssertEqual(far.dx, 0); XCTAssertNil(far.gapX)
        // Not beside them vertically: not between them.
        let elsewhere = Geometry.equalGap(moving: CGRect(x: 190, y: 300, width: 100, height: 50), siblings: [left, right], threshold: 12)
        XCTAssertNil(elsewhere.gapX)
    }

    func testEqualSpacingWorksVertically() {
        let above = CGRect(x: 0, y: 0, width: 100, height: 50)
        let below = CGRect(x: 0, y: 300, width: 100, height: 50)
        let moving = CGRect(x: 10, y: 120, width: 50, height: 60)   // gaps 70 and 120: too far
        XCTAssertNil(Geometry.equalGap(moving: moving, siblings: [above, below], threshold: 12).gapY)
        let near = CGRect(x: 10, y: 140, width: 50, height: 60)     // gaps 90 and 100
        let even = Geometry.equalGap(moving: near, siblings: [above, below], threshold: 12)
        XCTAssertEqual(even.dy, 5, accuracy: 0.001)
        XCTAssertEqual(even.gapY, 95)
    }
}
