// Captions: the cue at a moment, the `captions` key as the file carries
// it, SRT and WebVTT in and out, splitting and shifting cues, grouping
// words heard into cues, what the renderer draws, and the steps the store
// makes of them. The shared rows are the Android twin's CaptionsTest.

import XCTest
import CoreGraphics
@testable import Canvia

final class CaptionsTests: XCTestCase {

    private let hello = Captions(source: "video:clip1",
                                 cues: [CaptionCue(start: 1, end: 2, text: "Hello world"), CaptionCue(start: 2.5, end: 3.5, text: "Again")],
                                 style: Captions.plain)

    private func json(_ el: Element) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(el)) as? [String: Any])
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "captions", width: 1000, height: 800)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    // MARK: the cue at a moment

    func testTheCueAtAMomentNoneBetweenCuesOrBeforeTheFirst() {
        XCTAssertEqual(hello.cueAt(1)?.text, "Hello world")
        XCTAssertEqual(hello.cueAt(1.99)?.text, "Hello world")
        XCTAssertNil(hello.cueAt(2))
        XCTAssertNil(hello.cueAt(0.5))
        XCTAssertEqual(hello.cueAt(3)?.text, "Again")
        XCTAssertNil(hello.cueAt(3.5))
    }

    // MARK: the file

    func testCaptionsAreWrittenOnTheBoxWithItsTextAtTheFirstCueAndReadBack() throws {
        let box = Captions.on(Element.text("typed"), hello)
        XCTAssertEqual(box.text, "Hello world")
        XCTAssertEqual(box.captions, hello)
        let written = try XCTUnwrap(try json(box)["captions"] as? [String: Any])
        XCTAssertEqual(written["source"] as? String, "video:clip1")
        XCTAssertEqual(written["style"] as? String, "plain")
        let cues = try XCTUnwrap(written["cues"] as? [[String: Any]])
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0]["start"] as? Double, 1)
        XCTAssertEqual(cues[0]["end"] as? Double, 2)
        XCTAssertEqual(cues[0]["text"] as? String, "Hello world")
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(box)).captions, hello)
        // No source is written as null; a style this build does not know
        // is plain; a cue that cannot be read is passed over; the cues come
        // sorted.
        let none = try json(Captions.on(Element.text("x"), Captions(cues: [CaptionCue(start: 0, end: 1, text: "a")])))
        XCTAssertTrue(try XCTUnwrap(none["captions"] as? [String: Any])["source"] is NSNull)
        let loose = #"{"id":"t","type":"text","text":"x","captions":{"source":null,"cues":[{"start":3,"end":4,"text":"b"},"#
            + #"{"start":"1","end":2,"text":"bad"},{"start":2,"end":1,"text":"backwards"},{"start":0,"end":1,"text":"a"}],"style":"karaoke"}}"#
        let read = try JSONDecoder().decode(Element.self, from: Data(loose.utf8))
        XCTAssertEqual(read.captions, Captions(source: nil, cues: [CaptionCue(start: 0, end: 1, text: "a"),
                                                                   CaptionCue(start: 3, end: 4, text: "b")], style: Captions.plain))
        XCTAssertNil(Element.text("plain").captions)
        XCTAssertNil(try json(Element.text("plain"))["captions"])
        // Captions on anything but a text box are no captions.
        let shape = #"{"id":"s","type":"shape","shapeId":"rect","captions":{"source":null,"cues":[],"style":"plain"}}"#
        XCTAssertNil(try JSONDecoder().decode(Element.self, from: Data(shape.utf8)).captions)
        XCTAssertNil(Captions.on(box, nil).captions)
        XCTAssertEqual(Captions.on(Element.text("x"), Captions()).text, "")
    }

    func testANewCaptionBoxSitsAcrossTheLowerPartOfThePage() {
        let box = Captions.element(width: 1000, height: 800, captions: hello)
        XCTAssertEqual(box.fontSize, 36)
        XCTAssertEqual(box.h, 90, accuracy: 1e-9)
        XCTAssertEqual(box.x, 100, accuracy: 1e-9)
        XCTAssertEqual(box.w, 800, accuracy: 1e-9)
        XCTAssertEqual(box.y, 662, accuracy: 1e-9)
        XCTAssertEqual(box.color, "#ffffff")
        XCTAssertEqual(box.fontWeight, 600)
        XCTAssertEqual(box.text, "Hello world")
        XCTAssertEqual(Captions.element(width: 100, height: 100, captions: hello).fontSize, 12)
    }

    func testSRTAndWebVTTReadTagsDroppedAndWrite() throws {
        let srt = "1\n00:00:01,000 --> 00:00:04,000\nHello <b>there</b>\n\n2\n00:00:05,500 --> 00:00:07,250\nSecond line one\nline two\n"
        XCTAssertEqual(Captions.parse(srt), [CaptionCue(start: 1, end: 4, text: "Hello there"),
                                             CaptionCue(start: 5.5, end: 7.25, text: "Second line one\nline two")])
        let vtt = "WEBVTT\n\nNOTE made by hand\n\n00:01.000 --> 00:03.000 position:10%\nHi\n\n00:00:02.000 --> 00:00:01.000\nbackwards\n\n01:00:00.000 --> 01:00:01.000\n\n"
        XCTAssertEqual(Captions.parse(vtt), [CaptionCue(start: 1, end: 3, text: "Hi")])
        XCTAssertEqual(Captions.parse("just words"), [])
        XCTAssertEqual(Captions.parse("\u{FEFF}1\r\n00:00:01,000 --> 00:00:02,000\r\nWindows\r\n"),
                       [CaptionCue(start: 1, end: 2, text: "Windows")])
        XCTAssertEqual(Captions.srt(hello.cues), "1\n00:00:01,000 --> 00:00:02,000\nHello world\n\n2\n00:00:02,500 --> 00:00:03,500\nAgain\n\n")
        XCTAssertEqual(Captions.vtt(hello.cues), "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHello world\n\n00:00:02.500 --> 00:00:03.500\nAgain\n\n")
        XCTAssertEqual(Captions.timeCode(3723.45, srt: true), "01:02:03,450")
        XCTAssertEqual(try XCTUnwrap(Captions.time("01:02:03.450")), 3723.45, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Captions.time("01:03,500")), 63.5, accuracy: 1e-9)
        XCTAssertNil(Captions.time("3.5"))
        XCTAssertNil(Captions.time("-1:00"))
        // Out and back in is the same.
        XCTAssertEqual(Captions.parse(Captions.srt(hello.cues)), hello.cues)
        XCTAssertEqual(Captions.parse(Captions.vtt(hello.cues)), hello.cues)
    }

    // MARK: splitting and shifting

    func testLongCuesWrapTo42CharactersAndSplitPastTwoLinesSharingTheirTimeByCharacters() {
        let words = "The quick brown fox jumps over the lazy dog while the band plays on and on into the night"
        XCTAssertEqual(Captions.wrapped(words),
                       ["The quick brown fox jumps over the lazy", "dog while the band plays on and on into", "the night"])
        XCTAssertEqual(Captions.wrapped(String(repeating: "a", count: 50)), [String(repeating: "a", count: 50)])
        let split = Captions.split([CaptionCue(start: 0, end: 10, text: words)])
        XCTAssertEqual(split.count, 2)
        XCTAssertEqual(split[0].text, "The quick brown fox jumps over the lazy\ndog while the band plays on and on into")
        XCTAssertEqual(split[1].text, "the night")
        // 79 of 88 characters in the first part: 8.98 seconds of the ten.
        XCTAssertEqual(split[0].start, 0)
        XCTAssertEqual(split[0].end, 8.98, accuracy: 1e-9)
        XCTAssertEqual(split[1].start, 8.98, accuracy: 1e-9)
        XCTAssertEqual(split[1].end, 10)
        // A short cue is wrapped and left as one.
        XCTAssertEqual(Captions.split([CaptionCue(start: 0, end: 1, text: "  Hi  ")]), [CaptionCue(start: 0, end: 1, text: "Hi")])
        XCTAssertEqual(Captions.split([CaptionCue(start: 0, end: 1, text: "   ")]), [])
    }

    func testAPageSplitCutsTheCuesBetweenTheHalves() throws {
        let cues = [CaptionCue(start: 0, end: 2, text: "a"), CaptionCue(start: 1.5, end: 3, text: "b"),
                    CaptionCue(start: 4, end: 5, text: "c")]
        let halves = Captions.cut(cues, at: 2.5)
        XCTAssertEqual(halves.first, [CaptionCue(start: 0, end: 2, text: "a"), CaptionCue(start: 1.5, end: 2.5, text: "b")])
        XCTAssertEqual(halves.second, [CaptionCue(start: 0, end: 0.5, text: "b"), CaptionCue(start: 1.5, end: 2.5, text: "c")])
        // Through the timeline: the first half keeps what ends by the cut,
        // the second what plays on, moved back.
        let box = Captions.on(Element.text(""), Captions(cues: [CaptionCue(start: 1, end: 2, text: "a"),
                                                                CaptionCue(start: 2.5, end: 3.5, text: "b")]))
        var page = Page(elements: [box])
        page.holdSeconds = 4
        let split = try XCTUnwrap(Timeline.split(page, at: 2, hold: 4, duration: { _ in nil }))
        XCTAssertEqual(split.first.elements[0].captions?.cues, [CaptionCue(start: 1, end: 2, text: "a")])
        XCTAssertEqual(split.second.elements[0].captions?.cues, [CaptionCue(start: 0.5, end: 1.5, text: "b")])
        XCTAssertEqual(split.second.elements[0].text, "b")
    }

    func testAClipsTrimAndSpeedMoveItsCuesSoTheWordsStayOnTheirFrames() {
        let cues = [CaptionCue(start: 2, end: 4, text: "a"), CaptionCue(start: 0, end: 0.5, text: "gone")]
        // Trimmed to start at 1 and played at double speed: 2…4 of the clip
        // is 0.5…1.5 of the page.
        XCTAssertEqual(Captions.retimed(cues, from: ClipPlayback(), to: ClipPlayback(start: 1, speed: 2)),
                       [CaptionCue(start: 0.5, end: 1.5, text: "a")])
        // And back again.
        XCTAssertEqual(Captions.retimed([CaptionCue(start: 0.5, end: 1.5, text: "a")], from: ClipPlayback(start: 1, speed: 2),
                                        to: ClipPlayback()),
                       [CaptionCue(start: 2, end: 4, text: "a")])
        // A trim that starts after a cue starts cuts it to the page's start.
        XCTAssertEqual(Captions.retimed([CaptionCue(start: 2, end: 4, text: "a")], from: ClipPlayback(), to: ClipPlayback(start: 3)),
                       [CaptionCue(start: 0, end: 1, text: "a")])
    }

    func testWordsHeardBecomeCuesBrokenAtSilencesAtFiveSecondsAndAtTwoLines() {
        let words = [Captions.Word(start: 0, text: "Hello"), Captions.Word(start: 0.3, text: "there"),
                     Captions.Word(start: 2, text: "after"), Captions.Word(start: 2.4, text: "the"),
                     Captions.Word(start: 2.6, text: "gap")]
        XCTAssertEqual(Captions.fromWords(words),
                       [CaptionCue(start: 0, end: 0.8, text: "Hello there"), CaptionCue(start: 2, end: 3.1, text: "after the gap")])
        // Seven seconds of steady words: cut where the cue would run past five.
        let steady = (0..<14).map { Captions.Word(start: Double($0) * 0.5, text: "w\($0)") }
        let cues = Captions.fromWords(steady)
        XCTAssertEqual(cues.count, 2)
        XCTAssertTrue(cues.allSatisfy { $0.end - $0.start <= Captions.maxCue + 1e-9 })
        XCTAssertEqual(cues[0].text, "w0 w1 w2 w3 w4 w5 w6 w7 w8 w9")
        XCTAssertEqual(cues[0].end, 5, accuracy: 1e-9)
        XCTAssertEqual(cues[1].start, 5, accuracy: 1e-9)
        XCTAssertEqual(cues[1].end, 7, accuracy: 1e-9)
        // Long words: a new cue once another would not fit two lines.
        let long = (0..<12).map { Captions.Word(start: Double($0) * 0.2, text: String(repeating: "x", count: 20)) }
        XCTAssertTrue(Captions.fromWords(long).allSatisfy { Captions.wrapped($0.text).count <= 2 })
        XCTAssertEqual(Captions.fromWords([]), [])
    }

    // MARK: drawn

    func testTheRendererDrawsTheCueAtTheMomentTheFirstForAStillStyled() {
        let box = Captions.on(Element.text("x"), hello)
        XCTAssertEqual(Captions.shown(box, at: 1.5).text, "Hello world")
        XCTAssertEqual(Captions.shown(box, at: 2.2).text, "")
        XCTAssertEqual(Captions.shown(box, at: nil).text, "Hello world")
        XCTAssertEqual(TextEffect.from(Captions.shown(box, at: 1.5).effect), .none)
        let boxed = Captions.on(box, Captions(source: hello.source, cues: hello.cues, style: Captions.box))
        XCTAssertEqual(Captions.shown(boxed, at: 1.5).effect?.type, "highlight")
        let sung = Captions.on(box, Captions(source: hello.source, cues: hello.cues, style: Captions.highlightWord))
        XCTAssertEqual(Captions.shown(sung, at: 1.6).liveSpans, [TextSpan(start: 6, end: 11, color: Captions.highlightColour)])
        XCTAssertEqual(Captions.shown(sung, at: 1.2).liveSpans, [TextSpan(start: 0, end: 5, color: Captions.highlightColour)])
        XCTAssertEqual(Captions.shown(sung, at: nil).liveSpans, [TextSpan(start: 0, end: 5, color: Captions.highlightColour)])
        XCTAssertEqual(Captions.shown(sung, at: 2.2).liveSpans, [])
        // A plain box is left alone.
        let plain = Element.text("words")
        XCTAssertEqual(Captions.shown(plain, at: 1), plain)
        XCTAssertEqual(Captions.wordRanges("Hello world").map { [$0.start, $0.end] }, [[0, 5], [6, 11]])
    }

    func testAFilmsCaptionsAreEveryPagesMovedOnByWhereThePageStarts() {
        let one = Page(elements: [Captions.on(Element.text(""), Captions(cues: [CaptionCue(start: 1, end: 2, text: "a")]))])
        let two = Page(elements: [Captions.on(Element.text(""), Captions(cues: [CaptionCue(start: 0.5, end: 1, text: "b")]))])
        var design = Design(title: "film", width: 100, height: 100)
        design.pages = [one, Page(), two]
        XCTAssertEqual(Captions.film(design, indices: [0, 2]) { $0 == 0 ? 3 : 4 },
                       [CaptionCue(start: 1, end: 2, text: "a"), CaptionCue(start: 3.5, end: 4, text: "b")])
        XCTAssertTrue(Captions.any(design))
        var bare = Design(title: "bare", width: 100, height: 100)
        bare.pages = [Page()]
        XCTAssertFalse(Captions.any(bare))
    }

    // MARK: the store

    func testSettingCaptionsMakesABoxThenKeepsItAsOneStepEach() {
        let s = store([])
        s.setCaptions("video:clip1", cues: hello.cues)
        XCTAssertEqual(s.page.elements.count, 1)
        let box = s.page.elements[0]
        XCTAssertEqual(box.captions, Captions(source: "video:clip1", cues: hello.cues))
        XCTAssertEqual(box.text, "Hello world")
        XCTAssertEqual(s.selection, [box.id])
        XCTAssertEqual(s.captionsFor("video:clip1")?.id, box.id)
        // The same source again writes the box it has, its style kept.
        s.setCaptionStyle("video:clip1", Captions.box)
        s.setCaptions("video:clip1", cues: [CaptionCue(start: 0, end: 1, text: "New")])
        XCTAssertEqual(s.page.elements.count, 1)
        XCTAssertEqual(s.page.elements[0].captions?.style, Captions.box)
        XCTAssertEqual(s.page.elements[0].text, "New")
        s.undo()
        XCTAssertEqual(s.page.elements[0].text, "Hello world")
        s.undo()
        XCTAssertEqual(s.page.elements[0].captions?.style, Captions.plain)
        s.undo()
        XCTAssertTrue(s.page.elements.isEmpty)
        // Nothing goes on a locked page.
        s.setPageLocked(true)
        s.setCaptions("video:clip1", cues: hello.cues)
        XCTAssertTrue(s.page.elements.isEmpty)
        XCTAssertEqual(s.announcementUnlocks, s.page.id)
    }

    func testAClipsCaptionsMoveWithItsTrimAndSpeed() {
        var clip = Element.image("video:vid_1", w: 400, h: 300)
        clip.x = 100
        let box = Captions.on(Element.text(""), Captions(source: "video:vid_1", cues: [CaptionCue(start: 2, end: 4, text: "a")]))
        let s = store([clip, box])
        s.selection = [clip.id]
        s.setClip(ClipPlayback(start: 1, speed: 2))
        XCTAssertEqual(s.page.elements[0].clip, ClipPlayback(start: 1, speed: 2))
        XCTAssertEqual(s.page.elements[1].captions?.cues, [CaptionCue(start: 0.5, end: 1.5, text: "a")])
        s.undo()
        XCTAssertEqual(s.page.elements[1].captions?.cues, [CaptionCue(start: 2, end: 4, text: "a")])
        XCTAssertEqual(s.pageStartSeconds, 0)
    }

    /// The .srt beside a video: the pages played, each moved on by where
    /// it starts.
    @MainActor
    func testTheVideosCaptionsFileHoldsThePagesPlayed() throws {
        var design = Design(title: "Talk", width: 100, height: 100)
        var first = Page(elements: [Captions.on(Element.text(""), Captions(cues: [CaptionCue(start: 1, end: 2, text: "a")]))])
        first.holdSeconds = 3
        let second = Page(elements: [Captions.on(Element.text(""), Captions(cues: [CaptionCue(start: 0.5, end: 1, text: "b")]))])
        design.pages = [first, second]
        let url = try XCTUnwrap(ExportJobs.captionsFile(ExportSnapshot(design, range: .all, current: 0)))
        XCTAssertEqual(url.pathExtension, "srt")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8),
                       "1\n00:00:01,000 --> 00:00:02,000\na\n\n2\n00:00:03,500 --> 00:00:04,000\nb\n\n")
        var silent = Design(title: "Silent", width: 100, height: 100)
        silent.pages = [Page()]
        XCTAssertNil(try ExportJobs.captionsFile(ExportSnapshot(silent, range: .all, current: 0)))
    }
}
