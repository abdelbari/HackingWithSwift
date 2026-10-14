// Clips read in order (ClipReader): the moments a video asks of a trimmed,
// sped-up, looping clip only go back at its loop points, so between them
// its reader reads on rather than seeking; it shows the frame nearest each
// moment; and each pool keeps four clips open, the least recently used let
// go first — the Android twin's rules.

import XCTest
import CoreGraphics
import ImageIO
@testable import Canvia

final class ClipReaderTests: XCTestCase {

    /// A reader reads on to a moment at or after where it stands, a second
    /// ahead at most; anything else — behind it, further on, or a reader
    /// standing nowhere yet — is a seek.
    func testAReaderReadsOnUpToASecondAhead() {
        // Rows: where the reader stands, the moment asked → reads on.
        let rows: [(Double?, Double, Bool)] = [
            (nil, 0, false),
            (1, 1, true),
            (1, 1.5, true),
            (1, 2, true),
            (1, 2.01, false),
            (1, 0.99, false),
            (0, 1 / 30.0, true),
        ]
        for row in rows {
            XCTAssertEqual(ClipReader.readsOn(from: row.0, to: row.1), row.2, "from \(String(describing: row.0)) to \(row.1)")
        }
    }

    /// A reader shows the frame nearest the moment — the last at or before
    /// it, or the first after — the earlier on a tie, as the Android twin
    /// reads it: the same rows on both phones.
    func testAReaderShowsTheFrameNearestTheMoment() {
        // Rows: the frame at or before, the first after, the moment → whether the one after shows.
        let rows: [(Double?, Double?, Double, Bool)] = [
            // 29.97 frames a second, frame 18 stamped 0.6006 and asked at 0.60.
            (0.5672, 0.6006, 0.60, true),
            // 30 frames a second: 0.06 is nearer the third frame than the second.
            (0.0333, 0.0667, 0.06, true),
            (0.0333, 0.0667, 0.04, false),
            // Halfway: the earlier.
            (0, 0.04, 0.02, false),
            (2, 2.0333, 2, false),
            // Before the first frame, the first; past the last, the last.
            (nil, 0.0333, 0, true),
            (4.9667, nil, 6, false),
        ]
        for row in rows {
            XCTAssertEqual(ClipReader.showsAhead(before: row.0, after: row.1, at: row.2), row.3,
                           "\(String(describing: row.0)) \(String(describing: row.1)) at \(row.2)")
        }
    }

    /// Thirty frames a second for ten seconds of page, of a clip trimmed to
    /// 1–3 s at 1.5× that loops: each moment, as the video stamps it to the
    /// hundredth and the store reads the stamp, is at or after the one
    /// before by a frame's worth at most, so the reader reads on — except
    /// at a loop point, where it goes back to the trim's start and seeks.
    /// Fifteen seconds of clip round a two-second trim loop seven times.
    func testTrimSpeedAndLoopOnlyGoBackAtLoopPoints() {
        let clip = ClipPlayback(start: 1, end: 3, speed: 1.5, loop: true)
        let fps = 30.0
        let step = 1.5 / fps
        var previous: Double?
        var seeks = 0
        for f in 0..<300 {
            let raw = VideoStore.clipTime(Double(f) / fps, clip: clip, duration: 10)
            let at = VideoStore.stampedTime((raw * 100).rounded() / 100, duration: 10)
            if let previous {
                if ClipReader.readsOn(from: previous, to: at) {
                    XCTAssertLessThanOrEqual(at - previous, step + 0.01, "frame \(f)")
                } else {
                    seeks += 1
                    XCTAssertLessThan(at, previous, "only a loop goes back, frame \(f)")
                    XCTAssertEqual(at, 1, accuracy: step + 0.01, "back to the trim's start, frame \(f)")
                }
            }
            previous = at
        }
        XCTAssertEqual(seeks, 7)
    }

    /// A clip that does not loop is held on its last frame: the moments
    /// never go back, and the reader never seeks after the first.
    func testAHeldClipNeverSeeks() {
        let clip = ClipPlayback(start: 2, end: 4, speed: 2, loop: false)
        var previous: Double?
        for f in 0..<120 {
            let at = VideoStore.clipTime(Double(f) / 30, clip: clip, duration: 10)
            if let previous { XCTAssertTrue(ClipReader.readsOn(from: previous, to: at), "frame \(f)") }
            previous = at
        }
    }

    /// Four clips stay open; a fifth lets the least recently used go, and
    /// using one moves it to the back of the line.
    func testThePoolKeepsTheFourMostRecentlyUsed() {
        XCTAssertEqual(ClipPool.limit, 4)
        var order: [String] = []
        var dropped: [String] = []
        for id in ["a", "b", "c", "d"] {
            let touched = ClipPool.touched(order, id)
            order = touched.order
            dropped += touched.dropped
        }
        XCTAssertEqual(order, ["a", "b", "c", "d"])
        XCTAssertEqual(dropped, [])
        var touched = ClipPool.touched(order, "e")
        XCTAssertEqual(touched.order, ["b", "c", "d", "e"])
        XCTAssertEqual(touched.dropped, ["a"])
        touched = ClipPool.touched(touched.order, "b")
        XCTAssertEqual(touched.order, ["c", "d", "e", "b"])
        XCTAssertEqual(touched.dropped, [])
        touched = ClipPool.touched(touched.order, "f")
        XCTAssertEqual(touched.order, ["d", "e", "b", "f"])
        XCTAssertEqual(touched.dropped, ["c"])
    }

    /// A clip filmed with the phone upright is turned the way up the
    /// random-access frame turns it.
    func testAClipIsTurnedTheWayItWasFilmed() {
        XCTAssertEqual(ClipReader.orientation(.identity), .up)
        XCTAssertEqual(ClipReader.orientation(CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)), .right)
        XCTAssertEqual(ClipReader.orientation(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)), .left)
        XCTAssertEqual(ClipReader.orientation(CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)), .down)
    }
}
