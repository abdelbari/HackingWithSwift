// Audio tracks: the `audio` array as both phones write it, the mix of every
// track in the video (AudioMix.plan, the same table as the Android twin's),
// the old soundtrack's track playing as the old plan did, fades, a talk in
// Present, each change to a track one undo step, what the sheet says, and
// the music a design file carries.

import XCTest
@testable import Canvia

final class AudioTracksTests: XCTestCase {

    /// Pages of these lengths in seconds, one after another, at 30 fps.
    private func pages(_ seconds: Double...) -> [MovieExporter.Timing] {
        var start = 0
        return seconds.map { s in
            defer { start += Int(s * 30) }
            return MovieExporter.Timing(start: start, frames: Int(s * 30), transition: "fade")
        }
    }

    private func track(_ id: String, start: Double = 0, trimStart: Double = 0, trimEnd: Double = -1,
                       volume: Double = 1, fadeIn: Double = 0, fadeOut: Double = 0, loop: Bool = false) -> AudioTrack {
        AudioTrack(id: "t-" + id, src: AudioTrack.src(id), start: start, trimStart: trimStart,
                   trimEnd: trimEnd < 0 ? nil : trimEnd, volume: volume, fadeIn: fadeIn, fadeOut: fadeOut, loop: loop)
    }

    private func segment(_ source: String, _ sourceStart: Double, _ at: Double, _ duration: Double, _ gain: Double,
                         fadeIn: ClosedRange<Double>? = nil, fadeOut: ClosedRange<Double>? = nil) -> AudioMix.Segment {
        AudioMix.Segment(source: source, sourceStart: sourceStart, at: at, duration: duration, gain: gain,
                         fadeOut: fadeOut, fadeIn: fadeIn)
    }

    private func assertPlan(_ plan: [AudioMix.Segment], _ want: [AudioMix.Segment], _ name: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(plan.count, want.count, name, file: file, line: line)
        for (want, got) in zip(want, plan) {
            XCTAssertEqual(got.source, want.source, name, file: file, line: line)
            XCTAssertEqual(got.sourceStart, want.sourceStart, accuracy: 1e-9, name, file: file, line: line)
            XCTAssertEqual(got.at, want.at, accuracy: 1e-9, name, file: file, line: line)
            XCTAssertEqual(got.duration, want.duration, accuracy: 1e-9, name, file: file, line: line)
            XCTAssertEqual(got.gain, want.gain, accuracy: 1e-9, name, file: file, line: line)
            XCTAssertEqual(got.fadeIn, want.fadeIn, name, file: file, line: line)
            XCTAssertEqual(got.fadeOut, want.fadeOut, name, file: file, line: line)
        }
    }

    // MARK: the plan

