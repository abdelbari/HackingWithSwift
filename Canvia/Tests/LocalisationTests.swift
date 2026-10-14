// The app in other languages, as the Android twin's catalogue tests have
// it: every entry of Tools/strings/strings.json in all seven languages,
// keeping the English placeholders in order, a plural entry with the CLDR
// forms each language needs, and no key empty; the built app holding every
// entry in every language; plural forms picked as each language counts;
// the English shown when an entry is missing; a word read in its context;
// numbers written as the language writes them; and a design drawn left to
// right under a right-to-left language, with Present's arrows going the
// way the language reads.
//
// strings.json is read from beside this file (#filePath), as the PptxReader
// fixtures are: the synchronized Tests folder bundles nothing from Tools,
// and the catalogue the app bundles is compiled, so the source is the
// simplest thing to check.

import XCTest
import SwiftUI
import UIKit
@testable import Canvia

final class LocalisationTests: XCTestCase {

    private static let languages = ["es", "fr", "de", "pt-BR", "it", "ja", "ar"]

    /// The CLDR plural forms each language's translation of a plural
    /// entry has.
    private static func forms(_ lang: String) -> [String] {
        switch lang {
        case "ar": return ["few", "many", "one", "other", "two", "zero"]
        case "ja": return ["other"]
        default: return ["one", "other"]
        }
    }

    private func catalogue(file: StaticString = #filePath) throws -> [String: Any] {
        let url = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
            .appendingPathComponent("../Tools/strings/strings.json").standardized
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try XCTUnwrap(json as? [String: Any])
    }

    /// The %@ and %d in `text`, in order; a %% is a percent sign.
    private func placeholders(_ text: String) -> [String] {
        let chars = Array(text)
        var out: [String] = []
        var i = 0
        while i < chars.count - 1 {
            guard chars[i] == "%" else { i += 1; continue }
            if chars[i + 1] == "@" || chars[i + 1] == "d" { out.append("%\(chars[i + 1])") }
            i += 2
        }
        return out
    }

