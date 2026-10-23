// A whole family added at once: a .zip's faces and a collection's fonts,
// each kept as one file is — the shared fixtures (the Android twin's
// tools/generate_woff_fixture.py makes the same pair) and their hashes.

import XCTest
@testable import Canvia

final class FontFamilyImportTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String, file: StaticString = #filePath) throws -> Data {
        if let url = Bundle(for: FontFamilyImportTests.self).url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }
        let here = URL(fileURLWithPath: "\(file)").deletingLastPathComponent()
        return try Data(contentsOf: here.appendingPathComponent("Fixtures/\(name).\(ext)"))
    }

    /// Shared: the zip gives its three static faces, in the order of their
    /// paths — not the variable file beside them, the licence or the Mac's
    /// litter — byte for byte.
    func testAZipGivesItsThreeFaces() throws {
        let faces = CustomFonts.expand(try fixture("karla-family", "zip"), name: "karla-family.zip")
        XCTAssertEqual(faces.map { $0.name }, ["Karla-Bold.ttf", "Karla-Italic.ttf", "Karla-Regular.ttf"])
        XCTAssertEqual(faces.map { CustomFonts.sha12($0.data) }, ["d69346726ef2", "7c088f3657e8", "e6f8766ae87d"])
        let karla = try Data(contentsOf: try XCTUnwrap(FontLibrary.bundledURL("karla-400.ttf")))
        XCTAssertEqual(faces.last?.data, karla)
    }

    /// Shared: the collection gives its two fonts, each a file of its own
    /// with its tables in its records' order, and the same hashes as on the
    /// Android twin; each reads as the face it is.
    func testACollectionIsSplitIntoItsFonts() throws {
        let faces = CustomFonts.expand(try fixture("karla-pair", "ttc"), name: "karla-pair.ttc")
        XCTAssertEqual(faces.map { $0.name }, ["karla-pair-1.ttf", "karla-pair-2.ttf"])
        XCTAssertEqual(faces.map { CustomFonts.sha12($0.data) }, ["a6b6c3e9831a", "e73a2eaa7da2"])
        let described = faces.compactMap { CustomFonts.describe($0.data) }
        XCTAssertEqual(described.map(\.family), ["Karla", "Karla"])
        XCTAssertEqual(described.map(\.weight), [400, 700])
        XCTAssertEqual(try faces.map { try CustomFonts.check($0.data).get().ext }, ["ttf", "ttf"])
    }

    /// Any other file is itself; something that is not a zip or a font
    /// still goes on, to be refused as one file is.
    func testAnyOtherFileIsItself() throws {
        let karla = try Data(contentsOf: try XCTUnwrap(FontLibrary.bundledURL("karla-700.ttf")))
        let faces = CustomFonts.expand(karla, name: "Karla-Bold.ttf")
        XCTAssertEqual(faces.map { $0.name }, ["Karla-Bold.ttf"])
        XCTAssertEqual(faces.first?.data, karla)
        XCTAssertTrue(CustomFonts.expand(Data("PK\u{3}\u{4}broken".utf8), name: "x.zip").isEmpty)
    }

    /// One line for the lot, as both phones say it.
    func testTheSummaryIsOneLine() {
        XCTAssertEqual(CustomFonts.importSummary(families: ["Inter"], styles: 9, skipped: 2),
                       "Added Inter: 9 styles; skipped 2 files")
        XCTAssertEqual(CustomFonts.importSummary(families: ["Inter"], styles: 1, skipped: 0), "Added Inter: 1 style")
        XCTAssertEqual(CustomFonts.importSummary(families: ["Inter", "Lora"], styles: 3, skipped: 1),
                       "Added Inter, Lora: 3 styles; skipped 1 file")
        XCTAssertEqual(CustomFonts.importSummary(families: [], styles: 0, skipped: 2), "Skipped 2 files")
        XCTAssertEqual(CustomFonts.skippedLine("notes.ttf", .notAFont),
                       "notes.ttf: That file is not a font Canvia can use.")
    }
}
