// Stickers found by their own words, and the Animated row — the same rows
// as the Android twin's StickersTest.

import XCTest
@testable import Canvia

final class StickerWordsTests: XCTestCase {

    private var groups: [StickerGroup] { ContentLibrary.stickerGroups }

    func testEveryStickerHasWordsAndASearchFindsStickersByThem() throws {
        let glyphs = Set(groups.flatMap(\.emoji))
        XCTAssertEqual(glyphs, Set(Stickers.allWords.keys))
        XCTAssertTrue(Stickers.allWords.values.allSatisfy { words in !words.isEmpty && words.allSatisfy { $0 == $0.lowercased() } })
        XCTAssertEqual(Stickers.words(for: "🎉"), ["party", "celebrate", "popper", "confetti"])
        // "party" finds the stickers that are for one, in their groups.
        let party = Stickers.search("Party", in: groups)
        XCTAssertEqual(party.map(\.name), ["Celebration", "Smileys"])
        XCTAssertEqual(party[0].emoji, ["🎉", "🎊", "🎈", "🎂", "🥳"])
        XCTAssertEqual(party[1].emoji, ["🥳"])
        // "heart" across groups; a group's own name still finds it whole.
        XCTAssertEqual(Stickers.search("heart", in: groups).map(\.name), ["Celebration", "Symbols", "Smileys"])
        XCTAssertEqual(Stickers.search("heart", in: groups)[0].emoji, ["💝"])
        let marks = try XCTUnwrap(groups.first { $0.name == "Marks" })
        XCTAssertEqual(Stickers.search("marks", in: groups).map(\.emoji), [marks.emoji])
        XCTAssertEqual(Stickers.search("pizza", in: groups).flatMap(\.emoji), ["🍕"])
        XCTAssertEqual(Stickers.search("", in: groups).map(\.name), groups.map(\.name))
        XCTAssertTrue(Stickers.search("zebra", in: groups).isEmpty)
    }

    func testTheAnimatedRowIsTwentyFourStickersSixOfEachLoop() throws {
        XCTAssertEqual(Stickers.animated.count, 24)
        let counts = Dictionary(grouping: Stickers.animated, by: \.loop).mapValues(\.count)
        XCTAssertEqual(counts, ["wiggle": 6, "pulse": 6, "bounce": 6, "spin": 6])
        let glyphs = Set(groups.flatMap(\.emoji))
        XCTAssertTrue(Stickers.animated.allSatisfy { glyphs.contains($0.glyph) })
        XCTAssertEqual(Set(Stickers.animated.map(\.glyph)).count, 24)
        let first = try XCTUnwrap(Stickers.animated.first)
        XCTAssertEqual(first.name, "Party, wiggling")
        // An ordinary sticker with a loop animation, as both phones draw one.
        let el = first.element(size: 160)
        XCTAssertEqual(el.glyph, "🎉")
        XCTAssertEqual(el.w, 160)
        XCTAssertEqual(el.animation, ElementAnimation(kind: "wiggle", delay: 0, duration: 0.6))
        XCTAssertEqual(Stickers.searchAnimated("anim"), Stickers.animated)
        XCTAssertEqual(Stickers.searchAnimated("rocket").map(\.glyph), ["🚀"])
        XCTAssertEqual(Stickers.searchAnimated("spin").count, 6)
    }
}
