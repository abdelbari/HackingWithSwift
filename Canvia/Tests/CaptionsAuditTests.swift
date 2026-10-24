// Check accessibility's captions rule: a clip that is heard with no caption
// box for it on its page, and a voice-over with none on the page its start
// falls on, each offering Add captions; MP4 and GIF exports remind about
// those alone. The rows are the Android twin's AccessibilityAuditTest's,
// and the shared fixture (Fixtures/captions-audit.json) lists the same
// findings in the same order on both phones.

import XCTest
@testable import Canvia

final class CaptionsAuditTests: XCTestCase {

    private func clip(_ id: String = "c", src: String = "video:v1") -> Element {
        var el = Element.image(src)
        el.id = id
        el.altText = "A clip"
        return el
    }

    /// Shared: the same captions findings, with the others, in the same
    /// order on both phones.
    func testTheCaptionsFixtureListsWhatItSaysInItsOrder() throws {
        let fixture = try SharedFixture.object("captions-audit")
        let design = try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(fixture["design"])))
        let silent = Set(try XCTUnwrap(fixture["silentClips"] as? [String]))
        let found = AccessibilityAudit.findings(design, silentClips: silent).filter { $0.kind != .headings }
        let expected = try XCTUnwrap(fixture["findings"] as? [[String: Any]])
        XCTAssertEqual(found.count, expected.count)
        for (f, row) in zip(found, expected) {
            XCTAssertEqual(f.kind.rawValue, row["kind"] as? String)
            XCTAssertEqual(f.pageIndex, row["page"] as? Int)
            XCTAssertEqual(f.elementId, row["id"] as? String)
            XCTAssertEqual(f.message, row["message"] as? String)
            XCTAssertEqual(f.fix?.rawValue, row["fix"] as? String)
            XCTAssertEqual(f.source, row["source"] as? String)
        }
        // Two narrations on one page would be two rows, each its own.
        XCTAssertEqual(Set(found.map(\.id)).count, found.count)
    }

    func testCaptionsComeAfterColourVisionAndBeforeMissingLetters() {
        let kinds = AccessibilityAudit.Kind.allCases
        XCTAssertEqual(kinds.firstIndex(of: .colourVision).map { $0 + 1 }, kinds.firstIndex(of: .captions))
        XCTAssertEqual(kinds.last, .missingLetters)
        XCTAssertEqual(AccessibilityAudit.Fix.addCaptions.rawValue, "Add captions")
    }

    func testAClipIsAskedAboutOnlyWhileItIsHeardAndUncaptioned() {
        let heard = clip()
        let page = Page(elements: [heard])
        XCTAssertTrue(AccessibilityAudit.needsCaptions(page, heard))
        var muted = heard
        muted.clip = ClipPlayback(muted: true)
        XCTAssertFalse(AccessibilityAudit.needsCaptions(page, muted))
        var quiet = heard
        quiet.clip = ClipPlayback(volume: 0)
        XCTAssertFalse(AccessibilityAudit.needsCaptions(page, quiet))
        XCTAssertFalse(AccessibilityAudit.needsCaptions(page, heard, silentClips: ["v1"]))
        XCTAssertFalse(AccessibilityAudit.needsCaptions(page, Element.image("media:a")))
        let box = Captions.element(width: 1080, height: 1080,
                                   captions: Captions(source: "video:v1", cues: [CaptionCue(start: 0, end: 1, text: "Hi")]))
        XCTAssertFalse(AccessibilityAudit.needsCaptions(Page(elements: [heard, box]), heard))
        // A box with no cue yet captions nothing; a hidden one is not seen.
        let empty = Captions.element(width: 1080, height: 1080, captions: Captions(source: "video:v1"))
        XCTAssertTrue(AccessibilityAudit.needsCaptions(Page(elements: [heard, empty]), heard))
        var hidden = box
        hidden.hidden = true
        XCTAssertTrue(AccessibilityAudit.needsCaptions(Page(elements: [heard, hidden]), heard))
        // A still from a moment of the clip is the clip's, said as the clip.
        let still = clip(src: VideoStore.src("v1", at: 2))
        XCTAssertEqual(AccessibilityAudit.clipSource(still), "video:v1")
    }

    func testAVoiceOverIsNarrationAndASongIsNot() {
        XCTAssertTrue(AccessibilityAudit.isNarration(AudioTrack(src: "audio:r1", name: "Voice-over")))
        XCTAssertTrue(AccessibilityAudit.isNarration(AudioTrack(src: "audio:r2", name: "Voice-over 3")))
        XCTAssertFalse(AccessibilityAudit.isNarration(AudioTrack(src: "audio:r3", volume: 0, name: "Voice-over")))
        XCTAssertFalse(AccessibilityAudit.isNarration(AudioTrack(src: "music:sunny", name: "Song")))
    }

    func testMp4AndGifExportsMentionTheCaptionsFindingsAlone() {
        var pale = Element.text("Hard to see", fontSize: 20)
        pale.id = "pale"
        pale.color = "#cccccc"
        pale.y = 600
        var d = Design(title: "Film", width: 1080, height: 1080)
        d.pages = [Page(elements: [clip(), pale])]
        let all = AccessibilityAudit.findings(d)
        XCTAssertEqual(all.map(\.kind), [.contrast, .captions])
        for type in ["mp4", "gif"] {
            XCTAssertEqual(ExportPlan.nudgeFindings(all, format: type).map(\.kind), [.captions])
        }
        XCTAssertEqual(ExportPlan.nudgeFindings(all, format: "pdf"), all)
        XCTAssertTrue(ExportPlan.nudgeFindings(all, format: "svg").isEmpty)
        XCTAssertTrue(ExportPlan.nudgeFindings(all.filter { $0.kind != .captions }, format: "mp4").isEmpty)
    }
}
