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

    func testKeepProportionsStartsOnForAPhotoAndAGroupsMember() {
        // The Android twin's Resize.keepsProportionsAtFirst rows.
        let rows: [(Element, Bool)] = [
            (Element.image("asset:mesh-sunset"), true),
            (Element.shape("rect"), false),
            (Element.line(), false),
            (Element.text("Hi"), false),
            (Element.sticker("⭐"), false),
            (box("a", x: 0, y: 0, group: "g"), true),
        ]
        for (el, on) in rows {
            XCTAssertEqual(RatioLock.startsOn(el), on, "\(el.type) \(el.group ?? "")")
        }
    }

    func testKeepProportionsHoldsTheTurnedTopLeftCorner() {
        // The Android twin's ResizeTest rows: a 400 × 300 photo at 50, 60.
        var photo = Element.image("p", w: 400, h: 300)
        photo.x = 50
        photo.y = 60
        let size = RatioLock.size(width: 800, from: CGSize(width: photo.w, height: photo.h))
        XCTAssertEqual(RatioLock.placed(photo, at: size), CGRect(x: 50, y: 60, width: 800, height: 600))
        // Turned, its turned top left corner stays put.
        photo.rotation = 30
        let corner = Geometry.handlePoint(photo, .nw)
        let box = RatioLock.placed(photo, at: size)
        XCTAssertEqual(Double(box.minX), -51.794919, accuracy: 1e-6)
        XCTAssertEqual(Double(box.minY), 139.903811, accuracy: 1e-6)
        XCTAssertEqual(Double(box.width), 800)
        XCTAssertEqual(Double(box.height), 600)
        var grown = photo
        grown.x = Double(box.minX)
        grown.y = Double(box.minY)
        grown.w = Double(box.width)
        grown.h = Double(box.height)
        let after = Geometry.handlePoint(grown, .nw)
        XCTAssertEqual(Double(after.x), Double(corner.x), accuracy: 1e-9)
        XCTAssertEqual(Double(after.y), Double(corner.y), accuracy: 1e-9)
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

    func testATypedSizeOnABoxWithASideOfZeroIsTaken() {
        // The Android twin's ResizeTest rows: box w, h, typed width, typed
        // height -> width, height, the top left held at 50, 60.
        let rows: [(Double, Double, Double?, Double?, Double, Double)] = [
            (400, 0, 200, nil, 200, 8),
            (400, 0, nil, 30, 400, 30),
            (0, 300, 200, nil, 200, 300),
            (0, 300, nil, 2, 8, 8),
        ]
        for (w, h, typedW, typedH, wantW, wantH) in rows {
            var flat = Element.image("p", w: w, h: h)
            flat.x = 50
            flat.y = 60
            let box = CGSize(width: w, height: h)
            let size = typedW.map { RatioLock.size(width: $0, from: box) } ?? RatioLock.size(height: typedH ?? 0, from: box)
            XCTAssertEqual(RatioLock.placed(flat, at: size), CGRect(x: 50, y: 60, width: wantW, height: wantH), "\(w) × \(h)")
        }
    }

    // MARK: quick actions

    func testTheBubbleSitsAboveUnlessTooNearTheTop() {
        // The Android twin's BubbleAnchorTest rows: selection x, y, w, h,
        // handle outset -> side, point x, point y, in a 400 × 800 view.
        let screen = CGRect(x: 0, y: 0, width: 400, height: 800)
        let rows: [(CGRect, Double, Geometry.BubbleSide, Double, Double)] = [
            // Room above: 12 over the handles.
            (CGRect(x: 100, y: 300, width: 200, height: 100), 46, .above, 200, 242),
            // Exactly 56 left above.
            (CGRect(x: 100, y: 114, width: 200, height: 100), 46, .above, 200, 56),
            // Within 56 of the top: below, as far clear of the handles.
            (CGRect(x: 100, y: 113, width: 200, height: 100), 46, .below, 200, 271),
            (CGRect(x: 0, y: 20, width: 100, height: 100), 0, .below, 50, 132),
            // Filling the view: below, kept 56 up from the bottom.
            (CGRect(x: 0, y: 0, width: 400, height: 800), 46, .below, 200, 744),
            // Mostly off to the side: kept across inside the view.
            (CGRect(x: 350, y: 400, width: 200, height: 100), 0, .above, 400, 388),
            (CGRect(x: -300, y: 400, width: 200, height: 100), 0, .above, 0, 388),
        ]
        for (rect, outset, side, x, y) in rows {
            let anchor = Geometry.bubbleAnchor(rect, viewport: screen, handleOutset: outset)
            XCTAssertEqual(anchor.side, side, "side of \(rect)")
            XCTAssertEqual(Double(anchor.point.x), x, accuracy: 1e-9, "x of \(rect)")
            XCTAssertEqual(Double(anchor.point.y), y, accuracy: 1e-9, "y of \(rect)")
        }
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
