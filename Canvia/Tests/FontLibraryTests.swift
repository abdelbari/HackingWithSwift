// The font library, as the Android twin's FontLibraryTest has it: the
// bundled Fonts.json (the very file Android ships) read in the picker's
// order, every bundled file there, a TrueType font of the family it is
// listed under that loads and draws, the twelve personality keys as
// aliases, the nearest face, the weights from Light to Black each font has
// and the one a text is drawn at, search with accents aside, Recently used,
// In this design, and the picker's lists.

import XCTest
import UIKit
import CryptoKit
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
        XCTAssertEqual(FontLibrary.all.reduce(0) { $0 + $1.files.count }, 148)
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

    func testTheCatalogueIsTheSameBytesOnBothPhones() throws {
        // The Android twin's FontLibraryTest checks the same digest of its copy.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "Fonts", withExtension: "json"))
        let digest = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(digest, "cc119aa93a74e398f12885209e9a53407aed366840c157e576a0a062d0ebd6da")
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
        // The cuts from Light to Black are the families' own, by name.
        XCTAssertEqual(FontLibrary.of("roboto").postScript["900"], "Roboto-Black")
        XCTAssertEqual(FontLibrary.of("montserrat").postScript["300"], "Montserrat-Light")
        XCTAssertEqual(FontLibrary.of("didone").postScript["600"], "PlayfairDisplay-SemiBold")
        XCTAssertEqual(FontLibrary.of("slab").files["800"], "roboto-slab-800.ttf")
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
        // Twelve families have their cuts from Light to Black.
        let roboto = FontLibrary.of("roboto")
        XCTAssertEqual(face(roboto, 300), "roboto-300.ttf 300")
        XCTAssertEqual(face(roboto, 600), "roboto-600.ttf 600")
        XCTAssertEqual(face(roboto, 950), "roboto-900.ttf 900")
        XCTAssertEqual(face(roboto, 900, italic: true), "roboto-700i.ttf 700")
        // Anton has one face, already black; Oswald no italic; the system's none.
        XCTAssertEqual(face(FontLibrary.of("impact"), 900), "anton-400.ttf 400")
        XCTAssertNil(face(FontLibrary.of("condensed"), 400, italic: true))
        XCTAssertNil(face(FontLibrary.of("serif"), 400))
    }

    /// The rows of the Android twin's FontLibraryTest: the weights each font
    /// has.
    func testEachFontListsTheWeightsItHasTheSameOnBothPhones() {
        let all = [300, 400, 500, 600, 700, 800, 900]
        let expected: [String: [Int]] = [
            "sans": [300, 400, 500, 700],
            "serif": [400, 700],
            "mono": [400, 700],
            "roboto": all,
            "open-sans": [300, 400, 500, 600, 700, 800],
            "lato": [300, 400, 700, 900],
            "montserrat": all,
            "poppins": all,
            "raleway": all,
            "nunito": all,
            "dm-sans": all,
            "roboto-slab": all,
            "space-grotesk": [300, 400, 500, 600, 700],
            "oswald": [300, 400, 500, 600, 700],
            "playfair-display": [400, 500, 600, 700, 800, 900],
            "lora": [400, 700],
            "crimson-text": [400, 700],
            "dm-serif-display": [400],
            "anton": [400],
            // Aliases have their family's; unknown keys and fonts of your own Modern Sans's.
            "didone": [400, 500, 600, 700, 800, 900],
            "condensed": [300, 400, 500, 600, 700],
            "impact": [400],
            "comic": [300, 400, 500, 700],
            "custom:0123456789ab": [300, 400, 500, 700],
        ]
        for (key, weights) in expected { XCTAssertEqual(FontLibrary.weights(key), weights, key) }
        // Twelve families have more than regular and bold; every bundled
        // family's list is its upright files, and every weight has a name.
        XCTAssertEqual(FontLibrary.all.filter { f in !f.system && f.weights.contains { $0 != 400 && $0 != 700 } }.count, 12)
        for font in FontLibrary.all where !font.system {
            let upright = font.files.keys.filter { !$0.hasSuffix("i") }.compactMap { Int($0) }.sorted()
            XCTAssertEqual(font.weights, upright, font.id)
        }
        XCTAssertTrue(FontLibrary.all.allSatisfy { f in
            !f.weights.isEmpty && f.weights.allSatisfy { FontLibrary.weightNames[$0] != nil }
        })
    }

    func testTheWeightsAreNamedLightToBlack() {
        XCTAssertEqual([300, 400, 500, 600, 700, 800, 900].map(FontLibrary.weightName),
                       ["Light", "Regular", "Medium", "Semibold", "Bold", "Extra bold", "Black"])
        XCTAssertEqual(FontLibrary.weightName(450), "450")
    }

    /// The rows of the Android twin's FontLibraryTest: the weight each
    /// request is drawn and measured at.
    func testAWeightResolvesToTheNearestTheFontHasTiesToTheHeavier() {
        let rows: [(String, Int, Int)] = [
            ("lora", 400, 400),
            ("lora", 500, 400),
            ("lora", 550, 700),
            ("lora", 900, 700),
            ("lato", 500, 400),
            ("lato", 800, 900),
            ("lato", 200, 300),
            ("roboto", 650, 700),
            ("roboto", 350, 400),
            ("montserrat", 900, 900),
            ("didone", 300, 400),
            ("didone", 850, 900),
            ("condensed", 800, 700),
            ("grotesk", 600, 600),
            ("impact", 900, 400),
            ("sans", 600, 700),
            ("sans", 900, 700),
            ("sans", 200, 300),
            ("sans", 450, 500),
            ("serif", 500, 400),
            ("serif", 550, 700),
            ("mono", 300, 400),
            ("comic", 600, 700),
        ]
        for (key, requested, drawn) in rows {
            XCTAssertEqual(FontLibrary.resolveWeight(key, requested), drawn, "\(key) \(requested)")
        }
    }

    /// The system's own faces at the cut of each weight they list, by name:
    /// Modern Sans from Light to Bold, Classic Serif and Typewriter regular
    /// and bold — the weights resolveWeight picks, as the Android twin draws.
    func testTheSystemFacesDrawAtTheirOwnCuts() {
        func name(_ key: String, _ weight: Int) -> String {
            FontLibrary.uiFont(family: key, size: 40, weight: weight, italic: false).fontName
        }
        XCTAssertEqual(name("sans", 300), "HelveticaNeue-Light")
        XCTAssertEqual(name("sans", 400), "HelveticaNeue")
        XCTAssertEqual(name("sans", 500), "HelveticaNeue-Medium")
        XCTAssertEqual(name("sans", 600), "HelveticaNeue-Bold")
        XCTAssertEqual(name("sans", 900), "HelveticaNeue-Bold")
        XCTAssertEqual(name("comic", 200), "HelveticaNeue-Light")
        XCTAssertEqual(name("serif", 550), "Georgia-Bold")
        XCTAssertEqual(name("serif", 500), "Georgia")
        XCTAssertEqual(name("mono", 300), "Menlo-Regular")
        XCTAssertEqual(name("mono", 800), "Menlo-Bold")
        // Bundled families from Light to Black, each its own file.
        XCTAssertEqual(name("poppins", 800), "Poppins-ExtraBold")
        XCTAssertEqual(name("didone", 600), "PlayfairDisplay-SemiBold")
        XCTAssertEqual(name("lato", 800), "Lato-Black")
        XCTAssertEqual(name("roboto", 300), "Roboto-Light")
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

    /// Shared: a search matches the name, the category or a tag, in
    /// English or in the app's language; a font of your own by its name
    /// alone.
    func testSearchFindsStyleTagsAndCategoriesInEnglishAndTranslated() {
        XCTAssertEqual(FontLibrary.search("cursive").map(\.id), ["dancing-script", "pacifico", "sacramento", "satisfy"])
        XCTAssertEqual(FontLibrary.search("mono").map(\.id), ["mono", "roboto-mono", "space-mono", "jetbrains-mono", "ibm-plex-mono"])
        XCTAssertEqual(FontLibrary.search("condensed").map(\.id), ["oswald", "anton", "bebas-neue"])
        let handwritten = Set(FontLibrary.search("handwritten").map(\.id))
        XCTAssertTrue(handwritten.isSuperset(of: ["caveat", "indie-flower", "patrick-hand"]))
        XCTAssertEqual(FontLibrary.search("elegant", category: "Script").map(\.id), ["dancing-script", "sacramento"])
        // Every family is tagged from the shared list, and the chips offered are tags.
        XCTAssertTrue(FontLibrary.all.allSatisfy { !$0.tags.isEmpty && $0.tags.allSatisfy { FontLibrary.tags.contains($0) } })
        XCTAssertEqual(FontLibrary.tags.count, 15)
        XCTAssertTrue(FontLibrary.suggestedTags.allSatisfy { FontLibrary.tags.contains($0) })
        XCTAssertEqual(FontLibrary.suggestedTags, ["elegant", "retro", "handwritten", "rounded"])
        // In the app's language: the tag's word there finds it too.
        let italian: (String) -> String = { $0 == "cursive" ? "corsivo" : $0 == "Mono" ? "Monospazio" : $0 }
        let found = FontLibrary.all.filter { FontLibrary.matches($0, "Corsivo", translate: italian) }.map(\.id)
        XCTAssertEqual(found, ["dancing-script", "pacifico", "sacramento", "satisfy"])
        XCTAssertTrue(FontLibrary.matches(FontLibrary.of("space-mono"), "monospazio", translate: italian))
        XCTAssertEqual(FontLibrary.tagName("cursive"), tr("cursive"))
        // A font of your own is matched by its name alone.
        let own = [Uploads.FontEntry(id: "ab12cd34ef56", name: "Handwritten Mine", file: "ab12cd34ef56.ttf", added: 1)]
        XCTAssertTrue(FontChoices.found(query: "mine", category: "All", own: own).contains("custom:ab12cd34ef56"))
        XCTAssertEqual(FontLibrary.search("zzz"), [])
        XCTAssertEqual(FontChoices.tryTitle, "Try:")
    }

    /// Shared: the eight most popular, by rank.
    func testPopularIsTheTopEightByRank() {
        XCTAssertEqual(FontLibrary.popular.map(\.id),
                       ["montserrat", "poppins", "playfair-display", "roboto", "open-sans", "lato", "oswald", "dancing-script"])
        XCTAssertEqual(FontLibrary.of("montserrat").popular, 1)
        XCTAssertNil(FontLibrary.of("lora").popular)
        XCTAssertEqual(FontChoices.popularTitle, "Popular")
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
                       ["Brand fonts", "Recently used", "Popular", "In this design"])
        // A run with nothing in it is left out; Popular is always there.
        XCTAssertEqual(FontChoices.browsing(kit: BrandKit(), recent: [], design: design),
                       [FontChoices.Section(title: "Popular", keys: FontLibrary.popular.map(\.id)),
                        FontChoices.Section(title: "In this design", keys: ["caveat"])])

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
