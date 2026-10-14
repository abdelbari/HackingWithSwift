// Per-page timing and transitions, the GIF budget, and margins; and the
// editor's timeline: its blocks, a dragged edge's hold, Split page's
// arithmetic, and elements shown for part of their page. The timeline's rows
// are the same as the Android twin's MovieTest.

import XCTest
import CoreGraphics
@testable import Canvia

final class TimelineTests: XCTestCase {

    private func design(holds: [Double?], transitions: [String?] = []) -> Design {
        var d = Design(title: "t", width: 400, height: 300)
        d.pages = holds.enumerated().map { i, hold in
            var p = Page()
            p.holdSeconds = hold
            p.transition = i < transitions.count ? transitions[i] : nil
            return p
        }
        return d
    }

    private var settings: MovieExporter.Settings {
        var s = MovieExporter.Settings()
        s.secondsPerPage = 2
        s.fps = 10
        s.crossfade = 0.5
        return s
    }

    func testEachPageHoldsForItsOwnTime() {
        let timeline = MovieExporter.timeline(design: design(holds: [nil, 4, 0.5]), settings: settings)
        XCTAssertEqual(timeline.map(\.frames), [20, 40, 5])
        XCTAssertEqual(timeline.map(\.start), [0, 20, 60])
        XCTAssertEqual(MovieExporter.frameCount(design: design(holds: [nil, 4, 0.5]), settings: settings), 65)
        XCTAssertEqual(MovieExporter.uniformTimeline(pages: 3, settings: settings).map(\.start), [0, 20, 40])
    }

    func testLocateFindsThePageAndHowFarThroughIt() {
        let timeline = MovieExporter.timeline(design: design(holds: [nil, 4]), settings: settings)
        let a = MovieExporter.locate(frame: 0, in: timeline)
        XCTAssertEqual(a.page, 0); XCTAssertEqual(a.progress, 0); XCTAssertEqual(a.remaining, 20)
        let b = MovieExporter.locate(frame: 30, in: timeline)
        XCTAssertEqual(b.page, 1); XCTAssertEqual(b.progress, 0.25, accuracy: 0.001); XCTAssertEqual(b.remaining, 30)
        let past = MovieExporter.locate(frame: 999, in: timeline)
        XCTAssertEqual(past.page, 1, "past the end is the last page")
    }

    func testTransitionsFallBackToTheDocument() {
        let timeline = MovieExporter.timeline(design: design(holds: [nil, nil, nil], transitions: ["slide", nil, "cut"]),
                                              settings: settings)
        XCTAssertEqual(timeline.map(\.transition), ["slide", "fade", "cut"])
        var cut = settings; cut.crossfade = 0
        XCTAssertEqual(MovieExporter.timeline(design: design(holds: [nil]), settings: cut)[0].transition, "cut")
    }

    /// Rendered: a page in white cutting to a page in black shows no grey in
    /// the last frame before the cut; a fade does.
    func testACutShowsNoBlendAndAFadeDoes() throws {
        let size = CGSize(width: 40, height: 30)
        func solid(_ gray: CGFloat) -> CGImage {
            let ctx = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(gray: gray, alpha: 1); ctx.fill(CGRect(origin: .zero, size: size))
            return ctx.makeImage()!
        }
        let pages = [solid(1), solid(0)]
        var s = settings; s.zoom = 0
        func centre(_ transition: String) throws -> UInt8 {
            var d = design(holds: [1, 1], transitions: [transition, nil])
            d.pages[0].transition = transition
            let timings = MovieExporter.timeline(design: d, settings: s)
            var px = [UInt8](repeating: 0, count: 40 * 30 * 4)
            try px.withUnsafeMutableBytes { raw in
                let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: 40, height: 30, bitsPerComponent: 8,
                                                  bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                // Two frames before the hand-over: deep in a 5-frame overlap.
                MovieExporter.draw(frame: 8, pages: pages, size: size, settings: s, timings: timings, into: ctx)
            }
            return px[(15 * 40 + 20) * 4]
        }
        XCTAssertEqual(try centre("cut"), 255, "a cut shows the first page untouched until the last frame")
        let faded = try centre("fade")
        XCTAssertTrue(faded > 20 && faded < 235, "a fade blends: \(faded)")
        let slid = try centre("slide")
        XCTAssertTrue(slid == 0 || slid == 255, "a slide shows one page or the other at any pixel, never a blend: \(slid)")
    }

