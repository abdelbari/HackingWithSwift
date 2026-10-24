// Round 34's filters on Add's search: type, animated or static, and colour.
// The distance and filter rows are the shared fixture search-filters.json,
// read by the Android twin's ElementSearchTest too.

import XCTest
@testable import Canvia

final class SearchFiltersTests: XCTestCase {

    private func hit(_ key: String) throws -> ElementSearch.Hit {
        let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
        let kind = try XCTUnwrap(ElementSearch.HitKind(rawValue: parts[0]), key)
        return try XCTUnwrap(ElementSearch.hit(kind, parts[1]), key)
    }

    func testTheSharedHueDistanceRows() throws {
        let rows = try XCTUnwrap(SharedFixture.object("search-filters")["distance"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let a = try XCTUnwrap(row["a"] as? String), b = try XCTUnwrap(row["b"] as? String)
            let expected = try XCTUnwrap((row["deltaE"] as? NSNumber)?.doubleValue)
            XCTAssertEqual(ColourVision.deltaE(a, b), expected, accuracy: 0.01, "\(a) \(b)")
            XCTAssertEqual(ElementSearch.near(a, b), row["match"] as? Bool, "\(a) \(b)")
        }
        XCTAssertFalse(ElementSearch.near("none", "#ffffff"))
    }

    func testTheSharedFilterRows() throws {
        let fixture = try SharedFixture.object("search-filters")
        let hits = try XCTUnwrap(fixture["hits"] as? [String]).map(hit)
        let rows = try XCTUnwrap(fixture["filter"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            var filter = ElementSearch.Filter()
            if let kinds = row["kinds"] as? [String] {
                filter.kinds = Set(try kinds.map { try XCTUnwrap(ElementSearch.HitKind(rawValue: $0)) })
            }
            filter.motion = try XCTUnwrap(ElementSearch.Motion(rawValue: try XCTUnwrap(row["motion"] as? String)))
            filter.colour = row["colour"] as? String
            let expected = try XCTUnwrap(row["out"] as? [String])
            XCTAssertEqual(ElementSearch.filtered(hits, filter).map(\.key), expected, "\(row)")
        }
    }

    func testAnEmptyFilterKeepsEverythingAndRecentlyUsedIsLeftAlone() throws {
        XCTAssertTrue(ElementSearch.Filter().isEmpty)
        XCTAssertTrue(ElementSearch.Filter(kinds: []).isEmpty)
        XCTAssertFalse(ElementSearch.Filter(motion: .still).isEmpty)
        let hits = ElementSearch.results("star")
        XCTAssertEqual(ElementSearch.filtered(hits, ElementSearch.Filter()), hits)
        XCTAssertEqual(ElementSearch.Motion.still.rawValue, "static")
    }

    func testTheTypesCoverEveryKindOnce() {
        let kinds = ElementSearch.FilterType.allCases.flatMap { Array($0.kinds) }
        XCTAssertEqual(Set(kinds), Set(ElementSearch.HitKind.allCases))
        XCTAssertEqual(kinds.count, ElementSearch.HitKind.allCases.count)
        XCTAssertEqual(ElementSearch.FilterType.allCases.map(\.rawValue),
                       ["Graphics", "Stickers", "Shapes", "Photos", "Frames", "Grids", "Charts", "Tables"])
    }

    func testHuesComeFromThePackAndTheStockSeeds() {
        // Every graphic and every curated sticker has one to three.
        XCTAssertTrue(GraphicsLibrary.graphics.allSatisfy { (1...3).contains($0.hues.count) })
        for group in ContentLibrary.stickerGroups {
            for glyph in group.emoji {
                XCTAssertTrue((1...3).contains(GraphicsLibrary.stickerHues(glyph).count), glyph)
            }
        }
        XCTAssertEqual(PhotoLibrary.hues("mesh-sunset"), ["#ff9a8b", "#ff6a88", "#ff99ac"])
        XCTAssertTrue(PhotoLibrary.photos.allSatisfy { !PhotoLibrary.hues($0.id).isEmpty })
        // A shape takes the page's colours, so it has none of its own.
        XCTAssertEqual(ElementSearch.hues(of: ElementSearch.Hit(kind: .shape, id: "heart", name: "Heart")), [])
        XCTAssertEqual(ElementSearch.swatches.count, 12)
    }

    func testTheChipsSayWhatTheyFilterAndWhetherTheyAreOn() {
        XCTAssertEqual(ElementSearch.filterLabel("Animated", on: true), "Filter: animated, on")
        XCTAssertEqual(ElementSearch.filterLabel("Static", on: false), "Filter: static, off")
    }
}
