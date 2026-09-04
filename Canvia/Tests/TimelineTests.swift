// Per-page timing and transitions, the GIF budget, and margins.

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
}
