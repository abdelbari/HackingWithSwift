// The built-in music library, row for row with the Android twin's
// MusicLibraryTest: a dozen seamless mono loops the app ships, two a mood,
// found by mood and words, each going under the film as a looping
// "music:" track that no design file or backup carries, with beats from
// its tempo.

import XCTest
@testable import Canvia

final class MusicLibraryTests: XCTestCase {

    func testTwelveLoopsTwoAMoodEachAMonoWAVTheAppShips() throws {
        let all = MusicLibrary.all
        XCTAssertEqual(all.count, 12)
        XCTAssertEqual(Set(all.map(\.id)).count, 12, "ids are unique")
        for mood in MusicLibrary.moods {
            XCTAssertEqual(all.filter { $0.mood == mood }.count, 2, mood)
        }
        for music in all {
            let url = try XCTUnwrap(MusicLibrary.url(music.id), music.id)
            XCTAssertEqual(MusicLibrary.assetPath(music.id), "music/\(music.id).wav")
            let data = try Data(contentsOf: url)
            XCTAssertLessThan(data.count, 768 * 1024, music.id)
            let head = [UInt8](data.prefix(44))
            func u16(_ at: Int) -> Int { Int(head[at]) | Int(head[at + 1]) << 8 }
            func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
            XCTAssertEqual(u16(20), 1, music.id)          // PCM
            XCTAssertEqual(u16(22), 1, music.id)          // mono
            XCTAssertEqual(u32(24), 22050, music.id)
            XCTAssertEqual(u16(34), 16, music.id)
            let seconds = Double(u32(40)) / 2 / 22050
            XCTAssertEqual(music.seconds, seconds, accuracy: 0.001, music.id)
            XCTAssertTrue((12...16).contains(music.seconds), music.id)
            // Eight bars of four beats at its tempo.
            XCTAssertEqual(music.seconds, 32 * 60 / music.bpm, accuracy: 0.001, music.id)
            XCTAssertFalse(music.tags.isEmpty, music.id)
            XCTAssertFalse(music.genre.isEmpty, music.id)
        }
    }

    func testTheListIsReadLeniently() {
        let json = """
        [{"id":"a","name":"Alpha","mood":"calm","genre":"Ambient","bpm":120,"seconds":16,"tags":["soft","Rain"]},
         {"id":"b","name":"Beta","mood":"sleepy","bpm":120,"seconds":16},
         {"name":"No id","mood":"calm"},
         {"id":"c","name":"Gamma","mood":"upbeat","bpm":128,"seconds":15}]
        """
        let tracks = MusicLibrary.parse(Data(json.utf8))
        XCTAssertEqual(tracks.map(\.id), ["a", "c"], "an unknown mood or a missing id is left out")
        XCTAssertEqual(tracks[1].tags, [])
        XCTAssertEqual(MusicLibrary.parse(Data("{}".utf8)), [])

        XCTAssertEqual(MusicLibrary.filter(tracks, mood: "calm", query: "").map(\.id), ["a"])
        XCTAssertEqual(MusicLibrary.filter(tracks, mood: nil, query: "").map(\.id), ["a", "c"])
        XCTAssertEqual(MusicLibrary.filter(tracks, mood: nil, query: "rain").map(\.id), ["a"], "tags, case aside")
        XCTAssertEqual(MusicLibrary.filter(tracks, mood: nil, query: " GAM ").map(\.id), ["c"], "names")
        XCTAssertEqual(MusicLibrary.filter(tracks, mood: nil, query: "ambient").map(\.id), [], "not the genre")
        XCTAssertEqual(MusicLibrary.filter(tracks, mood: "upbeat", query: "alpha").map(\.id), [])
        XCTAssertEqual(MusicLibrary.byId("c", in: tracks)?.name, "Gamma")
        XCTAssertNil(MusicLibrary.byId("z", in: tracks))
        XCTAssertNil(MusicLibrary.byId(nil, in: tracks))
    }

    func testBeatsComeFromTheTempo() {
        let loop = MusicTrack(id: "x", name: "X", mood: "calm", bpm: 120, seconds: 16)
        let beats = MusicLibrary.beats(of: loop)
        XCTAssertEqual(beats.count, 32)
        XCTAssertEqual(beats.prefix(3), [0, 0.5, 1])
        XCTAssertEqual(beats.last, 15.5)
        let odd = MusicLibrary.beats(of: MusicTrack(id: "y", name: "Y", mood: "chill", bpm: 124, seconds: 15.484))
        XCTAssertEqual(odd.count, 32)
        XCTAssertEqual(odd[1], 0.484)
        XCTAssertEqual(MusicLibrary.beats(of: MusicTrack(id: "z", name: "Z", mood: "chill", bpm: 0, seconds: 10)), [])
    }

    func testALoopIsALoopingTrackThatNoFileOrBackupCarries() throws {
        let music = try XCTUnwrap(MusicLibrary.all.first)
        let track = MusicLibrary.track(music)
        XCTAssertEqual(track.src, "music:\(music.id)")
        XCTAssertEqual(track.start, 0)
        XCTAssertTrue(track.loop)
        XCTAssertEqual(track.fadeIn, 0)
        XCTAssertEqual(track.fadeOut, 1)
        XCTAssertEqual(track.name, music.name)
        XCTAssertEqual(track.audioId, "music:\(music.id)")
        XCTAssertNil(track.storedAudioId)
        XCTAssertEqual(MusicLibrary.of(track.src), music)
        XCTAssertNotNil(AudioStore.url(for: track.audioId))
        XCTAssertEqual(AudioStore.label(for: track.src), music.name)
        XCTAssertNil(AudioTrack(src: "music:").audioId)
        XCTAssertEqual(Soundtrack.packed(["music:\(music.id)": (bytes: 1000, ext: "wav"), "song.m4a": (bytes: 1000, ext: "m4a")]),
                       ["song.m4a"], "a built-in loop is never packed")

        var design = Design(title: "music")
        design.audioTracks = [track]
        let data = try JSONEncoder().encode(design)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try XCTUnwrap(json["audio"] as? [[String: Any]])
        XCTAssertEqual(written[0]["src"] as? String, "music:\(music.id)")
        XCTAssertEqual(written[0]["loop"] as? Bool, true)
        let read = try JSONDecoder().decode(Design.self, from: data)
        XCTAssertEqual(read.audioTracks.map(\.src), ["music:\(music.id)"])
        XCTAssertNil(DesignPackage.packedAudio(of: read))
        XCTAssertEqual(DesignLibrary.soundtracks(in: [read]), [])
    }

    func testBeatSyncReadsALoopsTempo() async throws {
        let music = try XCTUnwrap(MusicLibrary.all.first)
        let beats = await AudioStore.beats(of: AudioTrack.musicSrc(music.id))
        XCTAssertEqual(beats, MusicLibrary.beats(of: music))
    }

    @MainActor
    func testALoopGoesOnAsOneStep() throws {
        let s = DesignStore(design: Design(title: "music", width: 1000, height: 1000))
        let music = try XCTUnwrap(MusicLibrary.all.last)
        let added = s.addMusic(music)
        XCTAssertEqual(s.design.audioTracks.map(\.src), [added.src])
        XCTAssertTrue(added.loop)
        s.undo()
        XCTAssertTrue(s.design.audioTracks.isEmpty)
    }
}
