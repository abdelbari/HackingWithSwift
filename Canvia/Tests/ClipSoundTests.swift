// Sound: each clip's volume and mute in its `clip` JSON, the mix of clips
// and audio tracks in the video (AudioMix.plan, the same tables as the
// Android twin's), where the music starts in Play, the clips a page is heard
// with, the tracks' music travelling in a design file, and the video
// carrying a clip's sound.

import AVFoundation
import XCTest
@testable import Canvia

final class ClipSoundTests: XCTestCase {

    // MARK: the plan

    /// Pages of these lengths in seconds, one after another, at 30 fps.
    private func pages(_ seconds: Double...) -> [MovieExporter.Timing] {
        var start = 0
        return seconds.map { s in
            defer { start += Int(s * 30) }
            return MovieExporter.Timing(start: start, frames: Int(s * 30), transition: "fade")
        }
    }

    private func clip(_ source: String, _ playback: ClipPlayback = ClipPlayback(),
                      timing: ElementTiming? = nil) -> AudioMix.Clip {
        AudioMix.Clip(source: source, playback: playback, timing: timing)
    }

    private func segment(_ source: String, _ sourceStart: Double, _ at: Double, _ duration: Double, _ gain: Double,
                         _ fadeOut: ClosedRange<Double>? = nil, fadeIn: ClosedRange<Double>? = nil,
                         speed: Double = 1) -> AudioMix.Segment {
        AudioMix.Segment(source: source, sourceStart: sourceStart, at: at, duration: duration, gain: gain,
                         fadeOut: fadeOut, fadeIn: fadeIn, speed: speed)
    }

