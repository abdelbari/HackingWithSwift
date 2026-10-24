// The letters each font has: "scripts" in Fonts.json, worked out from each
// family's regular face, and the rule that says whether a font has a box's
// letters — the rows the Android twin's FontLibraryTest runs too.

import XCTest
@testable import Canvia

final class FontScriptsTests: XCTestCase {

    private func regular(_ font: FontDef) throws -> Data {
        try Data(contentsOf: try XCTUnwrap(FontLibrary.bundledURL(try XCTUnwrap(font.files["400"]))))
    }

    /// Shared: every family has latin, and a bundled family's scripts are
    /// what its regular face's cmap covers, by the rule a font of your own
    /// gets them by.
    func testEveryFamilyCoversLatinAndItsScriptsAreItsCmaps() throws {
        for font in FontLibrary.all {
            XCTAssertTrue(font.scripts.contains("latin"), font.id)
            XCTAssertEqual(FontLibrary.scriptKeys.filter { font.scripts.contains($0) }, font.scripts, font.id)
            if !font.system { XCTAssertEqual(CustomFonts.scripts(try regular(font)), font.scripts, font.id) }
        }
        XCTAssertEqual(FontLibrary.of("roboto").scripts, ["latin", "latin-ext", "vietnamese", "cyrillic", "greek"])
        XCTAssertEqual(FontLibrary.of("lato").scripts, ["latin"])
        XCTAssertEqual(FontLibrary.of("lora").scripts, ["latin", "latin-ext", "vietnamese", "cyrillic"])
    }

    /// Shared: covers(family, "Привет") matches the cmap of each family's
    /// regular face.
    func testCoversMatchesTheCmap() throws {
        let privet = "Привет"
        for font in FontLibrary.all where !font.system {
            let has = CustomFonts.codePoints(try regular(font))
            XCTAssertEqual(FontLibrary.covers(font.id, privet), privet.unicodeScalars.allSatisfy { has.contains($0.value) },
                           font.id)
        }
        XCTAssertTrue(FontLibrary.covers("lora", privet))
        XCTAssertFalse(FontLibrary.covers("lato", privet))
        XCTAssertFalse(FontLibrary.covers("abril-fatface", "Γεια"))
        XCTAssertTrue(FontLibrary.covers("roboto", "Γεια"))
        // A toned Latin-1 vowel is Latin too; a letter only Vietnamese has is not.
        XCTAssertTrue(FontLibrary.covers("lato", "Xin chào"))
        XCTAssertFalse(FontLibrary.covers("lato", "Việt Nam"))
        XCTAssertTrue(FontLibrary.covers("lato", "café 123 !"))
        // Letters of no script here, and fonts of unknown scripts, never count.
        XCTAssertTrue(FontLibrary.covers("lato", "日本語"))
        XCTAssertTrue(FontLibrary.covers("custom:0123456789ab", privet))
    }

    /// Shared: the scripts a box's letters need.
    func testTheScriptsABoxsLettersNeed() {
        XCTAssertTrue(FontLibrary.scriptsNeeded("Xin chào").contains("vietnamese"))
        XCTAssertEqual(FontLibrary.scriptsNeeded("Xin chào"), ["latin", "vietnamese"])
        XCTAssertEqual(FontLibrary.scriptsNeeded("Big sale 50%"), ["latin"])
        XCTAssertEqual(FontLibrary.scriptsNeeded("Привет"), ["cyrillic"])
        XCTAssertEqual(FontLibrary.scriptsNeeded("Γεια"), ["greek"])
        XCTAssertEqual(FontLibrary.scriptsNeeded("Łęk"), ["latin", "latin-ext"])
        XCTAssertEqual(FontLibrary.scriptsNeeded("ệ"), ["vietnamese"])
        XCTAssertEqual(FontLibrary.scriptsNeeded("日本 123"), [])
        XCTAssertTrue(FontLibrary.needsMoreThanLatin("Привет"))
        XCTAssertFalse(FontLibrary.needsMoreThanLatin("Big sale"))
    }

    /// A font of your own says the letters it has when it is described.
    func testAFontOfYourOwnIsDescribedWithItsScripts() throws {
        let lora = try regular(FontLibrary.of("lora"))
        XCTAssertEqual(CustomFonts.describe(lora)?.scripts, FontLibrary.of("lora").scripts)
    }

    /// Check accessibility says when a box's font lacks some of its letters.
    func testCheckAccessibilitySaysWhenAFontLacksLetters() {
        var design = Design(title: "letters", width: 800, height: 600)
        var lato = Element.text("Привет", fontSize: 40, w: 400)
        lato.fontFamily = "lato"
        var lora = Element.text("Привет", fontSize: 40, w: 400)
        lora.fontFamily = "lora"
        lora.y = 200
        design.pages[0].elements = [lato, lora]
        let found = AccessibilityAudit.findings(design).filter { $0.kind == .missingLetters }
        XCTAssertEqual(found.map(\.elementId), [lato.id])
        XCTAssertEqual(found.first?.message, "Letters missing from the font")
        // Shared: words set in a font of their own are checked in it.
        var fixed = lato
        fixed.setSpans([TextSpan(start: 0, end: 6, font: "lora")])
        XCTAssertFalse(AccessibilityAudit.lacksLetters(fixed))
        var broken = lora
        broken.setSpans([TextSpan(start: 0, end: 3, font: "lato")])
        XCTAssertTrue(AccessibilityAudit.lacksLetters(broken))
    }
}
