// Live captions in Present: the lines in the shared rows
// (Fixtures/live-captions.json, byte for byte the Android twin's), the
// "presentCaptions" setting read leniently and written with all three keys,
// the band's contrast; and a talk's burnt-in captions, kept with it and
// given to each page of its film they were said on.

import XCTest
@testable import Canvia

final class LiveCaptionsTests: XCTestCase {

    func testTheSharedRowsWrapTheSameOnBothPhones() throws {
        let rows = try XCTUnwrap(try SharedFixture.object("live-captions")["rows"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let text = try XCTUnwrap(row["text"] as? String)
            let maxChars = try XCTUnwrap(row["maxChars"] as? Int)
            XCTAssertEqual(LiveCaptionLines.wrap(text, maxChars: maxChars), row["lines"] as? [String], text)
        }
    }

    func testTheSettingReadsLenientlyAndWritesAllThreeKeys() {
        XCTAssertEqual(LiveCaptionLines.Settings.decoded(nil), LiveCaptionLines.Settings())
        XCTAssertEqual(LiveCaptionLines.Settings().encoded(), #"{"on":false,"size":"medium","position":"bottom"}"#)
        let set = LiveCaptionLines.Settings.decoded(#"{"on":true,"size":"large","position":"top"}"#)
        XCTAssertEqual(set, LiveCaptionLines.Settings(on: true, size: "large", position: "top"))
        XCTAssertEqual(LiveCaptionLines.Settings.decoded(#"{"on":"yes","size":"huge","position":5}"#),
                       LiveCaptionLines.Settings())
        XCTAssertEqual(LiveCaptionLines.Settings.decoded(#"{"on":1}"#), LiveCaptionLines.Settings(),
                       "a number is no switch")
        XCTAssertEqual(LiveCaptionLines.Settings.decoded("not json"), LiveCaptionLines.Settings())
        XCTAssertEqual(LiveCaptionLines.Settings.decoded(set.encoded()), set)
        XCTAssertEqual(LiveCaptionLines.pref, "presentCaptions")
    }

    func testWhiteWordsOnTheBandReadAt45To1OnAnySlide() {
        XCTAssertGreaterThanOrEqual(LiveCaptionLines.worstContrast(), 4.5)
        XCTAssertEqual(LiveCaptionLines.lineChars(LiveCaptionLines.medium), 40)
        XCTAssertEqual(LiveCaptionLines.textShare("unknown"), 0.05)
        XCTAssertEqual(LiveCaptionLines.maxLines, 2)
        XCTAssertEqual(LiveCaptionLines.hideSeconds, 3)
        XCTAssertEqual(LiveCaptionLines.restartSeconds, 55)
    }

    func testBurntInCaptionsAreKeptWithTheTalkAndGivenToEachPageTheyWereSaidOn() throws {
        var design = Design(width: 1000, height: 500)
        design.pages = [Page(id: "p1"), Page(id: "p2")]
        let talk = Recording(id: "rec_1", createdAt: 1, audio: "rec_1.m4a", camera: nil,
                             pages: [RecordingSpan(pageId: "p1", start: 0, end: 4),
                                     RecordingSpan(pageId: "p2", start: 4, end: 9)],
                             captions: [CaptionCue(start: 0.5, end: 2, text: "Hello"),
                                        CaptionCue(start: 3.5, end: 5, text: "and welcome")])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let written = String(decoding: try encoder.encode(talk), as: UTF8.self)
        XCTAssertTrue(written.contains(#""captions":[{"end":2,"start":0.5,"text":"Hello"},{"end":5,"start":3.5,"text":"and welcome"}]"#),
                      written)
        XCTAssertEqual(try JSONDecoder().decode(Recording.self, from: Data(written.utf8)), talk)
        // None is no key, as before.
        var plain = talk
        plain.captions = []
        XCTAssertFalse(String(decoding: try encoder.encode(plain), as: UTF8.self).contains("captions"))
        let film = RecordingPlan.film(design, talk, fps: RecordingPlan.fps)
        let first = try XCTUnwrap(film.pages[0].elements.compactMap(\.captions).first)
        XCTAssertEqual(first.cues, [CaptionCue(start: 0.5, end: 2, text: "Hello"), CaptionCue(start: 3.5, end: 4, text: "and welcome")])
        XCTAssertEqual(first.style, Captions.box)
        XCTAssertEqual(film.pages[1].elements.compactMap(\.captions).first?.cues, [CaptionCue(start: 0, end: 1, text: "and welcome")])
        // Without captions, the pages are as they were.
        XCTAssertTrue(RecordingPlan.film(design, plain, fps: RecordingPlan.fps).pages.allSatisfy { $0.elements.isEmpty })
    }
}