    /// The old soundtrack `source`, `volume` loud, as the track it is read
    /// in as.
    private func soundtrack(_ source: String, volume: Double) -> [AudioTrack] {
        [AudioTrack.migrated(soundtrack: source, volume: volume)]
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
            XCTAssertEqual(got.fadeOut, want.fadeOut, name, file: file, line: line)
            XCTAssertEqual(got.fadeIn, want.fadeIn, name, file: file, line: line)
            XCTAssertEqual(got.speed, want.speed, accuracy: 1e-9, name, file: file, line: line)
        }
    }

    func testClipsAndTheSoundtrackAreLaidAsOnAndroid() {
        let rows: [(name: String, timeline: [MovieExporter.Timing], clipsByPage: [[AudioMix.Clip]],
                    durations: [String: Double], tracks: [AudioTrack], segments: [AudioMix.Segment])] = [
            ("a looping clip over a longer page",
             pages(10), [[clip("a")]], ["a": 4], [],
             [segment("a", 0, 0, 4, 1), segment("a", 0, 4, 4, 1), segment("a", 0, 8, 2, 1)]),
            ("a clip shorter than its page, not looping",
             pages(10), [[clip("a", ClipPlayback(loop: false))]], ["a": 4], [],
             [segment("a", 0, 0, 4, 1)]),
            ("a trimmed clip",
             pages(5), [[clip("a", ClipPlayback(start: 2, end: 5))]], ["a": 10], [],
             [segment("a", 2, 0, 3, 1), segment("a", 2, 3, 2, 1)]),
            ("a muted clip",
             pages(5), [[clip("a", ClipPlayback(muted: true))]], ["a": 10], [],
             []),
            ("two pages each with a clip",
             pages(3, 4), [[clip("a")], [clip("b", ClipPlayback(volume: 0.5))]], ["a": 10, "b": 10], [],
             [segment("a", 0, 0, 3, 1), segment("b", 0, 3, 4, 0.5)]),
            ("the soundtrack and a clip",
             pages(10), [[clip("a", ClipPlayback(loop: false, volume: 0.8))]], ["a": 4, "m": 6],
             soundtrack("m", volume: 0.5),
             [segment("a", 0, 0, 4, 0.8), segment("m", 0, 0, 6, 0.5, 9...10), segment("m", 0, 6, 4, 0.5, 9...10)]),
            ("a clip at double speed, a silent one, and one of no known length",
             pages(5), [[clip("a", ClipPlayback(speed: 2)), clip("b", ClipPlayback(volume: 0)), clip("c")]],
             ["a": 10, "b": 10], [],
             [segment("a", 0, 0, 5, 1, speed: 2)]),
            ("a looping clip at double speed goes round twice as often",
             pages(5), [[clip("a", ClipPlayback(speed: 2))]], ["a": 4], [],
             [segment("a", 0, 0, 2, 1, speed: 2), segment("a", 0, 2, 2, 1, speed: 2), segment("a", 0, 4, 1, 1, speed: 2)]),
            ("a trimmed clip at a quarter speed",
             pages(4), [[clip("a", ClipPlayback(start: 2, speed: 0.25))]], ["a": 10], [],
             [segment("a", 2, 0, 4, 1, speed: 0.25)]),
            ("a timed clip at double speed, cut where its window has got to",
             pages(4), [[clip("a", ClipPlayback(speed: 2), timing: ElementTiming(start: 1))]], ["a": 10], [],
             [segment("a", 2, 1, 3, 1, speed: 2)]),
            ("a timed clip, heard only while it shows",
             pages(6), [[clip("a", timing: ElementTiming(start: 3, end: 5))]], ["a": 10], [],
             [segment("a", 3, 3, 2, 1)]),
            ("a looping clip shown from 3 s, cut where its loop has got to",
             pages(10), [[clip("a", timing: ElementTiming(start: 3))]], ["a": 4], [],
             [segment("a", 3, 3, 1, 1), segment("a", 0, 4, 4, 1), segment("a", 0, 8, 2, 1)]),
            ("a clip shown only after it has played out",
             pages(10), [[clip("a", ClipPlayback(loop: false), timing: ElementTiming(start: 5))]], ["a": 4], [],
             []),
            ("a timed clip whose end is past its page's",
             pages(5), [[clip("a", timing: ElementTiming(start: 1, end: 8))]], ["a": 10], [],
             [segment("a", 1, 1, 4, 1)]),
            ("a timed clip on the second page",
             pages(3, 4), [[], [clip("b", timing: ElementTiming(start: 0.5, end: 2))]], ["b": 10], [],
             [segment("b", 0.5, 3.5, 1.5, 1)]),
        ]
        for row in rows {
            // Durations by source: the clips' and the tracks' music alike.
            let plan = AudioMix.plan(timeline: row.timeline, fps: 30, clipsByPage: row.clipsByPage,
                                     clipDurations: row.durations, tracks: row.tracks, trackDurations: row.durations)
            assertPlan(plan, row.segments, row.name)
        }
    }

    func testTheSoundtrackFadesOutOverTheFilmsLastSecond() throws {
        let plan = AudioMix.plan(timeline: pages(10), fps: 30, clipsByPage: [[]], clipDurations: [:],
                                 tracks: soundtrack("m", volume: 0.8), trackDurations: ["m": 20])
        XCTAssertEqual(plan.count, 1)
        let music = try XCTUnwrap(plan.first)
        XCTAssertEqual(music.gainAt(5), 0.8, accuracy: 1e-9)
        XCTAssertEqual(music.gainAt(9.5), 0.4, accuracy: 1e-9)
        XCTAssertEqual(music.gainAt(10), 0, accuracy: 1e-9)
        // Silent music is no music.
        XCTAssertTrue(AudioMix.plan(timeline: pages(10), fps: 30, clipsByPage: [[]], clipDurations: [:],
                                    tracks: soundtrack("m", volume: 0), trackDurations: ["m": 20]).isEmpty)
    }

    func testTheMusicInPlayStartsWhereThePageStartsInTheFilm() {
        var d = Design(title: "starts", width: 320, height: 240)
        d.pages = [Page(), Page(), Page()]
        for (i, hold) in [2.0, 3.0, 4.0].enumerated() { d.pages[i].holdSeconds = hold }
        XCTAssertEqual(AudioMix.pageStart(design: d, index: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(AudioMix.pageStart(design: d, index: 2), 5, accuracy: 1e-9)
        // A hidden page is not in the film: the pages after it start
        // sooner, and it plays from where it would be.
        d.pages[1].hidden = true
        XCTAssertEqual(AudioMix.pageStart(design: d, index: 1), 2, accuracy: 1e-9)
        XCTAssertEqual(AudioMix.pageStart(design: d, index: 2), 2, accuracy: 1e-9)
    }

    func testAVoiceOverPlaysTheShownPagesFromItsPageOnAHiddenOneFromTheNextShownPage() {
        var d = Design(title: "through", width: 320, height: 240)
        d.pages = [Page(), Page(), Page(), Page()]
        d.pages[1].hidden = true
        d.pages[3].hidden = true
        XCTAssertEqual(AudioMix.playedThrough(design: d, index: 0), [0, 2])
        XCTAssertEqual(AudioMix.playedThrough(design: d, index: 1), [2])
        XCTAssertEqual(AudioMix.playedThrough(design: d, index: 2), [2])
        // No shown page after a hidden one: it plays alone.
        XCTAssertEqual(AudioMix.playedThrough(design: d, index: 3), [3])
    }

    func testTheClipsHeardOnAPageAreItsOwnAndTheMastersNeverABackgroundOrAFill() {
        let master = Page(elements: [Element.image("video:vid-m")])
        var fill = Element.shape("rect")
        fill.fill = .image("video:vid-f")
        var muted = Element.image("video:vid-x")
        muted.clip = ClipPlayback(muted: true)
        let page = Page(background: .image("video:vid-bg"),
                        elements: [fill, Element.image("video:vid-1@2.00"), Element.image("media:gif"), muted])
        var design = Design(title: "heard", width: 320, height: 240)
        design.pages = [master, page]
        design.masterPageId = master.id
        XCTAssertEqual(AudioMix.clips(design: design, page: design.pages[1]).map(\.source), ["vid-m", "vid-1"])
        // The master's own page hears its clip once.
        XCTAssertEqual(AudioMix.clips(design: design, page: design.pages[0]).map(\.source), ["vid-m"])
        // Each with its own timing, which is when it is heard.
        var timed = Element.image("video:vid-t")
        timed.timing = ElementTiming(start: 1, end: 2)
        var timedDesign = Design(title: "timed", width: 320, height: 240)
        timedDesign.pages = [Page(elements: [timed, Element.image("video:vid-u")])]
        XCTAssertEqual(AudioMix.clips(design: timedDesign, page: timedDesign.pages[0]).map(\.timing),
                       [ElementTiming(start: 1, end: 2), nil])
    }

    // MARK: volume and mute

    private func clipElement(_ clip: String?) throws -> Element {
        let extra = clip.map { ", \"clip\": \($0)" } ?? ""
        let json = "{\"id\": \"v1\", \"type\": \"image\", \"src\": \"video:vid_1\"\(extra)}"
        return try JSONDecoder().decode(Element.self, from: Data(json.utf8))
    }

    private func clipObject(_ el: Element) throws -> [String: Any]? {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any]
        return object?["clip"] as? [String: Any]
    }

    func testAnOldClipIsHeardAtFullVolume() throws {
        let el = try clipElement(nil)
        let clip = el.clip ?? ClipPlayback()
        XCTAssertEqual(clip.volume, 1)
        XCTAssertFalse(clip.muted)
        XCTAssertTrue(clip.sounds)
        XCTAssertNil(try clipElement("{\"volume\": 1, \"muted\": false}").clip, "both at their defaults is no clip")
    }

    func testVolumeAndMuteAreWrittenOnlyWhenTheyDiffer() throws {
        let el = try clipElement("{\"volume\": 0.35, \"muted\": true}")
        XCTAssertEqual(el.clip, ClipPlayback(volume: 0.35, muted: true))
        let written = try XCTUnwrap(try clipObject(el))
        XCTAssertEqual(written["volume"] as? Double, 0.35)
        XCTAssertEqual(written["muted"] as? Bool, true)
        XCTAssertEqual(Set(written.keys), ["volume", "muted"])
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.clip, el.clip)

        let trimmed = try XCTUnwrap(try clipObject(try clipElement("{\"start\": 2, \"volume\": 1, \"muted\": false}")))
        XCTAssertEqual(Set(trimmed.keys), ["start"], "full volume and unmuted are left out")
        XCTAssertNil(try clipElement("{\"volume\": \"loud\"}").clip, "an odd volume reads as full")
    }

    func testAnUnmutedAudibleClipSoundsAtAnySpeed() {
        XCTAssertTrue(ClipPlayback().sounds)
        XCTAssertTrue(ClipPlayback(start: 2, end: 4, loop: false, volume: 0.1).sounds)
        XCTAssertFalse(ClipPlayback(muted: true).sounds)
        XCTAssertFalse(ClipPlayback(volume: 0).sounds)
        XCTAssertTrue(ClipPlayback(speed: 1.5).sounds)
        XCTAssertTrue(ClipPlayback(speed: 0.25).sounds)
        XCTAssertFalse(ClipPlayback(speed: 2, muted: true).sounds)
    }

    @MainActor
    func testTheClipSheetSaysVolumeAsAPercentage() {
        XCTAssertEqual(ClipSheet.percentLabel(0), "0%")
        XCTAssertEqual(ClipSheet.percentLabel(0.355), "36%")
        XCTAssertEqual(ClipSheet.percentLabel(1), "100%")
    }

    /// Seven speeds, a quarter to twice, as the Android twin's panel offers
    /// them; a file's speed is still read from a quarter to four times.
    @MainActor
    func testTheClipSheetOffersSevenSpeeds() {
        XCTAssertEqual(ClipPlayback.speeds, [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2])
        XCTAssertEqual(ClipPlayback.speeds.map(ClipSheet.speedLabel), ["0.25×", "0.5×", "0.75×", "1×", "1.25×", "1.5×", "2×"])
        XCTAssertEqual(ClipPlayback.speedRange, 0.25...4.0)
        XCTAssertEqual(ClipPlayback(speed: 10).playbackSpeed, 4)
        XCTAssertEqual(ClipPlayback(speed: 0.1).playbackSpeed, 0.25)
    }

    // MARK: fades

    /// The clips' fades, in the plan as the Android twin lays them: once a
    /// page, rising from where the clip is first heard on it and falling to
    /// where it is last heard, each only when the clip sounds there for more
    /// than twice its length — the rule a track's fades follow.
    func testAClipsFadesAreLaidOverWhereItIsHeardOnItsPage() {
        let rows: [(name: String, timeline: [MovieExporter.Timing], clipsByPage: [[AudioMix.Clip]],
                    durations: [String: Double], segments: [AudioMix.Segment])] = [
            ("a looping clip fading in 1 s and out 2 s over its page",
             pages(10), [[clip("a", ClipPlayback(fadeIn: 1, fadeOut: 2))]], ["a": 4],
             [segment("a", 0, 0, 4, 1, 8...10, fadeIn: 0...1), segment("a", 0, 4, 4, 1, 8...10, fadeIn: 0...1),
              segment("a", 0, 8, 2, 1, 8...10, fadeIn: 0...1)]),
            ("a fade in too long for a short page is not heard; the fade out is",
             pages(3), [[clip("a", ClipPlayback(fadeIn: 2, fadeOut: 1))]], ["a": 10],
             [segment("a", 0, 0, 3, 1, 2...3)]),
            ("a clip at half speed played once fades out at its own end",
             pages(10), [[clip("a", ClipPlayback(start: 1, end: 3, speed: 0.5, loop: false, fadeOut: 1))]], ["a": 10],
             [segment("a", 1, 0, 4, 1, 3...4, speed: 0.5)]),
            ("a timed clip on the second page fades in from where it shows",
             pages(3, 4), [[], [clip("b", ClipPlayback(fadeIn: 0.5), timing: ElementTiming(start: 0.5, end: 2))]],
             ["b": 10],
             [segment("b", 0.5, 3.5, 1.5, 1, fadeIn: 3.5...4)]),
            ("a fade past five seconds is heard as five",
             pages(20), [[clip("a", ClipPlayback(volume: 0.5, fadeOut: 9))]], ["a": 30],
             [segment("a", 0, 0, 20, 0.5, 15...20)]),
        ]
        for row in rows {
            let plan = AudioMix.plan(timeline: row.timeline, fps: 30, clipsByPage: row.clipsByPage,
                                     clipDurations: row.durations)
            assertPlan(plan, row.segments, row.name)
        }
    }

    /// The fade rule a track's and a clip's share, row for row with the
    /// Android twin's.
    func testTheFadeRuleIsATracksAndAClipsAlike() {
        let rows: [(fadeIn: Double, fadeOut: Double, heard: Double, until: Double,
                    want: (ClosedRange<Double>?, ClosedRange<Double>?))] = [
            (1, 1, 0, 10, (0...1, 9...10)),
            (3, 0, 0, 5, (nil, nil)),
            (7, 7, 0, 20, (0...5, 15...20)),
            (1, 1, 2, .infinity, (2...3, nil)),
            (-1, 0.5, 4, 6, (nil, 5.5...6)),
        ]
        for row in rows {
            let got = AudioMix.fades(fadeIn: row.fadeIn, fadeOut: row.fadeOut, heard: row.heard, until: row.until)
            XCTAssertEqual(got.fadeIn, row.want.0, "\(row)")
            XCTAssertEqual(got.fadeOut, row.want.1, "\(row)")
        }
    }

    /// Where a clip is heard on its page: its timing, the page, and — played
    /// once — its window at its speed.
    func testWhereAClipIsHeardOnItsPage() {
        XCTAssertEqual(AudioMix.clipHeard(ClipPlayback(), window: 4, timing: nil, page: 10), 0...10)
        XCTAssertEqual(AudioMix.clipHeard(ClipPlayback(speed: 2, loop: false), window: 4, timing: nil, page: 10), 0...2)
        XCTAssertEqual(AudioMix.clipHeard(ClipPlayback(), window: 4, timing: ElementTiming(start: 3, end: 5), page: nil),
                       3...5)
        XCTAssertNil(AudioMix.clipHeard(ClipPlayback(loop: false), window: 1, timing: ElementTiming(start: 3), page: 10))
        XCTAssertEqual(AudioMix.clipHeard(ClipPlayback(), window: 4, timing: nil, page: nil)?.upperBound, .infinity)
        // A page with no end — a talk in Present — fades a looping clip in,
        // never out.
        let present = AudioMix.clipFades(ClipPlayback(fadeIn: 1, fadeOut: 1), heard: 0...Double.infinity)
        XCTAssertEqual(present.fadeIn, 0...1)
        XCTAssertNil(present.fadeOut)
    }

    /// A clip's fade rises and falls on its gain.
    func testAClipsFadeRisesAndFallsOnItsGain() throws {
        let plan = AudioMix.plan(timeline: pages(10), fps: 30, clipsByPage: [[clip("a", ClipPlayback(volume: 0.8,
                                 fadeIn: 2, fadeOut: 2))]], clipDurations: ["a": 20])
        let sound = try XCTUnwrap(plan.first)
        XCTAssertEqual(sound.gainAt(0), 0, accuracy: 1e-9)
        XCTAssertEqual(sound.gainAt(1), 0.4, accuracy: 1e-9)
        XCTAssertEqual(sound.gainAt(5), 0.8, accuracy: 1e-9)
        XCTAssertEqual(sound.gainAt(9.5), 0.2, accuracy: 1e-9)
        XCTAssertEqual(sound.gainAt(10), 0, accuracy: 1e-9)
    }

    /// A sped-up stretch takes its length times its speed of the file, and
    /// lasts its length over its speed in the composition.
    func testASpedUpStretchIsScaledInTheComposition() {
        XCTAssertEqual(segment("a", 0, 0, 3, 1, speed: 2).sourceDuration, 6, accuracy: 1e-9)
        XCTAssertEqual(segment("a", 0, 0, 3, 1, speed: 0.5).sourceDuration, 1.5, accuracy: 1e-9)
        let two = CMTime(seconds: 2, preferredTimescale: 600)
        XCTAssertEqual(PageSound.scaled(two, speed: 1), two)
        XCTAssertEqual(PageSound.scaled(two, speed: 2).seconds, 1, accuracy: 1e-6)
        XCTAssertEqual(PageSound.scaled(two, speed: 0.25).seconds, 8, accuracy: 1e-6)
    }

    func testFadesAreWrittenOnlyAboveZeroAndReadForgivingly() throws {
        let el = try clipElement("{\"fadeIn\": 1.5, \"fadeOut\": 0}")
        XCTAssertEqual(el.clip, ClipPlayback(fadeIn: 1.5))
        let written = try XCTUnwrap(try clipObject(el))
        XCTAssertEqual(Set(written.keys), ["fadeIn"])
        XCTAssertEqual(written["fadeIn"] as? Double, 1.5)
        let both = try XCTUnwrap(try clipObject(try clipElement("{\"fadeIn\": 2, \"fadeOut\": 5, \"speed\": 0.25}")))
        XCTAssertEqual(both["fadeOut"] as? Double, 5)
        XCTAssertEqual(both["speed"] as? Double, 0.25)
        XCTAssertNil(try clipElement("{\"fadeIn\": \"slow\"}").clip, "an odd fade reads as none")
        XCTAssertNil(try clipElement("{\"fadeIn\": 0, \"fadeOut\": 0}").clip, "no fades is no clip")
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(el))
        XCTAssertEqual(back.clip, el.clip)
    }

    @MainActor
    func testTheClipSheetStepsAFadeByHalfSeconds() {
        XCTAssertEqual(ClipSheet.halves(1.2), 1)
        XCTAssertEqual(ClipSheet.halves(1.3), 1.5)
        XCTAssertEqual(ClipSheet.halves(4.9), 5)
        XCTAssertEqual(ClipPlayback.fadeRange, 0...5)
    }

    @MainActor
    func testAFadeIsOneStep() {
        var design = Design(title: "fades", width: 1000, height: 1000)
        let clip = Element.image(VideoStore.src("vid_1", at: nil), w: 320, h: 180)
        design.pages[0].elements = [clip]
        let s = DesignStore(design: design)
        s.select(clip.id)
        s.setClip(ClipPlayback(fadeIn: 1.5))
        XCTAssertEqual(s.element(clip.id)?.clip?.fadeIn, 1.5)
        s.setClip(ClipPlayback(fadeIn: 1.5, fadeOut: 2))
        s.undo()
        XCTAssertEqual(s.element(clip.id)?.clip, ClipPlayback(fadeIn: 1.5))
        s.undo()
        XCTAssertNil(s.element(clip.id)?.clip)
    }

    @MainActor
    func testVolumeAndMuteAreEachOneStep() throws {
        var design = Design(title: "sound", width: 1000, height: 1000)
        let clip = Element.image(VideoStore.src("vid_1", at: nil), w: 320, h: 180)
        design.pages[0].elements = [clip]
        let s = DesignStore(design: design)
        s.select(clip.id)
        s.setClip(ClipPlayback(volume: 0.4))
        XCTAssertEqual(s.element(clip.id)?.clip?.volume, 0.4)
        s.setClip(ClipPlayback(volume: 0.4, muted: true))
        XCTAssertEqual(s.element(clip.id)?.clip?.muted, true)
        s.undo()
        XCTAssertEqual(s.element(clip.id)?.clip, ClipPlayback(volume: 0.4), "one step for the mute")
        s.undo()
        XCTAssertNil(s.element(clip.id)?.clip, "one step for the volume")
    }

    // MARK: the design file

    func testMusicTravelsWhenItIsSmallEnoughAndOfATypeBothPhonesPlay() {
        let mb = 1024 * 1024
        XCTAssertTrue(Soundtrack.packs(bytes: 20 * mb, ext: "MP3"))
        XCTAssertTrue(Soundtrack.packs(bytes: mb, ext: "wav"))
        XCTAssertTrue(Soundtrack.packs(bytes: mb, ext: "aac"))
        XCTAssertFalse(Soundtrack.packs(bytes: 20 * mb + 1, ext: "m4a"))
        XCTAssertFalse(Soundtrack.packs(bytes: mb, ext: "ogg"))
        XCTAssertFalse(Soundtrack.packs(bytes: 0, ext: "m4a"))
    }

    func testEveryTracksMusicTravelsUnderAudioAndComesBackPlayedByItsTracks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = dir.appendingPathComponent("Song.m4a")
        let bytes = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 * 7) })
        try bytes.write(to: song)
        let id = try XCTUnwrap(AudioStore.store(song))
        let voice = dir.appendingPathComponent("Voice.m4a")
        try Data([9, 8, 7]).write(to: voice)
        let spoken = try XCTUnwrap(AudioStore.store(voice))
        defer { for id in [id, spoken] { AudioStore.delete(id) } }

        var d = Design(title: "Scored", width: 400, height: 300)
        d.audio = [AudioTrack(src: AudioTrack.src(id), volume: 0.5, loop: true),
                   AudioTrack(src: AudioTrack.src(spoken), start: 2.5, name: "Voice-over 1"),
                   AudioTrack(src: AudioTrack.src(id), start: 4, trimStart: 1, trimEnd: 3)]
        let data = try DesignPackage.export(d, mediaDirectory: dir)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let audio = try XCTUnwrap(object["audio"] as? [String: Any])
        XCTAssertEqual(Set(audio.keys), [id, spoken], "each file once, however many tracks play it")
        let packed = try XCTUnwrap(audio[id] as? [String: Any])
        XCTAssertEqual(packed["ext"] as? String, "m4a")
        XCTAssertEqual((packed["data"] as? String).flatMap { Data(base64Encoded: $0) }, bytes)

        // Stored under fresh ids, each track points at its music again, all
        // else kept.
        let back = try DesignPackage.import(data, mediaDirectory: dir)
        let moved = back.audioTracks.compactMap(\.audioId)
        defer { for id in Set(moved) { AudioStore.delete(id) } }
        XCTAssertEqual(moved.count, 3)
        XCTAssertFalse(moved.contains(id))
        XCTAssertFalse(moved.contains(spoken))
        XCTAssertEqual(moved[0], moved[2], "two tracks of one song still share it")
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(AudioStore.url(for: moved[0]))), bytes)
        XCTAssertEqual(back.audioTracks[0].volume, 0.5)
        XCTAssertEqual(back.audioTracks[1].start, 2.5)
        XCTAssertEqual(back.audioTracks[1].name, "Voice-over 1")
        XCTAssertEqual(back.audioTracks[2].trimEnd, 3)

        // No music, or music not on this phone, writes no "audio".
        let plain = try JSONSerialization.jsonObject(with: DesignPackage.export(Design(title: "Quiet"), mediaDirectory: dir)) as? [String: Any]
        XCTAssertNil(plain?["audio"])
        var elsewhere = d
        elsewhere.audio = [AudioTrack(src: "audio:audio_elsewhere.m4a")]
        let away = try DesignPackage.import(try DesignPackage.export(elsewhere, mediaDirectory: dir), mediaDirectory: dir)
        XCTAssertEqual(away.audioTracks.map(\.src), ["audio:audio_elsewhere.m4a"], "music that did not travel is left as it was")
    }

    /// A file written by the Android twin before tracks, music first as the
    /// sorted keys put it, opens with its music as one track; the file type
    /// it names is kept to letters and digits.
    func testADesignFileWithMusicFromAndroidOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let d = Design(title: "From Android", width: 400, height: 300)
        var design = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as? [String: Any])
        design["motion"] = ["secondsPerPage": 2.5, "fps": 30, "movement": true, "crossfade": true,
                            "soundtrack": "audio-1.m4a", "soundVolume": 0.6] as [String: Any]
        let file: [String: Any] = [
            "audio": ["audio-1.m4a": ["data": "AQID", "ext": "../m4a"]],
            "design": design, "format": "canvia-package", "media": [String: Any](), "version": 1,
        ]
        let back = try DesignPackage.import(try JSONSerialization.data(withJSONObject: file), mediaDirectory: dir)
        let track = try XCTUnwrap(back.audio?.first)
        let moved = try XCTUnwrap(track.audioId)
        defer { AudioStore.delete(moved) }
        XCTAssertTrue(moved.hasSuffix(".m4a"), moved)
        XCTAssertFalse(moved.contains("/"))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(AudioStore.url(for: moved))), Data([1, 2, 3]))
        XCTAssertEqual(track.volume, 0.6)
        XCTAssertTrue(track.loop)
    }

    // MARK: the video

    /// One second of a tone as a WAV file.
    private func tone(seconds: Double, rate: Int = 44_100) -> Data {
        var pcm = Data()
        for i in 0..<Int(seconds * Double(rate)) {
            let v = Int16(sin(Double(i) * 2 * .pi * 440 / Double(rate)) * 8000)
            withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var d = Data()
        func text(_ s: String) { d.append(contentsOf: Array(s.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + pcm.count)); text("WAVE")
        text("fmt "); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        text("data"); u32(UInt32(pcm.count))
        d.append(pcm)
        return d
    }

    private func audioTracks(_ url: URL) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).count
    }

    /// A clip's own sound goes into the video, music or none; muted, it
    /// does not.
    @MainActor
    func testAClipsSoundIsInTheVideoWithoutASoundtrack() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sound-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wav = dir.appendingPathComponent("tone.wav")
        try tone(seconds: 1).write(to: wav)
        let music = try XCTUnwrap(AudioStore.store(wav))
        defer { AudioStore.delete(music) }

        // A clip with sound in it: a second of video with the tone under it.
        var scored = Design(title: "scored", width: 320, height: 240)
        var m = MotionSettings(); m.secondsPerPage = 1; m.fps = 24; m.movement = false; m.crossfade = false
        scored.motion = m
        scored.audio = [AudioTrack(src: AudioTrack.src(music), loop: true)]
        let made = dir.appendingPathComponent("made.mp4")
        let first = try await MovieExporter.exportMP4(design: scored, settings: MovieExporter.Settings(scored.motion), to: made)
        XCTAssertFalse(first.musicLost)
        let madeTracks = try await audioTracks(made)
        XCTAssertEqual(madeTracks, 1)
        let id = try XCTUnwrap(VideoStore.store(try Data(contentsOf: made), ext: "mp4"))
        defer { VideoStore.delete(id) }
        let length = await VideoStore.soundLength(of: id)
        XCTAssertNotNil(length)

        // On a page with no music, the video has its sound.
        var film = Design(title: "film", width: 320, height: 240)
        film.motion = m
        film.pages[0].elements = [Element.image(VideoStore.src(id, at: nil), w: 320, h: 240)]
        let heard = dir.appendingPathComponent("heard.mp4")
        let outcome = try await MovieExporter.exportMP4(design: film, settings: MovieExporter.Settings(film.motion), to: heard)
        XCTAssertFalse(outcome.musicLost)
        let heardTracks = try await audioTracks(heard)
        XCTAssertEqual(heardTracks, 1)
        let presentable = await PageSound.heard(in: film)
        XCTAssertTrue(presentable, "the speaker button shows")

        // Muted, the clip is silent and the video has no sound at all.
        film.pages[0].elements[0].clip = ClipPlayback(muted: true)
        let silent = dir.appendingPathComponent("silent.mp4")
        try await MovieExporter.exportMP4(design: film, settings: MovieExporter.Settings(film.motion), to: silent)
        let silentTracks = try await audioTracks(silent)
        XCTAssertEqual(silentTracks, 0)
        let quiet = await PageSound.heard(in: film)
        XCTAssertFalse(quiet, "nothing to hear, no speaker button")

        // At double speed its sound is in the video, scaled, as it plays.
        film.pages[0].elements[0].clip = ClipPlayback(speed: 2)
        let fast = dir.appendingPathComponent("fast.mp4")
        let sped = try await MovieExporter.exportMP4(design: film, settings: MovieExporter.Settings(film.motion), to: fast)
        XCTAssertFalse(sped.musicLost)
        let fastTracks = try await audioTracks(fast)
        XCTAssertEqual(fastTracks, 1)
    }
}