    func testTracksAreLaidAsOnAndroid() {
        let rows: [(name: String, timeline: [MovieExporter.Timing], tracks: [AudioTrack],
                    durations: [String: Double], segments: [AudioMix.Segment])] = [
            ("two tracks overlapping",
             pages(10), [track("a"), track("b", start: 3, volume: 0.5)], ["a": 6, "b": 4],
             [segment("a", 0, 0, 6, 1), segment("b", 0, 3, 4, 0.5)]),
            ("a trimmed track",
             pages(10), [track("t", start: 1, trimStart: 2, trimEnd: 5)], ["t": 10],
             [segment("t", 2, 1, 3, 1)]),
            ("a trim past the file's end stops at the end",
             pages(10), [track("t", trimStart: 8, trimEnd: 20)], ["t": 10],
             [segment("t", 8, 0, 2, 1)]),
            ("fades in and out",
             pages(10), [track("f", start: 1, fadeIn: 2, fadeOut: 1)], ["f": 8],
             [segment("f", 0, 1, 8, 1, fadeIn: 1...3, fadeOut: 8...9)]),
            ("a fade not under twice its length is not heard",
             pages(10), [track("g", fadeIn: 3, fadeOut: 0.5)], ["g": 5],
             [segment("g", 0, 0, 5, 1, fadeOut: 4.5...5)]),
            ("a fade past five seconds is five",
             pages(30), [track("h", fadeIn: 8)], ["h": 20],
             [segment("h", 0, 0, 20, 1, fadeIn: 0...5)]),
            ("loop to the end",
             pages(10), [track("l", start: 2, fadeOut: 1, loop: true)], ["l": 3],
             [segment("l", 0, 2, 3, 1, fadeOut: 9...10), segment("l", 0, 5, 3, 1, fadeOut: 9...10),
              segment("l", 0, 8, 2, 1, fadeOut: 9...10)]),
            ("a looping trimmed track",
             pages(5), [track("r", trimStart: 1, trimEnd: 3, loop: true)], ["r": 10],
             [segment("r", 1, 0, 2, 1), segment("r", 1, 2, 2, 1), segment("r", 1, 4, 1, 1)]),
            ("a track cut short by the film's end",
             pages(10), [track("c", start: 7)], ["c": 6],
             [segment("c", 0, 7, 3, 1)]),
            ("a track starting after the design ends is absent",
             pages(10), [track("late", start: 12), track("edge", start: 10)], ["late": 5, "edge": 5],
             []),
            ("a silent track, and one of no known length",
             pages(10), [track("q", volume: 0), track("unknown")], ["q": 5],
             []),
            ("a track across two pages",
             pages(3, 4), [track("x", start: 1)], ["x": 10],
             [segment("x", 0, 1, 6, 1)]),
            ("the same music on two tracks",
             pages(10), [track("s"), track("s", start: 5)], ["s": 3],
             [segment("s", 0, 0, 3, 1), segment("s", 0, 5, 3, 1)]),
            ("the migrated soundtrack",
             pages(10), [AudioTrack.migrated(soundtrack: "m", volume: 0.5)], ["m": 4],
             [segment("m", 0, 0, 4, 0.5, fadeOut: 9...10), segment("m", 0, 4, 4, 0.5, fadeOut: 9...10),
              segment("m", 0, 8, 2, 0.5, fadeOut: 9...10)]),
        ]
        for row in rows {
            let plan = AudioMix.plan(timeline: row.timeline, fps: 30, clipsByPage: [], clipDurations: [:],
                                     tracks: row.tracks, trackDurations: row.durations)
            assertPlan(plan, row.segments, row.name)
        }
    }

    /// The soundtrack a design had before tracks plays exactly as it did:
    /// the old plan's pieces, at its volume, under its fade — none on a film
    /// too short for one.
    func testTheMigratedSoundtrackPlaysAsTheOldPlanDid() {
        for (audio, film) in [(4.0, 10.0), (30.0, 5.0), (3.0, 1.5), (2.5, 2.0), (7.0, 7.0)] {
            let old = Soundtrack.plan(audioDuration: audio, videoDuration: film)
            let want = old.segments.map {
                segment("m", $0.sourceStart, $0.at, $0.duration, 0.7, fadeOut: old.fadeOut)
            }
            let plan = AudioMix.plan(timeline: pages(film), fps: 30, clipsByPage: [], clipDurations: [:],
                                     tracks: [AudioTrack.migrated(soundtrack: "m", volume: 0.7)],
                                     trackDurations: ["m": audio])
            assertPlan(plan, want, "\(audio)s of music under \(film)s")
        }
    }

    func testAFadeRisesFromNothingAndFallsToNothing() throws {
        let plan = AudioMix.plan(timeline: pages(10), fps: 30, clipsByPage: [], clipDurations: [:],
                                 tracks: [track("f", start: 1, volume: 0.8, fadeIn: 2, fadeOut: 1)],
                                 trackDurations: ["f": 8])
        let s = try XCTUnwrap(plan.first)
        XCTAssertEqual(s.gainAt(1), 0, accuracy: 1e-9)
        XCTAssertEqual(s.gainAt(2), 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.gainAt(3), 0.8, accuracy: 1e-9)
        XCTAssertEqual(s.gainAt(6), 0.8, accuracy: 1e-9)
        XCTAssertEqual(s.gainAt(8.5), 0.4, accuracy: 1e-9)
        XCTAssertEqual(s.gainAt(9), 0, accuracy: 1e-9)
    }

