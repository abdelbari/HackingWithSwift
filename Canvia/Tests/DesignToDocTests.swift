// Turn into a Doc: a design read as a Doc's blocks, held to the fixture
// both phones share (Fixtures/design-to-doc.json), as the Android twin's
// DesignToDocTest.

import XCTest
@testable import Canvia

final class DesignToDocTests: XCTestCase {

    private func fixture() throws -> (design: Design, root: [String: Any]) {
        let root = try SharedFixture.object("design-to-doc")
        let design = try JSONDecoder().decode(Design.self, from: try SharedFixture.encoded(try XCTUnwrap(root["design"])))
        return (design, root)
    }

    /// Each block as its JSON, without its id.
    private func withoutIds(_ design: Design) throws -> [NSDictionary] {
        try Docs.blocks(design).map { b in
            var dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(b)) as? [String: Any])
            dict["id"] = nil
            return dict as NSDictionary
        }
    }

    /// Shared with the Android twin's DesignToDocTest.
    func testTheSharedDesignReadsAsTheSharedBlocks() throws {
        let (design, root) = try fixture()
        let before = design
        let doc = Docs.fromDesign(design, notes: true)
        let want = try XCTUnwrap(root["blocks"] as? [[String: Any]]).map { $0 as NSDictionary }
        let got = try withoutIds(doc)
        XCTAssertEqual(got.count, want.count)
        for (g, w) in zip(got, want) { XCTAssertEqual(g, w) }
        XCTAssertEqual(doc.title, root["title"] as? String)
        XCTAssertEqual(doc.folder, root["folder"] as? String)
        XCTAssertTrue(Docs.isDoc(doc))
        // The design itself is not changed, and a new id is the Doc's.
        XCTAssertEqual(design.pages, before.pages)
        XCTAssertNotEqual(doc.id, design.id)
    }

    func testWithoutSpeakerNotesTheNotesAreLeftOut() throws {
        let (design, _) = try fixture()
        XCTAssertFalse(Docs.blocks(Docs.fromDesign(design, notes: false)).contains { $0.text == "Speak slowly." })
    }

    func testAChartComesInOnceAsAChartBlockOfItsSpec() throws {
        let spec = ChartSpec(id: UID.make("chart"), kind: DataGraphics.ChartKind.column.rawValue, data: "A, 1\nB, 2")
        let parts = DataGraphics.chart(spec, in: CGRect(x: 100, y: 100, width: 800, height: 500),
                                       palette: ["#3355ff", "#ff5533"], heightFor: { _ in 20 })
        var design = Design(title: "Chart", width: 1080, height: 1080)
        design.pages = [Page(elements: parts)]
        let blocks = Docs.blocks(Docs.fromDesign(design))
        let charts = blocks.filter { $0.type == Docs.chart }
        XCTAssertEqual(charts.count, 1)
        XCTAssertEqual(charts.first.flatMap(Docs.chartSpec)?.data, spec.data)
        // The first page's heading, when it has none, is nothing at all.
        XCTAssertEqual(blocks.first?.type, Docs.chart)
    }
}
