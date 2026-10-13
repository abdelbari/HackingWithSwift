// The font library, as the Android twin's FontLibraryTest has it: the
// bundled Fonts.json (the very file Android ships) read in the picker's
// order, every bundled file there, a TrueType font of the family it is
// listed under that loads and draws, the twelve personality keys as
// aliases, the nearest face, search with accents aside, Recently used,
// In this design, and the picker's lists.

import XCTest
import UIKit
@testable import Canvia

final class FontLibraryTests: XCTestCase {

    func testTheCatalogueTheAndroidTwinReadsTooInThePickersOrder() {
        // Fonts.json is byte-identical on both phones; these are its ids.
        XCTAssertEqual(FontLibrary.all.map(\.id), [
            "sans", "roboto", "open-sans", "lato", "montserrat", "poppins", "raleway", "nunito", "space-grotesk", "dm-sans", "karla",
            "serif", "playfair-display", "crimson-text", "lora", "libre-baskerville", "pt-serif", "dm-serif-display", "roboto-slab",
            "oswald", "anton", "bebas-neue", "abril-fatface", "alfa-slab-one", "bungee", "righteous",
            "dancing-script", "pacifico", "sacramento", "satisfy",
            "caveat", "indie-flower", "shadows-into-light", "permanent-marker", "patrick-hand",
            "mono", "roboto-mono", "space-mono", "jetbrains-mono", "ibm-plex-mono",
        ])
        XCTAssertEqual(FontLibrary.all.count, 40)
        XCTAssertEqual(FontLibrary.all.reduce(0) { $0 + $1.files.count }, 97)
        XCTAssertEqual(FontLibrary.categories, ["Sans", "Serif", "Display", "Script", "Handwriting", "Mono"])
        XCTAssertEqual(FontLibrary.all.filter(\.system).map(\.id), ["sans", "serif", "mono"])
        XCTAssertEqual(FontLibrary.of("lora").name, "Lora")
        XCTAssertEqual(FontLibrary.of("caveat").category, "Handwriting")
        // Every family is in a category the chips show, and only open licences ship.
        XCTAssertTrue(FontLibrary.all.allSatisfy { FontLibrary.categories.contains($0.category) })
        XCTAssertTrue(FontLibrary.all.filter { !$0.system }.allSatisfy {
            ["OFL-1.1", "Apache-2.0"].contains($0.licence ?? "") && $0.files["400"] != nil
        })
    }

    func testEveryBundledFileIsThereATrueTypeFontOfItsFamilyThatLoads() throws {
        FontLibrary.registerBundledFonts()
        for font in FontLibrary.all {
            for (face, name) in font.files {
                let url = try XCTUnwrap(FontLibrary.bundledURL(name), "\(font.id) \(face): \(name) is not bundled")
                let data = try Data(contentsOf: url)
                guard case .success(let checked) = CustomFonts.check(data) else {
                    XCTFail("\(name) is not a font")
                    continue
                }
                XCTAssertEqual(checked.ext, "ttf", name)
                XCTAssertEqual(checked.name, font.name, name)
                XCTAssertEqual(name, "\(font.id)-\(face).ttf")
                XCTAssertTrue(FontStore.loads(data), "\(name) does not load")
                // Registered, and found by the PostScript name the catalogue gives.
                let postScript = try XCTUnwrap(font.postScript[face], name)
                XCTAssertEqual(UIFont(name: postScript, size: 20)?.fontName, postScript, name)
            }
        }
        // Nothing bundled that the catalogue does not list.
        let listed = Set(FontLibrary.all.flatMap { $0.files.values })
        let bundled = (Bundle.main.paths(forResourcesOfType: "ttf", inDirectory: nil)
            + Bundle.main.paths(forResourcesOfType: "ttf", inDirectory: "Fonts"))
            .map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(Set(bundled), listed)
    }

    func testTheTwelvePersonalityKeysAreAliasesOfTheFamiliesTheyWereDrawnWith() {
        let expected = [
            "sans": "sans", "serif": "serif", "mono": "mono",
            "grotesk": "space-grotesk", "didone": "playfair-display", "slab": "roboto-slab",
            "rounded": "nunito", "condensed": "oswald", "humanist": "open-sans",
            "script": "dancing-script", "elegant": "crimson-text", "impact": "anton",
        ]
        for (key, id) in expected { XCTAssertEqual(FontLibrary.of(key).id, id, key) }
        XCTAssertEqual(FontLibrary.resolve("didone"), "playfair-display")
        XCTAssertEqual(FontLibrary.resolve("lora"), "lora")
    }

