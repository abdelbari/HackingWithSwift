// Styling several text boxes at once, and a type size typed exactly: every
// selected, unlocked text changes in one step and is measured again, the
// controls read "Mixed" where the texts differ, and a typed size is whole
// points from 6 to 500 — as on the Android twin.

import XCTest
@testable import Canvia

@MainActor
final class SeveralTextsTests: XCTestCase {

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "several", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    // MARK: what counts as several texts

    func testSeveralTextsOrAGroupOfThemGetTheTextControls() {
        let a = Element.text("One"), b = Element.text("Two"), shape = Element.shape("rect")
        var c = Element.text("Three"), d = Element.text("Four")
        c.group = "g"; d.group = "g"
        let s = store([a, b, shape, c, d])
        s.selection = [a.id, b.id]
        XCTAssertEqual(s.textSelection?.count, 2)
        s.selection = [a.id, shape.id]
        XCTAssertNil(s.textSelection, "a shape among them has its own controls")
        s.selection = [a.id]
        XCTAssertNil(s.textSelection, "one box has its own controls")
        s.select(c.id)
        XCTAssertEqual(s.textSelection?.count, 2, "a group of nothing but text")
    }

    // MARK: switches

    func testASwitchTurnsOnForAllUnlessEveryOneHasIt() {
        var a = Element.text("One"), b = Element.text("Two")
        a.italic = true
        let s = store([a, b])
        s.selection = [a.id, b.id]
        XCTAssertNil(s.sharedText { TextToggle.italic.isOn($0) }, "mixed")
        s.toggleText(.italic)
        XCTAssertEqual(s.element(a.id)?.italic, true)
        XCTAssertEqual(s.element(b.id)?.italic, true)
        XCTAssertEqual(s.sharedText { TextToggle.italic.isOn($0) }, true)
        s.toggleText(.italic)
        XCTAssertEqual(s.element(a.id)?.italic, false)
        XCTAssertEqual(s.element(b.id)?.italic, false)
        s.undo()
        XCTAssertEqual(s.element(b.id)?.italic, true, "each change is one step for all of them")
        s.undo()
        XCTAssertEqual(s.element(a.id)?.italic, true)
        XCTAssertNil(s.element(b.id)?.italic)
        XCTAssertFalse(s.canUndo)
    }

    func testBoldKeepsAHeavierWeightAndLockedTextIsLeftAlone() {
        var heavy = Element.text("Heavy"), plain = Element.text("Plain"), locked = Element.text("Locked")
        heavy.fontWeight = 900
        locked.locked = true
        let s = store([heavy, plain, locked])
        s.selection = [heavy.id, plain.id, locked.id]
        s.toggleText(.bold)
        XCTAssertEqual(s.element(heavy.id)?.fontWeight, 900, "already bold, and heavier")
        XCTAssertEqual(s.element(plain.id)?.fontWeight, 700)
        XCTAssertEqual(s.element(locked.id)?.fontWeight, 400, "locked")
        s.toggleText(.bold)
        XCTAssertEqual(s.element(heavy.id)?.fontWeight, 400)
        XCTAssertEqual(s.element(plain.id)?.fontWeight, 400)
    }

    func testEachBoxIsMeasuredAgain() {
        var a = Element.text("oooo oooo", fontSize: 40, w: 220)
        var b = Element.text("oooo", fontSize: 40, w: 220)
        a.h = FontLibrary.layoutHeight(for: a)
        b.h = FontLibrary.layoutHeight(for: b)
        let s = store([a, b])
        s.selection = [a.id, b.id]
        s.toggleText(.uppercase)
        for id in [a.id, b.id] {
            let el = s.element(id)
            XCTAssertEqual(el?.uppercase, true)
            XCTAssertEqual(el?.h, el.map { FontLibrary.layoutHeight(for: $0) })
        }
        XCTAssertGreaterThan(s.element(a.id)?.h ?? 0, a.h, "the longer one wraps in capitals")
    }

    // MARK: shared readouts

    func testReadoutsShowTheSharedValueOrMixed() {
        let a = Element.text("One", fontSize: 24)
        var b = Element.text("Two", fontSize: 24)
        b.fontFamily = "serif"
        let s = store([a, b])
        s.selection = [a.id, b.id]
        let size = s.sharedText { $0.fontSize ?? 42 }
        XCTAssertEqual(size, 24)
        XCTAssertEqual(TypeReadouts.fontSize(size), "24")
        XCTAssertNil(s.sharedText { $0.fontFamily ?? "sans" })
        XCTAssertEqual(TypeReadouts.fontSize(nil), "Mixed")
        XCTAssertEqual(TypeReadouts.shared(["left", "left"]), "left")
        XCTAssertNil(TypeReadouts.shared(["left", "center"]))
        XCTAssertNil(TypeReadouts.shared([String]()))
    }

