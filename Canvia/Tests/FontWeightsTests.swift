// The Weight row, Light to Black: the weights it offers the texts selected,
// the one it shows chosen and the name it says, as the Android twin's
// TextSelectionTest has them; and a tap, which sets every unlocked text — a
// shape's words among them — to that weight in one step, each measured again.

import XCTest
@testable import Canvia

@MainActor
final class FontWeightsTests: XCTestCase {

    private func text(_ words: String, font: String, weight: Int) -> Element {
        var el = Element.text(words, fontSize: 18)
        el.fontFamily = font
        el.fontWeight = weight
        return el
    }

    /// The rows of the Android twin's TextSelectionTest.
    func testTheRowOffersTheWeightsTheFontsHaveAndNamesTheOneDrawn() {
        let lora = text("Lora", font: "lora", weight: 400)
        let roboto = text("Roboto", font: "roboto", weight: 650)
        let oswald = text("Oswald", font: "condensed", weight: 500)
        let own = text("Own", font: "custom:0123456789ab", weight: 400)
        let body = text("Body", font: "sans", weight: 400)
        let heading = text("Heading", font: "sans", weight: 700)
        XCTAssertEqual(TypeReadouts.weights([lora]), [400, 700])
        XCTAssertEqual(TypeReadouts.weights([lora, roboto]), [300, 400, 500, 600, 700, 800, 900])
        XCTAssertEqual(TypeReadouts.weights([oswald, lora]), [300, 400, 500, 600, 700])
        XCTAssertEqual(TypeReadouts.weights([body]), [300, 400, 500, 700])
        // A font of your own is one face: it adds no weights, and alone has no row.
        XCTAssertEqual(TypeReadouts.weights([own]), [])
        XCTAssertEqual(TypeReadouts.weights([own, lora]), [400, 700])
        // The readout names the weight drawn: 650 in Roboto is its Bold.
        XCTAssertEqual(TypeReadouts.weightReadout([lora]), "Regular")
        XCTAssertEqual(TypeReadouts.weightReadout([roboto]), "Bold")
        XCTAssertEqual(TypeReadouts.weightReadout([oswald]), "Medium")
        XCTAssertEqual(TypeReadouts.weightReadout([heading]), "Bold")
        XCTAssertEqual(TypeReadouts.weightReadout([lora, roboto]), "Mixed")
        XCTAssertEqual(TypeReadouts.weightReadout([lora, own]), "Regular")
        // 550 in Lora and 700 in Roboto are both drawn Bold.
        var lora550 = lora, roboto700 = roboto
        lora550.fontWeight = 550
        roboto700.fontWeight = 700
        XCTAssertEqual(TypeReadouts.drawnWeight([lora550, roboto700]), 700)
        XCTAssertNil(TypeReadouts.drawnWeight([own]))
    }

    private func store(_ elements: [Element]) -> DesignStore {
        var design = Design(title: "weights", width: 1000, height: 1000)
        design.pages[0].elements = elements
        return DesignStore(design: design)
    }

    func testATapSetsEveryUnlockedTextToTheWeightInOneStepEachMeasuredAgain() {
        var light = text("A long line of words that wraps", font: "montserrat", weight: 300)
        light.w = 220
        light.h = FontLibrary.layoutHeight(for: light)
        var plain = text("Plain", font: "lora", weight: 400)
        plain.h = FontLibrary.layoutHeight(for: plain)
        var locked = text("Locked", font: "lora", weight: 400)
        locked.locked = true
        let s = store([light, plain, locked])
        s.selection = [light.id, plain.id, locked.id]
        XCTAssertEqual(TypeReadouts.weights(s.textsRead), [300, 400, 500, 600, 700, 800, 900], "the unlocked ones")
        XCTAssertEqual(TypeReadouts.weightReadout(s.textsRead), "Mixed")
        s.setFontWeight(900)
        XCTAssertEqual(s.element(light.id)?.fontWeight, 900)
        XCTAssertEqual(s.element(plain.id)?.fontWeight, 900)
        XCTAssertEqual(s.element(locked.id)?.fontWeight, 400, "locked")
        for id in [light.id, plain.id] {
            let el = s.element(id)
            XCTAssertEqual(el?.h, el.map { FontLibrary.layoutHeight(for: $0) })
        }
        // Montserrat's Black is its own; Lora's 900 is drawn at its Bold.
        XCTAssertEqual(TypeReadouts.weightReadout(s.textsRead), "Mixed")
        XCTAssertEqual(TypeReadouts.drawnWeight([s.element(plain.id)!]), 700)
        s.undo()
        XCTAssertEqual(s.element(light.id)?.fontWeight, 300)
        XCTAssertEqual(s.element(plain.id)?.fontWeight, 400)
        XCTAssertFalse(s.canUndo, "one step for all of them")
    }

    func testBoldKeepsItsOwnRuleBesideTheRow() {
        var medium = text("Medium", font: "poppins", weight: 500)
        medium.h = FontLibrary.layoutHeight(for: medium)
        let s = store([medium])
        s.selection = [medium.id]
        XCTAssertFalse(TextToggle.bold.isOn(medium))
        s.toggleText(.bold)
        XCTAssertEqual(s.element(medium.id)?.fontWeight, 700)
        s.setFontWeight(800)
        XCTAssertTrue(TextToggle.bold.isOn(s.element(medium.id)!), "on from 700")
        s.toggleText(.bold)
        XCTAssertEqual(s.element(medium.id)?.fontWeight, 400, "off is regular")
    }

    func testAShapesWordsTakeTheWeightToo() {
        var shape = Element.shape("rect", w: 300, h: 120)
        shape.text = "Sale"
        shape.fontFamily = "roboto"
        shape.fontWeight = 400
        let s = store([shape])
        s.selection = [shape.id]
        XCTAssertEqual(TypeReadouts.weights(s.textsRead), [300, 400, 500, 600, 700, 800, 900])
        s.setFontWeight(300)
        XCTAssertEqual(s.element(shape.id)?.fontWeight, 300)
        XCTAssertEqual(TypeReadouts.weightReadout(s.textsRead), "Light")
    }

    func testTextsOnlyInFontsOfYourOwnHaveNoRow() {
        let own = text("Own", font: "custom:0123456789ab", weight: 400)
        let s = store([own])
        s.selection = [own.id]
        XCTAssertEqual(TypeReadouts.weights(s.textsRead), [])
    }
}
