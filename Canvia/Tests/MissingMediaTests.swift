// Photos, clips, animated pictures and sounds whose files are gone
// (MissingMedia): what is listed, held to the shared fixture
// missing-media.json; Replace keeping the look; the words said; the audit's
// missingMedia finding and the meta.json key — the rows the Android twin's
// MissingMediaTest holds.

import XCTest
@testable import Canvia

final class MissingMediaTests: XCTestCase {

    private func fixture() throws -> (design: Design, present: Set<String>, missing: [MissingMedia.Absent]) {
        let object = try SharedFixture.object("missing-media")
        let design = try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(object["design"])))
        let present = Set(try XCTUnwrap(object["exists"] as? [String]))
        let rows = try XCTUnwrap(object["missing"] as? [[String: Any]])
        let missing = try rows.map { row in
            MissingMedia.Absent(elementId: try XCTUnwrap(row["elementId"] as? String),
                              pageIndex: row["pageIndex"] as? Int,
                              kind: try XCTUnwrap(MissingMedia.MediaKind(rawValue: try XCTUnwrap(row["kind"] as? String))))
        }
        return (design, present, missing)
    }

    func testWhatIsMissingMatchesTheSharedFixture() throws {
        let f = try fixture()
        var asked: [String] = []
        let found = MissingMedia.missing(f.design) { file in
            asked.append(file)
            return f.present.contains(file)
        }
        XCTAssertEqual(found, f.missing)
        // Each file asked once, unstamped.
        XCTAssertEqual(asked.count, Set(asked).count)
        XCTAssertTrue(asked.contains("video:clip-gone"))
        XCTAssertFalse(asked.contains { $0.hasPrefix("asset:") || $0.hasPrefix("qr:") || $0.hasPrefix("motion:") })
        // Everything here: nothing missing.
        XCTAssertTrue(MissingMedia.missing(f.design) { _ in true }.isEmpty)
    }

    func testOnlyTheDesignsOwnFilesCount() {
        XCTAssertEqual(MissingMedia.stored("media:abc"), "media:abc")
        XCTAssertEqual(MissingMedia.stored("video:v1@3.25"), "video:v1")
        XCTAssertEqual(MissingMedia.stored("anim:a1@0.50"), "anim:a1")
        XCTAssertNil(MissingMedia.stored("asset:mountain"))
        XCTAssertNil(MissingMedia.stored("motion:waves"))
        XCTAssertNil(MissingMedia.stored("qr:https://example.com"))
        XCTAssertNil(MissingMedia.stored(nil))
        XCTAssertNil(MissingMedia.trackFile(AudioTrack(src: "sfx:pop")))
        XCTAssertNil(MissingMedia.trackFile(AudioTrack(src: "music:big-idea")))
        XCTAssertEqual(MissingMedia.trackFile(AudioTrack(src: "audio:song")), "audio:song")
        XCTAssertEqual(MissingMedia.trackFile(AudioTrack(src: "video:clip")), "video:clip")
    }

    func testReplaceKeepsTheCropFrameFiltersAndAltText() {
        var el = Element.image("media:gone")
        el.cropScale = 1.6
        el.cropX = 0.2
        el.straighten = 4
        el.maskShapeId = "circle"
        el.filter = "noir"
        el.altText = "A dog on a beach"
        el.altTextSource = "media:gone"
        let out = MissingMedia.replaced(el, src: "media:new")
        XCTAssertEqual(out.src, "media:new")
        XCTAssertEqual(out.cropScale, 1.6)
        XCTAssertEqual(out.cropX, 0.2)
        XCTAssertEqual(out.straighten, 4)
        XCTAssertEqual(out.maskShapeId, "circle")
        XCTAssertEqual(out.filter, "noir")
        XCTAssertEqual(out.altText, "A dog on a beach")
        XCTAssertNil(out.altTextSource)
    }

    func testTheWordsSaid() {
        XCTAssertEqual(MissingMedia.saying(.photo), "Photo missing")
        XCTAssertEqual(MissingMedia.saying(.anim), "Photo missing")
        XCTAssertEqual(MissingMedia.saying(.video), "Video missing")
        XCTAssertEqual(MissingMedia.saying(.audio), "Sound missing")
        XCTAssertEqual(MissingMedia.saying(background: "video:v"), "Video missing")
        XCTAssertEqual(MissingMedia.saying(background: "media:p"), "Photo missing")
        XCTAssertEqual(MissingMedia.chipText(.photo), "Photo missing · Replace")
        XCTAssertEqual(MissingMedia.chipText(.audio), "Sound missing · Replace")
        XCTAssertEqual(MissingMedia.banner(1), "1 item is missing from this design")
        XCTAssertEqual(MissingMedia.banner(3), "3 items are missing from this design")
        XCTAssertEqual(MissingMedia.spoken("Photo", missing: true), "Photo, missing")
        XCTAssertEqual(MissingMedia.spoken("Photo", missing: false), "Photo")
    }

    func testTheAuditSaysSoFirstOnItsPageWithReplace() throws {
        let f = try fixture()
        let all = AccessibilityAudit.findings(f.design, missingMedia: f.missing)
        let missing = all.filter { $0.kind == .missingMedia }
        XCTAssertEqual(missing.map(\.elementId), [nil, "e2", "e4", "e11", "e8", "e10"])
        XCTAssertEqual(missing.map(\.pageIndex), [0, 0, 0, 0, 1, 1])
        // A background's Replace opens Background.
        XCTAssertTrue(missing.allSatisfy { $0.fix == .replace })
        XCTAssertEqual(missing.map(\.message), ["Photo missing", "Photo missing", "Video missing", "Photo missing",
                                                "Photo missing", "Photo missing"])
        XCTAssertEqual(all.first?.kind, .missingMedia)
        XCTAssertEqual(AccessibilityAudit.Fix.replace.rawValue, "Replace")
        // The export row counts them for every file type.
        for format in ["pdf", "mp4", "gif", "svg", "docx"] {
            XCTAssertEqual(ExportPlan.nudgeFindings(missing, format: format).count, missing.count, format)
        }
        // None passed, none found.
        XCTAssertTrue(AccessibilityAudit.findings(f.design).allSatisfy { $0.kind != .missingMedia })
    }

    func testTheDismissedLineIsKeptInMetaJsonOnlyOnceDismissed() throws {
        var meta = DesignLibrary.VersionMeta(pinned: ["1": "Kept"])
        XCTAssertFalse(String(decoding: try XCTUnwrap(meta.data), as: UTF8.self).contains("missingNoteDismissed"))
        meta.missingNoteDismissed = 1_760_000_000_123
        let text = String(decoding: try XCTUnwrap(meta.data), as: UTF8.self)
        XCTAssertEqual(text, #"{"missingNoteDismissed":1760000000123,"pinned":{"1":"Kept"},"version":1}"#)
        XCTAssertEqual(DesignLibrary.VersionMeta.read(Data(text.utf8))?.missingNoteDismissed, 1_760_000_000_123)
    }
}
