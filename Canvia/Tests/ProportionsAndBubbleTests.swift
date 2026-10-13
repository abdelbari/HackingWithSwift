// Keep proportions in the Position panel and where the quick-action bubble
// sits, with the rows the Android twin's tests hold too.

import XCTest
@testable import Canvia

final class ProportionsAndBubbleTests: XCTestCase {

    private func box(_ id: String, x: Double, y: Double, w: Double = 100, h: Double = 100,
                     group: String? = nil) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.id = id
        el.x = x
        el.y = y
        el.group = group
        return el
    }

    // MARK: keep proportions

    func testKeepProportionsStartsOnForAPhotoAndAGroup() {
        XCTAssertTrue(RatioLock.startsOn([Element.image("asset:mesh-sunset")]))
        XCTAssertFalse(RatioLock.startsOn([Element.shape("rect")]))
        XCTAssertFalse(RatioLock.startsOn([Element.line()]))
        XCTAssertFalse(RatioLock.startsOn([Element.text("Hi")]))
        XCTAssertFalse(RatioLock.startsOn([Element.sticker("⭐")]))
        XCTAssertTrue(RatioLock.startsOn([box("a", x: 0, y: 0, group: "g"), box("b", x: 0, y: 0, group: "g")]))
        XCTAssertFalse(RatioLock.startsOn([box("a", x: 0, y: 0), box("b", x: 0, y: 0)]))
        XCTAssertFalse(RatioLock.startsOn([]))
    }

    func testKeepProportionsSizes() {
        let frame = CGSize(width: 400, height: 300)
        XCTAssertEqual(RatioLock.size(width: 200, from: frame), CGSize(width: 200, height: 150))
        let tall = RatioLock.size(height: 600, from: frame)
        XCTAssertEqual(tall.width, 800, accuracy: 0.000001)
        XCTAssertEqual(tall.height, 600)
        // Neither side under 8: the other grows to keep the proportion.
        XCTAssertEqual(RatioLock.size(width: 16, from: CGSize(width: 400, height: 100)), CGSize(width: 32, height: 8))
        XCTAssertEqual(RatioLock.size(height: 2, from: CGSize(width: 100, height: 100)), CGSize(width: 8, height: 8))
    }

    // MARK: quick actions

    func testTheBubbleSitsAboveUnlessTooNearTheTop() {
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        let above = Geometry.bubbleAnchor(CGRect(x: 100, y: 200, width: 200, height: 100), viewport: screen, handleOutset: 8)
        XCTAssertEqual(above, Geometry.BubbleAnchor(point: CGPoint(x: 200, y: 180), side: .above))
        let below = Geometry.bubbleAnchor(CGRect(x: 100, y: 60, width: 200, height: 100), viewport: screen, handleOutset: 8)
        XCTAssertEqual(below, Geometry.BubbleAnchor(point: CGPoint(x: 200, y: 180), side: .below))
        // Just room: its foot 56 from the top.
        let edge = Geometry.bubbleAnchor(CGRect(x: 100, y: 76, width: 200, height: 100), viewport: screen, handleOutset: 8)
        XCTAssertEqual(edge.side, .above)
        XCTAssertEqual(edge.point.y, 56)
        // Kept on screen across.
        let left = Geometry.bubbleAnchor(CGRect(x: -150, y: 300, width: 200, height: 100), viewport: screen, handleOutset: 0)
        XCTAssertEqual(left.point, CGPoint(x: 0, y: 288))
        // Against a canvas that does not start at the top.
        let lower = Geometry.bubbleAnchor(CGRect(x: 100, y: 150, width: 100, height: 100),
                                          viewport: CGRect(x: 0, y: 100, width: 400, height: 700), handleOutset: 0)
        XCTAssertEqual(lower, Geometry.BubbleAnchor(point: CGPoint(x: 150, y: 262), side: .below))
    }

    func testAPageBoxOnScreen() {
        let rect = Geometry.screenRect(CGRect(x: 200, y: 300, width: 100, height: 50),
                                       visible: CGRect(x: 100, y: 100, width: 400, height: 800), zoom: 0.5)
        XCTAssertEqual(rect, CGRect(x: 50, y: 100, width: 50, height: 25))
    }
}