    func testOldSpellingsAndUnknownKeysResolveToSomethingDrawable() {
        XCTAssertEqual(FontLibrary.of("monospace").id, "mono")
        XCTAssertEqual(FontLibrary.of("sans-serif").id, "sans")
        XCTAssertEqual(FontLibrary.of(nil).id, "sans")
        XCTAssertEqual(FontLibrary.of("comic").id, "sans")
        // A font of your own is drawn from its own file; its fallback is Modern Sans.
        XCTAssertEqual(FontLibrary.of("custom:0123456789ab").id, "sans")
        XCTAssertEqual(FontLibrary.resolve("custom:0123456789ab"), "custom:0123456789ab")
    }

    func testAFaceIsTheNearestWeightTiesToTheHeavierItalicOnlyWhenTheFamilyHasOne() {
        let lora = FontLibrary.of("lora")
        func face(_ font: FontDef, _ weight: Int, italic: Bool = false) -> String? {
            FontLibrary.face(font, weight: weight, italic: italic).map { "\($0.file) \($0.weight)" }
        }
        XCTAssertEqual(face(lora, 400), "lora-400.ttf 400")
        XCTAssertEqual(face(lora, 900), "lora-700.ttf 700")
        XCTAssertEqual(face(lora, 550), "lora-700.ttf 700")
        XCTAssertEqual(face(lora, 500), "lora-400.ttf 400")
        XCTAssertEqual(face(lora, 700, italic: true), "lora-700i.ttf 700")
        XCTAssertEqual(FontLibrary.face(lora, weight: 700, italic: true)?.postScript, "Lora-BoldItalic")
        // Anton has one face, already black; Oswald no italic; the system's none.
        XCTAssertEqual(face(FontLibrary.of("impact"), 900), "anton-400.ttf 400")
        XCTAssertNil(face(FontLibrary.of("condensed"), 400, italic: true))
        XCTAssertNil(face(FontLibrary.of("serif"), 400))
    }

    /// The canvas, measurement and export all ask FontLibrary for a face:
    /// a bundled family is its own file, at the face the catalogue picks.
    func testAFamilyDrawsInItsOwnFace() {
        func name(_ key: String?, _ weight: Int = 400, italic: Bool = false) -> String {
            FontLibrary.uiFont(family: key, size: 40, weight: weight, italic: italic).fontName
        }
        XCTAssertEqual(name("lora"), "Lora-Regular")
        XCTAssertEqual(name("lora", 900), "Lora-Bold")
        XCTAssertEqual(name("lora", italic: true), "Lora-Italic")
        XCTAssertEqual(name("didone", 700), "PlayfairDisplay-Bold")
        XCTAssertEqual(name("impact", 900), "Anton-Regular")
        // No italic of its own: the upright, slanted.
        XCTAssertEqual(name("condensed", italic: true), "Oswald-Regular")
        // The system's own, as they always were.
        XCTAssertEqual(FontLibrary.uiFont(family: "serif", size: 40, weight: 400, italic: false).familyName, "Georgia")
        XCTAssertEqual(name("comic"), name("sans"))
    }

    func testSearchFindsNamesWhateverTheirCaseAndAccents() {
        XCTAssertEqual(FontLibrary.search("LORA").map(\.id), ["lora"])
        XCTAssertEqual(FontLibrary.search("robo").map(\.id), ["roboto", "roboto-slab", "roboto-mono"])
        XCTAssertEqual(FontLibrary.search("robo", category: "Mono").map(\.id), ["roboto-mono"])
        XCTAssertEqual(FontLibrary.search("Pacífico").map(\.id), ["pacifico"])
        XCTAssertEqual(FontLibrary.search("  space ").map(\.id), ["space-grotesk", "space-mono"])
        XCTAssertTrue(FontLibrary.matches("Crème Brûlée", "creme bru"))
        XCTAssertFalse(FontLibrary.matches("Lora", "lorax"))
        XCTAssertEqual(FontLibrary.search(""), FontLibrary.all)
        XCTAssertEqual(FontLibrary.search("", category: "Handwriting").map(\.id),
                       ["caveat", "indie-flower", "shadows-into-light", "permanent-marker", "patrick-hand"])
        XCTAssertEqual(FontLibrary.search("zzz"), [])
    }

