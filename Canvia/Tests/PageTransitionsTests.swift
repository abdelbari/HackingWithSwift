// More page transitions — push, wipe, circle and zoom — and a length of
// their own, as the Android twin has them: the shared layers table, the
// file keys, the video drawing them, Present's timings and Apply to all
// pages as one Undo. The layers table is the same as the Android twin's.

import XCTest
import CoreGraphics
@testable import Canvia

final class PageTransitionsTests: XCTestCase {

    private typealias Layer = PageTransitions.Layer

    private func assertLayer(_ got: Layer, _ want: Layer, _ what: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.alpha, want.alpha, accuracy: 1e-9, "\(what) alpha", file: file, line: line)
        XCTAssertEqual(got.dx, want.dx, accuracy: 1e-9, "\(what) dx", file: file, line: line)
        XCTAssertEqual(got.scale, want.scale, accuracy: 1e-9, "\(what) scale", file: file, line: line)
        switch (got.clip, want.clip) {
        case (.none, .none):
            break
        case let (.rect(a), .rect(b)), let (.circle(a), .circle(b)):
            XCTAssertEqual(a, b, accuracy: 1e-9, "\(what) clip", file: file, line: line)
        default:
            XCTFail("\(what) clip: \(got.clip), wanted \(want.clip)", file: file, line: line)
        }
    }

    private func layer(alpha: Double = 1, dx: Double = 0, scale: Double = 1,
                       clip: PageTransitions.Clip = .none) -> Layer {
        Layer(alpha: alpha, dx: dx, scale: scale, clip: clip)
    }

    // MARK: the shared table

    func testEaseOutCubic() {
        XCTAssertEqual(PageTransitions.eased(0), 0)
        XCTAssertEqual(PageTransitions.eased(0.5), 0.875, accuracy: 1e-12)
        XCTAssertEqual(PageTransitions.eased(1), 1)
    }

    /// Kind, t, forward, then the page leaving and the page coming. The eased
    /// value is 1 - (1 - t)^3: 0, 0.875 and 1 at t = 0, 0.5 and 1. A fade is
    /// linear. Going back is the forward table at 1 - t with the pages
    /// swapped. The same rows as the Android twin's PageTransitionsTest.
    func testTheLayersTable() {
        let still = layer()
        let rows: [(String, Double, Bool, Layer, Layer)] = [
            ("fade", 0, true, still, layer(alpha: 0)),
            ("fade", 0.5, true, still, layer(alpha: 0.5)),
            ("fade", 1, true, still, still),
            ("fade", 0, false, still, still),
            ("fade", 0.5, false, layer(alpha: 0.5), still),
            ("fade", 1, false, layer(alpha: 0), still),

            ("slide", 0, true, still, layer(dx: 1)),
            ("slide", 0.5, true, still, layer(dx: 0.125)),
            ("slide", 1, true, still, still),
            ("slide", 0, false, still, still),
            ("slide", 0.5, false, layer(dx: 0.125), still),
            ("slide", 1, false, layer(dx: 1), still),

            ("push", 0, true, still, layer(dx: 1)),
            ("push", 0.5, true, layer(dx: -0.875), layer(dx: 0.125)),
            ("push", 1, true, layer(dx: -1), still),
            ("push", 0, false, still, layer(dx: -1)),
            ("push", 0.5, false, layer(dx: 0.125), layer(dx: -0.875)),
            ("push", 1, false, layer(dx: 1), still),

            ("wipe", 0, true, still, layer(clip: .rect(fromLeftFraction: 0))),
            ("wipe", 0.5, true, still, layer(clip: .rect(fromLeftFraction: 0.875))),
            ("wipe", 1, true, still, layer(clip: .rect(fromLeftFraction: 1))),
            ("wipe", 0, false, layer(clip: .rect(fromLeftFraction: 1)), still),
            ("wipe", 0.5, false, layer(clip: .rect(fromLeftFraction: 0.875)), still),
            ("wipe", 1, false, layer(clip: .rect(fromLeftFraction: 0)), still),

            ("circle", 0, true, still, layer(clip: .circle(radiusFraction: 0))),
            ("circle", 0.5, true, still, layer(clip: .circle(radiusFraction: 0.875))),
            ("circle", 1, true, still, layer(clip: .circle(radiusFraction: 1))),
            ("circle", 0, false, layer(clip: .circle(radiusFraction: 1)), still),
            ("circle", 0.5, false, layer(clip: .circle(radiusFraction: 0.875)), still),
            ("circle", 1, false, layer(clip: .circle(radiusFraction: 0)), still),

            ("zoom", 0, true, still, layer(alpha: 0, scale: 0.85)),
            ("zoom", 0.5, true, still, layer(alpha: 0.875, scale: 0.98125)),
            ("zoom", 1, true, still, still),
            ("zoom", 0, false, still, still),
            ("zoom", 0.5, false, layer(alpha: 0.875, scale: 0.98125), still),
            ("zoom", 1, false, layer(alpha: 0, scale: 0.85), still),
        ]
        for (kind, t, forward, outgoing, incoming) in rows {
            let got = PageTransitions.layers(kind, t: t, forward: forward)
            let what = "\(kind) t=\(t) \(forward ? "forward" : "back")"
            assertLayer(got.outgoing, outgoing, what + " outgoing")
            assertLayer(got.incoming, incoming, what + " incoming")
        }
    }

    func testAnUnknownKindIsAFade() {
        let got = PageTransitions.layers("spiral", t: 0.5, forward: true)
        assertLayer(got.outgoing, layer(), "outgoing")
        assertLayer(got.incoming, layer(alpha: 0.5), "incoming")
    }

    // MARK: the file

    func testTheLengthIsWrittenOnlyWhenSetAndAnyKindSurvives() throws {
        var page = Page()
        page.transition = "spiral"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        XCTAssertNil(json["transitionSeconds"], "no length, no key")
        XCTAssertEqual(json["transition"] as? String, "spiral", "a kind from a newer build is kept")
        page.transition = "wipe"
        page.transitionSeconds = 0.3
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        XCTAssertEqual(json["transitionSeconds"] as? Double, 0.3)
        let back = try JSONDecoder().decode(Page.self, from: JSONEncoder().encode(page))
        XCTAssertEqual(back.transition, "wipe")
        XCTAssertEqual(back.transitionSeconds, 0.3)
        let android = try JSONDecoder().decode(Page.self, from: Data(#"{"id":"p","elements":[],"transition":"circle","transitionSeconds":1.0}"#.utf8))
        XCTAssertEqual(android.transition, "circle")
        XCTAssertEqual(android.transitionSeconds, 1.0)
    }

    func testTheLengthIsKeptToItsRange() {
        XCTAssertNil(PageTransitions.seconds(nil))
        XCTAssertEqual(PageTransitions.seconds(0.05), 0.2)
        XCTAssertEqual(PageTransitions.seconds(0.3), 0.3)
        XCTAssertEqual(PageTransitions.seconds(9), 2.0)
    }

    func testTheLengthsOnOffer() {
        XCTAssertEqual(PageTransitions.lengths.map { $0.name }, ["Quick", "Normal", "Slow"])
        XCTAssertEqual(PageTransitions.lengths.map { $0.seconds }, [0.3, nil, 1.0])
        XCTAssertEqual(PageTransitions.lengthName(nil), "Normal")
        XCTAssertEqual(PageTransitions.lengthName(0.3), "Quick")
        XCTAssertEqual(PageTransitions.lengthName(1.0), "Slow")
        // A length of its own reads as the nearest, as Android's lengthName.
        XCTAssertEqual(PageTransitions.lengthName(0.5), "Quick")
        XCTAssertEqual(PageTransitions.lengthName(0.8), "Slow")
        XCTAssertEqual(PageTransitions.lengthName(2.0), "Slow")
        XCTAssertEqual(PageTransitions.lengthName(0.2), "Quick")
    }

    // MARK: present

    func testPresentKeepsTodaysTimingsUnlessThePageSays() {
        XCTAssertEqual(PageTransitions.presentSeconds("fade", own: nil), 0.25)
        XCTAssertEqual(PageTransitions.presentSeconds("slide", own: nil), 0.5)
        for kind in ["push", "wipe", "circle", "zoom"] {
            XCTAssertEqual(PageTransitions.presentSeconds(kind, own: nil), 0.5, kind)
        }
        XCTAssertEqual(PageTransitions.presentSeconds("fade", own: 1.0), 1.0)
        XCTAssertEqual(PageTransitions.presentSeconds("push", own: 5), 2.0, "kept to the range")
    }

    func testEveryNewKindIsKnown() {
        XCTAssertEqual(MovieExporter.transitions, ["fade", "cut", "slide", "push", "wipe", "circle", "zoom"])
    }

    /// Android's "a page gives way by its own transition, else the design's".
    func testAPageGivesWayByItsOwnTransitionElseTheDesigns() {
        var plain = Design(title: "t", width: 400, height: 300)
        plain.pages = [Page()]
        XCTAssertEqual(PageTransitions.transitionKind(after: plain.pages[0], in: plain), "fade")
        var cutting = plain
        var motion = MotionSettings()
        motion.crossfade = false
        cutting.motion = motion
        XCTAssertEqual(PageTransitions.transitionKind(after: cutting.pages[0], in: cutting), "cut")
        var page = Page()
        page.transition = "slide"
        XCTAssertEqual(PageTransitions.transitionKind(after: page, in: cutting), "slide")
        page.transition = "spiral"
        XCTAssertEqual(PageTransitions.transitionKind(after: page, in: plain), "fade", "a kind this build does not know is the design's")
        XCTAssertEqual(PageTransitions.transitionKind(after: page, in: cutting), "cut")
    }

    // MARK: video

    private var settings: MovieExporter.Settings {
        var s = MovieExporter.Settings()
        s.secondsPerPage = 1
        s.fps = 10
        s.crossfade = 0.5
        s.zoom = 0
        return s
    }

    private func design(transition: String, seconds: Double? = nil) -> Design {
        var d = Design(title: "t", width: 400, height: 300)
        d.pages = [Page(), Page()]
        d.pages[0].holdSeconds = 1
        d.pages[1].holdSeconds = 1
        d.pages[0].transition = transition
        d.pages[0].transitionSeconds = seconds
        return d
    }

    func testTheTimelineCarriesThePagesLength() {
        let timings = MovieExporter.timeline(design: design(transition: "push", seconds: 5), settings: settings)
        XCTAssertEqual(timings[0].transitionSeconds, 2.0, "kept to the range")
        XCTAssertNil(timings[1].transitionSeconds)
        XCTAssertEqual(MovieExporter.overlapSeconds(timings[0], settings: settings), 2.0)
        XCTAssertEqual(MovieExporter.overlapSeconds(timings[1], settings: settings), 0.5, "today's overlap")
        var cut = timings[1]; cut.transition = "cut"
        XCTAssertEqual(MovieExporter.overlapSeconds(cut, settings: settings), 0)
    }

    /// Across a hidden page, the page before the gap decides, as Present
    /// turns from it to the next page shown.
    func testAcrossAHiddenPageThePageBeforeItDecides() {
        var d = design(transition: "wipe")
        var hidden = Page()
        hidden.hidden = true
        hidden.transition = "zoom"
        d.pages.insert(hidden, at: 1)
        let timings = MovieExporter.timeline(design: d, settings: settings)
        XCTAssertEqual(timings.count, 2)
        XCTAssertEqual(timings[0].transition, "wipe")
    }

    /// A white page handing over to a black one, `frame` of the 20, read at
    /// the pixels asked for (x, y).
    private func pixels(_ transition: String, seconds: Double? = nil, frame: Int,
                        at points: [(Int, Int)]) throws -> [UInt8] {
        let size = CGSize(width: 40, height: 30)
        func solid(_ gray: CGFloat) -> CGImage {
            let ctx = CGContext(data: nil, width: 40, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.setFillColor(gray: gray, alpha: 1); ctx.fill(CGRect(origin: .zero, size: size))
            return ctx.makeImage()!
        }
        let timings = MovieExporter.timeline(design: design(transition: transition, seconds: seconds), settings: settings)
        var px = [UInt8](repeating: 0, count: 40 * 30 * 4)
        try px.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(data: raw.baseAddress, width: 40, height: 30, bitsPerComponent: 8,
                                              bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            MovieExporter.draw(frame: frame, pages: [solid(1), solid(0)], size: size, settings: settings,
                               timings: timings, into: ctx)
        }
        return points.map { px[($0.1 * 40 + $0.0) * 4] }
    }

    /// Frame 8 of a 5-frame overlap: t = 0.6, eased 0.936.
    func testAWipeShowsTheNextPageFromTheLeft() throws {
        let px = try pixels("wipe", frame: 8, at: [(2, 15), (39, 15)])
        XCTAssertEqual(px[0], 0, "the next page, left of the edge at 37 of 40")
        XCTAssertEqual(px[1], 255, "this page, right of it")
    }

    func testACircleGrowsFromTheMiddle() throws {
        let px = try pixels("circle", frame: 8, at: [(20, 15), (0, 0)])
        XCTAssertEqual(px[0], 0, "the next page in the middle")
        XCTAssertEqual(px[1], 255, "this page in the corner, past the radius of 23.4")
    }

    func testAPushMovesBothPages() throws {
        let px = try pixels("push", frame: 8, at: [(1, 15), (20, 15)])
        XCTAssertEqual(px[0], 255, "what is left of this page, at the left")
        XCTAssertEqual(px[1], 0, "the next page, most of the way in")
    }

    func testAZoomFadesTheNextPageIn() throws {
        let px = try pixels("zoom", frame: 8, at: [(20, 15)])
        XCTAssertTrue(px[0] > 0 && px[0] < 255, "a blend while it fades in: \(px[0])")
    }

    func testAShortLengthStartsTheTransitionLater() throws {
        // Frame 7: three frames left. The usual overlap of five has begun;
        // a page's own 0.2 s, two frames, has not.
        XCTAssertEqual(try pixels("wipe", frame: 7, at: [(2, 15)])[0], 0)
        XCTAssertEqual(try pixels("wipe", seconds: 0.2, frame: 7, at: [(2, 15)])[0], 255)
    }

    // MARK: the editor

    @MainActor
    func testApplyToAllPagesReachesHiddenPagesInOneUndo() {
        var d = Design(title: "a", width: 400, height: 300)
        d.pages = [Page(), Page(), Page()]
        d.pages[1].hidden = true
        d.pages[2].transition = "cut"
        d.pages[2].transitionSeconds = 1.0
        let store = DesignStore(design: d)
        store.applyToPage { $0.transition = "circle"; $0.transitionSeconds = 0.3 }
        store.applyTransitionToAllPages()
        XCTAssertEqual(store.design.pages.map(\.transition), ["circle", "circle", "circle"])
        XCTAssertEqual(store.design.pages.map(\.transitionSeconds), [0.3, 0.3, 0.3])
        store.undo()
        XCTAssertEqual(store.design.pages.map(\.transition), ["circle", nil, "cut"])
        XCTAssertEqual(store.design.pages.map(\.transitionSeconds), [0.3, nil, 1.0])
    }

    /// A kind a newer build made is given to every page as written, as on
    /// the Android twin.
    @MainActor
    func testAKindThisBuildDoesNotKnowIsGivenToEveryPageAsWritten() {
        var d = Design(title: "a", width: 400, height: 300)
        d.pages = [Page(), Page(), Page()]
        d.pages[0].transition = "dissolve"
        d.pages[1].transition = "push"
        d.pages[2].transition = "push"
        let store = DesignStore(design: d)
        store.applyTransitionToAllPages()
        XCTAssertEqual(store.design.pages.map(\.transition), ["dissolve", "dissolve", "dissolve"])
    }

    @MainActor
    func testApplyingNormalTakesTheLengthAwayEverywhere() {
        var d = Design(title: "a", width: 400, height: 300)
        d.pages = [Page(), Page()]
        d.pages[1].transitionSeconds = 1.0
        let store = DesignStore(design: d)
        store.applyTransitionToAllPages()
        XCTAssertEqual(store.design.pages.map(\.transitionSeconds), [nil, nil])
    }
}