    // MARK: gif

    func testTheGIFPlanShrinksToFitTheBudgetAndKeepsHonestDelays() {
        let short = MovieExporter.gifPlan(design: design(holds: [1]), settings: settings)
        XCTAssertEqual(short.maxEdge, 640)
        XCTAssertEqual(short.fps, 20)
        let long = MovieExporter.gifPlan(design: design(holds: [30, 30, 30, 30]), settings: settings)
        XCTAssertLessThan(long.maxEdge, 640)
        let tiny = MovieExporter.gifPlan(design: design(holds: [30, 30, 30, 30]), settings: settings, budget: 1)
        XCTAssertEqual(tiny, MovieExporter.GIFPlan(maxEdge: 240, fps: 10), "nothing fits: the smallest plan, not a crash")
        for fps in [short.fps, long.fps, tiny.fps] {
            let centiseconds = 100.0 / Double(fps)
            XCTAssertEqual(centiseconds, centiseconds.rounded(), "\(fps)fps is not a whole number of hundredths")
        }
    }

    // MARK: margins

    func testMarginsSnapAndScaleWithTheShortSide() {
        var s = SnapSettings(toPage: false, toElements: false)
        s.margin = 0.05
        let d = Design(title: "m", width: 1000, height: 400)
        XCTAssertEqual(s.marginInset(for: d), 20)
        let lines = Geometry.snapLines(design: d, page: Page(), excluding: [], settings: s)
        XCTAssertEqual(lines.x, [20, 980])
        XCTAssertEqual(lines.y, [20, 380])
        XCTAssertTrue(Geometry.snapLines(design: d, page: Page(), excluding: [],
                                         settings: SnapSettings(toPage: false, toElements: false)).x.isEmpty)
    }

    // MARK: the editor's timeline — shared rows, the same as Android's MovieTest

    /// Holds, points a second, then each block's x and width: side by side
    /// from 0, no gap, each as wide as its hold at the scale.
    func testBlocksSitSideBySideAsWideAsTheirHolds() {
        let rows: [([Double], Double, [Double], [Double])] = [
            ([2.5, 4, 0.5], 10, [0, 25, 65], [25, 40, 5]),
            ([1, 2], 12, [0, 12], [12, 24]),
            ([60], 2, [0], [120]),
            ([2.5, 1, 4], 20, [0, 50, 70], [50, 20, 80]),
            ([], 10, [], []),
        ]
        for (holds, scale, xs, widths) in rows {
            let blocks = Timeline.blocks(holds: holds, scale: scale)
            XCTAssertEqual(blocks.map(\.x), xs, "\(holds) at \(scale)")
            XCTAssertEqual(blocks.map(\.width), widths, "\(holds) at \(scale)")
        }
    }

    /// Hold, points dragged, points a second, then the hold set: to the
    /// nearest tenth, within 0.5...60.
    func testADraggedEdgeSetsTheHoldToATenthWithinItsRange() {
        let rows: [(Double, Double, Double, Double)] = [
            (2, 13, 10, 3.3),
            (2, -4, 10, 1.6),
            (2, 0.4, 10, 2.0),
            (2, 0.6, 10, 2.1),
            (2.5, 30, 12, 5.0),
            (2, -100, 10, 0.5),
            (59, 200, 10, 60),
            (2.5, 0, 20, 2.5),
            (2.5, 13.4, 20, 3.2),
            (2.5, -40, 20, 0.5),
            (3, 12, 40, 3.3),
        ]
        for (hold, dx, scale, expected) in rows {
            XCTAssertEqual(Timeline.draggedHold(hold, by: dx, scale: scale), expected, accuracy: 1e-9,
                           "\(hold) dragged \(dx) at \(scale)")
        }
    }

