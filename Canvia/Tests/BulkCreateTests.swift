// Bulk create, as the Android twin's BulkCreateTest checks it: the shared
// rows and page (Tests/Fixtures/bulk-create.json) give the same pages on
// both phones — the same words and pictures, fresh ids — the "bulk" and
// "bulkField" keys, the words that no longer fit, and one undo step.

import XCTest
@testable import Canvia

final class BulkCreateTests: XCTestCase {

    private struct Fixture: Decodable {
        struct Made: Decodable {
            var texts: [String]
            var srcs: [String]
        }
        var grid: [[String]]
        var columns: [String]
        var rows: [[String]]
        var page: Page
        var pictures: [String: String]
        var pages: [Made]
    }

    private func fixture() throws -> Fixture {
        try JSONDecoder().decode(Fixture.self, from: SharedFixture.data("bulk-create"))
    }

    func testTheSharedRowsMakeTheSamePagesAsOnAndroid() throws {
        let f = try fixture()
        let data = BulkCreate.data(from: f.grid)
        XCTAssertEqual(data.columns, f.columns)
        XCTAssertEqual(data.rows, f.rows)
        var design = Design(title: "Certificates")
        design.pages = [f.page]
        let made = BulkCreate.pages(design, pageId: f.page.id, data: data, pictures: f.pictures)
        XCTAssertEqual(made.count, f.pages.count)
        for (page, want) in zip(made, f.pages) {
            XCTAssertEqual(page.elements.filter { $0.type == .text }.map { $0.text ?? "" }, want.texts)
            XCTAssertEqual(page.elements.filter { $0.type == .image }.compactMap(\.src), want.srcs)
            XCTAssertNotEqual(page.id, f.page.id, "a page of its own")
            XCTAssertTrue(Set(page.elements.map(\.id)).isDisjoint(with: f.page.elements.map(\.id)), "fresh ids")
            XCTAssertEqual(page.elements.map(\.bulkField), f.page.elements.map(\.bulkField), "still connected")
        }
        XCTAssertTrue(BulkCreate.pages(design, pageId: "none", data: data).isEmpty)
    }

    func testPlaceholdersAndPictures() {
        let columns = ["Name", "Course"]
        XCTAssertEqual(BulkCreate.placeholders(in: "{{Course}} for {{ Name }} and {{Name}} {{Nope}}", columns: columns),
                       ["Course", "Name"])
        XCTAssertEqual(BulkCreate.filled("Hi {{Name}}, {{Other}} {{", columns: columns, row: ["A_b", "X"]),
                       "Hi A\\_b, {{Other}} {{")
        let pictures = ["pic": "media:pic", "clip": "video:clip"]
        XCTAssertEqual(BulkCreate.picture("pic", pictures: pictures), "media:pic")
        XCTAssertEqual(BulkCreate.picture(" media:pic.png ", pictures: pictures), "media:pic")
        XCTAssertEqual(BulkCreate.picture("video:clip", pictures: pictures), "video:clip")
        XCTAssertNil(BulkCreate.picture("holiday.jpg", pictures: pictures))
        XCTAssertNil(BulkCreate.capNote(rows: 500))
        XCTAssertEqual(BulkCreate.capNote(rows: 612), "Only the first 500 of 612 rows will be made")
        let many = [["Name"]] + (0..<600).map { ["n\($0)"] }
        XCTAssertEqual(BulkCreate.data(from: many).rows.count, BulkCreate.maxRows)
        XCTAssertEqual(BulkCreate.rowCount(many), 600)
        XCTAssertEqual(BulkCreate.title(of: ["  Ada "], fallback: "Badges"), "Ada")
        XCTAssertEqual(BulkCreate.title(of: [""], fallback: "Badges"), "Badges")
    }

    func testTheKeysAreWrittenAndReadBack() throws {
        var design = Design(title: "Badges")
        var text = Element.text("Name")
        text.bulkField = "Name"
        design.pages[0].elements = [text]
        design.bulk = BulkData(columns: ["Name"], rows: [["Ada"], ["Alan"]])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(design)) as? [String: Any])
        let bulk = try XCTUnwrap(object["bulk"] as? [String: Any])
        XCTAssertEqual(bulk["columns"] as? [String], ["Name"])
        XCTAssertEqual(bulk["rows"] as? [[String]], [["Ada"], ["Alan"]])
        let pages = try XCTUnwrap(object["pages"] as? [[String: Any]])
        let elements = try XCTUnwrap(pages.first?["elements"] as? [[String: Any]])
        XCTAssertEqual(elements.first?["bulkField"] as? String, "Name")
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(design))
        XCTAssertEqual(back.bulk, design.bulk)
        XCTAssertEqual(back.pages[0].elements[0].bulkField, "Name")
        let plain = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Design(title: "x")))
            as? [String: Any])
        XCTAssertNil(plain["bulk"], "none before it is used")
        let odd = try JSONDecoder().decode(BulkData.self, from: Data(#"{"columns":["A",3],"rows":[["x",null]]}"#.utf8))
        XCTAssertEqual(odd, BulkData(columns: ["A", ""], rows: [["x", ""]]))
    }

    func testWordsThatNoLongerFitAreSaidRowByRow() throws {
        let f = try fixture()
        let data = BulkCreate.data(from: f.grid)
        var design = Design(title: "Certificates")
        design.pages = [f.page]
        let made = BulkCreate.pages(design, pageId: f.page.id, data: data, pictures: f.pictures)
        // Measured as taller than its box when its words are over 26 letters.
        let lines = BulkCreate.overflows(made, template: f.page, data: data) { el in
            (el.text ?? "").count > 26 ? el.h * 2 : el.h
        }
        XCTAssertEqual(lines, ["Row 1: Name is too long", "Row 2: Name is too long"])
    }

    @MainActor
    func testGeneratingIsOneStepNamedBulkCreate() throws {
        let f = try fixture()
        var design = Design(title: "Certificates")
        design.pages = [f.page]
        let store = DesignStore(design: design)
        store.measure = { $0.h }
        let outcome = store.bulkCreatePages(BulkCreate.data(from: f.grid), pictures: f.pictures)
        XCTAssertEqual(outcome.made, 3)
        XCTAssertEqual(store.design.pages.count, 4)
        XCTAssertEqual(store.design.bulk?.rows.count, 3)
        XCTAssertEqual(store.undoLabel, "Bulk create")
        store.undo()
        XCTAssertEqual(store.design.pages.count, 1)
        XCTAssertNil(store.design.bulk)
        store.setBulkField("t3", column: "Name")
        XCTAssertEqual(store.design.pages[0].elements[3].bulkField, "Name")
    }
}
