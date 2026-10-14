// One search across every kind of element, and Recently used, as the
// Android twin's ElementSearchTest has them, row for row. One row differs
// by a name the phones' shape libraries already give differently: the
// right arrow is "Arrow Right" here and "Arrow" there, so here it is a
// prefix match after the line called Arrow, there an exact one before it.

import XCTest
@testable import Canvia

final class ElementSearchTests: XCTestCase {

    private func keys(_ query: String, _ n: Int) -> [String] {
        ElementSearch.results(query).prefix(n).map { "\($0.kind.rawValue)/\($0.id)" }
    }

    func testTheSharedRankingTable() {
        let rows: [(query: String, first: [String])] = [
            // An exact name first, kind by kind; then names that start so.
            ("heart", ["shape/heart", "sticker/💝"]),
            ("Arrow", ["line/Arrow", "shape/arrow-right", "shape/arrow-left"]),
            // A synonym finds what the word it stands for finds, as a word match.
            ("pointer", ["shape/arrow-right", "shape/arrow-left"]),
            ("Love", ["sticker/😍", "shape/heart"]),
            // Words a grid is found by, and a frame by its name.
            ("two photos", ["grid/two", "grid/twoStack"]),
            ("polaroid", ["photoFrame/polaroid"]),
            // A prefix, then a word of a name ("Puzzle piece").
            ("pie", ["icon/pie_chart", "chart/pie", "icon/extension"]),
            ("QR", ["icon/qr_code", "qr/qr"]),
            ("table", ["table/table", "icon/table_chart"]),
            // A sticker by its words; spaces and case aside.
            ("  ZZZ ", ["sticker/😴"]),
            ("sunset", ["icon/wb_twilight", "stockArt/mesh-sunset"]),
            ("nothing like this", []),
            ("   ", []),
        ]
        for row in rows {
            XCTAssertEqual(keys(row.query, row.first.count), row.first, row.query)
        }
        XCTAssertTrue(ElementSearch.results("nothing like this").isEmpty)
    }

    func testAnExactNameRanksAboveAPrefixAPrefixAboveAWordAWordAboveACategory() throws {
        let heart = ElementSearch.results("heart")
        let exact = try XCTUnwrap(heart.lastIndex { $0.name.lowercased() == "heart" })
        let prefix = try XCTUnwrap(heart.firstIndex { $0.id == "monitor_heart" })
        let word = try XCTUnwrap(heart.firstIndex { $0.id == "heart_broken" })
        XCTAssertTrue(exact < prefix && prefix < word, "\(exact) \(prefix) \(word)")
        // "Arrows" is a category: an icon in it with no "arrow" in its name
        // comes after every name with one.
        let arrows = ElementSearch.results("arrows")
        XCTAssertFalse(arrows.isEmpty)
        XCTAssertTrue(arrows.allSatisfy { $0.kind == .icon || $0.kind == .shape })
    }

    func testHitsAreShownInSectionsInAFixedOrder() {
        XCTAssertEqual(ElementSearch.sections(ElementSearch.results("star")).map { $0.section.title },
                       ["Shapes", "Icons", "Stickers"])
        XCTAssertEqual(ElementSearch.Shelf.allCases.map(\.title),
                       ["Shapes", "Icons", "Stickers", "Frames", "Grids", "Lines", "Charts and tables", "Artwork"])
        // Charts, the table and the QR code share a section.
        XCTAssertEqual(ElementSearch.HitKind.qr.section, .charts)
        XCTAssertEqual(ElementSearch.HitKind.table.section, .charts)
        XCTAssertEqual(ElementSearch.sectionLimit, 8)
        XCTAssertEqual(ElementSearch.nothingFound(" xq "), "Nothing called \"xq\". Try a shorter word.")
    }