    /// Holds, a moment in the film, then the page it falls on and how far
    /// into it, not rounded. A page owns its start, not its end; the film's
    /// ends hold.
    func testAMomentFallsOnAPage() {
        let rows: [([Double], Double, Int, Double)] = [
            ([2, 3, 1], -1, 0, 0), ([2, 3, 1], 0, 0, 0), ([2, 3, 1], 1.5, 0, 1.5), ([2, 3, 1], 2, 1, 0),
            ([2, 3, 1], 4.5, 1, 2.5), ([2, 3, 1], 5, 2, 0), ([2, 3, 1], 6, 2, 1), ([2, 3, 1], 9, 2, 1),
            ([2.5, 1, 4], 1.23, 0, 1.23), ([2.5, 1, 4], 2.5, 1, 0), ([2.5, 1, 4], 3.46, 1, 0.96),
            ([2.5, 1, 4], 3.5, 2, 0), ([2.5, 1, 4], 7.5, 2, 4), ([2.5, 1, 4], 99, 2, 4),
        ]
        for (holds, t, page, time) in rows {
            let spot = Timeline.locate(t, holds: holds)
            XCTAssertEqual(spot.page, page, "page at \(t) in \(holds)")
            XCTAssertEqual(spot.time, time, accuracy: 1e-9, "time at \(t) in \(holds)")
        }
        XCTAssertEqual(Timeline.locate(3, holds: []).page, 0)
    }

    /// Hold, cut, then the two holds, or nil: the cut to the tenth first,
    /// the rest to the tenth too, and each part at least half a second.
    func testSplitHolds() {
        let rows: [(Double, Double, (Double, Double)?)] = [
            (3, 1.2, (1.2, 1.8)),
            (3, 0.5, (0.5, 2.5)),
            (3, 2.5, (2.5, 0.5)),
            (3, 1.23, (1.2, 1.8)),
            (3, 0.46, (0.5, 2.5)),
            (1, 0.5, (0.5, 0.5)),
            (2.5, 1.2, (1.2, 1.3)),
            (5, 2, (2, 3)),
            (10, 0.5, (0.5, 9.5)),
            (2.5, 2, (2, 0.5)),
            (3, 0.4, nil),
            (3, 2.6, nil),
            (2.5, 2.1, nil),
            (0.9, 0.5, nil),
        ]
        for (hold, t, expected) in rows {
            let holds = Timeline.splitHolds(hold: hold, at: t)
            if let expected {
                XCTAssertEqual(holds?.first ?? -1, expected.0, accuracy: 1e-9, "\(hold) at \(t)")
                XCTAssertEqual(holds?.second ?? -1, expected.1, accuracy: 1e-9, "\(hold) at \(t)")
            } else {
                XCTAssertNil(holds, "\(hold) at \(t)")
            }
        }
    }

    /// Clip start, end, speed, loop, file length, cut, then where the clip
    /// starts on the second page: VideoStore.clipTime at the cut — t x speed
    /// on, round again within the trim when it loops, a hundredth short of
    /// its end when it does not, straight on with no known end — to the
    /// hundredth.
    func testAClipPicksUpWhereTheSplitLeftIt() {
        let rows: [(Double, Double?, Double, Bool, Double?, Double, Double)] = [
            (0, nil, 1, true, nil, 2, 2),
            (1, nil, 2, false, nil, 1.5, 4),
            (1, 3, 1, true, nil, 3, 2),
            (0, nil, 1, true, 5, 7, 2),
            (0, 4, 1, false, 10, 6, 3.99),
            (2, nil, 0.5, true, 10, 4, 4),
            (1, 1.005, 1, true, nil, 2, 1),
            (0, nil, 1.5, true, 2, 1.2, 1.8),
            (0.123, nil, 1, false, nil, 1, 1.12),
            (1, nil, 1.5, true, nil, 2, 4),
            (0, 3, 1, true, 10, 4, 1),
            (1, 3, 2, true, 10, 1.5, 2),
            (0, nil, 1, true, 2.5, 3, 0.5),
        ]
        for (start, end, speed, loop, duration, t, expected) in rows {
            let clip = ClipPlayback(start: start, end: end, speed: speed, loop: loop)
            XCTAssertEqual(Timeline.advancedClipStart(clip, by: t, duration: duration), expected, accuracy: 1e-9,
                           "start \(start) end \(String(describing: end)) speed \(speed) loop \(loop) at \(t)")
        }
    }

