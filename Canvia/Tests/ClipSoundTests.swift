// Sound: each clip's volume and mute in its `clip` JSON, the mix of clips
// and music in the video (AudioMix.plan, the same table as the Android
// twin's), where the music starts in Play, the clips a page is heard with,
// the soundtrack travelling in a design file, and the video carrying a
// clip's sound.

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

    func testTheSoundtrackTravelsUnderAudioAndComesBackAsTheDesignsMusic() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let song = dir.appendingPathComponent("Song.m4a")
        let bytes = Data((0..<5000).map { UInt8(truncatingIfNeeded: $0 * 7) })
        try bytes.write(to: song)
        let id = try XCTUnwrap(AudioStore.store(song))
        defer { AudioStore.delete(id) }

        var d = Design(title: "Scored", width: 400, height: 300)
        var m = MotionSettings(); m.soundtrack = id; m.soundVolume = 0.5
        d.motion = m
        let data = try DesignPackage.export(d, mediaDirectory: dir)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let audio = try XCTUnwrap(object["audio"] as? [String: Any])
        let packed = try XCTUnwrap(audio[id] as? [String: Any])
        XCTAssertEqual(packed["ext"] as? String, "m4a")
        XCTAssertEqual((packed["data"] as? String).flatMap { Data(base64Encoded: $0) }, bytes)

        // Stored under a fresh id, the design's soundtrack points at it, its
        // volume kept.
        let back = try DesignPackage.import(data, mediaDirectory: dir)
        let moved = try XCTUnwrap(back.motion?.soundtrack)
        defer { AudioStore.delete(moved) }
        XCTAssertNotEqual(moved, id)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(AudioStore.url(for: moved))), bytes)
        XCTAssertEqual(back.motion?.soundVolume, 0.5)

        // No music, or music not on this phone, writes no "audio".
        let plain = try JSONSerialization.jsonObject(with: DesignPackage.export(Design(title: "Quiet"), mediaDirectory: dir)) as? [String: Any]
        XCTAssertNil(plain?["audio"])
        var elsewhere = d
        elsewhere.motion?.soundtrack = "audio_elsewhere.m4a"
        let away = try DesignPackage.import(try DesignPackage.export(elsewhere, mediaDirectory: dir), mediaDirectory: dir)
        XCTAssertEqual(away.motion?.soundtrack, "audio_elsewhere.m4a", "music that did not travel is left as it was")
    }

    /// A file written by the Android twin, music first as the sorted keys
    /// put it, opens with its music; the file type it names is kept to
    /// letters and digits.
    func testADesignFileWithMusicFromAndroidOpens() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pkg-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var d = Design(title: "From Android", width: 400, height: 300)
        var m = MotionSettings(); m.soundtrack = "audio-1.m4a"
        d.motion = m
        let design = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d))
        let file: [String: Any] = [
            "audio": ["audio-1.m4a": ["data": "AQID", "ext": "../m4a"]],
            "design": design, "format": "canvia-package", "media": [String: Any](), "version": 1,
        ]
        let back = try DesignPackage.import(try JSONSerialization.data(withJSONObject: file), mediaDirectory: dir)
        let moved = try XCTUnwrap(back.motion?.soundtrack)
        defer { AudioStore.delete(moved) }
        XCTAssertTrue(moved.hasSuffix(".m4a"), moved)
        XCTAssertFalse(moved.contains("/"))
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(AudioStore.url(for: moved))), Data([1, 2, 3]))
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
        var withMusic = m
        withMusic.soundtrack = music
        scored.motion = withMusic
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
    }
}
