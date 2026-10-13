// Exit animations, as the Android twin has them: the evaluator's table, the
// file key written whole, exits combined with entrances, what counts as a
// page that moves, the Exit menu's step and stagger, and Present's clock
// held where the exits begin. The evaluator table is the same as the
// Android twin's.

import XCTest
import SwiftUI
@testable import Canvia

final class ExitAnimationTests: XCTestCase {

    // MARK: the shared table

    /// Kind, delay, duration, t, then opacity, dx, dy and scale, for a page
    /// held 3 s and an element of size 100. end = hold - delay, begin = end -
    /// duration, q = (t - begin) / duration and e = q^3: at q = 0.5, e =
    /// 0.125. Fade and rise fade by e; pop and the slides keep full opacity
    /// until e passes 0.5, as their entrances run the other way. The same
    /// rows as the Android twin's ElementAnimationTest.
    func testTheExitTable() {
        let rows: [(String, Double, Double, Double, Double, Double, Double, Double)] = [
            // before it begins: settled
            ("fade", 0, 0.6, 1.0, 1, 0, 0, 1),
            // half way: q = 0.5
            ("fade", 0, 0.6, 2.7, 0.875, 0, 0, 1),
            // at the end, and after it: gone
            ("fade", 0, 0.6, 3.0, 0, 0, 0, 1),
            ("fade", 0, 0.6, 5.0, 0, 0, 0, 1),
            // a delay of 0.5 s: over by 2.5 s, half way at 2.2 s
            ("fade", 0.5, 0.6, 1.9, 1, 0, 0, 1),
            ("fade", 0.5, 0.6, 2.2, 0.875, 0, 0, 1),
            ("fade", 0.5, 0.6, 2.5, 0, 0, 0, 1),
            // each kind at q = 0.5
            ("rise", 0, 0.6, 2.7, 0.875, 0, -3.75, 1),
            ("pop", 0, 0.6, 2.7, 1, 0, 0, 0.925),
            ("slideLeft", 0, 0.6, 2.7, 1, -12.5, 0, 1),
            ("slideRight", 0, 0.6, 2.7, 1, 12.5, 0, 1),
            // each kind at its end
            ("rise", 0, 0.6, 3.0, 0, 0, -30, 1),
            ("pop", 0, 0.6, 3.0, 0, 0, 0, 0.4),
            ("slideLeft", 0, 0.6, 3.0, 0, -100, 0, 1),
            ("slideRight", 0, 0.6, 3.0, 0, 100, 0, 1),
            // a kind from a newer build leaves as a fade
            ("spin", 0, 0.6, 2.7, 0.875, 0, 0, 1),
            // no length: settled until its end, gone from it
            ("fade", 0, 0, 2.9, 1, 0, 0, 1),
            ("fade", 0, 0, 3.0, 0, 0, 0, 1),
            // a length below nothing, from a file: still gone from its end
            ("fade", 1, -1, 1.5, 1, 0, 0, 1),
            ("fade", 1, -1, 2.5, 0, 0, 0, 1),
        ]
        for (kind, delay, duration, t, opacity, dx, dy, scale) in rows {
            let s = ElementAnimation(kind: kind, delay: delay, duration: duration).exitState(at: t, hold: 3, size: 100)
            let what = "\(kind) delay \(delay) at \(t)"
            XCTAssertEqual(s.opacity, opacity, accuracy: 1e-9, what + " opacity")
            XCTAssertEqual(s.offset.width, dx, accuracy: 1e-9, what + " dx")
            XCTAssertEqual(s.offset.height, dy, accuracy: 1e-9, what + " dy")
            XCTAssertEqual(s.scale, scale, accuracy: 1e-9, what + " scale")
            XCTAssertEqual(s.rotation, 0, what + " rotation")
            XCTAssertNil(s.visibleCharacters, what + " characters")
        }
    }

    func testBeforeItBeginsTheElementIsSettled() {
        let exit = ElementAnimation(kind: "rise", delay: 0, duration: 0.6)
        XCTAssertEqual(exit.exitState(at: 0, hold: 3, size: 100), .settled)
        XCTAssertEqual(exit.exitState(at: 2.3, hold: 3, size: 100), .settled)
    }

    func testTheExitIsCombinedWithTheEntrance() {
        let entrance = ElementAnimation(kind: "pop", delay: 0, duration: 4).state(at: 2, size: 100)
        let exit = ElementAnimation(kind: "rise", delay: 0, duration: 0.6).exitState(at: 2.7, hold: 3, size: 100)
        let both = entrance.combined(with: exit)
        XCTAssertEqual(both.opacity, entrance.opacity * 0.875, accuracy: 1e-9, "opacities multiply")
        XCTAssertEqual(both.scale, entrance.scale, accuracy: 1e-9, "scales multiply, by 1 here")
        XCTAssertEqual(both.offset.height, entrance.offset.height - 3.75, accuracy: 1e-9, "offsets add")
        let typed = ElementAnimation(kind: "typewriter", delay: 0, duration: 1).state(at: 0.5, text: "abcdefghij")
        XCTAssertEqual(typed.combined(with: exit).visibleCharacters, 5, "the entrance alone reveals text")
    }

