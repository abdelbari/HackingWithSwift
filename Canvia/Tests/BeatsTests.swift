// Beats and Beat Sync, row for row with the Android twin's BeatsTest, from
// the same fixture WAVs (tools/generate_sounds.py): Fixtures/beats/, mono
// 22050 Hz 16-bit.

import XCTest
@testable import Canvia

final class BeatsTests: XCTestCase {

    /// A fixture's samples: 16-bit mono PCM after a 44-byte header.
    private func fixture(_ name: String, file: StaticString = #filePath) throws -> [Float] {
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        let bytes = [UInt8](try Data(contentsOf: here.appendingPathComponent("Fixtures/beats/\(name).wav")))
        return stride(from: 44, to: bytes.count - 1, by: 2).map { i in
            Float(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)) / 32768
        }
    }

    func testClicksAt120BPMGiveABeatEachHalfSecond() throws {
        let beats = Beats.detect(try fixture("clicks-120"), rate: 22050)
        XCTAssertEqual(beats, [0.255, 0.743, 1.254, 1.741, 2.252, 2.74, 3.251, 3.738, 4.249, 4.737, 5.248, 5.759,
                               6.246, 6.757, 7.245, 7.755])
        // Each within a frame's hop of where the click is.
        for (i, b) in beats.enumerated() {
            XCTAssertEqual(b, 0.25 + Double(i) * 0.5, accuracy: 512.0 / 22050 + 1e-9)
        }
    }

    func testA100BPMGrooveGivesItsKicks() throws {
        XCTAssertEqual(Beats.detect(try fixture("groove-100"), rate: 22050),
                       [0.093, 0.697, 1.3, 1.904, 2.508, 3.111, 3.692, 4.296, 4.899, 5.503, 6.107, 6.711, 7.291, 7.895])
    }

    func testSilenceAndASongTooShortHaveNone() throws {
        XCTAssertEqual(Beats.detect(try fixture("silence"), rate: 22050), [])
        XCTAssertEqual(Beats.detect([Float](repeating: 0, count: 500), rate: 22050), [])
        XCTAssertEqual(Beats.detect(Array(try fixture("clicks-120").prefix(22050)), rate: 22050), [])
    }

    func testTheCacheKeepsThemCommaSeparatedToThreePlaces() {
        XCTAssertEqual(Beats.encode([0.255, 1.0, 1.5, 2.3333]), "0.255,1,1.5,2.333")
        XCTAssertEqual(Beats.decode("0.255,1"), [0.255, 1.0])
        XCTAssertEqual(Beats.decode(""), [])
        XCTAssertNil(Beats.decode("0.2,x"))
    }

    func testATracksBeatsMoveToWhereItPlaysInTheFilmAndLoopWithIt() {
        let beats = [0.5, 1.0, 1.5, 2.0, 2.5]
        let track = AudioTrack(src: "audio:a.m4a", start: 3, trimStart: 1, trimEnd: 2.2)
        XCTAssertEqual(Beats.inFilm(beats, track: track, length: 3, film: 20), [3.0, 3.5, 4.0])
        var looping = track
        looping.loop = true
        XCTAssertEqual(Beats.inFilm(beats, track: looping, length: 3, film: 5.3), [3.0, 3.5, 4.0, 4.2, 4.7, 5.2])
        XCTAssertEqual(Beats.inFilm(beats, track: AudioTrack(src: "audio:a.m4a"), length: 3, film: 1.2), [0.5, 1.0])
    }

    func testASplitSnapsToABeatWithinASixthOfASecondOrSo() {
        let beats = [1.0, 1.5, 2.0]
        XCTAssertEqual(Beats.snapped(1.4, beats: beats), 1.5)
        XCTAssertEqual(Beats.snapped(1.75, beats: beats), 1.75)
        XCTAssertEqual(Beats.snapped(1.15, beats: beats), 1.0)
        XCTAssertEqual(Beats.snapped(2.3, beats: beats), 2.3)
    }

    func testBeatSyncMovesEachCutToTheNearestBeatHalfASecondAtLeast() {
        let beats = [0.4, 0.9, 1.4, 1.9, 2.4, 2.9, 3.4, 3.9, 4.4, 4.9, 5.4]
        // Ends 2.5, 5.0, 5.3 become 2.4, 4.9, then 5.4 — 0.5 on from 4.9.
        XCTAssertEqual(BeatSync.holds([2.5, 2.5, 0.3], beats: beats), [2.4, 2.5, 0.5])
        // A page with no beat in reach keeps its hold.
        XCTAssertEqual(BeatSync.holds([2.5, 3.0], beats: [0.4, 2.4]), [2.4, 3.0])
        XCTAssertEqual(BeatSync.holds([2.5], beats: []), [2.5])
        // A locked page keeps its hold; the next starts where it ends.
        XCTAssertEqual(BeatSync.holds([2.5, 2.5], beats: beats, fixed: [true, false]), [2.5, 2.4])
        // Ties go to the earlier beat.
        XCTAssertEqual(BeatSync.holds([2.5], beats: [2.0, 3.0]), [2.0])
    }

    func testTurnedOnItKeepsTheHoldsItChangedTurnedOffItPutsThemBack() throws {
        var a = Page()
        a.holdSeconds = 3
        let b = Page()
        var design = Design(title: "beats")
        design.pages = [a, b]
        let synced = BeatSync.on(design, beats: [1.0, 2.0, 3.2, 4.0, 5.0])
        XCTAssertEqual(try XCTUnwrap(synced.pages[0].holdSeconds), 3.2, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(synced.pages[1].holdSeconds), 1.8, accuracy: 1e-9)
        let kept = try XCTUnwrap(synced.beatSyncRestore)
        XCTAssertEqual(kept[a.id], .some(3.0))
        XCTAssertEqual(kept[b.id], .some(nil))
        // Written as the Android twin writes it: the page with no hold of
        // its own as null.
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(synced)) as? [String: Any])
        let written = try XCTUnwrap(json["beatSyncRestore"] as? [String: Any])
        XCTAssertEqual(written[a.id] as? Double, 3.0)
        XCTAssertTrue(written[b.id] is NSNull)
        XCTAssertEqual(try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(synced)).beatSyncRestore, kept)
        // On again for a second track: the first holds are still the ones kept.
        let again = BeatSync.on(synced, beats: [1.0, 2.0])
        XCTAssertEqual(again.beatSyncRestore, kept)
        let back = BeatSync.off(again)
        XCTAssertEqual(try XCTUnwrap(back.pages[0].holdSeconds), 3.0, accuracy: 1e-9)
        XCTAssertNil(back.pages[1].holdSeconds)
        XCTAssertNil(back.beatSyncRestore)
        XCTAssertEqual(BeatSync.off(design), design)
    }

    func testALockedPageKeepsItsHoldIsNotKeptAndIsLeftAloneWhenTurnedOff() throws {
        var a = Page()
        a.holdSeconds = 3
        a.locked = true
        let b = Page()
        var design = Design(title: "beats")
        design.pages = [a, b]
        let synced = BeatSync.on(design, beats: [1.0, 2.0, 3.2, 4.0, 5.0])
        XCTAssertEqual(try XCTUnwrap(synced.pages[0].holdSeconds), 3.0, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(synced.pages[1].holdSeconds), 2.0, accuracy: 1e-9)
        let kept = try XCTUnwrap(synced.beatSyncRestore)
        XCTAssertEqual(Set(kept.keys), [b.id])
        // B locked since: off leaves its synced hold as it is.
        var lockedSince = synced
        lockedSince.pages[1].locked = true
        XCTAssertEqual(try XCTUnwrap(BeatSync.off(lockedSince).pages[1].holdSeconds), 2.0, accuracy: 1e-9)
        XCTAssertNil(BeatSync.off(synced).pages[1].holdSeconds)
    }

    func testATrackKeepsItsBeatSyncKeyForOlderBuildsAndLosesItWhenOff() throws {
        var track = AudioTrack(src: "audio:a.m4a")
        track.beatSync = true
        var design = Design(title: "beats")
        design.audioTracks = [track]
        let data = try JSONEncoder().encode(design)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let written = try XCTUnwrap((json["audio"] as? [[String: Any]])?.first)
        XCTAssertEqual(written["beatSync"] as? Bool, true)
        let read = try JSONDecoder().decode(Design.self, from: data)
        XCTAssertTrue(try XCTUnwrap(read.audioTracks.first).beatSync)
        XCTAssertTrue(BeatSync.active(read))
        track.beatSync = false
        let off = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(track)) as? [String: Any])
        XCTAssertNil(off["beatSync"])
    }

    @MainActor
    func testTheStoreTurnsItOnAndOffAsOneStepEach() throws {
        var a = Page()
        a.holdSeconds = 3
        var design = Design(title: "beats", width: 1000, height: 1000)
        design.pages = [a, Page()]
        design.audioTracks = [AudioTrack(id: "t1", src: "audio:a.m4a")]
        let s = DesignStore(design: design)
        s.turnBeatSyncOn("t1", beats: [1.0, 2.0, 3.2, 4.0, 5.0], length: 6)
        XCTAssertEqual(try XCTUnwrap(s.design.pages[0].holdSeconds), 3.2, accuracy: 1e-9)
        XCTAssertTrue(BeatSync.active(s.design))
        s.turnBeatSyncOff("t1")
        XCTAssertEqual(s.design.pages[0].holdSeconds, 3)
        XCTAssertFalse(BeatSync.active(s.design))
        XCTAssertNil(s.design.beatSyncRestore)
        s.undo()
        XCTAssertTrue(BeatSync.active(s.design))
        s.undo()
        XCTAssertEqual(s.design.pages[0].holdSeconds, 3)
        XCTAssertNil(s.design.beatSyncRestore)
    }

    func testOffOnOneTrackLeavesTheHoldsWhileAnotherHasItOnAndTheLastOneOffOrGoneBringsThemBack() throws {
        var a = Page()
        a.holdSeconds = 3
        var design = Design(title: "beats")
        design.pages = [a, Page()]
        var one = AudioTrack(id: "t1", src: "audio:a.m4a")
        one.beatSync = true
        var two = AudioTrack(id: "t2", src: "audio:b.m4a")
        two.beatSync = true
        design.audioTracks = [one, two]
        let synced = BeatSync.on(design, beats: [1.0, 2.0, 3.2, 4.0, 5.0])
        var oneOff = synced
        oneOff.audioTracks[0].beatSync = false
        oneOff = BeatSync.settled(oneOff)
        XCTAssertEqual(try XCTUnwrap(oneOff.pages[0].holdSeconds), 3.2, accuracy: 1e-9)
        XCTAssertNotNil(oneOff.beatSyncRestore)
        var bothOff = oneOff
        bothOff.audioTracks[1].beatSync = false
        bothOff = BeatSync.settled(bothOff)
        XCTAssertEqual(try XCTUnwrap(bothOff.pages[0].holdSeconds), 3.0, accuracy: 1e-9)
        XCTAssertNil(bothOff.beatSyncRestore)
        // The last synced track taken out: the same.
        var gone = oneOff
        gone.audioTracks.removeAll { $0.id == "t2" }
        gone = BeatSync.settled(gone)
        XCTAssertEqual(try XCTUnwrap(gone.pages[0].holdSeconds), 3.0, accuracy: 1e-9)
        XCTAssertNil(gone.beatSyncRestore)
    }

    func testTheKeptHoldsAndTheTalksFollowTheirPagesToACopy() throws {
        var a = Page()
        a.holdSeconds = 3
        let b = Page()
        var design = Design(title: "beats")
        design.pages = [a, b]
        let talk = Recording(id: "rec_1", createdAt: 0, audio: "a1", camera: nil,
                             pages: [RecordingSpan(pageId: a.id, start: 0, end: 2), RecordingSpan(pageId: b.id, start: 2, end: 5)])
        design = Recordings.added(design, talk)
        let synced = BeatSync.on(design, beats: [1.0, 2.0, 3.2, 4.0, 5.0])
        // Renamed, a page not among the new ids dropped.
        let renamed = BeatSync.withPageIds(synced, [a.id: "x"])
        XCTAssertEqual(renamed.beatSyncRestore, ["x": .some(3.0)])
        let talks = Recordings.of(Recordings.withPageIds(synced, [a.id: "x"]))
        XCTAssertEqual(try XCTUnwrap(talks.first).pages.map(\.pageId), ["x"])
        // A copy's pages are new, and what named the old ones names them.
        let copy = CopyResize.freshCopy(of: synced)
        let ids = copy.pages.map(\.id)
        XCTAssertEqual(Set(try XCTUnwrap(copy.beatSyncRestore).keys), Set(ids))
        XCTAssertEqual(try XCTUnwrap(Recordings.of(copy).first).pages.map(\.pageId), ids)
        XCTAssertEqual(try XCTUnwrap(BeatSync.off(copy).pages[0].holdSeconds), 3.0, accuracy: 1e-9)
    }
}
