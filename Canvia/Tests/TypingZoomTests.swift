// Round 29's typing zoom, with the rows the Android twin's ViewportTest
// holds too: typing into small words zooms them up to a size that reads,
// within the limit and the width, and never out; and where the tap that
// opened the typing landed, for the line the view centres on.

import XCTest
import CoreGraphics
@testable import Canvia

@MainActor
final class TypingZoomTests: XCTestCase {

    // MARK: typing zoom

    func testTypingZoomLeavesWordsThatAlreadyReadAlone() {
        let box = CGRect(x: 0, y: 0, width: 600, height: 40)
        let visible = CGRect(x: 0, y: 0, width: 400, height: 300)
        // 14 at 1.0, 50 at 0.3: both read.
        XCTAssertNil(Viewport.typingZoom(fontSize: 14, box: box, viewport: visible, zoom: 1, maxZoom: 5))
        XCTAssertNil(Viewport.typingZoom(fontSize: 50, box: box, viewport: visible, zoom: 0.3, maxZoom: 5))
    }

    func testTypingZoomBringsSmallWordsUpToEighteenWithinTheLimitAndTheWidth() throws {
        let visible = CGRect(x: 0, y: 0, width: 400, height: 300)
        let narrow = CGRect(x: 0, y: 0, width: 200, height: 30)
        // 12 at 0.3 is 3.6 on screen: up to 18 is 1.5, the box 200 wide fits.
        XCTAssertEqual(try XCTUnwrap(Viewport.typingZoom(fontSize: 12, box: narrow, viewport: visible, zoom: 0.3, maxZoom: 5)),
                       1.5, accuracy: 1e-9)
        // Capped at the most zoom allowed.
        XCTAssertEqual(try XCTUnwrap(Viewport.typingZoom(fontSize: 12, box: narrow, viewport: visible, zoom: 0.3, maxZoom: 1.2)),
                       1.2, accuracy: 1e-9)
        // Never wider than the visible width less 48: a box 704 wide in 400.
        let wide = CGRect(x: 0, y: 0, width: 704, height: 30)
        XCTAssertEqual(try XCTUnwrap(Viewport.typingZoom(fontSize: 12, box: wide, viewport: visible, zoom: 0.3, maxZoom: 5)),
                       0.5, accuracy: 1e-9)
        // And never out: a box already as wide as the view stays as it is.
        let wider = CGRect(x: 0, y: 0, width: 1408, height: 30)
        XCTAssertNil(Viewport.typingZoom(fontSize: 12, box: wider, viewport: visible, zoom: 0.3, maxZoom: 5))
        XCTAssertEqual(Viewport.minReadable, 14)
        XCTAssertEqual(Viewport.typingTarget, 18)
        XCTAssertEqual(Viewport.typingZoomKey, "canvia.typingZoom")
    }

    func testTypingCentresOnTheLineTappedHeldWithinTheBoxElseTheLastLine() {
        let box = CGRect(x: 0, y: 100, width: 200, height: 30)
        // No tap: the last line's middle, 0.6 of the type's size up from the bottom.
        XCTAssertEqual(Viewport.typingLine(box: box, fontSize: 12, tapY: nil), 122.8, accuracy: 1e-9)
        XCTAssertEqual(Viewport.typingLastLine, 0.6)
        // A tap: its own line.
        XCTAssertEqual(Viewport.typingLine(box: box, fontSize: 12, tapY: 110), 110, accuracy: 1e-9)
        // A tap past an edge is held to the box.
        XCTAssertEqual(Viewport.typingLine(box: box, fontSize: 12, tapY: 5), 100, accuracy: 1e-9)
        XCTAssertEqual(Viewport.typingLine(box: box, fontSize: 12, tapY: 500), 130, accuracy: 1e-9)
        // A box shorter than the type: never above its top.
        let short = CGRect(x: 0, y: 100, width: 200, height: 5)
        XCTAssertEqual(Viewport.typingLine(box: short, fontSize: 12, tapY: nil), 100, accuracy: 1e-9)
    }

    func testTypingRemembersWhereTheTapLanded() {
        var d = Design(title: "typing", width: 1000, height: 1000)
        var words = Element.text("Hello", fontSize: 12, w: 300)
        words.id = "t"
        d.pages = [Page(id: "p1", elements: [words])]
        let s = DesignStore(design: d)
        s.startTyping("t", at: CGPoint(x: 10, y: 5))
        XCTAssertEqual(s.typingPoint, CGPoint(x: 10, y: 5))
        s.endTextEdit()
        s.startTyping("t")
        XCTAssertNil(s.typingPoint, "opened without a tap: the last line")
    }
}
