// The built-in sound effects, row for row with the Android twin's
// SoundEffectsTest: two dozen short mono WAVs and Present's drumroll and mic
// drop in the bundle, found by their
// tags, each going under the film as an "sfx:" track that no design file
// or backup carries.

import XCTest
@testable import Canvia

final class SoundEffectsTests: XCTestCase {

    func testTwoDozenEffectsAndPresentsTwoEachAShortMonoWAVTheAppShips() throws {
        XCTAssertEqual(SoundEffects.all.map(\.id), [
            "whoosh", "swoosh", "pop", "click", "tick", "ding", "chime", "bell", "sparkle", "riser", "drop", "boom",
            "kick", "snare", "clap", "typewriter-key", "camera-shutter", "notification", "error-buzz", "success",
            "coin", "bubble", "swipe", "glitch", "drumroll", "micdrop",
        ])
        for e in SoundEffects.all {
            let url = try XCTUnwrap(SoundEffects.url(e.id), e.id)
            XCTAssertEqual(SoundEffects.assetPath(e.id), "sfx/\(e.id).wav")
            let head = [UInt8](try Data(contentsOf: url).prefix(44))
            func u16(_ at: Int) -> Int { Int(head[at]) | Int(head[at + 1]) << 8 }
            func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
            XCTAssertEqual(u16(20), 1, e.id)          // PCM
            XCTAssertEqual(u16(22), 1, e.id)          // mono
            XCTAssertEqual(u32(24), 44100, e.id)
            XCTAssertEqual(u16(34), 16, e.id)
            let seconds = Double(u32(40)) / 2 / 44100
            XCTAssertEqual(e.seconds, seconds, accuracy: 0.001, e.id)
            // Present's drumroll and mic drop play as long as their pictures.
            let most = Presenter.sounds(e.id) ? Presenter.seconds(of: e.id) : 2
            XCTAssertTrue(e.seconds <= most && !e.tags.isEmpty, e.id)
        }
    }

    func testASearchReadsNamesIdsAndTags() {
        XCTAssertEqual(SoundEffects.search("drum").map(\.id), ["kick", "snare", "drumroll"])
        XCTAssertEqual(SoundEffects.search("Camera").map(\.id), ["camera-shutter"])
        XCTAssertEqual(SoundEffects.search("").count, 26)
    }

    func testAnEffectIsATrackFromThePagesStartOnceThatNoFileOrBackupCarries() throws {
        let pop = try XCTUnwrap(SoundEffects.effect("pop"))
        let track = SoundEffects.track(pop, start: 2.5)
        XCTAssertEqual(track.src, "sfx:pop")
        XCTAssertEqual(track.start, 2.5)
        XCTAssertFalse(track.loop)
        XCTAssertEqual(track.name, "Pop")
        XCTAssertEqual(track.audioId, "sfx:pop")
        XCTAssertEqual(AudioTrack.sfxId(of: track.audioId), "pop")
        XCTAssertEqual(SoundEffects.of(track.src), pop)
        XCTAssertNotNil(AudioStore.url(for: track.audioId))
        XCTAssertEqual(AudioStore.label(for: "sfx:pop"), "Pop")
        XCTAssertEqual(AudioTrack(src: "audio:song.m4a").audioId, "song.m4a")
        XCTAssertNil(AudioTrack(src: "sfx:").audioId)
        XCTAssertEqual(AudioTrack(src: "video:x").audioId, "video:x", "a clip's detached sound, as on Android")

        var design = Design(title: "sfx")
        design.audioTracks = [AudioTrack(src: AudioTrack.src("song.m4a")), track]
        // Read back from the file both phones write.
        let data = try JSONEncoder().encode(design)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try XCTUnwrap(json["audio"] as? [[String: Any]])
        XCTAssertEqual(written[1]["src"] as? String, "sfx:pop")
        let read = try JSONDecoder().decode(Design.self, from: data)
        XCTAssertEqual(read.audioTracks.map(\.src), ["audio:song.m4a", "sfx:pop"])
        XCTAssertEqual(read.audioTracks.map(\.storedAudioId), ["song.m4a", nil])
        XCTAssertEqual(DesignLibrary.soundtracks(in: [read]), ["song.m4a"])
        var effectOnly = Design(title: "only an effect")
        effectOnly.audioTracks = [track]
        XCTAssertNil(DesignPackage.packedAudio(of: effectOnly))
    }

    @MainActor
    func testAnEffectGoesOnFromThePageOnScreenAsOneStep() throws {
        var design = Design(title: "sfx", width: 1000, height: 1000)
        var second = Page()
        second.holdSeconds = 4
        var first = Page()
        first.holdSeconds = 3
        design.pages = [first, second]
        let s = DesignStore(design: design)
        s.setPage(1)
        let added = s.addSoundEffect(try XCTUnwrap(SoundEffects.effect("whoosh")))
        XCTAssertEqual(added.start, 3)
        XCTAssertEqual(s.design.audioTracks.map(\.src), ["sfx:whoosh"])
        s.undo()
        XCTAssertTrue(s.design.audioTracks.isEmpty)
    }
}
