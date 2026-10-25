// Present's pen, from the fixture both phones read
// (Fixtures/present_ink.json, the Android twin's PresentInkTest): its
// colours, widths and keys, how a stroke fades once lifted, and the ink
// drawn, lifted, kept until faded and cleared.

import XCTest
@testable import Canvia

final class PresentInkTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("present_ink") }

    func testColoursWidthsAndKeysMatchTheFixture() throws {
        let f = try fixture()
        XCTAssertEqual(PresentInk.colors, f["colors"] as? [String])
        XCTAssertEqual(PresentInk.widths, f["widths"] as? [Double])
        XCTAssertEqual(PresentInk.fadeAfter, f["fadeAfter"] as? Double)
        XCTAssertEqual(PresentInk.fadeSeconds, f["fadeSeconds"] as? Double)
        let keys = try XCTUnwrap(f["keys"] as? [String: String])
        XCTAssertEqual(PresentInk.laserKey, keys["laser"])
        XCTAssertEqual(PresentInk.penKey, keys["pen"])
        XCTAssertEqual(PresentInk.clearKey, keys["clear"])
        // No magic shortcut is played by the pen's keys.
        for key in [PresentInk.laserKey, PresentInk.penKey, PresentInk.clearKey] {
            XCTAssertNil(Presenter.effect(forKey: key), key)
        }
        XCTAssertEqual(PresentInk.colorNames.count, 3)
        XCTAssertEqual(PresentInk.widthNames.count, 3)
        XCTAssertEqual(PresentInk.fadePref, "presentInkFade")
    }

    func testAStrokeFades3SecondsAfterItIsLiftedWhileFadeInkIsOn() throws {
        for row in try XCTUnwrap(try fixture()["alpha"] as? [[String: Any]]) {
            let stroke = PresentInk.Stroke(points: [.zero], liftedAt: row["liftedAt"] as? Double)
            let now = try XCTUnwrap(row["now"] as? Double)
            let fade = try XCTUnwrap(row["fade"] as? Bool)
            let expected = try XCTUnwrap(row["alpha"] as? Double)
            XCTAssertEqual(PresentInk.alpha(stroke, now: now, fade: fade), expected, accuracy: 1e-9, "\(row)")
        }
    }

    func testAStrokesWidthIsAShareOfThePagesShorterSide() throws {
        let w = try XCTUnwrap(try fixture()["width"] as? [String: Any])
        let page = try XCTUnwrap(w["page"] as? [Double])
        let stroke = PresentInk.Stroke(points: [], width: try XCTUnwrap(w["stroke"] as? Int))
        XCTAssertEqual(PresentInk.width(stroke, page: CGSize(width: page[0], height: page[1])),
                       try XCTUnwrap(w["points"] as? Double), accuracy: 1e-9)
    }

    func testStrokesAreDrawnLiftedKeptUntilFadedAndCleared() {
        var ink = PresentInk.Ink()
        ink = ink.extended(to: CGPoint(x: 1, y: 1))
        XCTAssertTrue(ink.strokes.isEmpty)
        ink = ink.started(at: .zero, color: 2, width: 0)
            .extended(to: CGPoint(x: 10, y: 0))
            .extended(to: CGPoint(x: 20, y: 5))
        XCTAssertEqual(ink.strokes.count, 1)
        XCTAssertEqual(ink.strokes[0].points.count, 3)
        XCTAssertEqual(PresentInk.color(ink.strokes[0]), "#ffffff")
        XCTAssertFalse(ink.fading(true))
        ink = ink.lifted(at: 1)
        // Lifted, nothing more is added to it.
        XCTAssertEqual(ink, ink.extended(to: CGPoint(x: 30, y: 0)))
        XCTAssertTrue(ink.fading(true))
        XCTAssertFalse(ink.fading(false))
        ink = ink.started(at: CGPoint(x: 5, y: 5), color: 0, width: 1).lifted(at: 3)
        XCTAssertEqual(ink.kept(at: 4.2, fade: true).strokes.count, 2)
        XCTAssertEqual(ink.kept(at: 4.5, fade: true).strokes.count, 1)
        XCTAssertEqual(ink.kept(at: 100, fade: false).strokes.count, 2)
        // Smoothed as a drawn line is in the editor.
        XCTAssertNotNil(Freehand.segments(ink.strokes[0].points))
    }

    /// A finger on the slide: with the pen on it draws, and the touch is no
    /// tap; held, it points; with Laser lock it points at once; lifted, the
    /// dot goes and the stroke is done. Ink goes with the page.
    @MainActor
    func testAFingerDrawsWithThePenAndPointsWhenHeld() {
        var design = Design(title: "Talk", width: 1000, height: 500)
        design.pages = [Page(), Page()]
        let session = PresentSession(design: design)
        let size = CGSize(width: 1000, height: 500)

        session.touched(at: CGPoint(x: 100, y: 100), moved: .zero, held: false, in: size)
        XCTAssertNil(session.pointer, "a touch not yet held points at nothing")
        XCTAssertFalse(session.heldThisTouch)
        session.touched(at: CGPoint(x: 100, y: 100), moved: .zero, held: true, in: size)
        XCTAssertEqual(session.pointer, CGPoint(x: 100, y: 100))
        XCTAssertTrue(session.heldThisTouch, "a hold is no tap")
        session.released()
        XCTAssertNil(session.pointer)

        session.laserLock = true
        session.touched(at: CGPoint(x: 200, y: 50), moved: .zero, held: false, in: size)
        XCTAssertEqual(session.pointer, CGPoint(x: 200, y: 50))
        XCTAssertFalse(session.heldThisTouch, "with Laser lock a tap still taps")
        session.released()

        session.penOn = true
        session.penColor = 1
        session.touched(at: CGPoint(x: 10, y: 10), moved: .zero, held: false, in: size)
        session.touched(at: CGPoint(x: 30, y: 20), moved: CGSize(width: 20, height: 10), held: false, in: size)
        XCTAssertTrue(session.heldThisTouch)
        XCTAssertNil(session.pointer)
        session.released()
        XCTAssertEqual(session.ink.strokes.count, 1)
        XCTAssertEqual(session.ink.strokes[0].points, [CGPoint(x: 10, y: 10), CGPoint(x: 30, y: 20)])
        XCTAssertEqual(session.ink.strokes[0].color, 1)
        XCTAssertNotNil(session.ink.strokes[0].liftedAt)
        // A new touch is a new stroke.
        session.touched(at: CGPoint(x: 50, y: 50), moved: .zero, held: false, in: size)
        session.released()
        XCTAssertEqual(session.ink.strokes.count, 2)
    }
}