    /// In Present the talk has no end: a looping track goes round for as
    /// long as it runs, with no fade out, and one played once ends and fades
    /// as in the video.
    func testATalkLoopsATrackForAsLongAsItRuns() throws {
        let looping = try XCTUnwrap(AudioMix.span(of: track("l", start: 2, fadeIn: 1, fadeOut: 1, loop: true),
                                                  duration: 3, film: .infinity))
        XCTAssertEqual(looping.at, 2)
        XCTAssertEqual(looping.until, .infinity)
        XCTAssertEqual(looping.fadeIn, 2...3)
        XCTAssertNil(looping.fadeOut)
        XCTAssertTrue(looping.segments.isEmpty, "a span with no end lays nothing in a video")
        let once = try XCTUnwrap(AudioMix.span(of: track("o", start: 2, fadeOut: 1), duration: 4, film: .infinity))
        XCTAssertEqual(once.until, 6)
        XCTAssertEqual(once.fadeOut, 5...6)
    }

    func testTheFilmIsAsLongAsItsShownPages() {
        var d = Design(title: "film", width: 320, height: 240)
        d.pages = [Page(), Page(), Page()]
        for (i, hold) in [2.0, 3.0, 4.0].enumerated() { d.pages[i].holdSeconds = hold }
        XCTAssertEqual(AudioMix.filmLength(design: d), 9, accuracy: 1e-9)
        d.pages[1].hidden = true
        XCTAssertEqual(AudioMix.filmLength(design: d), 6, accuracy: 1e-9)
    }

    // MARK: the file

    func testATrackIsWrittenWithTheSharedKeys() throws {
        var d = Design(title: "keys")
        d.audio = [AudioTrack(id: "t1", src: "audio:song.m4a", start: 2, trimStart: 1, trimEnd: 4, volume: 0.5,
                              fadeIn: 1, fadeOut: 2, loop: true, name: "Song"),
                   AudioTrack(id: "t2", src: "audio:voice.m4a")]
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
        let tracks = try XCTUnwrap(object["audio"] as? [[String: Any]])
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(Set(tracks[0].keys),
                       ["id", "src", "start", "trimStart", "trimEnd", "volume", "fadeIn", "fadeOut", "loop", "name"])
        XCTAssertEqual(tracks[0]["src"] as? String, "audio:song.m4a")
        XCTAssertEqual(tracks[0]["trimEnd"] as? Double, 4)
        XCTAssertEqual(tracks[0]["loop"] as? Bool, true)
        XCTAssertNil(tracks[1]["trimEnd"], "to the file's end writes no trimEnd")
        XCTAssertEqual(tracks[1]["volume"] as? Double, 1)
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.audio, d.audio)

