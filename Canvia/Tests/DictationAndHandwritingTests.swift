// Dictation's merge, strokes rendered for handwriting recognition, and the
// design user activity.

import XCTest
import UIKit
@testable import Canvia

final class DictationAndHandwritingTests: XCTestCase {

    func testDictatedWordsAppendOneSpaceApart() {
        XCTAssertEqual(Dictation.merge("", "hello there"), "hello there")
        XCTAssertEqual(Dictation.merge("Big sale ", " today only "), "Big sale today only")
        XCTAssertEqual(Dictation.merge("Kept", "   "), "Kept")
    }

    func testAStrokeIsAnUnfilledPathShape() {
        let stroke = Freehand.element(points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), CGPoint(x: 100, y: 0)],
                                      tool: Freehand.Tool(color: "#000000", width: 6))!
        XCTAssertTrue(Freehand.isStroke(stroke))
        var filled = stroke; filled.fill = .solid("#ff0000")
        XCTAssertFalse(Freehand.isStroke(filled))
        XCTAssertFalse(Freehand.isStroke(Element.shape("rect")))
        XCTAssertFalse(Freehand.isStroke(Element.text("hi")))
    }

    func testStrokesRenderBlackOnWhiteOverTheirUnion() throws {
        let tool = Freehand.Tool(color: "#000000", width: 8)
        let a = Freehand.element(points: [CGPoint(x: 100, y: 100), CGPoint(x: 160, y: 100)], tool: tool)!
        let b = Freehand.element(points: [CGPoint(x: 200, y: 140), CGPoint(x: 260, y: 200)], tool: tool)!
        let rendered = try XCTUnwrap(Freehand.bitmap(of: [a, b, Element.shape("rect")], scale: 2))
        // Padded union of the two strokes, at two pixels per unit.
        XCTAssertLessThan(rendered.frame.minX, 95); XCTAssertGreaterThan(rendered.frame.maxX, 265)
        XCTAssertEqual(rendered.image.size.width, (rendered.frame.width * 2).rounded(), accuracy: 1)
        // Ink where the first stroke runs, none in the padding.
        let cg = try XCTUnwrap(rendered.image.cgImage)
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        func value(_ page: CGPoint) -> UInt8 {
            let x = Int(((page.x - rendered.frame.minX) * 2).rounded()), y = Int(((page.y - rendered.frame.minY) * 2).rounded())
            return px[(y * w + x) * 4]
        }
        XCTAssertLessThan(value(CGPoint(x: 130, y: 100)), 60, "on the first stroke")
        XCTAssertGreaterThan(value(CGPoint(x: 130, y: 130)), 200, "between the strokes")
        XCTAssertNil(Freehand.bitmap(of: [Element.shape("rect")]))
    }

    func testDesignActivityCarriesTheID() {
        let d = Design(title: "Flyer", width: 100, height: 100)
        let activity = NSUserActivity(activityType: DesignActivity.type)
        DesignActivity.configure(activity, design: d)
        XCTAssertEqual(activity.title, "Flyer")
        XCTAssertTrue(activity.isEligibleForHandoff)
        XCTAssertEqual(DesignActivity.designID(from: activity), d.id)
        XCTAssertNil(DesignActivity.designID(from: NSUserActivity(activityType: "other")))
    }
}