    /// Timing, moment, then whether the element shows: from its start,
    /// gone at its end; always with no timing.
    func testAnElementShowsWithinItsTiming() {
        let rows: [(ElementTiming?, Double, Bool)] = [
            (nil, 0, true), (nil, 100, true),
            (ElementTiming(start: 1), 0.99, false), (ElementTiming(start: 1), 1, true), (ElementTiming(start: 1), 100, true),
            (ElementTiming(start: 0, end: 2), 0, true), (ElementTiming(start: 0, end: 2), 1.99, true),
            (ElementTiming(start: 0, end: 2), 2, false),
            (ElementTiming(start: 1, end: 2), 0.5, false), (ElementTiming(start: 1, end: 2), 1.5, true),
            (ElementTiming(start: 1, end: 2), 2.5, false),
            (ElementTiming(start: 2, end: 2), 2, false), (ElementTiming(start: 0, end: 0), 0, false),
        ]
        for (timing, t, shows) in rows {
            XCTAssertEqual(ElementTiming.shows(timing, at: t), shows, "\(String(describing: timing)) at \(t)")
        }
    }

    /// Show and Hide from playhead: to the tenth; an end at or before a new
    /// start dropped, a start at or after a new end back to 0; the whole
    /// page is no timing; hiding from the very start changes nothing.
    func testShowAndHideFromThePlayhead() {
        XCTAssertEqual(ElementTiming.showing(nil, from: 1.23), ElementTiming(start: 1.2))
        XCTAssertEqual(ElementTiming.showing(ElementTiming(start: 0, end: 3), from: 1), ElementTiming(start: 1, end: 3))
        XCTAssertEqual(ElementTiming.showing(ElementTiming(start: 0, end: 3), from: 3), ElementTiming(start: 3))
        XCTAssertEqual(ElementTiming.showing(ElementTiming(start: 0, end: 1), from: 2), ElementTiming(start: 2))
        XCTAssertEqual(ElementTiming.showing(ElementTiming(start: 1, end: 3), from: 0), ElementTiming(start: 0, end: 3))
        XCTAssertEqual(ElementTiming.showing(ElementTiming(start: 1, end: 2), from: 0.04), ElementTiming(start: 0, end: 2))
        XCTAssertNil(ElementTiming.showing(ElementTiming(start: 1), from: 0))
        XCTAssertNil(ElementTiming.showing(nil, from: 0))
        XCTAssertEqual(ElementTiming.hiding(nil, from: 2.5), ElementTiming(start: 0, end: 2.5))
        XCTAssertEqual(ElementTiming.hiding(ElementTiming(start: 1), from: 3), ElementTiming(start: 1, end: 3))
        XCTAssertEqual(ElementTiming.hiding(ElementTiming(start: 2), from: 1.5), ElementTiming(start: 0, end: 1.5))
        XCTAssertEqual(ElementTiming.hiding(ElementTiming(start: 1, end: 4), from: 0.02), ElementTiming(start: 1, end: 4))
        XCTAssertNil(ElementTiming.hiding(nil, from: 0))
    }

    /// Timing, cut, then its timing on the second page: moved earlier by
    /// the cut, to the tenth, none before the page's start; one over before
    /// the cut never shows; the whole page is no timing.
    func testTimingsMoveEarlierOnTheSecondPage() {
        let rows: [(ElementTiming, Double, ElementTiming?)] = [
            (ElementTiming(start: 2, end: 3), 1.5, ElementTiming(start: 0.5, end: 1.5)),
            (ElementTiming(start: 0, end: 1), 1.5, ElementTiming(start: 0, end: 0)),
            (ElementTiming(start: 3), 1.5, ElementTiming(start: 1.5)),
            (ElementTiming(start: 1), 1.5, nil),
            (ElementTiming(start: 1, end: 3), 2, ElementTiming(start: 0, end: 1)),
            (ElementTiming(start: 2.5), 1, ElementTiming(start: 1.5)),
            (ElementTiming(start: 1.23, end: 3.47), 1, ElementTiming(start: 0.2, end: 2.5)),
        ]
        for (timing, t, expected) in rows {
            XCTAssertEqual(Timeline.shiftedTiming(timing, by: t), expected, "\(timing) by \(t)")
        }
        XCTAssertNil(Timeline.shiftedTiming(nil, by: 1.5))
        XCTAssertFalse(ElementTiming.shows(ElementTiming(start: 0, end: 0), at: 0))
    }

