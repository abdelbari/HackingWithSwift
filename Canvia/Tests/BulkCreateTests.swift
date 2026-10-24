// Bulk create, as the Android twin's BulkCreateTest checks it: the shared
// rows and page (Tests/Fixtures/bulk-create.json) give the same columns,
// rows and pages on both phones — the pages in the JSON the two apps
// exchange, ids by place — the "bulk" and "bulkField" keys, the photos a
// cell names, the titles of separate designs, the words that no longer fit,
// and one undo step.

import XCTest
@testable import Canvia

final class BulkCreateTests: XCTestCase {

    private struct Shared {
        var design: Design
        var cells: [[String]]
        var pictures: [BulkCreate.Picture]
        var columns: [String]
        var rows: [[String]]
        var pages: [Page]
    }

    /// The fixture: its design and expected pages decoded as the app reads
    /// a design, and its photo uploads ({"id", "kind", "name"?}, as
    /// uploads.json lists them) as Bulk create finds them.
    private func fixture() throws -> Shared {
        let object = try SharedFixture.object("bulk-create")
        let design = try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(object["design"])))
        let pages = try JSONDecoder().decode([Page].self, from: SharedFixture.encoded(try XCTUnwrap(object["pages"])))
        let uploads = try XCTUnwrap(object["uploads"] as? [[String: Any]])
        var pictures: [BulkCreate.Picture] = []
        for upload in uploads where upload["kind"] as? String == "image" {
            guard let id = upload["id"] as? String else { continue }
            pictures.append(BulkCreate.Picture(id: id, name: upload["name"] as? String, src: "media:\(id)"))
        }
        return Shared(design: design,
                       cells: try XCTUnwrap(object["cells"] as? [[String]]),
                       pictures: pictures,
                       columns: try XCTUnwrap(object["columns"] as? [String]),
                       rows: try XCTUnwrap(object["rows"] as? [[String]]),
                       pages: pages)
    }

    /// Each page's id as "page-<n>" and each of its elements' as
    /// "el-<n>-<m>", by place, as Android's test names them: the ids are
    /// fresh on each phone.
    private func placed(_ pages: [Page]) -> [Page] {
        var out = pages
        for i in out.indices {
            out[i].id = "page-\(i + 1)"
            for j in out[i].elements.indices { out[i].elements[j].id = "el-\(i + 1)-\(j + 1)" }
        }
        return out
    }

    func testTheSharedRowsMakeTheSharedPages() throws {
        let f = try fixture()
        let data = BulkCreate.data(from: f.cells)
        XCTAssertEqual(data.columns, f.columns)
        XCTAssertEqual(data.rows, f.rows)
        let template = try XCTUnwrap(f.design.pages.first)
        let made = BulkCreate.pages(f.design, pageId: template.id, data: data, pictures: f.pictures)
        XCTAssertEqual(placed(made), f.pages)
        for page in made {
            XCTAssertNotEqual(page.id, template.id, "a page of its own")
            XCTAssertTrue(Set(page.elements.map(\.id)).isDisjoint(with: template.elements.map(\.id)), "fresh ids")
        }
        XCTAssertTrue(BulkCreate.pages(f.design, pageId: "none", data: data).isEmpty)
    }

    func testTheRowsAndTheirColumns() {
        let data = BulkCreate.data(from: [["", "Name", "Name"], ["a", "b", "c"], [" ", "", ""]])
        XCTAssertEqual(data.columns, ["Column 1", "Name", "Name 2"])
        XCTAssertEqual(data.rows, [["a", "b", "c"]])
        XCTAssertEqual(BulkCreate.data(from: [["A"], ["a", "b"]]).columns, ["A", "Column 2"],
                       "a row wider than the names has a column of its own")
    }

    /// Shared: Android's BulkCreateTest finds and caps the same.
    func testPlaceholdersAndPictures() {
        let columns = ["Name", "Course"]
        XCTAssertEqual(BulkCreate.placeholders(in: "{{Course}} for {{ Name }} and {{Name}} {{Nope}} {{}}", columns: columns),
                       ["Course", "Name"])
        XCTAssertEqual(BulkCreate.filled("Hi {{Name}}, {{Other}} {{", columns: columns, row: ["A_b", "X"]),
                       "Hi A\\_b, {{Other}} {{")
        let pictures = [BulkCreate.Picture(id: "p1", name: "Turing.JPG", src: "media:p1")]
        XCTAssertEqual(BulkCreate.picture("p1", pictures: pictures), "media:p1")
        XCTAssertEqual(BulkCreate.picture("media:p1", pictures: pictures), "media:p1")
        XCTAssertEqual(BulkCreate.picture(" p1.png ", pictures: pictures), "media:p1")
        XCTAssertEqual(BulkCreate.picture("media:p1.jpg", pictures: pictures), "media:p1")
        XCTAssertEqual(BulkCreate.picture(" turing.jpg ", pictures: pictures), "media:p1")
        XCTAssertNil(BulkCreate.picture("nobody.png", pictures: pictures))
        XCTAssertNil(BulkCreate.picture("media:nobody", pictures: pictures))
        XCTAssertEqual(BulkCreate.bare(".hidden"), ".hidden")
        XCTAssertEqual(BulkCreate.bare("a.b.jpg"), "a.b")
        XCTAssertNil(BulkCreate.capNote(rows: 500))
        XCTAssertEqual(BulkCreate.capNote(rows: 520), "Only the first 500 of 520 rows will be made.")
        let many = [["Name"]] + (0..<520).map { ["n\($0)"] }
        XCTAssertEqual(BulkCreate.data(from: many).rows.count, BulkCreate.maxRows)
        XCTAssertEqual(BulkCreate.rowCount(many), 520)
        XCTAssertEqual(BulkCreate.title(of: ["  Ada "], fallback: "Badges"), "Ada")
        XCTAssertEqual(BulkCreate.title(of: [""], fallback: "Badges"), "Badges")
    }

    /// Shared: Android's BulkCreate.designs titles them the same.
    func testSeparateDesignsAreTitledEachTheirOwn() {
        let rows = BulkCreate.data(from: [["Name"], ["Ada"], ["  "], ["Alan"], ["ada"], ["Badges"]]).rows
        XCTAssertEqual(BulkCreate.titles(of: rows, fallback: "Badges", taken: ["Alan"]),
                       ["Ada", "Alan 2", "ada 2", "Badges 2"])
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
        let data = BulkCreate.data(from: f.cells)
        let template = try XCTUnwrap(f.design.pages.first)
        let made = BulkCreate.pages(f.design, pageId: template.id, data: data, pictures: f.pictures)
        // Measured as taller than its box when its words are over 26 letters.
        let lines = BulkCreate.overflows(made, template: template, data: data) { el in
            (el.text ?? "").count > 26 ? el.h * 2 : el.h
        }
        XCTAssertEqual(lines, ["Row 1: Name is too long"])
    }

    @MainActor
    func testGeneratingIsOneStepNamedBulkCreate() throws {
        let f = try fixture()
        let store = DesignStore(design: f.design)
        store.measure = { $0.h }
        let outcome = store.bulkCreatePages(BulkCreate.data(from: f.cells), pictures: f.pictures)
        XCTAssertEqual(outcome.made, 4)
        XCTAssertEqual(store.design.pages.count, 5)
        XCTAssertEqual(store.design.bulk?.rows.count, 4)
        XCTAssertEqual(store.undoLabel, "Bulk create")
        store.undo()
        XCTAssertEqual(store.design.pages.count, 1)
        XCTAssertNil(store.design.bulk)
        store.setBulkField("band", column: "Name")
        XCTAssertEqual(store.design.pages[0].elements[3].bulkField, "Name")
    }
}
