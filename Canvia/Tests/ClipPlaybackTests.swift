// A clip's trim, speed and loop: where the page's time falls in the file,
// the hold that plays it through, its `clip` JSON, and the store's steps —
// the same tables as the Android twin's.

import XCTest
@testable import Canvia

final class ClipPlaybackTests: XCTestCase {

    func testClipTimeTable() {
        let trimmed = ClipPlayback(start: 2, end: 6, speed: 2)
        let rows: [(name: String, clip: ClipPlayback, pageTime: Double, duration: Double?, result: Double)] = [
            ("default", ClipPlayback(), 0, 10, 0),
            ("default, past the end", ClipPlayback(), 12.5, 10, 2.5),
            ("start 2, end 6, speed 2", trimmed, 0, 10, 2),
            ("start 2, end 6, speed 2", trimmed, 1, 10, 4),
            ("start 2, end 6, speed 2", trimmed, 2, 10, 2),
            ("start 2, end 6, speed 2", trimmed, 2.5, 10, 3),
            ("start 2, end 6, speed 2, loop false", ClipPlayback(start: 2, end: 6, speed: 2, loop: false), 3, 10, 5.99),
            ("start 1, loop true", ClipPlayback(start: 1), 12, 10, 4),
            ("start 1, duration unknown", ClipPlayback(start: 1), 12, nil, 13),
            ("end 20 beyond duration 10", ClipPlayback(end: 20), 15, 10, 5),
            ("speed 10 clamped to 4", ClipPlayback(speed: 10), 1, 10, 4),
            ("start 5, end 5", ClipPlayback(start: 5, end: 5), 3, 10, 5),
            ("default, before the page", ClipPlayback(), -2, 10, 0),
        ]
        for row in rows {
            XCTAssertEqual(VideoStore.clipTime(row.pageTime, clip: row.clip, duration: row.duration),
                           row.result, accuracy: 0.0001, "\(row.name) at \(row.pageTime)")
        }
    }

    func testFitHoldTable() {
        XCTAssertEqual(VideoStore.fitHold(ClipPlayback(), duration: 10), 10, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.fitHold(ClipPlayback(start: 2, end: 6, speed: 2), duration: 10), 2, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.fitHold(ClipPlayback(), duration: 200), 60, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.fitHold(ClipPlayback(start: 9.9), duration: 10), 0.5, accuracy: 0.0001)
    }

    /// A stamp has been through clipTime, so the store takes it as it is;
    /// only one past the end — stamped before the length was known — loops.
    func testAStampedTimeIsTakenAsItIs() {
        XCTAssertEqual(VideoStore.stampedTime(4, duration: 10), 4, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.stampedTime(10, duration: 10), 9.99, accuracy: 0.0001, "kept within the clip")
        XCTAssertEqual(VideoStore.stampedTime(13, duration: 10), 3, accuracy: 0.0001, "past the end, it loops")
        XCTAssertEqual(VideoStore.stampedTime(-1, duration: 10), 0, accuracy: 0.0001)
        XCTAssertEqual(VideoStore.stampedTime(3, duration: 0), 0)
    }

    func testTrimLabels() {
        XCTAssertEqual(VideoStore.rangeLabel(2, 6), "0:02.0 – 0:06.0")
        XCTAssertEqual(VideoStore.timeLabel(65.25), "1:05.3")
        XCTAssertEqual(VideoStore.timeLabel(0), "0:00.0")
    }

    // MARK: JSON

    private func clipElement(_ clip: String?) throws -> Element {
        let extra = clip.map { ", \"clip\": \($0)" } ?? ""
        let json = "{\"id\": \"v1\", \"type\": \"image\", \"src\": \"video:vid_1\"\(extra)}"
        return try JSONDecoder().decode(Element.self, from: Data(json.utf8))
    }

    private func clipObject(_ el: Element) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any]
        return object?["clip"] as? [String: Any]
    }

    private func hasClipKey(_ el: Element) throws -> Bool {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any]
        return object?["clip"] != nil
    }

    func testAnAbsentClipReadsAsTheDefaultsAndWritesNoKey() throws {
        let el = try clipElement(nil)
        XCTAssertNil(el.clip)
        XCTAssertEqual(el.clip ?? ClipPlayback(), ClipPlayback())
        XCTAssertFalse(try hasClipKey(el))
        XCTAssertNil(try clipElement("{}").clip, "an object at every default is none")
        XCTAssertFalse(try hasClipKey(try clipElement("{\"speed\": 1, \"loop\": true}")))
    }

    func testAPartialClipReadsWithDefaults() throws {
        let clip = try XCTUnwrap(try clipElement("{\"start\": 2}").clip)
        XCTAssertEqual(clip.start, 2)
        XCTAssertNil(clip.end)
        XCTAssertEqual(clip.speed, 1)
        XCTAssertTrue(clip.loop)
        let odd = try XCTUnwrap(try clipElement("{\"start\": 3, \"speed\": \"fast\", \"volume\": 0.5}").clip)
        XCTAssertEqual(odd.start, 3, "an odd field still lets the rest read")
        XCTAssertEqual(odd.speed, 1)
        let written = try XCTUnwrap(try clipObject(try clipElement("{\"start\": 2}")))
        XCTAssertEqual(written["start"] as? Double, 2)
        XCTAssertEqual(Set(written.keys), ["start"], "defaults are left out")
    }

    func testAnOutOfRangeSpeedPlaysClampedButRoundTrips() throws {
        let el = try clipElement("{\"speed\": 10}")
        let clip = try XCTUnwrap(el.clip)
        XCTAssertEqual(clip.speed, 10)
        XCTAssertEqual(clip.playbackSpeed, 4)
        XCTAssertEqual(VideoStore.clipTime(1, clip: clip, duration: 10), 4, accuracy: 0.0001)
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.clip?.speed, 10)
        XCTAssertEqual(try clipObject(el)?["speed"] as? Double, 10)
    }

    func testLoopOffRoundTrips() throws {
        let el = try clipElement("{\"start\": 1.5, \"end\": 4, \"loop\": false}")
        XCTAssertEqual(el.clip, ClipPlayback(start: 1.5, end: 4, loop: false))
        let written = try XCTUnwrap(try clipObject(el))
        XCTAssertEqual(written["loop"] as? Bool, false)
        XCTAssertEqual(written["end"] as? Double, 4)
        XCTAssertNil(written["speed"])
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.clip, el.clip)
    }
}
