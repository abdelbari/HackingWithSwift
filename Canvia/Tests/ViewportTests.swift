// Fitting a design into the viewport when it opens.
//
// This exists because the offset was wrong and nothing caught it: the app
// built, every test passed, and every design opened pushed half a viewport
// down and to the right, most of it off screen. The formula looked plausible
// — it folded in the scroll view's content inset — and the only way to see
// that it was not is to look at the screen.
//
// So the assertions below are stated as the property, not as the formula: the
// centre of the content lands on the centre of the viewport. A test that
// restated the arithmetic would have shipped the same bug twice.

import XCTest
import CoreGraphics
@testable import Canvia

final class ViewportTests: XCTestCase {

    /// Where a content point ends up on screen, given a scroll offset.
    private func onScreen(_ point: CGPoint, offset: CGPoint) -> CGPoint {
        CGPoint(x: point.x - offset.x, y: point.y - offset.y)
    }

    // MARK: centring

    func testCentringPutsTheContentCentreOnTheViewportCentre() {
        let cases: [(content: CGSize, viewport: CGSize)] = [
            (CGSize(width: 345, height: 345), CGSize(width: 393, height: 600)),   // fits
            (CGSize(width: 2000, height: 2000), CGSize(width: 393, height: 600)), // zoomed in
            (CGSize(width: 800, height: 100), CGSize(width: 393, height: 600)),   // wide
            (CGSize(width: 100, height: 800), CGSize(width: 1024, height: 768)),  // tall, iPad
        ]
        for (content, viewport) in cases {
            let offset = Geometry.centeredOffset(scaledContent: content, in: viewport)
            let middle = onScreen(CGPoint(x: content.width / 2, y: content.height / 2),
                                  offset: offset)
            XCTAssertEqual(middle.x, viewport.width / 2, accuracy: 0.001,
                           "\(content) in \(viewport)")
            XCTAssertEqual(middle.y, viewport.height / 2, accuracy: 0.001,
                           "\(content) in \(viewport)")
        }
    }

    /// Content smaller than the viewport leaves equal margins on both sides.
    func testSmallContentIsInsetEquallyOnBothSides() {
        let content = CGSize(width: 345, height: 200)
        let viewport = CGSize(width: 393, height: 600)
        let offset = Geometry.centeredOffset(scaledContent: content, in: viewport)
        let leading = onScreen(.zero, offset: offset)
        let trailing = onScreen(CGPoint(x: content.width, y: content.height), offset: offset)
        XCTAssertEqual(leading.x, viewport.width - trailing.x, accuracy: 0.001)
        XCTAssertEqual(leading.y, viewport.height - trailing.y, accuracy: 0.001)
    }

    /// Content exactly the size of the viewport sits flush at the origin.
    func testExactFitNeedsNoOffset() {
        let size = CGSize(width: 393, height: 600)
        XCTAssertEqual(Geometry.centeredOffset(scaledContent: size, in: size), .zero)
    }

    // MARK: fitting

    func testFitScaleUsesTheTighterAxis() {
        // A square page in a portrait viewport is limited by width.
        let scale = Geometry.fitScale(content: CGSize(width: 1080, height: 1080),
                                      in: CGSize(width: 393, height: 600))
        XCTAssertEqual(scale, (393 - 48) / 1080, accuracy: 0.0001)
    }

    func testFitScaleLeavesThePaddingItPromises() {
        let content = CGSize(width: 1080, height: 1350)
        let viewport = CGSize(width: 393, height: 600)
        let scale = Geometry.fitScale(content: content, in: viewport, padding: 48)
        let scaled = CGSize(width: content.width * scale, height: content.height * scale)
        // The tighter axis is exactly `padding` short of the viewport; the
        // other has at least that much to spare.
        let slack = min(viewport.width - scaled.width, viewport.height - scaled.height)
        XCTAssertEqual(slack, 48, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(viewport.width - scaled.width, 48 - 0.001)
        XCTAssertGreaterThanOrEqual(viewport.height - scaled.height, 48 - 0.001)
    }

    /// A design far larger than the viewport still gets a usable scale rather
    /// than a negative or zero one.
    func testFitScaleStaysPositiveForHugeDesigns() {
        let scale = Geometry.fitScale(content: CGSize(width: 4000, height: 4000),
                                      in: CGSize(width: 393, height: 600))
        XCTAssertGreaterThan(scale, 0)
        XCTAssertLessThan(scale, 1)
    }

    /// Called before layout, a viewport can be zero. Dividing by it would
    /// give infinity and then a NaN content offset, which UIScrollView
    /// traps on.
    func testDegenerateSizesFallBackToOne() {
        XCTAssertEqual(Geometry.fitScale(content: .zero, in: CGSize(width: 393, height: 600)), 1)
        XCTAssertEqual(Geometry.fitScale(content: CGSize(width: 1080, height: 1080), in: .zero), 1)
    }

    // MARK: the two together

    /// What actually happens when a design opens: fit it, then centre it.
    func testAFittedDesignOpensCentredAndFullyOnScreen() {
        let viewport = CGSize(width: 393, height: 600)
        for page in [CGSize(width: 1080, height: 1080),
                     CGSize(width: 1080, height: 1920),
                     CGSize(width: 1920, height: 1080),
                     CGSize(width: 40, height: 40)] {
            let scale = Geometry.fitScale(content: page, in: viewport)
            let scaled = CGSize(width: page.width * scale, height: page.height * scale)
            let offset = Geometry.centeredOffset(scaledContent: scaled, in: viewport)
            let topLeft = onScreen(.zero, offset: offset)
            let bottomRight = onScreen(CGPoint(x: scaled.width, y: scaled.height), offset: offset)
            XCTAssertGreaterThanOrEqual(topLeft.x, 0, "\(page) starts off the left edge")
            XCTAssertGreaterThanOrEqual(topLeft.y, 0, "\(page) starts above the top edge")
            XCTAssertLessThanOrEqual(bottomRight.x, viewport.width, "\(page) runs off the right")
            XCTAssertLessThanOrEqual(bottomRight.y, viewport.height, "\(page) runs off the bottom")
        }
    }
}
