// Enhance voice and Detach audio, row for row with the Android twin's
// VoiceEnhanceTest: the four stages over the same made-up PCM (sines and a
// seeded noise, 8000 samples a second), the `enhance` keys on a track and a
// clip, a clip's sound as a "video:" track, and the mix reading enhanced
// sound.

import XCTest
@testable import Canvia

final class VoiceEnhanceTests: XCTestCase {

    private let rate = 8000

    /// `seconds` of a sine of `hz` at `amplitude`.
    private func sine(_ hz: Double, _ amplitude: Double, seconds: Double = 1) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { Float(amplitude * sin(2 * Double.pi * hz * Double($0) / Double(rate))) }
    }

    private func rms(_ s: ArraySlice<Float>) -> Double { VoiceEnhance.rms(Array(s)) }

    // MARK: the stages

    func testTheHighPassTakesOutHumAndKeepsTheVoice() {
        let hum = sine(30, 0.5), voice = sine(1000, 0.5)
        let half = rate / 2
        let humOut = VoiceEnhance.highPassed(hum, rate: rate)
        let voiceOut = VoiceEnhance.highPassed(voice, rate: rate)
        XCTAssertEqual(rms(humOut[half...]) / rms(hum[half...]), 0.139, accuracy: 0.005)
        XCTAssertEqual(rms(voiceOut[half...]) / rms(voice[half...]), 1, accuracy: 0.001)
    }

    func testTheGateTurnsTheNoiseFloorDownTwelveDecibels() {
        // A steady 1 kHz hum, then a loud 2 kHz tone over it.
        var x = sine(1000, 0.01, seconds: 2)
        let tone = sine(2000, 0.5)
        for i in tone.indices { x[rate + i] += tone[i] }
        let out = VoiceEnhance.gated(x)
        XCTAssertEqual(out.count, x.count)
        XCTAssertEqual(rms(out[2000..<(rate - 2000)]) / rms(x[2000..<(rate - 2000)]), 0.2512, accuracy: 0.001,
                       "the hum alone is at its floor: 12 dB down")
        XCTAssertEqual(rms(out[(rate + 2000)..<(2 * rate - 2000)]) / rms(x[(rate + 2000)..<(2 * rate - 2000)]), 1,
                       accuracy: 0.001, "the tone is kept")
    }

    func testTheNoiseFloorIsTheQuietestTenthOfTheFrames() {
        XCTAssertEqual(VoiceEnhance.quietest([5, 1, 3, 1, 9]), [1], "at least one, the earlier on a tie")
        XCTAssertEqual(VoiceEnhance.quietest([9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20]), [9, 8])
    }

    func testTheCompressorTurnsFullScaleDownToAThirdOverTheThreshold() {
        // A full-scale square wave: once its level is up, 0 dBFS reads as
        // −18 + 18/3 = −12 dBFS.
        let square: [Float] = (0..<rate).map { sin(2 * Double.pi * 100 * Double($0) / Double(rate)) >= 0 ? 1 : -1 }
        let out = VoiceEnhance.compressed(square, rate: rate)
        for s in out[(rate / 2)...] { XCTAssertEqual(abs(Double(s)), 0.2512, accuracy: 0.0005) }
        let quiet = sine(440, 0.05)
        XCTAssertEqual(VoiceEnhance.compressed(quiet, rate: rate), quiet, "under −18 dBFS it is left alone")
    }

    func testTheLevelIsSixteenDecibelsDown() {
        let out = VoiceEnhance.normalised(sine(440, 0.01))
        XCTAssertEqual(20 * log10(VoiceEnhance.rms(out)), -16, accuracy: 0.0001)
        let silence = [Float](repeating: 0, count: 100)
        XCTAssertEqual(VoiceEnhance.normalised(silence), silence)
    }

    func testTheWholeChainKeepsTheLengthAndLandsOnTheLevel() {
        var x = sine(1000, 0.01, seconds: 2)
        let tone = sine(2000, 0.5)
        for i in tone.indices { x[rate + i] += tone[i] }
        let out = VoiceEnhance.enhanced(x, rate: rate)
        XCTAssertEqual(out.count, x.count)
        XCTAssertEqual(20 * log10(VoiceEnhance.rms(out)), -16, accuracy: 0.001)
        XCTAssertEqual(VoiceEnhance.enhanced([], rate: rate), [])
    }

    func testTheKeptFileIsSixteenBitMonoWav() {
        let data = VoiceEnhance.wav([0, 1, -1, 0.5], rate: 44100)
        let bytes = [UInt8](data)
        XCTAssertEqual(bytes.count, 44 + 8)
        XCTAssertEqual(String(decoding: bytes[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: bytes[8..<16], as: UTF8.self), "WAVEfmt ")
        XCTAssertEqual(Array(bytes[44...]), [0x00, 0x00, 0xFF, 0x7F, 0x01, 0x80, 0x00, 0x40])
        XCTAssertEqual(AudioStore.enhancedFile(for: "video:vid_1").lastPathComponent, "video_vid_1.enh.wav")
        XCTAssertEqual(AudioStore.enhancedFile(for: "audio_2.m4a").lastPathComponent, "audio_2.m4a.enh.wav")
    }

    // MARK: the file

    func testEnhanceIsWrittenOnlyWhenOn() throws {
        var track = AudioTrack(id: "t", src: "audio:song.m4a")
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        XCTAssertNil(plain["enhance"])
        track.enhance = true
        let on = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        XCTAssertEqual(on["enhance"] as? Bool, true)
        XCTAssertEqual(try JSONDecoder().decode(AudioTrack.self, from: JSONEncoder().encode(track)), track)

        var clip = ClipPlayback()
        clip.enhance = true
        XCTAssertFalse(clip.isDefault)
        let written = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(clip)) as? [String: Any])
        XCTAssertEqual(written as NSDictionary, ["enhance": true] as NSDictionary)
        XCTAssertEqual(try JSONDecoder().decode(ClipPlayback.self, from: Data("{\"enhance\":true}".utf8)), clip)
        XCTAssertFalse(try JSONDecoder().decode(ClipPlayback.self, from: Data("{\"enhance\":\"yes\"}".utf8)).enhance)
    }

    func testAClipsSoundReadsAsATrack() throws {
        let track = try JSONDecoder().decode(AudioTrack.self, from: Data("{\"id\":\"t\",\"src\":\"video:vid_1\"}".utf8))
        XCTAssertEqual(track.audioId, "video:vid_1")
        XCTAssertNil(track.storedAudioId, "it travels with its clip")
        XCTAssertEqual(AudioTrack.videoId(of: track.src), "vid_1")
        XCTAssertNil(try? JSONDecoder().decode(AudioTrack.self, from: Data("{\"src\":\"video:\"}".utf8)))
        var d = Design(title: "clip sound")
        d.audioTracks = [track]
        XCTAssertEqual(DesignPackage.videoIDs(in: d), ["vid_1"])
        XCTAssertEqual(DesignLibrary.clips(in: [d]), ["vid_1"])
    }

    // MARK: detach

    private func film() -> Design {
        var d = Design(title: "detach", width: 320, height: 240)
        d.pages = [Page(), Page()]
        d.pages[0].holdSeconds = 4
        d.pages[1].holdSeconds = 6
        var clip = Element.image(VideoStore.src("vid_1", at: nil), w: 160, h: 120)
        clip.id = "c1"
        clip.clip = ClipPlayback(start: 1.5, end: 5, speed: 2, volume: 0.6, fadeIn: 0.5, fadeOut: 1, enhance: true)
        clip.timing = ElementTiming(start: 1, end: nil)
        d.pages[1].elements = [clip]
        return d
    }

    func testDetachingLiftsTheClipsSoundIntoATrackAndMutesIt() throws {
        let out = try XCTUnwrap(AudioTracks.detached(film(), clipElementId: "c1"))
        let track = try XCTUnwrap(out.audioTracks.last)
        XCTAssertEqual(track.src, "video:vid_1")
        XCTAssertEqual(track.start, 5, accuracy: 1e-9, "page start 4 + its timing's 1")
        XCTAssertEqual(track.trimStart, 1.5)
        XCTAssertEqual(track.trimEnd, 5)
        XCTAssertEqual(track.volume, 0.6)
        XCTAssertEqual(track.fadeIn, 0.5)
        XCTAssertEqual(track.fadeOut, 1)
        XCTAssertTrue(track.enhance)
        XCTAssertFalse(track.loop)
        XCTAssertEqual(out.pages[1].elements[0].clip?.muted, true)
        XCTAssertEqual(out.pages[1].elements[0].clip?.speed, 2, "the rest of the clip is as it was")
        XCTAssertNil(AudioTracks.detached(out, clipElementId: "c1"), "a muted clip has nothing to detach")
        XCTAssertNil(AudioTracks.detached(film(), clipElementId: "nothing"))
        var locked = film()
        locked.pages[1].locked = true
        XCTAssertNil(AudioTracks.detached(locked, clipElementId: "c1"))
    }

    @MainActor
    func testDetachIsOneStepNamedDetachAudio() {
        let s = DesignStore(design: film())
        s.detachAudio("c1")
        XCTAssertEqual(s.design.audioTracks.count, 1)
        XCTAssertEqual(s.undoLabel, "Detach audio")
        s.undo()
        XCTAssertTrue(s.design.audioTracks.isEmpty)
        XCTAssertNotEqual(s.design.pages[1].elements[0].clip?.muted, true)
    }

    // MARK: the mix

    func testEnhancedSoundIsReadFromItsOwnSource() {
        let timeline = [MovieExporter.Timing(start: 0, frames: 300, transition: "fade")]
        var playback = ClipPlayback()
        playback.enhance = true
        var track = AudioTrack(id: "t", src: "audio:song.m4a", start: 1)
        track.enhance = true
        let plan = AudioMix.plan(timeline: timeline, fps: 30,
                                 clipsByPage: [[AudioMix.Clip(source: "vid_1", playback: playback)]],
                                 clipDurations: ["vid_1": 20], tracks: [track], trackDurations: ["song.m4a": 3])
        XCTAssertEqual(plan.map(\.source), ["vid_1.enh", "song.m4a.enh"])
        XCTAssertEqual(plan.map(\.at), [0, 1])
    }
}