    /// The app's own words in one language.
    private func bundle(_ lang: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: lang, ofType: "lproj"), "no \(lang).lproj")
        return try XCTUnwrap(Bundle(path: path))
    }

    /// The Info.plist sentences, which InfoPlist.xcstrings holds.
    private var usageDescriptions: [String: String] {
        (Bundle.main.infoDictionary ?? [:]).reduce(into: [:]) { out, pair in
            if pair.key.hasSuffix("UsageDescription"), let text = pair.value as? String { out[pair.key] = text }
        }
    }

    // MARK: the catalogue

    func testEveryEntryIsInEveryLanguageWithItsPlaceholders() throws {
        let entries = try catalogue()
        XCTAssertFalse(entries.isEmpty)
        for (key, value) in entries {
            XCTAssertFalse(key.trimmingCharacters(in: .whitespaces).isEmpty, "an empty key")
            let plural = key.contains("|")
            let english = Tr.forms(key)
            let wanted = placeholders(plural ? english.other : key)
            if plural {
                XCTAssertEqual(placeholders(english.one), wanted, "\(key): its one and other forms differ")
                // Here the count comes first; one that comes later is the
                // Android twin's alone, which generate.py leaves out.
                XCTAssertTrue(wanted.contains("%d"), "\(key): a plural entry has no count")
            }
            let translations = try XCTUnwrap(value as? [String: Any], key)
            XCTAssertEqual(Set(translations.keys), Set(Self.languages), key)
            for lang in Self.languages {
                let texts: [String]
                if plural {
                    let byForm = try XCTUnwrap(translations[lang] as? [String: String], "\(key): \(lang)")
                    XCTAssertEqual(byForm.keys.sorted(), Self.forms(lang), "\(key): \(lang)'s plural forms")
                    texts = Array(byForm.values)
                } else {
                    texts = try [XCTUnwrap(translations[lang] as? String, "\(key): \(lang)")]
                }
                for text in texts {
                    XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty, "\(key): \(lang) is empty")
                    XCTAssertEqual(placeholders(text), wanted, "\(key): \(lang) \(text)")
                }
            }
        }
    }

    /// The app as built has every entry, in every language: the catalogue
    /// files were made again after strings.json last changed.
    func testTheAppHoldsEveryEntryInEveryLanguage() throws {
        let entries = try catalogue()
        let plist = usageDescriptions
        for lang in Self.languages {
            let words = try bundle(lang)
            for (key, value) in entries where !key.contains("|") {
                let translations = try XCTUnwrap(value as? [String: Any])
                let wanted = try Tr.key(XCTUnwrap(translations[lang] as? String))
                if let name = plist.first(where: { $0.value == key })?.key {
                    XCTAssertEqual(words.localizedString(forKey: name, value: nil, table: "InfoPlist"), wanted,
                                   "\(lang): \(name)")
                } else {
                    XCTAssertEqual(words.localizedString(forKey: Tr.key(key), value: nil, table: nil), wanted,
                                   "\(lang): \(key)")
                }
            }
        }
    }

    // MARK: plurals

    /// The rows of the Android twin's PluralRules test, through the String
    /// Catalog: each count picks the form its language says.
    func testEachLanguageCountsAsItsPluralRulesSay() throws {
        let entries = try catalogue()
        guard let entry = entries.sorted(by: { $0.key < $1.key })
            .first(where: { $0.key.contains("|") && placeholders($0.key) == ["%d", "%d"] }) else {
            throw XCTSkip("strings.json has no plural entry yet")
        }
        let key = entry.key
        let translations = try XCTUnwrap(entry.value as? [String: Any])
        let rows: [(String, [Int], String)] = [
            ("ar", [0], "zero"), ("ar", [1], "one"), ("ar", [2], "two"), ("ar", Array(3...10), "few"),
            ("ar", [11, 50, 99], "many"), ("ar", [100], "other"),
            ("ja", [0, 1, 2, 5, 100], "other"),
            ("es", [1], "one"), ("es", [0, 2, 5], "other"),
            ("fr", [0, 1], "one"), ("fr", [2, 5], "other"),
            ("de", [1], "one"), ("de", [0, 2, 5], "other"),
            ("it", [1], "one"), ("it", [0, 2, 5], "other"),
            ("pt-BR", [1], "one"), ("pt-BR", [2, 5], "other"),
        ]
        for (lang, counts, form) in rows {
            let words = try bundle(lang)
            let locale = Locale(identifier: lang)
            let byForm = try XCTUnwrap(translations[lang] as? [String: String])
            let text = try XCTUnwrap(byForm[form], "\(key): \(lang) has no \(form)")
            for n in counts {
                XCTAssertEqual(Tr.plural(key, n, [], bundle: words, locale: locale),
                               String(format: Tr.key(text), locale: Tr.numbers(locale), n), "\(lang) \(n) is \(form)")
            }
        }
    }

    // MARK: the helpers

    func testTheKeysAreTheOnesSwiftUIMakes() {
        XCTAssertEqual(Tr.key("Page %d of %d"), "Page %lld of %lld")
        XCTAssertEqual(Tr.key("%@ and %d more"), "%@ and %lld more")
        XCTAssertEqual(Tr.key("100%"), "100%")
        XCTAssertEqual(Tr.key("%%d stays"), "%%d stays")
        XCTAssertEqual(Tr.pluralKey("%d page|%d pages"), "%lld pages")
        XCTAssertEqual(Tr.forms("%d page|%d pages").one, "%d page")
        XCTAssertEqual(Tr.key(Tr.inContext("Cut", "transition")), "Cut [transition]")
        XCTAssertEqual(Tr.english(Tr.inContext("Cut", "transition")), "Cut")
        XCTAssertEqual(Tr.english("Cut"), "Cut")
    }

    /// A word that means something else where it is shown has its own
    /// entry there; a place without one reads the word's plain entry, and
    /// English reads the word.
    func testAWordInContextIsSaidAsItIsThere() throws {
        let german = try bundle("de")
        let de = Locale(identifier: "de")
        XCTAssertEqual(Tr.text(Tr.inContext("Cut", "transition"), [], bundle: german, locale: de), "Schnitt")
        XCTAssertEqual(Tr.text("Cut", [], bundle: german, locale: de), "Ausschneiden")
        XCTAssertEqual(Tr.text(Tr.inContext("Light", "font weight"), [], bundle: german, locale: de), "Leicht")
        XCTAssertEqual(Tr.text(Tr.inContext("Light", "photo adjustments"), [], bundle: german, locale: de), "Licht")
        XCTAssertEqual(Tr.text(Tr.inContext("Fade", "transition"), [], bundle: german, locale: de),
                       Tr.text("Fade", [], bundle: german, locale: de))
        XCTAssertEqual(Tr.text(Tr.inContext("Nothing here", "zebra"), [], bundle: .main, locale: nil), "Nothing here")
    }

    /// Numbers in the app's words are written as the language writes them,
    /// as the Android twin's Copy.localNumber rows have it: grouped, in the
    /// language's digits; in English plain.
    func testNumbersAreWrittenAsTheLanguageWritesThem() {
        XCTAssertEqual(Tr.text("Nothing here is %d of %d", [3, 10], bundle: .main, locale: Locale(identifier: "ar")),
                       "Nothing here is \u{663} of \u{661}\u{660}")
        XCTAssertEqual(Tr.text("Nothing here is %d wide", [1080], bundle: .main, locale: Locale(identifier: "de")),
                       "Nothing here is 1.080 wide")
        XCTAssertEqual(Tr.text("Nothing here is %d wide", [1080], bundle: .main, locale: nil),
                       "Nothing here is 1080 wide")
    }

    /// Missing from the catalogue, the English shows, filled in; and in
    /// English a count is written as "\(n)" writes it, ungrouped.
    func testAMissingEntryShowsItsEnglish() {
        let english = Locale(identifier: "en")
        XCTAssertEqual(Tr.text("Nothing here is %@ number %d", ["text", 3], bundle: .main, locale: english),
                       "Nothing here is text number 3")
        XCTAssertEqual(Tr.text("A 100% literal", [], bundle: .main, locale: english), "A 100% literal")
        XCTAssertEqual(Tr.plural("%d zebra|%d zebras", 1, [], bundle: .main, locale: english), "1 zebra")
        XCTAssertEqual(Tr.plural("%d zebra|%d zebras", 4, [], bundle: .main, locale: english), "4 zebras")
        XCTAssertEqual(Tr.plural("%d zebra in %@|%d zebras in %@", 2, ["Kenya"], bundle: .main, locale: english),
                       "2 zebras in Kenya")
        XCTAssertEqual(Tr.plural("%d zebra|%d zebras", 1234, [], bundle: .main, locale: nil), "1234 zebras")
        XCTAssertEqual(Tr.text("%d zebras", [1234], bundle: .main, locale: nil), "1234 zebras")
    }

    /// Every language has a lproj in the app, and a name of its own.
    func testEveryLanguageIsBuiltAndNamedInItsOwnWords() throws {
        for lang in Self.languages {
            XCTAssertNotNil(Bundle.main.path(forResource: lang, ofType: "lproj"), lang)
            XCTAssertNotEqual(AppLanguage.name(lang), "English", lang)
        }
        XCTAssertEqual(AppLanguage.name("ar"), "العربية")
        XCTAssertEqual(AppLanguage.name("es"), "Español")
        XCTAssertEqual(AppLanguage.name("en"), "English")
    }

    // MARK: right to left

    /// A box at the page's left is drawn at its left under Arabic too.
    @MainActor
    func testADesignIsDrawnLeftToRightUnderARightToLeftLanguage() throws {
        var d = Design(title: "rtl", width: 200, height: 100)
        var box = Element.shape("rect", w: 50, h: 100)
        box.x = 0; box.y = 0
        box.fill = .solid("#000000")
        d.pages = [Page(background: .color("#ffffff"), elements: [box])]
        let renderer = ImageRenderer(content: PageRenderView(design: d, page: d.pages[0])
            .environment(\.layoutDirection, .rightToLeft))
        renderer.scale = 1
        renderer.isOpaque = true
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertLessThan(try red(image, x: 25, y: 50), 40, "the box left the page's left")
        XCTAssertGreaterThan(try red(image, x: 175, y: 50), 215, "the box went to the page's right")
        XCTAssertEqual(ReadingDirection.design, .leftToRight)
    }

    func testPresentsArrowsGoTheWayTheLanguageReads() {
        XCTAssertEqual(ReadingDirection.presentStep(.right, reading: .leftToRight), 1)
        XCTAssertEqual(ReadingDirection.presentStep(.left, reading: .leftToRight), -1)
        XCTAssertEqual(ReadingDirection.presentStep(.left, reading: .rightToLeft), 1)
        XCTAssertEqual(ReadingDirection.presentStep(.right, reading: .rightToLeft), -1)
    }

    private func red(_ image: CGImage, x: Int, y: Int) throws -> Int {
        var pixel: [UInt8] = [0, 0, 0, 0]
        try pixel.withUnsafeMutableBytes { raw in
            let ctx = try XCTUnwrap(CGContext(
                data: raw.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        }
        return Int(pixel[0])
    }
}
