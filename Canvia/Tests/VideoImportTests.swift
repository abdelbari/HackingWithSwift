// A clip made light as it comes in (VideoImport), the rows the Android
// twin's VideoImportTest holds: which clips are converted, what they come
// out as, what the upload remembers, and how much a long clip may weigh in
// a design file.

import XCTest
@testable import Canvia

final class VideoImportTests: XCTestCase {

    private let mb: Int64 = 1024 * 1024

    private var light: VideoImport.Probe {
        VideoImport.Probe(bytes: 20 * mb, width: 1920, height: 1080, videoCodec: "video/avc",
                          audioCodec: "audio/mp4a-latm", container: "mp4")
    }

    private func with(_ change: (inout VideoImport.Probe) -> Void) -> VideoImport.Probe {
        var clip = light
        change(&clip)
        return clip
    }

    func testAClipIsConvertedWhenItIsTooBigTooManyBytesOrNotH264AndAACInMP4OrMOV() {
        // The table both phones keep.
        let rows: [(VideoImport.Probe, Bool)] = [
            (light, false),
            (with { $0.container = "MOV" }, false),
            (with { $0.audioCodec = nil }, false),
            (with { $0.width = 1080; $0.height = 1920 }, false),
            (with { $0.width = 3840; $0.height = 2160 }, true),
            (with { $0.width = 1080; $0.height = 1921 }, true),
            (with { $0.bytes = 30 * mb }, false),
            (with { $0.bytes = 30 * mb + 1 }, true),
            (with { $0.videoCodec = "video/hevc" }, true),
            (with { $0.videoCodec = nil }, true),
            (with { $0.audioCodec = "audio/opus" }, true),
            (with { $0.container = "webm" }, true),
            (with { $0.container = "mkv" }, true),
            (with { $0.container = "3gp" }, true),
        ]
        for (clip, converted) in rows {
            XCTAssertEqual(VideoImport.needsOptimising(clip), converted, "\(clip)")
        }
        // This phone's own codec names are the rule's.
        XCTAssertEqual(VideoImport.codec(fourCC: "avc1"), VideoImport.h264)
        XCTAssertEqual(VideoImport.codec(fourCC: "hvc1"), "video/hevc")
        XCTAssertEqual(VideoImport.codec(fourCC: "mp4a"), VideoImport.aac)
        XCTAssertEqual(VideoImport.codec(fourCC: "opus"), "opus")
    }

    func testItComesOutAtMost1920OnItsLongSideEvenItsShapeKeptAtMost30Frames() {
        func size(_ w: Int, _ h: Int) -> [Int] {
            let s = VideoImport.targetSize(width: w, height: h)
            return [s.width, s.height]
        }
        XCTAssertEqual(size(3840, 2160), [1920, 1080])
        XCTAssertEqual(size(2160, 3840), [1080, 1920])
        XCTAssertEqual(size(1280, 720), [1280, 720])
        XCTAssertEqual(size(4000, 1845), [1920, 886])
        XCTAssertEqual(size(719, 479), [720, 480])
        XCTAssertEqual(VideoImport.targetFps(59.94), 30)
        XCTAssertEqual(VideoImport.targetFps(23.976), 24)
        XCTAssertEqual(VideoImport.targetFps(nil), 30)
        XCTAssertEqual(VideoImport.bitRate(width: 1920, height: 1080), 8_000_000)
        XCTAssertEqual(VideoImport.bitRate(width: 320, height: 240), 1_500_000)
        XCTAssertEqual(VideoImport.bitRate(width: 1280, height: 720), 3_555_555)
    }

    func testTheUploadRemembersWhatItWasAndUploadsSaysSo() {
        let raw: [[String: Any]] = [
            ["id": "vid-1", "kind": "video", "added": 1],
            ["id": "img-1", "kind": "image", "added": 2],
        ]
        let marked = Uploads.optimised(raw, id: "vid-1", originalBytes: 412_000_000)
        let entries = Uploads.entries(of: marked)
        XCTAssertEqual(entries.first { $0.id == "vid-1" }?.optimisedFrom, 412_000_000)
        XCTAssertEqual(marked[0]["optimised"] as? Bool, true)
        XCTAssertNil(entries.first { $0.id == "img-1" }?.optimisedFrom)
        // A photo is never marked.
        let photo = Uploads.optimised(raw, id: "img-1", originalBytes: 5)
        XCTAssertNil(photo[1]["optimised"])
        XCTAssertEqual(VideoImport.label(412_000_000), "Optimised from 412 MB")
        XCTAssertEqual(VideoImport.label(10), "Optimised from 1 MB")
    }

    func testALongClipMayTravelLargerAbout4MBAMinute() {
        XCTAssertEqual(VideoImport.packedLimit(nil), Int64(DesignPackage.maxPackedVideoBytes))
        XCTAssertEqual(VideoImport.packedLimit(60), Int64(DesignPackage.maxPackedVideoBytes))
        XCTAssertEqual(VideoImport.packedLimit(600), 40 * mb)
        let clips: [String: (bytes: Int, ext: String)] = [
            "long": (bytes: Int(35 * mb), ext: "mp4"),
            "short": (bytes: Int(35 * mb), ext: "mp4"),
        ]
        XCTAssertEqual(DesignPackage.packedVideoIDs(clips, seconds: ["long": 600, "short": 30]), ["long"])
        XCTAssertFalse(VideoImport.needsOptimising(light))
        XCTAssertTrue(DesignPackage.packableVideoTypes.contains("mp4"))
    }
}