    func testTheExitNames() {
        XCTAssertEqual(ElementAnimation.exitKinds, ["fade", "rise", "pop", "slideLeft", "slideRight"])
        XCTAssertEqual(ElementAnimation.exitName(nil), "No exit")
        XCTAssertEqual(ElementAnimation.exitKinds.map { ElementAnimation.exitName($0) },
                       ["Fade", "Rise", "Pop", "Slide left", "Slide right"])
        XCTAssertEqual(ElementAnimation.exitName("comet"), "Fade", "a kind from a newer build leaves as a fade")
    }

    // MARK: the file

    func testTheExitIsWrittenWholeAndOnlyWhenThere() throws {
        var el = Element.shape("rect")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        XCTAssertNil(json["exitAnimation"], "no exit, no key: every old design")
        el.exitAnimation = ElementAnimation(kind: "slideLeft", delay: 0, duration: 0.6)
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
        let exit = try XCTUnwrap(json["exitAnimation"] as? [String: Any])
        XCTAssertEqual(exit["kind"] as? String, "slideLeft")
        XCTAssertEqual(exit["delay"] as? Double, 0, "the default delay is still written")
        XCTAssertEqual(exit["duration"] as? Double, 0.6)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el)).exitAnimation, el.exitAnimation)
    }

    func testAnExitFromTheAndroidTwinIsRead() throws {
        let el = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e","type":"shape","exitAnimation":{"kind":"comet","delay":0.15,"duration":0.6}}"#.utf8))
        XCTAssertEqual(el.exitAnimation, ElementAnimation(kind: "comet", delay: 0.15, duration: 0.6),
                       "a kind this build does not know is kept, and plays as a fade")
        let broken = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e","type":"shape","exitAnimation":"fade"}"#.utf8))
        XCTAssertNil(broken.exitAnimation, "a value that is not an exit is no exit, not a failed design")
    }

    // MARK: what moves

    func testAPageWithAnExitMoves() {
        var d = Design(title: "x", width: 400, height: 300)
        var el = Element.shape("rect")
        d.pages[0].elements = [el]
        XCTAssertFalse(MovieExporter.isAnimated(d.pages[0], in: d))
        el.exitAnimation = ElementAnimation(kind: "fade", delay: 0, duration: 0.6)
        d.pages[0].elements = [el]
        XCTAssertTrue(MovieExporter.isAnimated(d.pages[0], in: d))
    }

    func testTheSpanIsTheLatestExitCappedAtTwoSeconds() {
        var a = Element.shape("rect"), b = Element.shape("rect")
        a.exitAnimation = ElementAnimation(kind: "fade", delay: 0, duration: 0.6)
        b.exitAnimation = ElementAnimation(kind: "pop", delay: 0.3, duration: 0.6)
        XCTAssertEqual(ElementAnimation.exitSpan([a, b, Element.shape("rect")]), 0.9, accuracy: 1e-9)
        XCTAssertEqual(ElementAnimation.exitSpan([Element.shape("rect")]), 0)
        b.exitAnimation = ElementAnimation(kind: "pop", delay: 3, duration: 0.6)
        XCTAssertEqual(ElementAnimation.exitSpan([a, b]), 2)
        // A hidden element leaves unseen, so its exit holds nothing back.
        a.hidden = true
        XCTAssertEqual(ElementAnimation.exitSpan([a]), 0)
    }

    // MARK: rendered

    /// A red square leaving by a fade over white: red until its exit begins,
    /// white at the page's end, and red again with no time, as a thumbnail.
    @MainActor
    func testAnExitIsDrawnAtTheEndOfThePageOnly() throws {
        var d = Design(title: "a", width: 100, height: 100)
        var el = Element.shape("rect", w: 100, h: 100)
        el.fill = .solid("#ff0000")
        el.exitAnimation = ElementAnimation(kind: "fade", delay: 0, duration: 1)
        d.pages[0].elements = [el]
        func green(at time: Double?) throws -> UInt8 {
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
            return px[1]
        }
        XCTAssertLessThan(try green(at: 0.5), 40, "still there before its exit")
        XCTAssertGreaterThan(try green(at: 2.0), 215, "gone at the end of the page")
        XCTAssertLessThan(try green(at: nil), 40, "a thumbnail has no time, and no exit")
    }

    // MARK: the editor

    @MainActor
    func testTheExitMenuIsOneUndoStaggeredSoTheFirstInIsTheLastOut() {
        var d = Design(title: "a", width: 400, height: 300)
        var locked = Element.shape("rect"); locked.locked = true
        d.pages[0].elements = [Element.shape("rect"), Element.shape("rect"), locked, Element.shape("rect")]
        let store = DesignStore(design: d)
        let ids = store.design.pages[0].elements.map(\.id)
        store.selection = Set(ids)
        store.exitSelected("rise")
        let exits = store.design.pages[0].elements.map(\.exitAnimation)
        XCTAssertEqual(exits[0], ElementAnimation(kind: "rise", delay: 0, duration: 0.6), "the first leaves last")
        XCTAssertEqual(exits[1], ElementAnimation(kind: "rise", delay: 0.15, duration: 0.6))
        XCTAssertNil(exits[2], "a locked element is left alone")
        XCTAssertEqual(exits[3]?.delay ?? 0, 0.3, accuracy: 1e-9)
        store.undo()
        XCTAssertTrue(store.design.pages[0].elements.allSatisfy { $0.exitAnimation == nil }, "one step")
        XCTAssertFalse(store.canUndo)
    }

    @MainActor
    func testNoExitTakesItAway() {
        var d = Design(title: "a", width: 400, height: 300)
        var el = Element.shape("rect")
        el.exitAnimation = ElementAnimation(kind: "pop", delay: 0, duration: 0.6)
        d.pages[0].elements = [el]
        let store = DesignStore(design: d)
        store.selection = [el.id]
        store.exitSelected(nil)
        XCTAssertNil(store.design.pages[0].elements[0].exitAnimation)
    }

    @MainActor
    func testThePreviewStartsHalfASecondBeforeTheExits() {
        var d = Design(title: "a", width: 400, height: 300)
        var el = Element.shape("rect")
        el.exitAnimation = ElementAnimation(kind: "pop", delay: 0.3, duration: 0.6)
        d.pages[0].elements = [el]
        d.pages[0].holdSeconds = 4
        let store = DesignStore(design: d)
        XCTAssertEqual(store.exitPreviewStart, 4 - 0.9 - 0.5, accuracy: 1e-9)
        store.design.pages[0].holdSeconds = 1
        XCTAssertEqual(store.exitPreviewStart, 0, "never before the page starts")
    }

    // MARK: present

    /// Present's clock for a page held 3 s, `after` seconds after it came
    /// up, the person having gone on `exitAfter` seconds after it did.
    /// The clock read `after` seconds into a page. It goes through Dates a
    /// billion seconds from their epoch, which hold a moment only to about a
    /// tenth of a microsecond, so its readings are compared to 1e-6.
    @MainActor
    private func time(_ after: Double, heldAt: Double? = nil, exitAfter: Double? = nil) throws -> Double {
        let start = Date(timeIntervalSince1970: 1000)
        let clock = PresentationView.clock(at: start.addingTimeInterval(after), from: start, hold: 3, playing: true,
                                           heldAt: heldAt,
                                           exitFrom: exitAfter.map { start.addingTimeInterval($0) })
        return try XCTUnwrap(clock).time
    }

    @MainActor
    func testPresentHoldsTheClockWhereTheExitsBeginUntilGoingOn() throws {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(try time(1), 1, accuracy: 1e-6, "no exits: the clock runs")
        XCTAssertEqual(try time(5), 5, accuracy: 1e-6)
        XCTAssertEqual(try time(1, heldAt: 2.4), 1, accuracy: 1e-6)
        XCTAssertEqual(try time(9, heldAt: 2.4), 2.4, accuracy: 1e-6, "held where the exits begin")
        XCTAssertEqual(try time(10, heldAt: 2.4, exitAfter: 9.7), 2.7, accuracy: 1e-6, "going on runs it on from there")
        XCTAssertEqual(try time(20, heldAt: 2.4, exitAfter: 9.7), 3, accuracy: 1e-6, "to the hold, no further")
        XCTAssertNil(PresentationView.clock(at: start, from: start, hold: 3, playing: false, heldAt: 2.4, exitFrom: nil))
    }

    /// Autoplay turned off once the exits of a page held 3 s, leaving over
    /// its last 0.6 s, have begun: the clock stays where it stood, rather
    /// than going back to 2.4 s and the elements that have left coming back.
    @MainActor
    func testTurningAutoplayOffKeepsTheClockWhereItStands() throws {
        XCTAssertNil(PresentationView.heldPoint(hold: 3, span: 0, stoppedAt: 2.8), "nothing leaves: never held")
        XCTAssertEqual(try XCTUnwrap(PresentationView.heldPoint(hold: 3, span: 0.6, stoppedAt: nil)), 2.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(PresentationView.heldPoint(hold: 3, span: 0.6, stoppedAt: 1)), 2.4, accuracy: 1e-9,
                       "stopped before the exits: held where they begin")
        let partway = try XCTUnwrap(PresentationView.heldPoint(hold: 3, span: 0.6, stoppedAt: 2.8))
        XCTAssertEqual(partway, 2.8, accuracy: 1e-9)
        XCTAssertEqual(try time(9, heldAt: partway), 2.8, accuracy: 1e-6, "partway out, it stays partway out")
        XCTAssertEqual(try time(10, heldAt: partway, exitAfter: 9.9), 2.9, accuracy: 1e-6, "going on runs it on from there")
        let atTheEnd = try XCTUnwrap(PresentationView.heldPoint(hold: 3, span: 0.6, stoppedAt: 3))
        XCTAssertEqual(try time(3.05, heldAt: atTheEnd), 3, accuracy: 1e-6, "at the last page's hold, gone stays gone")
    }
}
