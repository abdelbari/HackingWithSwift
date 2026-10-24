// Text that moves by letter, word or line: the "by" key, the units of the
// words, the frame table for the shared three-word fixture at 0, 0.5 and
// 1 second, exits as the frames played back, and the reveal by word and
// line. The tables are the Android twin's TextUnitAnimationTest's.

import XCTest
@testable import Canvia

final class TextUnitAnimationTests: XCTestCase {

    /// The shared fixture: three words at 40, by word, one second from 0.
    private func fixture(_ kind: String) -> Element {
        var el = Element.text("One two six", fontSize: 40)
        el.animation = ElementAnimation(kind: kind, delay: 0, duration: 1, by: "word")
        return el
    }

    private func assertFrame(_ f: ElementAnimation.UnitFrame, dx: Double = 0, dy: Double = 0, scale: Double = 1,
                             rotation: Double = 0, alpha: Double, blur: Double = 0, clip: Double = 1,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(f.dx, dx, accuracy: 1e-9, "dx", file: file, line: line)
        XCTAssertEqual(f.dy, dy, accuracy: 1e-9, "dy", file: file, line: line)
        XCTAssertEqual(f.scale, scale, accuracy: 1e-9, "scale", file: file, line: line)
        XCTAssertEqual(f.rotation, rotation, accuracy: 1e-9, "rotation", file: file, line: line)
        XCTAssertEqual(f.alpha, alpha, accuracy: 1e-9, "alpha", file: file, line: line)
        XCTAssertEqual(f.blur, blur, accuracy: 1e-9, "blur", file: file, line: line)
        XCTAssertEqual(f.clip, clip, accuracy: 1e-9, "clip", file: file, line: line)
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

    /// The shared table: Ascend by word at 0, 0.5 and 1 second.
    func testAscendByWordFramesAtZeroHalfAndOne() {
        let el = fixture("ascend")
        let zero = ElementAnimation.unitFrames(el, at: 0)
        XCTAssertEqual(zero.count, 3)
        for (f, start) in zip(zero, [0, 0.2, 0.4]) {
            XCTAssertEqual(f.start, start, accuracy: 1e-9)
            XCTAssertEqual(f.end, start + 0.4, accuracy: 1e-9)
        }
        for f in zero { assertFrame(f, dy: 20, alpha: 0) }
        let half = ElementAnimation.unitFrames(el, at: 0.5)
        assertFrame(half[0], alpha: 1)
        assertFrame(half[1], dy: 0.3125, alpha: 0.984375)
        assertFrame(half[2], dy: 8.4375, alpha: 0.578125)
        for f in ElementAnimation.unitFrames(el, at: 1) { assertFrame(f, alpha: 1) }
    }

    /// The shared table for the other kinds at 0.5 second: the second word,
    /// q = 0.75, e = 0.984375; the third, q = 0.25, e = 0.578125.
    func testEveryKindsFramesAtHalfASecond() {
        func half(_ kind: String) -> [ElementAnimation.UnitFrame] { ElementAnimation.unitFrames(fixture(kind), at: 0.5) }
        let shiftFrames = half("shift")
        assertFrame(shiftFrames[1], dx: 0.3125, alpha: 0.984375)
        let mergeFrames = half("merge")
        assertFrame(mergeFrames[1], dx: 0.625, alpha: 0.984375)
        assertFrame(mergeFrames[2], dx: -16.875, alpha: 0.578125)
        let blockFrames = half("block")
        assertFrame(blockFrames[1], alpha: 1, clip: 1)
        assertFrame(blockFrames[2], alpha: 0, clip: 0.5)
        let burstFrames = half("burst")
        assertFrame(burstFrames[2], scale: 1.421875, alpha: 0.578125)
        let bounceFrames = half("bounceIn")
        assertFrame(bounceFrames[2], dy: -(1 - ElementAnimation.bounce(0.25)) * 40, alpha: 0.5)
        let rollFrames = half("roll")
        assertFrame(rollFrames[2], dx: 8.4375, rotation: 37.96875, alpha: 0.578125)
        let skateFrames = half("skate")
        assertFrame(skateFrames[2], dx: 16.875, rotation: -6.328125, alpha: 0.578125)
        let spreadFrames = half("spread")
        assertFrame(spreadFrames[0], alpha: 1)
        assertFrame(spreadFrames[2], dx: 8.4375, alpha: 0.578125)
        let clarifyFrames = half("clarify")
        assertFrame(clarifyFrames[2], alpha: 0.578125, blur: 4.21875)
        let tumbleFrames = half("tumble")
        assertFrame(tumbleFrames[2], dy: -8.4375, scale: 0.7890625, rotation: -75.9375, alpha: 0.578125)
        let writeFrames = half("writeOn")
        assertFrame(writeFrames[2], alpha: 1, clip: 0.25)
        XCTAssertEqual(ElementAnimation.bounce(0), 0, accuracy: 1e-12)
        XCTAssertEqual(ElementAnimation.bounce(1), 1, accuracy: 1e-12)
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
