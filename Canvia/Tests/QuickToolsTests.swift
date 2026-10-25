// Home's quick file tools, planned, with the shared fixture
// Fixtures/quick-tools.json — the Android twin's QuickToolsTest reads the
// same file.

import XCTest
@testable import Canvia

final class QuickToolsTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("quick-tools") }

    private func numbers(_ o: [String: Any], _ key: String) throws -> [Double] {
        try XCTUnwrap(o[key] as? [NSNumber]).map(\.doubleValue)
    }

    func testEachToolsFilesAndPagesAreAsTheSharedFileSays() throws {
        let plans = try XCTUnwrap(fixture()["plans"] as? [[String: Any]])
        XCTAssertFalse(plans.isEmpty)
        for c in plans {
            let tool = try XCTUnwrap(QuickTools.Tool(rawValue: try XCTUnwrap(c["tool"] as? String)))
            let inputs = try XCTUnwrap(c["inputs"] as? [[String: Any]]).map {
                QuickTools.Input(name: $0["name"] as? String ?? "", pages: $0["pages"] as? Int ?? 1)
            }
            let o = c["options"] as? [String: Any] ?? [:]
            let options = QuickTools.Options(pages: o["pages"] as? [Int], each: o["each"] as? Bool ?? false,
                                             format: o["format"] as? String, zip: o["zip"] as? Bool ?? false)
            let plan = QuickTools.plan(tool, inputs, options)
            let expected = try XCTUnwrap(c["outputs"] as? [[String: Any]]).map { out in
                QuickTools.Output(name: out["name"] as? String ?? "", pages: (out["pages"] as? [[Int]] ?? []).map {
                    QuickTools.Ref(input: $0[0], page: $0[1])
                })
            }
            XCTAssertEqual(plan.outputs, expected, tool.rawValue)
            XCTAssertEqual(plan.zip, c["zip"] as? String, tool.rawValue)
        }
    }

    func testAPictureIsResizedAsTheSharedFileSays() throws {
        let cases = try XCTUnwrap(fixture()["resize"] as? [[String: Any]])
        for c in cases {
            let r = try XCTUnwrap(c["resize"] as? [String: Any])
            let size = (r["size"] as? [Int]).map { QuickTools.Size(width: $0[0], height: $0[1]) }
            let resize = QuickTools.Resize(longEdge: r["longEdge"] as? Int, percent: (r["percent"] as? NSNumber)?.doubleValue,
                                           size: size, cover: r["cover"] as? Bool ?? false)
            let made = QuickTools.resized(width: try XCTUnwrap(c["width"] as? Int), height: try XCTUnwrap(c["height"] as? Int),
                                          resize)
            let out = try numbers(c, "out")
            XCTAssertEqual(Double(made.width), out[0])
            XCTAssertEqual(Double(made.height), out[1])
            let crop = try numbers(c, "crop")
            XCTAssertEqual([made.crop.minX, made.crop.minY, made.crop.width, made.crop.height].map { Double($0) }, crop)
        }
    }

    func testAPhotoSitsOnItsPDFPageAsTheSharedFileSays() throws {
        let cases = try XCTUnwrap(fixture()["photoPage"] as? [[String: Any]])
        for c in cases {
            let paper = try XCTUnwrap(QuickTools.PhotoPaper(rawValue: try XCTUnwrap(c["paper"] as? String)))
            let placed = QuickTools.photoPage(width: try XCTUnwrap(c["width"] as? Int), height: try XCTUnwrap(c["height"] as? Int),
                                              paper: paper, margin: (c["margin"] as? NSNumber)?.doubleValue ?? 0)
            let want = try numbers(c, "page") + numbers(c, "box")
            let got = [placed.page.width, placed.page.height, placed.box.minX, placed.box.minY,
                       placed.box.width, placed.box.height].map { Double($0) }
            for (w, g) in zip(want, got) { XCTAssertEqual(w, g, accuracy: 1e-6) }
        }
    }

    func testNamesAndTypesAreReadFromTheFileNames() {
        XCTAssertEqual(QuickTools.stem("Report.pdf"), "Report")
        XCTAssertEqual(QuickTools.stem("my.holiday.jpg"), "my.holiday")
        XCTAssertEqual(QuickTools.stem("  .  "), "file")
        XCTAssertEqual(QuickTools.pictureType("HEIC"), "jpg")
        XCTAssertEqual(QuickTools.pictureType("webp"), "png")
        XCTAssertTrue(QuickTools.isPdf("A.PDF"))
        XCTAssertTrue(QuickTools.plan(.merge, []).outputs.isEmpty)
        XCTAssertEqual(QuickTools.Tool.allCases.count, 7)
    }
}
