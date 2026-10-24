// Colour emoji among outlined letters: which characters are emoji
// (Emoji.isEmojiCluster, over the shared Fixtures/emoji_clusters.json),
// the pictures the outliner keeps for them round a curve, and the <image>
// an SVG writes for each — the Android twin's EmojiClustersTest, row for
// row.

import XCTest
@testable import Canvia

final class EmojiOutlinesTests: XCTestCase {

    /// Shared rows: each cluster an emoji or not, on both phones.
    func testTheSharedClustersAreEmojiWhereTheFixtureSays() throws {
        let fixture = try SharedFixture.object("emoji_clusters")
        let rows = try XCTUnwrap(fixture["clusters"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(rows.count, 15)
        for row in rows {
            let cluster = try XCTUnwrap(row["cluster"] as? String)
            let emoji = try XCTUnwrap(row["emoji"] as? Bool)
            XCTAssertEqual(Emoji.isEmojiCluster(cluster), emoji, row["why"] as? String ?? cluster)
        }
    }

    func testTheTableIsTheGenerators() {
        XCTAssertTrue(Emoji.isPictographic(0xA9))
        XCTAssertTrue(Emoji.isPictographic(0x1F44B))
        XCTAssertTrue(Emoji.isPictographic(0x1FFFD))
        XCTAssertFalse(Emoji.isPictographic(0x41))
        // Skin tones and regional indicators are no pictographs of their own.
        XCTAssertFalse(Emoji.isPictographic(0x1F3FB))
        XCTAssertFalse(Emoji.isPictographic(0x1F1E6))
        XCTAssertFalse(Emoji.isEmojiCluster(""))
    }

    /// Shared: "Hi 👋" is three pieces traced and one emoji.
    func testHiAndAWaveIsThreeOutlinePiecesAndOneEmoji() {
        let clusters = Emoji.clusters("Hi 👋")
        XCTAssertEqual(clusters.count, 4)
        XCTAssertEqual(clusters.filter { !$0.emoji }.count, 3)
        XCTAssertEqual(clusters.filter(\.emoji).map(\.range), [NSRange(location: 3, length: 2)])
    }

    private func curved(_ words: String) -> Element {
        var el = Element.text(words, fontSize: 40, w: 200)
        el.x = 10
        el.y = 5
        el.h = 100
        el.curve = 90
        return el
    }

    /// Round a curve the wave is kept as a picture, turned with the arc,
    /// beside the letters' outlines — not dropped.
    func testACurvedEmojiIsKeptAsAPicture() throws {
        let el = curved("Hi 👋")
        let pieces = TextOutliner.emojiPieces(for: el)
        XCTAssertEqual(pieces.map(\.cluster), ["👋"])
        let piece = try XCTUnwrap(pieces.first)
        XCTAssertGreaterThan(piece.rect.width, 0)
        XCTAssertGreaterThan(piece.angle, 0, "the last character leans with the arc")
        XCTAssertFalse(try XCTUnwrap(TextOutliner.inkedPaths(for: el)).whole.isEmpty)
        // Nothing but an emoji still draws.
        XCTAssertEqual(TextOutliner.emojiPieces(for: curved("👋")).count, 1)
        XCTAssertNotNil(TextOutliner.emojiImage(piece))
    }

    /// Shared: an SVG writes each emoji piece as one <image> of its PNG.
    @MainActor
    func testAnEmojiPieceIsAnImageInTheSVG() {
        var design = Design(title: "emoji", width: 300, height: 200)
        design.pages[0].elements = [curved("Hi 👋")]
        let svg = SVGExporter.svg(design: design, page: design.pages[0])
        XCTAssertEqual(svg.components(separatedBy: "<image ").count - 1, 1, svg)
        XCTAssertTrue(svg.contains("href=\"data:image/png;base64,"))
        XCTAssertTrue(svg.contains("<g transform=\"translate(10 5)\"><image x=\""))
    }
}