    /// A size made fractional by a corner drag reads as its nearest whole
    /// point, as on the Android twin; one a hair from another is still not
    /// the same size.
    func testAFractionalSizeReadsRounded() {
        XCTAssertEqual(TypeReadouts.fontSize(47.6), "48")
        XCTAssertEqual(TypeReadouts.fontSize(47.4), "47")
        let a = Element.text("One", fontSize: 47.6), b = Element.text("Two", fontSize: 48)
        let s = store([a, b])
        s.selection = [a.id, b.id]
        XCTAssertNil(s.sharedText { $0.fontSize ?? 42 })
    }

    /// The readouts are the texts a change will reach: a locked box is left
    /// out, unless every one is locked, as on the Android twin.
    func testReadoutsLeaveOutALockedBox() {
        var title = Element.text("Title", fontSize: 24), caption = Element.text("Caption", fontSize: 36)
        title.fontWeight = 700
        title.locked = true
        let s = store([title, caption])
        s.selection = [title.id, caption.id]
        XCTAssertEqual(s.sharedText { $0.fontSize ?? 42 }, 36)
        XCTAssertEqual(s.sharedText { TextToggle.bold.isOn($0) }, false)

        var lockedCaption = caption
        lockedCaption.locked = true
        let all = store([title, lockedCaption])
        all.selection = [title.id, lockedCaption.id]
        XCTAssertNil(all.sharedText { $0.fontSize ?? 42 }, "every one locked, all of them are read")
    }

    func testAlignmentGoesRound() {
        XCTAssertEqual(TypeReadouts.nextAlignment(after: "left"), "center")
        XCTAssertEqual(TypeReadouts.nextAlignment(after: "center"), "right")
        XCTAssertEqual(TypeReadouts.nextAlignment(after: nil), "right", "nil is centred")
        XCTAssertEqual(TypeReadouts.nextAlignment(after: "right"), "justify")
        XCTAssertEqual(TypeReadouts.nextAlignment(after: "justify"), "left")
    }

    // MARK: a size typed exactly

    func testATypedSizeIsWholePointsInRange() {
        XCTAssertEqual(TypeReadouts.typedSize("24"), 24)
        XCTAssertEqual(TypeReadouts.typedSize(" 36 "), 36)
        XCTAssertEqual(TypeReadouts.typedSize("12.5"), 13)
        XCTAssertEqual(TypeReadouts.typedSize("12,4"), 12)
        XCTAssertEqual(TypeReadouts.typedSize("3"), 6)
        XCTAssertEqual(TypeReadouts.typedSize("9000"), 500)
        XCTAssertNil(TypeReadouts.typedSize(""))
        XCTAssertNil(TypeReadouts.typedSize("big"))
        XCTAssertNil(TypeReadouts.typedSize("inf"))
    }

    func testThePresetsAreTheListedSizes() {
        XCTAssertEqual(TypeReadouts.presetSizes,
                       [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56, 64, 72, 80, 96, 120, 144, 200])
        XCTAssertTrue(TypeReadouts.presetSizes.allSatisfy { TypeReadouts.sizeRange.contains($0) })
    }

    func testSettingASizeIsOneStepForEveryTextFittedAgain() {
        let a = Element.text("A line long enough to wrap", fontSize: 20, w: 300)
        let b = Element.text("Short", fontSize: 40, w: 300)
        let s = store([a, b])
        s.selection = [a.id, b.id]
        s.setFontSize(72.4)
        for id in [a.id, b.id] {
            let el = s.element(id)
            XCTAssertEqual(el?.fontSize, 72)
            XCTAssertEqual(el?.h, el.map { FontLibrary.layoutHeight(for: $0) })
        }
        s.undo()
        XCTAssertEqual(s.element(a.id)?.fontSize, 20)
        XCTAssertEqual(s.element(b.id)?.fontSize, 40)
        XCTAssertFalse(s.canUndo)

        s.selection = [b.id]
        s.setFontSize(2)
        XCTAssertEqual(s.element(b.id)?.fontSize, 6)
        s.setFontSize(900)
        XCTAssertEqual(s.element(b.id)?.fontSize, 500)
    }
}