    // MARK: split page

    /// Timing, cut, then whether the entrance stays on the second page and
    /// the exit on the first: an element coming in at the cut or after keeps
    /// its entrance; one gone at the cut or before keeps its exit.
    func testATimedElementKeepsItsEntranceOrExitWhereItPlays() throws {
        let rows: [(ElementTiming?, Double, Bool, Bool)] = [
            (nil, 1.5, false, false),
            (ElementTiming(start: 4), 3, true, false),
            (ElementTiming(start: 3), 3, true, false),
            (ElementTiming(start: 2.9), 3, false, false),
            (ElementTiming(start: 0, end: 2), 4, false, true),
            (ElementTiming(start: 0, end: 4), 4, false, true),
            (ElementTiming(start: 1, end: 4.1), 4, false, false),
            (ElementTiming(start: 4, end: 5), 3, true, false),
        ]
        for (timing, cut, entrance, exit) in rows {
            let name = "\(String(describing: timing)) at \(cut)"
            XCTAssertEqual(Timeline.entranceStaysAfter(timing, cut: cut), entrance, name)
            XCTAssertEqual(Timeline.exitStaysBefore(timing, cut: cut), exit, name)
        }
        // On a page split at 3: a title coming in at 4 still fades in, and
        // one gone at 2 still fades out.
        func animated(_ timing: ElementTiming) -> Element {
            var el = Element.text("Hi")
            el.animation = ElementAnimation(kind: "fade", delay: 0, duration: 1)
            el.exitAnimation = ElementAnimation(kind: "fade", delay: 0, duration: 0.5)
            el.timing = timing
            return el
        }
        var page = Page()
        page.elements = [animated(ElementTiming(start: 4)), animated(ElementTiming(start: 0, end: 2))]
        let parts = try XCTUnwrap(Timeline.split(page, at: 3, hold: 6, duration: { _ in nil }))
        XCTAssertEqual(parts.second.elements[0].animation?.kind, "fade")
        XCTAssertEqual(parts.second.elements[0].timing, ElementTiming(start: 1))
        XCTAssertNil(parts.first.elements[0].exitAnimation)
        XCTAssertEqual(parts.first.elements[1].exitAnimation?.kind, "fade")
        XCTAssertNil(parts.second.elements[1].animation)
    }

