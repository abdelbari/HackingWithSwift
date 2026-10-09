// Sound: each clip's volume and mute in its `clip` JSON, the mix of clips
// and music in the video (AudioMix.plan, the same table as the Android
// twin's), where the music starts in Play, and the clips a page is heard
// with.

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

    private func clip(_ source: String, _ playback: ClipPlayback = ClipPlayback()) -> AudioMix.Clip {
        AudioMix.Clip(source: source, playback: playback)
    }

    private func segment(_ source: String, _ sourceStart: Double, _ at: Double, _ duration: Double, _ gain: Double,
                         _ fadeOut: ClosedRange<Double>? = nil) -> AudioMix.Segment {
        AudioMix.Segment(source: source, sourceStart: sourceStart, at: at, duration: duration, gain: gain, fadeOut: fadeOut)
    }

    func testClipsAndTheSoundtrackAreLaidAsOnAndroid() {
        let rows: [(name: String, timeline: [MovieExporter.Timing], clipsByPage: [[AudioMix.Clip]],
                    durations: [String: Double], soundtrack: AudioMix.Music?, segments: [AudioMix.Segment])] = [
            ("a looping clip over a longer page",
             pages(10), [[clip("a")]], ["a": 4], nil,
             [segment("a", 0, 0, 4, 1), segment("a", 0, 4, 4, 1), segment("a", 0, 8, 2, 1)]),
            ("a clip shorter than its page, not looping",
             pages(10), [[clip("a", ClipPlayback(loop: false))]], ["a": 4], nil,
             [segment("a", 0, 0, 4, 1)]),
            ("a trimmed clip",
             pages(5), [[clip("a", ClipPlayback(start: 2, end: 5))]], ["a": 10], nil,
             [segment("a", 2, 0, 3, 1), segment("a", 2, 3, 2, 1)]),
            ("a muted clip",
             pages(5), [[clip("a", ClipPlayback(muted: true))]], ["a": 10], nil,
             []),
            ("two pages each with a clip",
             pages(3, 4), [[clip("a")], [clip("b", ClipPlayback(volume: 0.5))]], ["a": 10, "b": 10], nil,
             [segment("a", 0, 0, 3, 1), segment("b", 0, 3, 4, 0.5)]),
            ("the soundtrack and a clip",
             pages(10), [[clip("a", ClipPlayback(loop: false, volume: 0.8))]], ["a": 4],
             AudioMix.Music(source: "m", duration: 6, volume: 0.5),
             [segment("a", 0, 0, 4, 0.8), segment("m", 0, 0, 6, 0.5, 9...10), segment("m", 0, 6, 4, 0.5, 9...10)]),
            ("a clip at another speed, a silent one, and one of no known length",
             pages(5), [[clip("a", ClipPlayback(speed: 2)), clip("b", ClipPlayback(volume: 0)), clip("c")]],
             ["a": 10, "b": 10], nil,
             []),
        ]
        for row in rows {
            let plan = AudioMix.plan(timeline: row.timeline, fps: 30, clipsByPage: row.clipsByPage,
                                     clipDurations: row.durations, soundtrack: row.soundtrack)
            XCTAssertEqual(plan.count, row.segments.count, row.name)
            for (want, got) in zip(row.segments, plan) {
                XCTAssertEqual(got.source, want.source, row.name)
                XCTAssertEqual(got.sourceStart, want.sourceStart, accuracy: 1e-9, row.name)
                XCTAssertEqual(got.at, want.at, accuracy: 1e-9, row.name)
                XCTAssertEqual(got.duration, want.duration, accuracy: 1e-9, row.name)
                XCTAssertEqual(got.gain, want.gain, accuracy: 1e-9, row.name)
                XCTAssertEqual(got.fadeOut, want.fadeOut, row.name)
            }
        }
    }

    func testTheSoundtrackFadesOutOverTheFilmsLastSecond() throws {
        let plan = AudioMix.plan(timeline: pages(10), fps: 30, clipsByPage: [[]], clipDurations: [:],
                                 soundtrack: AudioMix.Music(source: "m", duration: 20, volume: 0.8))
        XCTAssertEqual(plan.count, 1)
        let music = try XCTUnwrap(plan.first)
        XCTAssertEqual(music.gainAt(5), 0.8, accuracy: 1e-9)
        XCTAssertEqual(music.gainAt(9.5), 0.4, accuracy: 1e-9)
        XCTAssertEqual(music.gainAt(10), 0, accuracy: 1e-9)
        // Silent music is no music.
        XCTAssertTrue(AudioMix.plan(timeline: pages(10), fps: 30, clipsByPage: [[]], clipDurations: [:],
                                    soundtrack: AudioMix.Music(source: "m", duration: 20, volume: 0)).isEmpty)
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

    func testOnlyAClipAtItsOwnSpeedUnmutedAndAudibleSounds() {
        XCTAssertTrue(ClipPlayback().sounds)
        XCTAssertTrue(ClipPlayback(start: 2, end: 4, loop: false, volume: 0.1).sounds)
        XCTAssertFalse(ClipPlayback(muted: true).sounds)
        XCTAssertFalse(ClipPlayback(volume: 0).sounds)
        XCTAssertFalse(ClipPlayback(speed: 1.5).sounds)
    }

    @MainActor
    func testTheClipSheetSaysVolumeAsAPercentage() {
        XCTAssertEqual(ClipSheet.percentLabel(0), "0%")
        XCTAssertEqual(ClipSheet.percentLabel(0.355), "36%")
        XCTAssertEqual(ClipSheet.percentLabel(1), "100%")
        XCTAssertEqual(ClipSheet.speedSoundNote, "Sound plays at 1× only")
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
}
