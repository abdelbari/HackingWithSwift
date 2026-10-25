// HDR clips brought to SDR (VideoImport, HdrToneMap): which clips count as
// HDR, that one is always converted, what the upload records, and the
// tone mapping held to the shared fixture hdr-tonemap.json — the rows the
// Android twin's HdrToneMapTest and VideoImportTest hold.

import XCTest
@testable import Canvia

final class HdrClipsTests: XCTestCase {

    private var light: VideoImport.Probe {
        VideoImport.Probe(bytes: 20 * 1024 * 1024, width: 1920, height: 1080, videoCodec: "video/avc",
                          audioCodec: "audio/mp4a-latm", container: "mp4")
    }

    private func with(_ change: (inout VideoImport.Probe) -> Void) -> VideoImport.Probe {
        var clip = light
        change(&clip)
        return clip
    }

    func testAClipIsHDRForHLGOrPQMoreThan8BitsOrBT2020() {
        let rows: [(VideoImport.Probe, Bool, String?)] = [
            (light, false, nil),
            (with { $0.transfer = "hlg" }, true, "hlg"),
            (with { $0.transfer = "pq" }, true, "pq"),
            (with { $0.bitDepth = 10 }, true, nil),
            (with { $0.bitDepth = 8 }, false, nil),
            (with { $0.primaries = "bt2020" }, true, nil),
            (with { $0.primaries = "bt2020"; $0.bitDepth = 10; $0.transfer = "hlg" }, true, "hlg"),
        ]
        for (clip, hdr, toneMapped) in rows {
            XCTAssertEqual(clip.hdr, hdr, "\(clip)")
            XCTAssertEqual(clip.toneMapped, toneMapped, "\(clip)")
        }
    }

    func testAnHDRClipIsAlwaysConvertedEvenWithTheSettingOff() {
        let hdr = with { $0.transfer = "hlg"; $0.bitDepth = 10 }
        XCTAssertTrue(VideoImport.needsOptimising(hdr))
        XCTAssertTrue(VideoImport.converts(hdr, settingOn: true))
        XCTAssertTrue(VideoImport.converts(hdr, settingOn: false))
        // An ordinary clip that needs it waits for the setting.
        let big = with { $0.width = 3840; $0.height = 2160 }
        XCTAssertTrue(VideoImport.converts(big, settingOn: true))
        XCTAssertFalse(VideoImport.converts(big, settingOn: false))
        XCTAssertFalse(VideoImport.converts(light, settingOn: true))
    }

    func testTheUploadRecordsWhatAnHDRClipWasToneMappedFrom() {
        let raw: [[String: Any]] = [["id": "vid-1", "kind": "video", "added": 1]]
        let marked = Uploads.optimised(raw, id: "vid-1", originalBytes: 90_000_000, toneMapped: "pq")
        XCTAssertEqual(marked[0]["optimised"] as? Bool, true)
        XCTAssertEqual(marked[0]["originalBytes"] as? Int64, 90_000_000)
        XCTAssertEqual(marked[0]["toneMapped"] as? String, "pq")
        // An ordinary clip has no such key.
        XCTAssertNil(Uploads.optimised(raw, id: "vid-1", originalBytes: 5)[0]["toneMapped"])
        XCTAssertEqual(VideoImport.convertingHDR, "Converting HDR video…")
        XCTAssertEqual(VideoImport.hdrFailed, "This HDR video couldn't be converted; it may look washed out")
    }

    func testToneMappingMatchesTheSharedFixture() throws {
        let fixture = try SharedFixture.object("hdr-tonemap")
        let tolerance = try XCTUnwrap(fixture["tolerance"] as? Double)
        XCTAssertEqual(fixture["peakNits"] as? Double, HdrToneMap.peakNits)
        XCTAssertEqual(fixture["whiteNits"] as? Double, HdrToneMap.whiteNits)
        let rows = try XCTUnwrap(fixture["rows"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 20)
        for row in rows {
            let transfer = try XCTUnwrap(row["transfer"] as? String)
            let input = try XCTUnwrap(row["in"] as? [Double])
            let expected = try XCTUnwrap(row["out"] as? [Double])
            let out = HdrToneMap.toneMap(input, transfer: transfer)
            for (got, want) in zip(out, expected) {
                XCTAssertEqual(got, want, accuracy: tolerance, "\(transfer) \(input)")
            }
        }
    }

    func testTheCurvesMeetTheirKnownPoints() {
        // PQ: 10,000 nits at full signal, and back again.
        XCTAssertEqual(HdrToneMap.pqToNits(1), 10000, accuracy: 0.5)
        XCTAssertEqual(HdrToneMap.nitsToPq(HdrToneMap.pqToNits(0.58)), 0.58, accuracy: 1e-6)
        // HLG: half signal is a twelfth of scene light; full signal all of it.
        XCTAssertEqual(HdrToneMap.hlgToScene(0.5), 1.0 / 12, accuracy: 1e-9)
        XCTAssertEqual(HdrToneMap.hlgToScene(1), 1, accuracy: 1e-6)
        // The roll-off leaves dark light alone and brings the peak to white.
        XCTAssertEqual(HdrToneMap.rolledOff(10), 10, accuracy: 0.01)
        XCTAssertEqual(HdrToneMap.rolledOff(HdrToneMap.peakNits), HdrToneMap.whiteNits, accuracy: 0.5)
        XCTAssertEqual(HdrToneMap.bt709(1), 1, accuracy: 1e-9)
    }
}