    func testSplitPageMakesTwoPagesThatPlayAsOne() throws {
        var page = Page()
        page.holdSeconds = 4
        page.transition = "slide"
        page.transitionSeconds = 1
        var title = Element.text("Hello")
        title.animation = ElementAnimation(kind: "rise", delay: 0, duration: 0.6)
        title.exitAnimation = ElementAnimation(kind: "fade", delay: 0, duration: 0.6)
        var star = Element.sticker("★")
        star.animation = ElementAnimation(kind: "pulse", delay: 0, duration: 0.6)
        star.timing = ElementTiming(start: 2, end: 3)
        var clip = Element.image("video:abc")
        clip.clip = ClipPlayback(start: 1, speed: 2, loop: false)
        var still = Element.image("video:still")
        still.clip = nil
        page.elements = [title, star, clip, still]

        let parts = try XCTUnwrap(Timeline.split(page, at: 1.5, hold: 4, duration: { $0 == "abc" ? 20 : 10 }))
        let first = parts.first, second = parts.second

        XCTAssertEqual(first.id, page.id, "the first part is the page")
        XCTAssertEqual(first.elements.map(\.id), page.elements.map(\.id))
        XCTAssertEqual(first.holdSeconds, 1.5)
        XCTAssertEqual(first.transition, "cut", "no transition between the parts: a cut")
        XCTAssertNil(first.transitionSeconds)
        XCTAssertEqual(first.elements[0].animation?.kind, "rise", "entrances stay on the first part")
        XCTAssertNil(first.elements[0].exitAnimation, "exits leave the first part")
        XCTAssertEqual(first.elements[1].timing, ElementTiming(start: 2, end: 3))
        XCTAssertEqual(first.elements[2].clip?.start, 1)

        XCTAssertNotEqual(second.id, page.id)
        XCTAssertTrue(Set(second.elements.map(\.id)).isDisjoint(with: page.elements.map(\.id)), "new ids")
        XCTAssertEqual(second.elements.count, 4, "both parts keep every element")
        XCTAssertEqual(second.holdSeconds, 2.5)
        XCTAssertEqual(second.transition, "slide", "the second part hands over as the page did")
        XCTAssertEqual(second.transitionSeconds, 1)
        XCTAssertNil(second.elements[0].animation, "entrances leave the second part")
        XCTAssertEqual(second.elements[0].exitAnimation?.kind, "fade", "exits stay on the second part")
        XCTAssertEqual(second.elements[1].animation?.kind, "pulse", "a loop is no entrance: it plays on both")
        XCTAssertEqual(second.elements[1].timing, ElementTiming(start: 0.5, end: 1.5))
        XCTAssertEqual(second.elements[2].clip?.start, 4, "1 + 1.5 s at double speed")
        XCTAssertEqual(second.elements[2].clip?.speed, 2)
        XCTAssertEqual(second.elements[3].clip?.start, 1.5, "a clip at its defaults picks up too")

        XCTAssertNil(Timeline.split(page, at: 0.3, hold: 4, duration: { _ in nil }))
        XCTAssertNil(Timeline.split(page, at: 3.7, hold: 4, duration: { _ in nil }))
    }

    // MARK: element timing in the file

