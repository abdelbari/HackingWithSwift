// A clip played by hand in Present (Videos), and its Autoplay switch
// (ClipPlayback.autoplay): the clip's time with and without what the
// presenter did, Play/Pause and the scrubber, what is heard, and the
// `clip` JSON — the rows the Android twin's VideosTest holds.

import XCTest
@testable import Canvia

final class PresentClipsTests: XCTestCase {

    private func clip(_ playback: ClipPlayback? = nil, id: String = "v1") -> Element {
        var el = Element.image("video:vid_1")
        el.id = id
        el.clip = playback
        return el
    }

    // MARK: JSON

    func testAutoplayIsWrittenOnlyWhenOffAndReadsOnByDefault() throws {
        let off = ClipPlayback(start: 1, autoplay: false)
        let data = try JSONEncoder().encode(off)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["autoplay"] as? Bool, false)
        XCTAssertEqual(try JSONDecoder().decode(ClipPlayback.self, from: data), off)
        // On is no key at all, and an old file reads on.
        let on = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ClipPlayback(start: 1))) as? [String: Any]
        XCTAssertNil(on?["autoplay"])
        XCTAssertTrue(try JSONDecoder().decode(ClipPlayback.self, from: Data("{\"start\": 1}".utf8)).autoplay)
        XCTAssertTrue(ClipPlayback().isDefault)
        XCTAssertFalse(ClipPlayback(autoplay: false).isDefault)
        // Round trip on an element, whose `clip` object carries it.
        let el = clip(off)
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.clip?.autoplay, false)
    }

    // MARK: the clip's time

    func testPresentTimeTable() {
        let trimmed = ClipPlayback(start: 2, end: 6, speed: 2)
        let waiting = ClipPlayback(start: 2, end: 6, autoplay: false)
        typealias O = Videos.Override
        let rows: [(name: String, clip: ClipPlayback?, moment: Double, override: O?, result: Double)] = [
            ("autoplay, nothing done: the page's clock", nil, 3, nil, 3),
            ("trimmed, speed 2, nothing done", trimmed, 1, nil, 4),
            ("autoplay off, nothing done: its start", waiting, 5, nil, 2),
            ("autoplay off, untrimmed: 0", ClipPlayback(autoplay: false), 5, nil, 0),
            ("paused at 3.5", nil, 9, O(state: .paused, anchor: 3.5, at: 4), 3.5),
            ("played from 3 at 4, now 5.5", nil, 5.5, O(state: .playing, anchor: 3, at: 4), 4.5),
            ("played at speed 2", trimmed, 5, O(state: .playing, anchor: 3, at: 4), 5),
            ("played round its loop", trimmed, 6, O(state: .playing, anchor: 3, at: 4), 3),
            ("played to its end, no loop", ClipPlayback(start: 2, end: 6, loop: false), 20,
             O(state: .playing, anchor: 3, at: 4), 5.99),
            ("autoplay off, played from its start", waiting, 7, O(state: .playing, anchor: 2, at: 5), 4),
        ]
        for row in rows {
            XCTAssertEqual(Videos.presentTime(clip(row.clip), pageMoment: row.moment, override: row.override, duration: 10),
                           row.result, accuracy: 0.0001, row.name)
        }
    }

    func testMovingIsAutoplayOrPlayedByHand() {
        XCTAssertTrue(Videos.moves(clip(), override: nil))
        XCTAssertFalse(Videos.moves(clip(ClipPlayback(autoplay: false)), override: nil))
        XCTAssertFalse(Videos.moves(clip(), override: .init(state: .paused, anchor: 1, at: 1)))
        XCTAssertTrue(Videos.moves(clip(ClipPlayback(autoplay: false)), override: .init(state: .playing, anchor: 0, at: 1)))
    }

    // MARK: play, pause, scrub

    func testPlayAndPauseKeepThePlaceAndReplayFromTheStartAtTheEnd() {
        let el = clip(ClipPlayback(start: 1, end: 5))
        // Playing by itself, paused where it is.
        let paused = Videos.toggled(el, override: nil, pageMoment: 2, duration: 10)
        XCTAssertEqual(paused, .init(state: .paused, anchor: 3, at: 2))
        // Played on from there later.
        let played = Videos.toggled(el, override: paused, pageMoment: 7, duration: 10)
        XCTAssertEqual(played, .init(state: .playing, anchor: 3, at: 7))
        XCTAssertEqual(Videos.presentTime(el, pageMoment: 8, override: played, duration: 10), 4, accuracy: 0.0001)
        // A clip that does not loop, played to its end, plays again from
        // its start.
        let once = clip(ClipPlayback(start: 1, end: 5, loop: false))
        let ended = Videos.Override(state: .paused, anchor: 4.99, at: 9)
        XCTAssertEqual(Videos.toggled(once, override: ended, pageMoment: 10, duration: 10),
                       .init(state: .playing, anchor: 1, at: 10))
        // A waiting clip plays from its start.
        let waiting = clip(ClipPlayback(start: 1, end: 5, autoplay: false))
        XCTAssertEqual(Videos.toggled(waiting, override: nil, pageMoment: 6, duration: 10),
                       .init(state: .playing, anchor: 1, at: 6))
    }

    func testTheScrubberStaysInTheTrimAndKeepsPlayingOrPaused() {
        let el = clip(ClipPlayback(start: 1, end: 5))
        XCTAssertEqual(Videos.trimRange(el, duration: 10), 1...5)
        XCTAssertEqual(Videos.trimRange(clip(), duration: 10), 0...10)
        XCTAssertNil(Videos.trimRange(clip(), duration: nil))
        XCTAssertEqual(Videos.scrubbed(el, to: 9, override: nil, pageMoment: 3, duration: 10),
                       .init(state: .playing, anchor: 5, at: 3))
        XCTAssertEqual(Videos.scrubbed(el, to: 0, override: .init(state: .paused, anchor: 2, at: 1), pageMoment: 3,
                                       duration: 10),
                       .init(state: .paused, anchor: 1, at: 3))
        XCTAssertEqual(Videos.controlsSeconds, 3)
        XCTAssertEqual(Videos.target, 44)
    }

    func testAClipPlayedByHandHoldsAutoplay() {
        XCTAssertFalse(Videos.playingByHand([:]))
        XCTAssertFalse(Videos.playingByHand(["a": .init(state: .paused, anchor: 0, at: 0)]))
        XCTAssertTrue(Videos.playingByHand(["a": .init(state: .paused, anchor: 0, at: 0),
                                            "b": .init(state: .playing, anchor: 0, at: 0)]))
    }

    func testATapFindsTheFrontClip() {
        var back = clip(id: "back")
        back.x = 0; back.y = 0; back.w = 100; back.h = 100
        var front = clip(id: "front")
        front.x = 50; front.y = 50; front.w = 100; front.h = 100
        let photo = Element.image("media:p")
        XCTAssertEqual(Videos.clip(at: CGPoint(x: 75, y: 75), in: [back, front, photo])?.id, "front")
        XCTAssertEqual(Videos.clip(at: CGPoint(x: 10, y: 10), in: [back, front])?.id, "back")
        XCTAssertNil(Videos.clip(at: CGPoint(x: 400, y: 400), in: [back, front]))
    }

    // MARK: sound

    func testWhatIsHeardFollowsWhatThePresenterDid() {
        let auto = clip(ClipPlayback(start: 2, speed: 2), id: "auto")
        var waiting = clip(ClipPlayback(autoplay: false), id: "wait")
        waiting.src = "video:vid_2"
        var paused = clip(id: "paused")
        paused.src = "video:vid_3"
        var played = clip(ClipPlayback(start: 2, speed: 2), id: "played")
        played.src = "video:vid_4"
        var design = Design(title: "talk", width: 320, height: 240)
        design.pages = [Page(elements: [auto, waiting, paused, played])]
        let overrides: [String: Videos.Override] = [
            "paused": .init(state: .paused, anchor: 1, at: 1),
            "played": .init(state: .playing, anchor: 6, at: 10),
        ]
        let heard = Videos.heard(design: design, page: design.pages[0], overrides: overrides)
        XCTAssertEqual(heard.map(\.clip.source), ["vid_1", "vid_4"])
        // From 6 s in at twice the speed: its clock read nought 2 s before 10.
        XCTAssertEqual(heard.map(\.shift), [0, 8])
        // Nothing done: the page's clips as AudioMix hears them, the waiting
        // one left out.
        XCTAssertEqual(Videos.heard(design: design, page: design.pages[0], overrides: [:]).map(\.clip.source),
                       ["vid_1", "vid_3", "vid_4"])
    }

    func testTheSpokenActionNamesTheClip() {
        var el = clip()
        XCTAssertEqual(Videos.spokenAction(el, moving: false), "Play video")
        el.altText = "Pouring a flat white"
        XCTAssertEqual(Videos.spokenAction(el, moving: false), "Play video, Pouring a flat white")
        XCTAssertEqual(Videos.spokenAction(el, moving: true), "Pause video, Pouring a flat white")
    }

    func testTheExportSaysWaitingClipsPlayAnyway() {
        var design = Design(title: "talk", width: 320, height: 240)
        design.pages = [Page(elements: [clip()])]
        XCTAssertFalse(Videos.anyWaiting(design))
        design.pages[0].elements[0].clip = ClipPlayback(autoplay: false)
        XCTAssertTrue(Videos.anyWaiting(design))
    }
}
