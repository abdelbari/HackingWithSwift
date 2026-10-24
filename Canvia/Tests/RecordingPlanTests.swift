// Present and record: the talks kept with a design, and how one is laid
// against its pages — the shared fixture recording-plan.json, which the
// Android twin's RecordingPlanTest reads too.

import CoreGraphics
import ImageIO
import XCTest
@testable import Canvia

final class RecordingPlanTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("recording-plan") }

    private func recording() throws -> Recording {
        try JSONDecoder().decode(Recording.self, from: SharedFixture.encoded(try XCTUnwrap(fixture()["recording"])))
    }

    /// Shared: the same page at the same moment on both phones.
    func testThePageAtAMoment() throws {
        let talk = try recording()
        for row in try XCTUnwrap(fixture()["at"] as? [[String: Any]]) {
            let t = try XCTUnwrap(row["t"] as? Double)
            XCTAssertEqual(RecordingPlan.pageAt(talk, t)?.pageId, row["page"] as? String, "t=\(t)")
        }
        XCTAssertEqual(talk.duration, 95, accuracy: 1e-9)
        var empty = talk
        empty.pages = []
        XCTAssertNil(RecordingPlan.pageAt(empty, 1))
    }

    /// Shared: a talk's page turns make the same spans.
    func testATalkCapturesTheSpans() throws {
        let o = try XCTUnwrap(fixture()["capture"] as? [String: Any])
        var capture = RecordingPlan.Capture(firstPage: try XCTUnwrap(o["first"] as? String))
        for turn in try XCTUnwrap(o["turns"] as? [[String: Any]]) {
            capture.turn(to: turn["page"] as? String ?? "", at: turn["at"] as? Double ?? 0)
        }
        let spans = capture.finish(at: try XCTUnwrap(o["end"] as? Double))
        let want = try XCTUnwrap(o["spans"] as? [[String: Any]])
        XCTAssertEqual(spans.map(\.pageId), want.map { $0["pageId"] as? String ?? "" })
        for (s, w) in zip(spans, want) {
            XCTAssertEqual(s.start, w["start"] as? Double ?? -1, accuracy: 1e-9)
            XCTAssertEqual(s.end, w["end"] as? Double ?? -1, accuracy: 1e-9)
        }
    }

    /// Shared: the film holds each span for its frames, long ones split,
    /// cut, the voice over the music ducked.
    func testTheFilmHoldsEachPage() throws {
        let o = try XCTUnwrap(fixture()["film"] as? [String: Any])
        var design = Design(width: 1920, height: 1080)
        design.pages = ["p1", "p2", "p3"].map { Page(id: $0) }
        design.audioTracks = [AudioTrack(id: "m", src: AudioTrack.src("song.m4a"), volume: 0.8)]
        // The talk's own rate, which both phones make its film at.
        XCTAssertEqual(o["fps"] as? Int, RecordingPlan.fps)
        XCTAssertEqual(MovieExporter.talkFps, RecordingPlan.fps)
        let film = RecordingPlan.film(design, try recording(), fps: RecordingPlan.fps)
        let holds = try XCTUnwrap(o["holds"] as? [Double])
        XCTAssertEqual(film.pages.count, holds.count)
        for (h, page) in zip(holds, film.pages) {
            XCTAssertEqual(page.holdSeconds ?? -1, h, accuracy: 1e-9)
            XCTAssertEqual(page.transition, "cut")
        }
        XCTAssertEqual(film.audioTracks.first { $0.id == "m" }?.volume ?? 0, 0.8 * RecordingPlan.duck, accuracy: 1e-9)
        XCTAssertEqual(film.audioTracks.first { $0.id == "rec_1" }?.audioId, "rec_1.m4a")
    }

    /// Shared: the bubble sits where the fixture says.
    func testTheCameraBubbleSits() throws {
        for row in try XCTUnwrap(fixture()["bubbles"] as? [[String: Any]]) {
            let bubble = try JSONDecoder().decode(RecordingBubble.self, from: SharedFixture.encoded(try XCTUnwrap(row["bubble"])))
            let r = RecordingPlan.bubbleRect(bubble, width: row["width"] as? Double ?? 0, height: row["height"] as? Double ?? 0)
            let want = try XCTUnwrap(row["rect"] as? [Double])
            let got = [r.minX, r.minY, r.width, r.height].map { (Double($0) * 1000).rounded() / 1000 }
            XCTAssertEqual(got, want)
        }
    }

    /// A camera clip made on the Android twin is written as the sensor
    /// sees and turned by its track's transform; the bubble turns it
    /// upright. This phone's own clips are upright already (identity).
    func testTheCameraClipIsTurnedUpright() {
        let turn = { (a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat) in
            TalkBubbleCompositor.orientation(of: CGAffineTransform(a: a, b: b, c: c, d: d, tx: 480, ty: 0))
        }
        XCTAssertEqual(turn(0, 1, -1, 0), .right)
        XCTAssertEqual(turn(0, -1, 1, 0), .left)
        XCTAssertEqual(turn(-1, 0, 0, -1), .down)
        XCTAssertEqual(TalkBubbleCompositor.orientation(of: .identity), .up)
    }

    /// Shared: a circle's corners are half its side, a rounded bubble's
    /// `RecordingPlan.roundedRadius` of it, in the MP4 and in playback.
    func testTheCameraBubblesCorners() throws {
        for row in try XCTUnwrap(fixture()["radii"] as? [[String: Any]]) {
            let bubble = RecordingBubble(shape: try XCTUnwrap(row["shape"] as? String))
            let radius = RecordingPlan.bubbleRadius(bubble, side: row["side"] as? Double ?? 0)
            XCTAssertEqual(radius, row["radius"] as? Double ?? -1, accuracy: 1e-9)
        }
    }

    /// Newest first, five at most, the camera written as null when there
    /// is none, keys in the twin's order; through a design file and back.
    func testTalksAreKeptNewestFirstAndTravel() throws {
        let talk = try recording()
        var design = Design()
        for n in 1...7 {
            var next = talk
            next.id = "rec_\(n)"
            next.audio = "rec_\(n).m4a"
            next.camera = n % 2 == 0 ? nil : "rec_\(n).mp4"
            design = Recordings.added(design, next)
        }
        let kept = Recordings.of(design)
        XCTAssertEqual(kept.map(\.id), ["rec_7", "rec_6", "rec_5", "rec_4", "rec_3"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let written = String(decoding: try JSONEncoder().encode(kept[1]), as: UTF8.self)
        XCTAssertTrue(written.contains("\"camera\":null"))
        XCTAssertTrue(written.contains("\"createdAt\":1700000000000"))
        XCTAssertTrue(written.contains("\"bubble\":"))
        let round = try JSONDecoder().decode(Design.self, from: encoder.encode(design))
        XCTAssertEqual(Recordings.of(round), kept)
        XCTAssertEqual(Recordings.audioIds(design), ["rec_7.m4a", "rec_6.m4a", "rec_5.m4a", "rec_4.m4a", "rec_3.m4a"])
        XCTAssertEqual(Recordings.cameraIds(design), ["rec_7", "rec_5", "rec_3"])
        XCTAssertTrue(DesignLibrary.soundtracks(in: [design]).contains("rec_3.m4a"))
        XCTAssertTrue(DesignLibrary.clips(in: [design]).isSuperset(of: ["rec_7", "rec_5", "rec_3"]))
        let moved = Recordings.remapped(design, audio: ["rec_7.m4a": "audio_9.m4a"], video: ["rec_7": "vid_9"])
        XCTAssertEqual(Recordings.of(moved).first?.audio, "audio_9.m4a")
        XCTAssertEqual(Recordings.of(moved).first?.camera, "vid_9.mp4")
        XCTAssertEqual(Recordings.of(moved).first?.cameraId, "vid_9")
        XCTAssertEqual(Recordings.of(Recordings.without(design, "rec_7")).map(\.id), ["rec_6", "rec_5", "rec_4", "rec_3"])
        XCTAssertNil(Recordings.with(design, []).recordings)
        XCTAssertEqual(Recordings.label(talk), "Talk, 1:35")
    }

    /// What does not read is passed over; an odd bubble reads as the
    /// default.
    func testTalksReadLeniently() throws {
        let json = #"{"id":"d","recordings":[{"id":"rec_a","audio":"rec_a.m4a","createdAt":5,"bubble":{"corner":"middle","size":9,"shape":"star"},"pages":[{"pageId":"p","start":2,"end":1},{"pageId":"q","start":0,"end":3}]},{"audio":"x.m4a"}]}"#
        let design = try JSONDecoder().decode(Design.self, from: Data(json.utf8))
        let talks = Recordings.of(design)
        XCTAssertEqual(talks.map(\.id), ["rec_a"])
        XCTAssertNil(talks[0].camera)
        XCTAssertEqual(talks[0].bubble, RecordingBubble(corner: "bottomLeft", size: 0.5, shape: "circle"))
        XCTAssertEqual(talks[0].pages, [RecordingSpan(pageId: "q", start: 0, end: 3)])
    }
}