    func testTimingIsReadAndWrittenWithTheSharedKeys() throws {
        let read = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e1","type":"shape","timing":{"start":1.5,"end":4}}"#.utf8))
        XCTAssertEqual(read.timing, ElementTiming(start: 1.5, end: 4))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(read)) as? [String: Any])
        let timing = try XCTUnwrap(json["timing"] as? [String: Any])
        XCTAssertEqual(timing["start"] as? Double, 1.5)
        XCTAssertEqual(timing["end"] as? Double, 4)

        var open = Element()
        open.timing = ElementTiming(start: 2)
        let openJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(open)) as? [String: Any])
        XCTAssertEqual((openJSON["timing"] as? [String: Any])?.keys.sorted(), ["start"], "no end is no key")

        let nullEnd = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e1","type":"shape","timing":{"start":2,"end":null}}"#.utf8))
        XCTAssertEqual(nullEnd.timing, ElementTiming(start: 2))

        let whole = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e1","type":"shape","timing":{"start":0}}"#.utf8))
        XCTAssertNil(whole.timing, "the whole page is no timing")
        let plain = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(Element())) as? [String: Any])
        XCTAssertNil(plain["timing"])

        let odd = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e1","type":"shape","timing":{"start":"soon","end":3}}"#.utf8))
        XCTAssertEqual(odd.timing, ElementTiming(start: 0, end: 3), "a start that cannot be read is the page's start")
        let early = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e1","type":"shape","timing":{"start":-1,"end":2}}"#.utf8))
        XCTAssertEqual(early.timing, ElementTiming(start: 0, end: 2), "a start below the page's is its start")
    }

    // MARK: playing a timed element

    func testATimedElementComesAndGoesWithItsAnimations() {
        var el = Element()
        el.timing = ElementTiming(start: 1, end: 3)
        el.animation = ElementAnimation(kind: "fade", delay: 0, duration: 1)
        el.exitAnimation = ElementAnimation(kind: "fade", delay: 0, duration: 0.5)
        func opacity(_ e: Element, _ t: Double, hold: Double = 5, exitTime: Double? = nil) -> Double {
            Timeline.motion(of: e, time: t, hold: hold, exitTime: exitTime, text: nil).opacity
        }
        XCTAssertEqual(opacity(el, 0.5), 0, "not yet shown")
        XCTAssertEqual(opacity(el, 1.5), 0.875, accuracy: 1e-9, "the entrance counts from the start")
        XCTAssertEqual(opacity(el, 2.75), 0.875, accuracy: 1e-9, "the exit ends at the end")
        XCTAssertEqual(opacity(el, 2.75, exitTime: 0), 0.875, accuracy: 1e-9, "played on the page's own clock")
        XCTAssertEqual(opacity(el, 3), 0, "gone at the end")
        XCTAssertEqual(opacity(el, 4), 0)

        var delayed = el
        delayed.exitAnimation = ElementAnimation(kind: "fade", delay: 0.2, duration: 0.5)
        XCTAssertEqual(opacity(delayed, 2.75), 0.875, accuracy: 1e-9, "over at the end whatever its delay")
        XCTAssertEqual(opacity(el, 2.25, hold: 2.5), 0.875, accuracy: 1e-9, "a page that ends first ends the exit")
        XCTAssertEqual(opacity(delayed, 2.25, hold: 2.5), 0.875, accuracy: 1e-9)
        XCTAssertEqual(opacity(el, 2.5, hold: 2.5), 0, accuracy: 1e-9)

        var untimed = el
        untimed.timing = nil
        XCTAssertEqual(opacity(untimed, 0.5), 0.875, accuracy: 1e-9)
        XCTAssertEqual(opacity(untimed, 4.75), 0.875, accuracy: 1e-9, "an untimed exit ends at the hold")
        XCTAssertEqual(opacity(untimed, 4.75, exitTime: 0), 1, accuracy: 1e-9, "on the exits' clock")
    }

    @MainActor
    func testATimedElementMakesThePagePlayAndLeavesOnItsOwn() {
        var d = Design(title: "t", width: 400, height: 300)
        var el = Element()
        d.pages = [Page(elements: [el])]
        XCTAssertFalse(MovieExporter.isAnimated(d.pages[0], in: d))
        el.timing = ElementTiming(start: 1)
        d.pages[0].elements = [el]
        XCTAssertTrue(MovieExporter.isAnimated(d.pages[0], in: d), "drawn frame by frame, to come in at its time")
        XCTAssertTrue(PresentSession.moves(d.pages[0], in: d))

        var leaving = Element()
        leaving.exitAnimation = ElementAnimation(kind: "fade", delay: 0, duration: 0.6)
        leaving.timing = ElementTiming(start: 0, end: 2)
        XCTAssertEqual(ElementAnimation.exitSpan([leaving]), 0, "it leaves at its own end, not as the page ends")
        leaving.timing = nil
        XCTAssertEqual(ElementAnimation.exitSpan([leaving]), 0.6, accuracy: 1e-9)
    }

    // MARK: the store

    private func store(holds: [Double]) -> DesignStore {
        var d = Design(title: "t", width: 400, height: 300)
        d.pages = holds.map { hold in
            var p = Page(elements: [Element()])
            p.holdSeconds = hold
            return p
        }
        return DesignStore(design: d)
    }

    func testDraggingAnEdgeIsOneUndo() {
        let s = store(holds: [2, 3])
        let id = s.design.pages[0].id
        s.dragHold(of: id, to: 2.5)
        s.dragHold(of: id, to: 3.1)
        s.commit()
        XCTAssertEqual(s.design.pages[0].holdSeconds, 3.1)
        s.undo()
        XCTAssertEqual(s.design.pages[0].holdSeconds, 2)
        XCTAssertFalse(s.canUndo, "the whole drag was one step")
    }

    func testScrubbingShowsThePageUnderThePlayheadAtThatMoment() {
        let s = store(holds: [2, 3])
        s.beginScrub()
        s.scrub(to: 2.5)
        XCTAssertEqual(s.pageIndex, 1)
        XCTAssertEqual(s.previewTime ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.playheadInPage ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertFalse(s.previewRuns, "a scrub's clock stands still, so no clip plays on")
        s.scrub(to: 99)
        XCTAssertEqual(s.filmPlayhead ?? -1, 5, accuracy: 1e-9, "kept to the film")
        XCTAssertEqual(s.previewTime ?? -1, 3, accuracy: 1e-9)
        s.endScrub()
        XCTAssertNil(s.previewTime, "the canvas at rest once the scrub ends")
        XCTAssertEqual(s.playheadInPage ?? -1, 3, accuracy: 1e-9, "the playhead stays")
        XCTAssertFalse(s.canUndo, "scrubbing changes nothing")

        s.selectTimelinePage(0)
        XCTAssertEqual(s.pageIndex, 0)
        XCTAssertEqual(s.playheadInPage, 0, "brought to the page tapped")
        XCTAssertEqual(s.filmPlayhead, 0)
    }

    /// The playhead is kept as a page and how far into it: a page before it
    /// held longer leaves it where it stands, and a page held shorter keeps
    /// it within its hold.
    func testThePlayheadStaysOnItsPageWhenAHoldChanges() {
        let s = store(holds: [2.5, 3])
        s.scrub(to: 3.5)
        s.endScrub()
        XCTAssertEqual(s.pageIndex, 1)
        s.dragHold(of: s.design.pages[0].id, to: 3.5)
        s.commit()
        XCTAssertEqual(s.pageIndex, 1)
        XCTAssertEqual(s.playheadInPage ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(s.filmPlayhead ?? -1, 4.5, accuracy: 1e-9)
        XCTAssertTrue(s.canSplitPage)
        s.setHold(of: s.design.pages[1].id, to: 0.8)
        XCTAssertEqual(s.playheadInPage ?? -1, 0.8, accuracy: 1e-9)
    }

    func testSplitPageIsOneUndo() {
        let s = store(holds: [4, 2])
        s.playhead = 0.3
        XCTAssertFalse(s.canSplitPage, "too near the start")
        s.splitPage()
        XCTAssertEqual(s.design.pages.count, 2)

        s.playhead = 1.5
        XCTAssertTrue(s.canSplitPage)
        s.splitPage()
        XCTAssertEqual(s.design.pages.map(\.holdSeconds), [1.5, 2.5, 2])
        XCTAssertEqual(s.pageIndex, 1, "the second part on screen")
        XCTAssertEqual(s.playheadInPage, 0, "at its start")
        XCTAssertEqual(s.filmPlayhead ?? -1, 1.5, accuracy: 1e-9)
        s.undo()
        XCTAssertEqual(s.design.pages.map(\.holdSeconds), [4, 2])
        XCTAssertEqual(s.pageIndex, 0)
        XCTAssertFalse(s.canUndo)
    }

    func testShowAndHideFromThePlayheadAreEachOneUndo() {
        let s = store(holds: [4, 2])
        let id = s.design.pages[0].elements[0].id
        s.select(id)
        s.playhead = 1
        s.showSelectedFromPlayhead()
        s.playhead = 3
        s.hideSelectedFromPlayhead()
        XCTAssertEqual(s.design.pages[0].elements[0].timing, ElementTiming(start: 1, end: 3))
        s.clearSelectedTiming()
        XCTAssertNil(s.design.pages[0].elements[0].timing)
        s.undo()
        s.undo()
        XCTAssertEqual(s.design.pages[0].elements[0].timing, ElementTiming(start: 1))
        s.undo()
        XCTAssertNil(s.design.pages[0].elements[0].timing)

        s.playhead = 0.02
        s.hideSelectedFromPlayhead()
        XCTAssertNil(s.design.pages[0].elements[0].timing, "nothing to hide from at the page's start")
        s.setPageHidden(true)
        XCTAssertNil(s.playheadInPage, "a hidden page has no playhead")
        s.playhead = 1
        s.showSelectedFromPlayhead()
        XCTAssertNil(s.design.pages[0].elements[0].timing, "nothing to time by")
    }

    func testDraggingAnEdgeWhileTypingLeavesTheWordsTheirOwnStep() {
        let s = store(holds: [2, 3])
        let words = Element.text("Hi")
        s.design.pages[0].elements = [words]
        s.startTyping(words.id)
        s.typeWords("Hello", into: words.id)
        s.dragHold(of: s.design.pages[1].id, to: 4)
        s.commit()
        XCTAssertEqual(s.design.pages[1].holdSeconds, 4)
        s.undo()
        XCTAssertEqual(s.design.pages[1].holdSeconds, 3, "the drag is one step")
        XCTAssertEqual(s.design.pages[0].elements.first?.text, "Hello", "the words are another")
    }
}
