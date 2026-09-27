// A text box set in capitals: drawn, measured and exported as capitals, the
// words kept as typed, and the key optional in the file — as on the Android
// twin, which keeps "uppercase" in its extras.

import XCTest
import UIKit
@testable import Canvia

@MainActor
final class UppercaseTextTests: XCTestCase {

    private func capitals(_ text: String, fontSize: Double = 40, w: Double = 400) -> Element {
        var el = Element.text(text, fontSize: fontSize, w: w)
        el.uppercase = true
        return el
    }

    // MARK: the file

    func testTheKeyIsOptionalAndRoundTrips() throws {
        let old = try JSONDecoder().decode(Element.self, from: Data(#"{"type":"text","text":"Sale"}"#.utf8))
        XCTAssertNil(old.uppercase, "absent is as typed")
        let oldJSON = try XCTUnwrap(String(data: JSONEncoder().encode(old), encoding: .utf8))
        XCTAssertFalse(oldJSON.contains("uppercase"), "an old file is written back without it")

        let shouted = try JSONDecoder().decode(Element.self,
                                               from: Data(#"{"type":"text","text":"Sale","uppercase":true}"#.utf8))
        XCTAssertEqual(shouted.uppercase, true)
        XCTAssertEqual(shouted.text, "Sale", "the words stay as typed")
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(shouted))
        XCTAssertEqual(back.uppercase, true)
    }

    // MARK: drawing and measuring

    func testTheWordsAreDrawnInCapitalsAndKeptAsTyped() {
        let el = capitals("Summer sale")
        XCTAssertEqual(FontLibrary.displayText(for: el), "SUMMER SALE")
        XCTAssertEqual(FontLibrary.attributedString(for: el).string, "SUMMER SALE")
        XCTAssertEqual(el.text, "Summer sale")
        var off = el
        off.uppercase = nil
        XCTAssertEqual(FontLibrary.displayText(for: off), "Summer sale", "turning it off gives them back")
    }

    func testRunsKeepTheirWordsWhenALetterGrows() {
        let caps = RichText.inCapitals(RichText.parse("straße **tag**"))
        XCTAssertEqual(caps.plain, "STRASSE TAG")
        XCTAssertEqual(caps.runs.count, 1)
        XCTAssertEqual((caps.plain as NSString).substring(with: caps.runs[0].range), "TAG")
        XCTAssertTrue(caps.runs[0].style.bold)

        let grown = RichText.inCapitals(RichText.parse("**straße** tag"))
        XCTAssertEqual((grown.plain as NSString).substring(with: grown.runs[0].range), "STRASSE")
    }

    func testTheAttributedStringIsTheDisplayTextWithItsRunsInPlace() {
        let el = capitals("**straße** tag")
        let attributed = FontLibrary.attributedString(for: el)
        XCTAssertEqual(attributed.string, FontLibrary.displayText(for: el))
        XCTAssertEqual(attributed.string, "STRASSE TAG")
        let lastOfBold = attributed.attribute(.font, at: 6, effectiveRange: nil) as? UIFont
        let plain = attributed.attribute(.font, at: 8, effectiveRange: nil) as? UIFont
        XCTAssertTrue(lastOfBold?.fontDescriptor.symbolicTraits.contains(.traitBold) == true,
                      "the second S of the grown letter is still bold")
        XCTAssertFalse(plain?.fontDescriptor.symbolicTraits.contains(.traitBold) == true)
    }

    func testCapitalsAreMeasuredAsCapitals() {
        let lower = Element.text("oooo oooo", fontSize: 40, w: 220)
        let upper = capitals("oooo oooo", fontSize: 40, w: 220)
        // Measured lower case first, so a cache that forgot the capitals
        // would hand back its height.
        let lowerHeight = FontLibrary.measuredHeight(for: lower)
        XCTAssertGreaterThan(FontLibrary.lineWidth(for: upper), FontLibrary.lineWidth(for: lower))
        XCTAssertGreaterThan(FontLibrary.measuredHeight(for: upper), lowerHeight, "the capitals wrap")
    }

    func testOutlinesAreCapitalsStraightAndCurved() throws {
        let lower = Element.text("ooo", fontSize: 60)
        let upper = capitals("ooo", fontSize: 60)
        let flat = try XCTUnwrap(TextOutliner.path(for: lower)).boundingBoxOfPath
        let tall = try XCTUnwrap(TextOutliner.path(for: upper)).boundingBoxOfPath
        XCTAssertGreaterThan(tall.height, flat.height, "a capital O stands taller than an o")
        XCTAssertGreaterThan(tall.width, flat.width)

        var curvedLower = lower, curvedUpper = upper
        curvedLower.curve = 90; curvedUpper.curve = 90
        let bentLower = try XCTUnwrap(TextOutliner.path(for: curvedLower)).boundingBoxOfPath
        let bentUpper = try XCTUnwrap(TextOutliner.path(for: curvedUpper)).boundingBoxOfPath
        XCTAssertGreaterThan(bentUpper.width, bentLower.width)
    }

    // MARK: styles and the store

    func testCopiedAndSavedStylesCarryIt() {
        let source = capitals("Heading")
        let style = DesignStore.style(of: source)
        XCTAssertEqual(style.uppercase, true)
        var target = Element.text("caption")
        DesignStore.apply(style, to: &target)
        XCTAssertEqual(target.uppercase, true)
        XCTAssertEqual(FontLibrary.displayText(for: target), "CAPTION")
        XCTAssertEqual(TextStyles.textOnly(style).uppercase, true, "a saved text style keeps it")

        var shape = Element.shape("rect")
        DesignStore.apply(style, to: &shape)
        XCTAssertNil(shape.uppercase, "a shape takes no type")
    }

    func testTheSwitchIsOneStepAndTheBoxIsMeasuredAgain() {
        var text = Element.text("oooo oooo", fontSize: 40, w: 220)
        text.h = FontLibrary.layoutHeight(for: text)
        var design = Design(title: "caps", width: 1000, height: 1000)
        design.pages[0].elements = [text]
        let s = DesignStore(design: design)
        s.select(text.id)
        s.toggleText(.uppercase)
        XCTAssertEqual(s.element(text.id)?.uppercase, true)
        XCTAssertEqual(s.element(text.id)?.text, "oooo oooo")
        XCTAssertEqual(s.element(text.id)?.h, s.element(text.id).map { FontLibrary.layoutHeight(for: $0) })
        XCTAssertGreaterThan(s.element(text.id)?.h ?? 0, text.h)
        s.toggleText(.uppercase)
        XCTAssertNil(s.element(text.id)?.uppercase, "off leaves no key")
        s.undo()
        XCTAssertEqual(s.element(text.id)?.uppercase, true)
        s.undo()
        XCTAssertNil(s.element(text.id)?.uppercase)
        XCTAssertFalse(s.canUndo)
    }

    func testReadAloudSaysTheWordsAsTyped() {
        var design = Design(title: "read", width: 1000, height: 1000)
        design.pages[0].elements = [capitals("Summer sale")]
        XCTAssertEqual(ReadAloud.script(for: design.pages[0], in: design), "Summer sale.")
    }
}
