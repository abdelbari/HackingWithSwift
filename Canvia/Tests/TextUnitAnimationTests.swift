// Text that moves by letter, word or line: the "by" key, the units of the
// words, the frame table for the shared three-word fixture at 0, 0.5 and
// 1 second (Fixtures/unit-frames.json, shared with the Android twin's
// TextUnitAnimationTest), exits as the frames played back, and the reveal
// by word and line.

import XCTest
@testable import Canvia

final class TextUnitAnimationTests: XCTestCase {

    /// The shared fixture: three words at 40, by word, one second from 0.
    private func fixture(_ kind: String) -> Element {
        var el = Element.text("One two six", fontSize: 40)
        el.animation = ElementAnimation(kind: kind, delay: 0, duration: 1, by: "word")
        return el
    }

    func testTheKindsAreInTheSameOrderOnBothPhones() {
        XCTAssertEqual(ElementAnimation.textKindOrder,
                       ["typewriter", "words", "letterPop", "lineRise", "ascend", "shift", "merge", "block", "burst",
                        "bounceIn", "roll", "skate", "spread", "clarify", "tumble", "writeOn"])
        XCTAssertTrue(ElementAnimation.kinds.contains("writeOn"))
        XCTAssertEqual(ElementAnimation.unitKinds.count, 12)
    }

    func testByReadsAndWritesAndOldFilesReadAsBefore() throws {
        let read = try JSONDecoder().decode(ElementAnimation.self,
                                            from: Data(#"{"kind":"ascend","delay":0,"duration":1,"by":"line"}"#.utf8))
        XCTAssertEqual(read.by, "line")
        XCTAssertEqual(read.unit, "line")
        let old = try JSONDecoder().decode(ElementAnimation.self,
                                           from: Data(#"{"kind":"typewriter","delay":0,"duration":1}"#.utf8))
        XCTAssertNil(old.by)
        XCTAssertEqual(old.unit, "letter")
        XCTAssertEqual(ElementAnimation(kind: "words").unit, "word")
        XCTAssertEqual(ElementAnimation(kind: "block").unit, "line")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(old), as: UTF8.self),
                       #"{"delay":0,"duration":1,"kind":"typewriter"}"#, "no by, no key")
    }

    func testTheUnitsOfTheWords() {
        let text = "Hi there\n  big day "
        XCTAssertEqual(ElementAnimation.units(text, by: "letter").count, 13)
        XCTAssertEqual(ElementAnimation.units(text, by: "word"),
                       [NSRange(location: 0, length: 2), NSRange(location: 3, length: 5),
                        NSRange(location: 11, length: 3), NSRange(location: 15, length: 3)])
        XCTAssertEqual(ElementAnimation.units(text, by: "line"),
                       [NSRange(location: 0, length: 8), NSRange(location: 11, length: 7)])
    }

    /// The shared table (Fixtures/unit-frames.json, the Android twin's
    /// byte for byte): every unit kind, three words by word, at 0, 0.5 and
    /// 1 second.
    func testEveryUnitKindGivesTheSharedFrames() throws {
        let fixture = try SharedFixture.object("unit-frames")
        let text = try XCTUnwrap(fixture["text"] as? String)
        let size = try XCTUnwrap(fixture["fontSize"] as? Double)
        let by = try XCTUnwrap(fixture["by"] as? String)
        let columns = try XCTUnwrap(fixture["columns"] as? [String])
        let frames = try XCTUnwrap(fixture["frames"] as? [String: [String: [[Double]]]])
        XCTAssertEqual(Set(frames.keys), ElementAnimation.unitKinds)
        var el = Element.text(text, fontSize: size)
        for (kind, table) in frames {
            el.animation = ElementAnimation(kind: kind, delay: 0, duration: 1, by: by)
            for (time, rows) in table {
                let got = ElementAnimation.unitFrames(el, at: try XCTUnwrap(Double(time)))
                XCTAssertEqual(got.count, rows.count, "\(kind) at \(time)")
                for (f, row) in zip(got, rows) {
                    let values = [Double(f.start), Double(f.end), f.dx, f.dy, f.scale, f.rotation, f.alpha, f.blur, f.clip]
                    for (k, v) in values.enumerated() {
                        XCTAssertEqual(v, row[k], accuracy: 1e-4, "\(kind) at \(time), \(columns[k])")
                    }
                }
            }
        }
        XCTAssertEqual(ElementAnimation.bounce(0), 0, accuracy: 1e-12)
        XCTAssertEqual(ElementAnimation.bounce(1), 1, accuracy: 1e-12)
    }

    func testTheOlderKindsKeepTheirRevealAndAnimateByIsKept() {
        var typed = fixture("typewriter")
        XCTAssertTrue(ElementAnimation.unitFrames(typed, at: 0.5).isEmpty, "a reveal, not units")
        XCTAssertEqual(ElementAnimation(kind: "lineRise").unit, "letter")
        typed = ElementAnimation.applied([typed], kind: "burst")[0]
        XCTAssertEqual(typed.animation?.by, "word", "kept for another text kind")
        XCTAssertNil(ElementAnimation.applied([typed], kind: "fade")[0].animation?.by)
    }

    func testAUnitKindDrawsAUnitAtATimeAndSettles() {
        let el = fixture("ascend")
        let moving = el.animation?.state(at: 0.5, text: "One two six", size: 40, el: el)
        XCTAssertEqual(moving?.unitClock?.time, 0.5)
        XCTAssertEqual(moving?.opacity, 1, "the box itself stays")
        XCTAssertNil(el.animation?.state(at: 1, el: el).unitClock, "settled once in")
    }

    func testAnExitPlaysTheFramesBackwards() {
        let exit = ElementAnimation(kind: "ascend", delay: 0, duration: 1, by: "word")
        XCTAssertNil(exit.exitState(at: 3.9, hold: 5).unitClock, "still in before it begins")
        let leaving = exit.exitState(at: 4.25, hold: 5)
        XCTAssertEqual(leaving.unitClock?.time ?? -1, 0.75, accuracy: 1e-9)
        XCTAssertEqual(leaving.unitClock?.animation.delay, 0)
        XCTAssertEqual(exit.exitState(at: 5, hold: 5).opacity, 0)
    }

    func testTheRevealGoesByItsUnit() {
        let text = "One two\nsix ten"
        XCTAssertEqual(ElementAnimation.revealed(text, by: "word", share: 0.5), 11, "words split at spaces, as before")
        XCTAssertEqual(ElementAnimation.revealed(text, by: "line", share: 0.5), 7)
        XCTAssertEqual(ElementAnimation.revealed(text, by: "letter", share: 0.5), 8)
        let typed = ElementAnimation(kind: "typewriter", delay: 0, duration: 1, by: "line")
        XCTAssertEqual(typed.state(at: 0.5, text: text).visibleCharacters, 7)
        XCTAssertEqual(ElementAnimation(kind: "words", delay: 0, duration: 1).state(at: 0.5, text: text).visibleCharacters,
                       ElementAnimation.revealed(text, by: "word", share: 0.5), "as Word by word always has")
    }
}
