// A whole family added at once: a .zip's faces and a collection's fonts,
// each kept as one file is — the shared fixtures, made by the Android
// twin's tools/generate_woff_fixture.py and copied here byte for byte —
// and their names, order and hashes, as its CustomFontsTest asserts them.

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
        let described = faces.compactMap { CustomFonts.describe($0.data) }
        XCTAssertEqual(described.map(\.family), ["Karla", "Karla", "Karla"])
        XCTAssertEqual(described.map(\.weight), [700, 400, 400])
        XCTAssertEqual(described.map(\.italic), [false, true, false])
        let karla = try Data(contentsOf: try XCTUnwrap(FontLibrary.bundledURL("karla-400.ttf")))
        XCTAssertEqual(faces.last?.data, karla)
    }

    /// Shared: the collection gives its two fonts, each a file of its own
    /// named "<name>-<n>.ttf", with the same sizes and hashes as on the
    /// Android twin; each reads as the face it is.
    func testACollectionIsSplitIntoItsFonts() throws {
        let faces = CustomFonts.expand(try fixture("two-faces", "ttc"), name: "Two.ttc")
        XCTAssertEqual(faces.map { $0.name }, ["Two-1.ttf", "Two-2.ttf"])
        XCTAssertEqual(faces.map { CustomFonts.sha12($0.data) }, ["4a441c7db1c9", "a6b6c3e9831a"])
        XCTAssertEqual(faces.map { $0.data.count }, [40908, 44040])
        XCTAssertEqual(try faces.map { try CustomFonts.check($0.data).get().name }, ["Righteous", "Karla"])
        XCTAssertEqual(try faces.map { try CustomFonts.check($0.data).get().ext }, ["ttf", "ttf"])
    }

    /// Shared: fixtures/righteous-400.woff2 unpacks through the shared
    /// decoder (Brotli, then glyf, loca and hmtx rebuilt) to the 41100-byte
    /// font both phones store under ebeccf263458, summing to head's magic
    /// number.
    func testAWoff2IsUnpackedIntoTheSameFont() throws {
        let woff2 = try fixture("righteous-400", "woff2")
        let font = try XCTUnwrap(Woff2.unpack(woff2, limit: CustomFonts.maxBytes))
        XCTAssertEqual(font.count, 41100)
        XCTAssertEqual(CustomFonts.sha12(font), "ebeccf263458")
        XCTAssertEqual(try CustomFonts.sfnt(woff2).get(), font)
        XCTAssertEqual(try CustomFonts.check(woff2).get(), CustomFonts.Checked(ext: "ttf", name: "Righteous"))
        let bytes = [UInt8](font)
        var sum: UInt32 = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            sum = sum &+ (UInt32(bytes[i]) << 24 | UInt32(bytes[i + 1]) << 16 | UInt32(bytes[i + 2]) << 8 | UInt32(bytes[i + 3]))
        }
        XCTAssertEqual(sum, 0xB1B0_AFBA)
        XCTAssertNil(Woff2.unpack(woff2.prefix(2000), limit: CustomFonts.maxBytes))
    }

    /// Brotli (RFC 7932), as the WOFF2 reader inflates it: the Android
    /// twin's stream with dictionary words, context modelling and several
    /// meta-blocks.
    func testBrotliStreamsInflate() throws {
        let packed = [UInt8](try fixture("brotli-text", "br"))
        XCTAssertEqual(try Brotli.decompress(packed, limit: 1_000_000), [UInt8](try fixture("brotli-text", "txt")))
        XCTAssertEqual(try Brotli.decompress([0x06], limit: 10), [])
        XCTAssertThrowsError(try Brotli.decompress(packed, limit: 100))
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
        XCTAssertEqual(CustomFonts.importSummary(families: ["Inter"], styles: 1, skipped: 1),
                       "Added Inter: 1 style; skipped 1 file")
        XCTAssertEqual(CustomFonts.importSummary(families: [], styles: 0, skipped: 1), "Skipped 1 file")
        XCTAssertEqual(CustomFonts.skippedLine("notes.ttf", .notAFont),
                       "notes.ttf: That file is not a font Canvia can use.")
    }
}
