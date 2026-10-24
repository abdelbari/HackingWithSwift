// Round 33's Zoom to selection: the zoom and pan that frame the selection
// (Viewport.zoomToBox) and when it counts as small on screen
// (Viewport.isSmall) — the Android twin's Viewport rows — and the store's
// request to the canvas.

import XCTest
import CoreGraphics
@testable import Canvia

final class ZoomToSelectionTests: XCTestCase {

    /// Shared rows: box, viewport, fit, max → zoom, pan. 24 points of margin.
    func testTheBoxIsFramedWithItsMargin() {
        let rows: [(box: CGRect, viewport: CGSize, fit: Double, max: Double, zoom: Double, pan: CGPoint)] = [
            // Wider than tall: the width decides.
            (CGRect(x: 100, y: 100, width: 200, height: 100), CGSize(width: 400, height: 800), 0.3, 4,
             1.76, CGPoint(x: -152, y: 136)),
            // Tiny: held at the furthest zoom.
            (CGRect(x: 10, y: 10, width: 4, height: 4), CGSize(width: 400, height: 800), 0.3, 4,
             4, CGPoint(x: 152, y: 352)),
            // Bigger than the screen at fit: never below fit.
            (CGRect(x: 0, y: 0, width: 2000, height: 2000), CGSize(width: 400, height: 800), 0.3, 4,
             0.3, CGPoint(x: -100, y: 100)),
            // A straight line has no height: its width decides.
            (CGRect(x: 100, y: 500, width: 200, height: 0), CGSize(width: 400, height: 800), 0.3, 4,
             1.76, CGPoint(x: -152, y: -480)),
        ]
        for row in rows {
            let out = Viewport.zoomToBox(row.box, viewport: row.viewport, fit: row.fit, maxZoom: row.max)
            XCTAssertEqual(out.zoom, row.zoom, accuracy: 1e-9, "\(row.box)")
            XCTAssertEqual(Double(out.pan.x), Double(row.pan.x), accuracy: 1e-9, "\(row.box) x")
            XCTAssertEqual(Double(out.pan.y), Double(row.pan.y), accuracy: 1e-9, "\(row.box) y")
        }
        XCTAssertEqual(Viewport.selectionMargin, 24)
    }

    /// The box's middle lands in the middle of the screen.
    func testTheBoxIsCentred() {
        let box = CGRect(x: 300, y: 40, width: 50, height: 120)
        let screen = CGSize(width: 390, height: 700)
        let out = Viewport.zoomToBox(box, viewport: screen, fit: 0.36, maxZoom: 8)
        XCTAssertEqual(Double(out.pan.x) + Double(box.midX) * out.zoom, 195, accuracy: 1e-9)
        XCTAssertEqual(Double(out.pan.y) + Double(box.midY) * out.zoom, 350, accuracy: 1e-9)
        XCTAssertEqual(out.zoom, (700 - 48) / 120.0, accuracy: 1e-9, "the height decides")
    }

    /// Small is the longer side under 44 points on screen.
    func testSmallIsUnder44PointsOnScreen() {
        XCTAssertTrue(Viewport.isSmall(CGRect(x: 0, y: 0, width: 100, height: 40), zoom: 0.4))
        XCTAssertFalse(Viewport.isSmall(CGRect(x: 0, y: 0, width: 110, height: 40), zoom: 0.4), "44 is not under 44")
        XCTAssertFalse(Viewport.isSmall(CGRect(x: 0, y: 0, width: 300, height: 2), zoom: 0.4), "a long thin line")
        XCTAssertEqual(Viewport.smallSelection, 44)
    }

    @MainActor
    func testTheStoreAsksTheCanvasToFrameTheSelection() {
        var d = Design(title: "zoom", width: 1080, height: 1080)
        var dot = Element.shape("circle", w: 20, h: 20)
        dot.id = "dot"
        dot.x = 500
        dot.y = 500
        d.pages = [Page(elements: [dot])]
        let s = DesignStore(design: d)
        s.zoom = 0.36
        s.fitZoom = 0.36
        s.viewport = CGRect(x: 0, y: 0, width: 1080, height: 1800)
        XCTAssertFalse(s.selectionIsSmallOnScreen, "nothing selected")
        s.zoomToSelection()
        XCTAssertNil(s.canvasRequest, "nothing selected, nothing asked")
        s.select("dot")
        XCTAssertTrue(s.selectionIsSmallOnScreen)
        s.zoomToSelection()
        XCTAssertEqual(s.canvasRequest?.kind, .frame(CGRect(x: 500, y: 500, width: 20, height: 20)))
        XCTAssertEqual(DesignStore.zoomedToSelectionNote(2.5), "Zoomed to selection, 250 percent")
        XCTAssertEqual(s.selectionFrameZoom ?? 0, Geometry.zoomRange(fit: 0.36).upperBound, accuracy: 1e-9)
    }
}