    func testEverythingAddHasIsThereToFind() {
        for shape in ContentLibrary.shapes {
            XCTAssertEqual(ElementSearch.hit(.shape, shape.id)?.name, shape.name)
        }
        XCTAssertEqual(IconLibrary.icons.filter { ElementSearch.hit(.icon, $0.id) != nil }.count, 567)
        for group in ContentLibrary.stickerGroups {
            for glyph in group.emoji { XCTAssertNotNil(ElementSearch.hit(.sticker, glyph), glyph) }
        }
        for frame in DecorativeFrames.presets { XCTAssertNotNil(ElementSearch.hit(.photoFrame, frame.id), frame.id) }
        for grid in PhotoGrids.layouts { XCTAssertNotNil(ElementSearch.hit(.grid, grid.id), grid.id) }
        for line in ElementSearch.linePresets { XCTAssertNotNil(ElementSearch.hit(.line, line.name), line.name) }
        for chart in DataGraphics.ChartKind.allCases {
            XCTAssertEqual(ElementSearch.hit(.chart, chart.rawValue)?.name, "\(chart.name) chart")
        }
        for art in PhotoLibrary.photos { XCTAssertNotNil(ElementSearch.hit(.stockArt, art.id), art.id) }
        XCTAssertEqual(ElementSearch.hit(.table, "table"), ElementSearch.Hit(kind: .table, id: "table", name: "Table"))
        XCTAssertEqual(ElementSearch.hit(.qr, "qr"), ElementSearch.Hit(kind: .qr, id: "qr", name: "QR code"))
        XCTAssertEqual(ElementSearch.linePresets.map(\.name), ["Line", "Arrow", "Double arrow", "Dot ends"])
    }

    func testRecentlyUsedKeepsTheLast24NewestFirstOnceEachAsAJSONArray() throws {
        let heart = try XCTUnwrap(ElementSearch.hit(.shape, "heart"))
        let pie = try XCTUnwrap(ElementSearch.hit(.chart, "pie"))
        var recent = ElementSearch.remembered([], heart)
        recent = ElementSearch.remembered(recent, pie)
        recent = ElementSearch.remembered(recent, heart)
        XCTAssertEqual(recent, [heart, pie])
        let text = ElementSearch.encode(recent)
        XCTAssertEqual(text, #"[{"kind":"shape","id":"heart"},{"kind":"chart","id":"pie"}]"#)
        XCTAssertEqual(ElementSearch.decode(text), recent)
        // Many more: only the last 24.
        for shape in ContentLibrary.shapes {
            let hit = try XCTUnwrap(ElementSearch.hit(.shape, shape.id))
            recent = ElementSearch.remembered(recent, hit)
        }
        XCTAssertEqual(recent.count, ElementSearch.recentLimit)
        XCTAssertEqual(recent.first?.id, ContentLibrary.shapes.last?.id)
        // Read tolerantly: what this build lacks, and what is not a list, is left out.
        let odd = #"[{"kind":"shape","id":"heart"},{"kind":"hologram","id":"x"},{"kind":"shape","id":"nope"},7]"#
        XCTAssertEqual(ElementSearch.decode(odd), [heart])
        XCTAssertEqual(ElementSearch.decode("not json"), [])
        XCTAssertEqual(ElementSearch.decode(nil), [])
    }

    func testRecentlyUsedIsKeptOnThePhoneUnderRecentElements() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "ElementSearchTests"))
        defaults.removePersistentDomain(forName: "ElementSearchTests")
        ElementSearch.remember(.sticker, "🎉", in: defaults)
        ElementSearch.remember(.qr, "qr", in: defaults)
        // Something this build does not have is not kept.
        ElementSearch.remember(.shape, "nope", in: defaults)
        XCTAssertEqual(ElementSearch.recent(in: defaults).map(\.id), ["qr", "🎉"])
        XCTAssertEqual(defaults.string(forKey: "recentElements"),
                       #"[{"kind":"qr","id":"qr"},{"kind":"sticker","id":"🎉"}]"#)
        defaults.removePersistentDomain(forName: "ElementSearchTests")
    }
}