        // None is no key at all.
        d.audioTracks = []
        XCTAssertNil(d.audio)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any]
        XCTAssertNil(plain?["audio"])
    }

    /// Keys left out are the defaults; a track with no "audio:" source is
    /// dropped, and only it.
    func testTracksAreReadLeniently() throws {
        let json = #"{"audio":[{"src":"audio:a.m4a","start":"soon"},{"src":"media:img"},{"id":"x"},{"id":"v","src":"audio:v.m4a","loop":true,"fadeIn":1.5}]}"#
        let d = try JSONDecoder().decode(Design.self, from: Data(json.utf8))
        XCTAssertEqual(d.audioTracks.map(\.audioId), ["a.m4a", "v.m4a"])
        let first = d.audioTracks[0]
        XCTAssertEqual(first.start, 0)
        XCTAssertEqual(first.trimStart, 0)
        XCTAssertNil(first.trimEnd)
        XCTAssertEqual(first.volume, 1)
        XCTAssertEqual(first.fadeIn, 0)
        XCTAssertEqual(first.fadeOut, 0)
        XCTAssertFalse(first.loop)
        XCTAssertEqual(first.name, "")
        XCTAssertFalse(first.id.isEmpty)
        XCTAssertEqual(d.audioTracks[1].id, "v")
        XCTAssertTrue(d.audioTracks[1].loop)
        XCTAssertEqual(d.audioTracks[1].fadeIn, 1.5)
        let none = try JSONDecoder().decode(Design.self, from: Data(#"{"audio":[{"src":"audio:"}]}"#.utf8))
        XCTAssertNil(none.audio)
    }

    func testMusicPacksInIdOrderWithinItsBudget() {
        let mb = 1024 * 1024
        let files: [String: (bytes: Int, ext: String)] = [
            "a.m4a": (bytes: 20 * mb, ext: "m4a"),
            "b.mp3": (bytes: 20 * mb, ext: "mp3"),
            "c.ogg": (bytes: mb, ext: "ogg"),
            "d.wav": (bytes: 20 * mb + 1, ext: "wav"),
            "e.m4a": (bytes: 20 * mb, ext: "m4a"),
            "f.m4a": (bytes: 20 * mb, ext: "m4a"),
            "g.m4a": (bytes: 20 * mb, ext: "m4a"),
            "h.aac": (bytes: 20 * mb, ext: "aac"),
            "i.m4a": (bytes: mb, ext: "m4a"),
        ]
        XCTAssertEqual(Soundtrack.maxPackedTotalBytes, 100 * mb)
        // Five of twenty fill the hundred; a sixth does not go in, nor a
        // file of a type the other phone cannot play, nor one too long.
        XCTAssertEqual(Soundtrack.packed(files), ["a.m4a", "b.mp3", "e.m4a", "f.m4a", "g.m4a"])
        XCTAssertEqual(Soundtrack.packed(["i.m4a": (bytes: mb, ext: "m4a")]), ["i.m4a"])
        XCTAssertTrue(Soundtrack.packed([:]).isEmpty)
    }

    // MARK: the sheet

    @MainActor
    func testEachTrackChangeIsOneStep() throws {
        let s = DesignStore(design: Design(title: "audio", width: 1000, height: 1000))
        let added = s.addAudioTrack("song.m4a", start: 2.04, name: "Song")
        XCTAssertEqual(s.design.audioTracks, [added])
        XCTAssertEqual(added.start, 2, "kept to the tenth the sheet shows")
        XCTAssertEqual(added.src, "audio:song.m4a")
        XCTAssertFalse(added.loop)
        s.updateAudioTrack(added.id) { $0.fadeIn = 1.5 }
        s.updateAudioTrack(added.id) { $0.loop = true }
        s.updateAudioTrack(added.id) { $0.loop = true }
        XCTAssertEqual(s.design.audioTracks.first?.fadeIn, 1.5)
        s.undo()
        XCTAssertEqual(s.design.audioTracks.first?.loop, false, "one step for the loop, none for no change")
        XCTAssertEqual(s.design.audioTracks.first?.fadeIn, 1.5)
        s.undo()
        XCTAssertEqual(s.design.audioTracks.first?.fadeIn, 0, "one step for the fade")
        s.removeAudioTrack(added.id)
        XCTAssertNil(s.design.audio)
        s.undo()
        XCTAssertEqual(s.design.audioTracks.count, 1, "one step for the delete")
        s.undo()
        XCTAssertNil(s.design.audio, "one step for the add")
    }

    @MainActor
    func testPlayIsOfferedOnAPageWithTracksUnderIt() {
        let s = DesignStore(design: Design(title: "still", width: 1000, height: 1000))
        XCTAssertFalse(s.pagePlays, "a still page with no sound has nothing to play")
        s.addAudioTrack("song.m4a", name: "Song")
        XCTAssertTrue(s.pagePlays)
    }

    func testTheSheetSaysEachTrack() {
        let t = AudioTrack(src: "audio:song.m4a", start: 2, trimStart: 1, trimEnd: 4, name: "Song")
        XCTAssertEqual(AudioTracks.name(of: t), "Song")
        XCTAssertEqual(AudioTracks.name(of: AudioTrack(src: "audio:gone.m4a")), "Music from another phone")
        XCTAssertEqual(AudioTracks.summary(of: t, duration: 10), "Starts at 0:02.0 · 0:03.0 long")
        XCTAssertEqual(AudioTracks.summary(of: t, duration: nil), "Starts at 0:02.0")
        var looped = t
        looped.loop = true
        XCTAssertEqual(AudioTracks.summary(of: looped, duration: 2.5), "Starts at 0:02.0 · 0:01.5 long · loops")
        XCTAssertEqual(AudioTracks.secondsLabel(1.5), "1.5s")
    }
}