    func testRecentlyUsedIsNewestFirstEachOnceEightAtMost() {
        var recent: [String] = []
        for key in ["lora", "anton", "lora", "didone", "caveat", "mono", "roboto", "karla", "bungee", "pacifico", "lato"] {
            recent = FontLibrary.recent(recent, adding: key)
        }
        XCTAssertEqual(recent, ["lato", "pacifico", "bungee", "karla", "roboto", "mono", "caveat", "playfair-display"])
        // An alias and its family are one entry.
        XCTAssertEqual(FontLibrary.recent(["lato", "anton"], adding: "impact"), ["anton", "lato"])
        XCTAssertEqual(FontLibrary.recent(["lato"], adding: "custom:0123456789ab"), ["custom:0123456789ab", "lato"])

        // Kept per phone.
        let defaults = UserDefaults(suiteName: "fonts-\(UUID())")!
        RecentFonts.record("lora", defaults: defaults)
        RecentFonts.record("didone", defaults: defaults)
        RecentFonts.record("lora", defaults: defaults)
        XCTAssertEqual(RecentFonts.all(defaults), ["lora", "playfair-display"])
    }

    func testInThisDesignListsEachFontItsTextsUseOnceInPageOrder() {
        var design = Design(title: "Fonts")
        var a = Element.text("A"); a.fontFamily = "didone"
        var b = Element.text("B"); b.fontFamily = "lora"
        var c = Element.text("C"); c.fontFamily = "playfair-display"
        var d = Element.text("D"); d.fontFamily = "custom:0123456789ab"
        var shape = Element.shape("rect"); shape.fontFamily = nil
        design.pages = [Page(elements: [a, b, shape]), Page(elements: [c, d])]
        XCTAssertEqual(FontLibrary.usedIn(design), ["playfair-display", "lora", "custom:0123456789ab"])
    }

    // MARK: the picker's lists

    func testThePickerListsBrandFontsRecentAndThisDesignsThenFinds() {
        var kit = BrandKit()
        kit.fonts.heading = BrandFont(family: "didone", weight: 700)
        kit.fonts.body = BrandFont(family: "playfair-display")
        XCTAssertEqual(FontChoices.brandFonts(kit), ["playfair-display"])
        kit.fonts.body = BrandFont(family: "lora")
        XCTAssertEqual(FontChoices.brandFonts(kit), ["playfair-display", "lora"])
        // Role by role, title first.
        kit.fonts.title = BrandFont(family: "anton")
        XCTAssertEqual(FontChoices.brandFonts(kit), ["anton", "playfair-display", "lora"])
        kit.fonts.title = nil

        var design = Design(title: "Fonts")
        var a = Element.text("A"); a.fontFamily = "caveat"
        design.pages = [Page(elements: [a])]
        XCTAssertEqual(FontChoices.browsing(kit: kit, recent: ["anton"], design: design).map(\.title),
                       ["Brand fonts", "Recently used", "In this design"])
        // A run with nothing in it is left out.
        XCTAssertEqual(FontChoices.browsing(kit: BrandKit(), recent: [], design: design),
                       [FontChoices.Section(title: "In this design", keys: ["caveat"])])

        XCTAssertTrue(FontChoices.isBrowsing(query: "  ", category: "All"))
        XCTAssertFalse(FontChoices.isBrowsing(query: "", category: "Serif"))
        XCTAssertFalse(FontChoices.isBrowsing(query: "lo", category: "All"))
        // Your fonts are found under All only, after the library's.
        let own = [Uploads.FontEntry(id: "ab12cd34ef56", name: "Lobster Mine", file: "ab12cd34ef56.ttf", added: 1)]
        XCTAssertEqual(FontChoices.found(query: "lo", category: "All", own: own),
                       ["lora", "indie-flower", "custom:ab12cd34ef56"])
        XCTAssertEqual(FontChoices.found(query: "lo", category: "Serif", own: own), ["lora"])
        XCTAssertEqual(FontChoices.noneFound(" zzz "), "No fonts match \u{201C}zzz\u{201D}.")
    }
}
