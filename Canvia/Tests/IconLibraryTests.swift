// The icons library, as the Android twin's IconLibraryTest has it: the
// bundled Icons.json (the very file Android ships) read once, every path
// read by this phone's own parser and filling the 0…100 box, search by name,
// id and tag, the inserted shape and its name, its fill, and iconId and
// pathData written as top-level keys and read back.

import XCTest
import CoreGraphics
@testable import Canvia

final class IconLibraryTests: XCTestCase {

    func testTheLibraryIsReadFromItsResourceEveryIdOnceEveryCategoryShown() {
        // Android's resource is the same file, so its count is this one.
        XCTAssertEqual(IconLibrary.icons.count, 567)
        XCTAssertEqual(Set(IconLibrary.icons.map(\.id)).count, IconLibrary.icons.count)
        XCTAssertEqual(IconLibrary.categories, [
            "Arrows", "Communication", "People", "Places", "Travel", "Food", "Nature", "Shopping", "Business",
            "Education", "Media", "Weather", "Sport", "Home", "Tech", "Health", "Celebration", "Symbols",
        ])
        XCTAssertEqual(Set(IconLibrary.categories), Set(IconLibrary.icons.map(\.category)))
        for icon in IconLibrary.icons {
            XCTAssertFalse(icon.name.trimmingCharacters(in: .whitespaces).isEmpty, icon.id)
            XCTAssertFalse(icon.tags.isEmpty, icon.id)
            XCTAssertTrue(icon.tags.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 == $0.lowercased() },
                          icon.id)
        }
        XCTAssertEqual(IconLibrary.icon("favorite")?.name, "Favourite")
        XCTAssertNil(IconLibrary.icon("no-such-icon"))
        XCTAssertNil(IconLibrary.icon(nil as String?))
    }

    func testEveryPathParsesInTheSubsetBothPhonesReadAndFillsTheBox() {
        for icon in IconLibrary.icons {
            XCTAssertNotNil(icon.path.range(of: "^M[-0-9. MLQCZ]*$", options: .regularExpression), icon.id)
            let path = SVGPath.path(icon.path)
            XCTAssertFalse(path.isEmpty, icon.id)
            // Tight bounds, curve extremes rather than control points.
            let box = path.boundingBoxOfPath
            XCTAssertTrue(box.minX >= -0.01 && box.minY >= -0.01 && box.maxX <= 100.01 && box.maxY <= 100.01,
                          "\(icon.id): \(box)")
            // Fitted by the longer side and centred on the shorter.
            XCTAssertGreaterThan(max(box.width, box.height), 99.97, icon.id)
            XCTAssertEqual(box.minX + box.maxX, 100, accuracy: 0.03, icon.id)
            XCTAssertEqual(box.minY + box.maxY, 100, accuracy: 0.03, icon.id)
        }
    }

    func testASearchFindsNamesIdsAndTagsCaseAside() {
        XCTAssertEqual(IconLibrary.search("  "), IconLibrary.icons)
        XCTAssertTrue(IconLibrary.search("FAVOURITE").map(\.id).contains("favorite"))
        XCTAssertTrue(IconLibrary.search("favorite").map(\.id).contains("favorite"))
        XCTAssertTrue(IconLibrary.search("Heart").map(\.id).contains("favorite"))
        XCTAssertEqual(IconLibrary.search("arrow_back").map(\.id), ["arrow_back"])
        XCTAssertTrue(IconLibrary.search("zebra").isEmpty)
        // Grouped in sheet order, and a category with nothing found drops out.
        let groups = IconLibrary.grouped("ball")
        XCTAssertEqual(groups.first?.category, "Sport")
        XCTAssertTrue(groups.allSatisfy { group in
            !group.icons.isEmpty && group.icons.allSatisfy { $0.category == group.category }
        })
        XCTAssertEqual(IconLibrary.grouped("").map(\.category), IconLibrary.categories)
    }

    func testAnIconGoesOnAsA160SquareShapeDrawnFromItsPathInTheMiddleOfThePage() throws {
        let heart = try XCTUnwrap(IconLibrary.icon("favorite"))
        let el = IconLibrary.element(heart, pageWidth: 1080, pageHeight: 1920, fill: "#1f2430")
        XCTAssertEqual(el.type, .shape)
        XCTAssertEqual([el.x, el.y, el.w, el.h], [460, 880, 160, 160])
        XCTAssertEqual(el.fill?.color, "#1f2430")
        XCTAssertEqual(el.pathData, heart.path)
        XCTAssertEqual(el.iconId, "favorite")
        XCTAssertEqual(ElementNames.name(of: el), "Favourite icon")
        // An icon this build does not know is named as the shape it draws.
        var unknown = el
        unknown.iconId = "future"
        XCTAssertEqual(ElementNames.name(of: unknown), "Dark blue custom shape")
    }

    /// Put on by the store: in the middle of the page, selected, and one Undo.
    @MainActor
    func testAddingAnIconSelectsItAsOneUndo() throws {
        let store = DesignStore(design: Design(title: "t", width: 1080, height: 1920))
        let cake = try XCTUnwrap(IconLibrary.icon("cake"))
        store.add(IconLibrary.element(cake, pageWidth: store.pageWidth, pageHeight: store.pageHeight,
                                      fill: IconLibrary.fill(for: store.page, brandColours: [])))
        let added = try XCTUnwrap(store.page.elements.last)
        XCTAssertEqual(store.selection, [added.id])
        XCTAssertEqual([added.x, added.y], [460, 880])
        XCTAssertEqual(added.iconId, "cake")
        store.undo()
        XCTAssertTrue(store.page.elements.isEmpty)
        XCTAssertFalse(store.canUndo)
    }

    func testAnIconIsFilledInTheBrandKitsFirstColourElseInkThatReadsOnThePage() {
        let white = Page()
        let dark = Page(background: .color("#14322a"))
        XCTAssertEqual(IconLibrary.fill(for: white, brandColours: ["#e94560", "#000000"]), "#e94560")
        XCTAssertEqual(IconLibrary.fill(for: white, brandColours: []), "#1f2430")
        XCTAssertEqual(IconLibrary.fill(for: dark, brandColours: []), "#ffffff")
    }

    func testTheIconsIdAndPathAreWrittenAsTopLevelKeysAndComeBack() throws {
        let cake = try XCTUnwrap(IconLibrary.icon("cake"))
        let el = IconLibrary.element(cake, pageWidth: 1080, pageHeight: 1080, fill: "#ffffff")
        let data = try JSONEncoder().encode(el)
        let written = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(written["iconId"] as? String, "cake")
        XCTAssertEqual(written["pathData"] as? String, cake.path)
        XCTAssertEqual(try JSONDecoder().decode(Element.self, from: data), el)
        // As Android writes one, and an element from before icons has none.
        let android = try JSONDecoder().decode(Element.self, from: Data(
            #"{"id":"e1","type":"shape","shapeId":"rect","pathData":"M0 0L100 0L50 100Z","iconId":"favorite"}"#.utf8))
        XCTAssertEqual(android.iconId, "favorite")
        let old = try JSONDecoder().decode(Element.self, from: Data(#"{"id":"e2","type":"shape","shapeId":"rect"}"#.utf8))
        XCTAssertNil(old.iconId)
        XCTAssertNil(try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])["iconId"])
    }
}
