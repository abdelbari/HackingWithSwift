// The emoji catalogue, row for row with the Android twin's
// EmojiCatalogueTest: eight groups from the shared emoji.json, fully
// qualified glyphs and flags, skin tones on and off, the search, and
// Recently used as the phone keeps it.

import XCTest
@testable import Canvia

final class EmojiCatalogueTests: XCTestCase {

    func testEightGroupsSomeSixteenHundredEmojiEachGlyphOnce() {
        XCTAssertEqual(EmojiCatalogue.groups.map(\.name), [
            "Smileys & People", "Animals & Nature", "Food", "Activities", "Travel", "Objects", "Symbols", "Flags",
        ])
        XCTAssertEqual(EmojiCatalogue.all.count, 1619)
        XCTAssertEqual(Set(EmojiCatalogue.all.map(\.g)).count, EmojiCatalogue.all.count)
        XCTAssertEqual(EmojiCatalogue.groups.last?.emoji.count, 263)
        for e in EmojiCatalogue.all {
            XCTAssertTrue(!e.name.isEmpty && !e.keywords.isEmpty, e.g)
            XCTAssertFalse(e.g.unicodeScalars.contains { $0.value == 0x200D }, e.g)
        }
    }

    func testGlyphsAreFullyQualifiedFlagsAreRegionalPairs() {
        XCTAssertEqual(EmojiCatalogue.of("😀")?.name, "Grinning face")
        // Drawn as text unless asked: listed with U+FE0F.
        XCTAssertEqual(EmojiCatalogue.of("\u{2600}\u{FE0F}")?.g, "\u{2600}\u{FE0F}")
        XCTAssertEqual(EmojiCatalogue.of("\u{2600}")?.name, "Black sun with rays")
        let france = EmojiCatalogue.of("🇫🇷")
        XCTAssertEqual(france?.name, "Flag: France")
        XCTAssertEqual(france?.keywords, ["flag", "france", "fr"])
        XCTAssertEqual(EmojiCatalogue.groupOf("🇫🇷"), "Flags")
        XCTAssertEqual(EmojiCatalogue.groupOf("🍕"), "Food")
        XCTAssertNil(EmojiCatalogue.of("x"))
    }

    func testSkinTonesGoOnTheOnesThatTakeThemAndComeOff() {
        XCTAssertEqual(EmojiCatalogue.of("👍")?.tone, true)
        XCTAssertEqual(EmojiCatalogue.of("😀")?.tone, false)
        XCTAssertEqual(EmojiCatalogue.tones.count, 5)
        XCTAssertEqual(EmojiCatalogue.toned("👍", EmojiCatalogue.tones[2]), "👍🏽")
        XCTAssertEqual(EmojiCatalogue.toned("👍🏽", nil), "👍")
        XCTAssertEqual(EmojiCatalogue.toned("👍🏽", EmojiCatalogue.tones[4]), "👍🏿")
        // One drawn as text loses its U+FE0F when a tone follows it.
        XCTAssertEqual(EmojiCatalogue.toned("\u{261D}\u{FE0F}", EmojiCatalogue.tones[0]), "\u{261D}\u{1F3FB}")
        XCTAssertEqual(EmojiCatalogue.toned("😀", EmojiCatalogue.tones[0]), "😀")
        XCTAssertEqual(EmojiCatalogue.untoned("👍🏾"), "👍")
        XCTAssertEqual(EmojiCatalogue.of("👍🏾")?.name, "Thumbs up sign")
    }

    func testASearchReadsNamesKeywordsAndTheStickersOwnWords() throws {
        XCTAssertEqual(EmojiCatalogue.search("party").map(\.g), ["🥳", "🎂", "🎈", "🎉", "🎊"])
        XCTAssertEqual(EmojiCatalogue.search("thumbs").map(\.g), ["👍", "👎"])
        // A word that starts a keyword before one inside a word.
        let sun = EmojiCatalogue.search("sun").map(\.g)
        let sunny = try XCTUnwrap(sun.firstIndex(of: "\u{2600}\u{FE0F}"))
        let flower = try XCTUnwrap(sun.firstIndex(of: "🌻"))
        XCTAssertLessThan(sunny, flower)
        XCTAssertEqual(EmojiCatalogue.search("France").map(\.g), ["🇫🇷"])
        XCTAssertTrue(EmojiCatalogue.search("party", in: "Flags").isEmpty)
        XCTAssertEqual(EmojiCatalogue.search("", in: "Food"), EmojiCatalogue.groups[2].emoji)
    }

    func testRecentlyUsedKeepsTwentyFourNewestFirstAsKeptOnThePhone() {
        var recent: [String] = []
        for e in EmojiCatalogue.all.prefix(30) { recent = EmojiCatalogue.remembered(recent, e.g) }
        XCTAssertEqual(recent.count, 24)
        XCTAssertEqual(recent.first, EmojiCatalogue.all[29].g)
        recent = EmojiCatalogue.remembered(recent, recent[5])
        XCTAssertEqual(recent.count, 24)
        XCTAssertEqual(recent.first, EmojiCatalogue.all[24].g)
        XCTAssertEqual(EmojiCatalogue.decode(EmojiCatalogue.encode(recent)), recent)
        XCTAssertEqual(EmojiCatalogue.decode("👍🏽\n\n🎉\n👍🏽"), ["👍🏽", "🎉"])
        XCTAssertEqual(EmojiCatalogue.decode(nil), [])
        XCTAssertEqual(EmojiCatalogue.recentKey, "recentEmoji")

        let defaults = UserDefaults(suiteName: "EmojiCatalogueTests")!
        defaults.removePersistentDomain(forName: "EmojiCatalogueTests")
        EmojiCatalogue.remember("🎉", in: defaults)
        EmojiCatalogue.remember("👍🏽", in: defaults)
        XCTAssertEqual(EmojiCatalogue.recent(in: defaults), ["👍🏽", "🎉"])
        XCTAssertNil(EmojiCatalogue.lastTone(in: defaults))
        EmojiCatalogue.keepTone(EmojiCatalogue.tones[3], in: defaults)
        XCTAssertEqual(EmojiCatalogue.lastTone(in: defaults), EmojiCatalogue.tones[3])
        EmojiCatalogue.keepTone(nil, in: defaults)
        XCTAssertNil(EmojiCatalogue.lastTone(in: defaults))
    }
}
