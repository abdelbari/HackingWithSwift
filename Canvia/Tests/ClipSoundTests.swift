// Sound: each clip's volume and mute in its `clip` JSON, the Clip
// sheet's readout and the store's steps.

import XCTest
@testable import Canvia

final class ClipSoundTests: XCTestCase {

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
