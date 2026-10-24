// The generated motion loops and still textures, as the Android twin's
// MotionArtTest checks them: every entry of Motion.json drawn at 48 × 36 at
// t = 0 and t = period / 2 gives the hash tools/generate_motion.py wrote to
// the shared fixture; and a loop on a page plays like a looping clip.

import XCTest
@testable import Canvia

final class MotionArtTests: XCTestCase {

    func testEveryFrameMatchesTheSharedFixture() throws {
        let fixture = try SharedFixture.object("motion-frames")
        let width = try XCTUnwrap(fixture["width"] as? Int)
        let height = try XCTUnwrap(fixture["height"] as? Int)
        let frames = try XCTUnwrap(fixture["frames"] as? [String: [String]])
        let all = MotionLibrary.loops + MotionLibrary.stills
        XCTAssertEqual(Set(frames.keys), Set(all.map(\.id)), "the fixture and the library list the same entries")
        for def in all {
            let want = try XCTUnwrap(frames[def.id], def.id)
            XCTAssertEqual(MotionArt.hash(MotionArt.frame(def, t: 0, width: width, height: height)), want.first,
                           "\(def.id) at 0")
            if def.period > 0 {
                XCTAssertEqual(MotionArt.hash(MotionArt.frame(def, t: def.period / 2, width: width, height: height)),
                               want.last, "\(def.id) half way round")
            }
        }
    }

    func testTheLibraryHasAboutThirtyLoopsAndSixtyStills() {
        let kinds: Set<String> = ["mesh", "waves", "bokeh", "confetti", "rays", "grain", "dots", "stars", "paper",
                                  "marble", "linen", "terrazzo", "sky", "halftone"]
        XCTAssertEqual(MotionLibrary.loops.count, 30)
        XCTAssertEqual(MotionLibrary.stills.count, 60)
        let ids = (MotionLibrary.loops + MotionLibrary.stills).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "every id once")
        for loop in MotionLibrary.loops {
            XCTAssertTrue(kinds.contains(loop.kind), loop.id)
            XCTAssertGreaterThan(loop.period, 0, loop.id)
            XCTAssertFalse(loop.tags.isEmpty, loop.id)
        }
        for still in MotionLibrary.stills { XCTAssertEqual(still.period, 0, still.id) }
        XCTAssertGreaterThanOrEqual(PhotoLibrary.photos.count, 80, "the drawn pictures and the stills")
        XCTAssertNotNil(PhotoLibrary.photos.first { $0.id == "still-marble-1" })
    }

    func testALoopIsTheSameFrameAWholeLoopLater() {
        let loop = MotionLibrary.loops[0]
        XCTAssertEqual(MotionArt.frame(loop, t: 1, width: 16, height: 12),
                       MotionArt.frame(loop, t: 1 + loop.period, width: 16, height: 12))
        XCTAssertNotEqual(MotionArt.frame(loop, t: 0, width: 16, height: 12),
                          MotionArt.frame(loop, t: loop.period / 2, width: 16, height: 12))
    }

    func testTheSharedMathsGivesTheSameNumbers() {
        XCTAssertEqual(MotionArt.hash01(0, 0, 0), 0)
        XCTAssertEqual(MotionArt.hash([]), "811c9dc5")
        XCTAssertEqual(MotionArt.hash([0x61]), "e40c292c", "FNV-1a of \"a\"")
        XCTAssertEqual(MotionArt.byte(0.5), 128)
        XCTAssertEqual(MotionArt.byte(-0.2), 0)
        XCTAssertEqual(MotionArt.byte(1.4), 255)
        XCTAssertEqual(MotionArt.grad([.init(0, 0, 0), .init(1, 1, 1)], 0.25), .init(0.25, 0.25, 0.25))
        XCTAssertEqual(MotionArt.RGB(hex: "#ff8000"), .init(1, 128.0 / 255, 0))
    }

    func testALoopIsStampedWithTheFrameItsMomentFallsIn() {
        let loop = MotionLibrary.loops[0]
        let src = MotionLibrary.src(loop.id, at: nil)
        XCTAssertEqual(src, "motion:" + loop.id)
        XCTAssertTrue(MotionLibrary.isMotion(src))
        XCTAssertEqual(MotionLibrary.frameTime(1.03, period: 8), 1.0, accuracy: 1e-9, "24 frames a second")
        XCTAssertEqual(MotionLibrary.frameTime(9.03, period: 8), 1.0, accuracy: 1e-9, "round again")
        XCTAssertEqual(MotionLibrary.frameTime(5, period: 0), 0)
        let playing = MotionLibrary.playing(src, at: loop.period + 0.5)
        XCTAssertEqual(playing, "motion:\(loop.id)@0.500")
        XCTAssertEqual(MotionLibrary.playing(playing, at: 3), playing, "stamped once")
        XCTAssertEqual(MotionLibrary.split(playing ?? "")?.time, 0.5)
        XCTAssertEqual(MotionLibrary.atRest(playing ?? ""), src)
        XCTAssertNotNil(PhotoLibrary.resolve(src), "at rest, its first frame")
        XCTAssertNil(PhotoLibrary.resolve("motion:none"))
    }

    func testAPageWithALoopMoves() {
        var d = Design(title: "loop", width: 320, height: 240)
        let src = MotionLibrary.src(MotionLibrary.loops[0].id, at: nil)
        d.pages = [Page(elements: [Element.image(src, w: 160, h: 120)]), Page()]
        XCTAssertTrue(MovieExporter.isAnimated(d.pages[0], in: d))
        XCTAssertFalse(MovieExporter.isAnimated(d.pages[1], in: d))
        d.pages[1].background = .image(src)
        XCTAssertTrue(MovieExporter.isAnimated(d.pages[1], in: d), "a loop behind the page plays too")
        XCTAssertTrue(ExportSuggestion.moves(d, d.pages[1]))
    }
}
