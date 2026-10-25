// The Details sheet's facts: the shared vectors (Fixtures/design-facts.json)
// the Android twin's DesignFactsTest reads too, and the same rows for the
// pages line, the brand kit a design follows and the last export kept.

import XCTest
@testable import Canvia

final class DesignFactsTests: XCTestCase {

    private func design(_ object: Any?) throws -> Design {
        try JSONDecoder().decode(Design.self, from: SharedFixture.encoded(try XCTUnwrap(object)))
    }

    func testTheFixtureDesignSaysWhatTheSharedFileSays() throws {
        let fixture = try SharedFixture.object("design-facts")
        let d = try design(fixture["design"])
        for case let row as [String: Any] in try XCTUnwrap(fixture["cases"] as? [Any]) {
            let available = Set(try XCTUnwrap(row["fontsAvailable"] as? [String]))
            let facts = DesignFacts.of(d, fontsAvailable: available)
            XCTAssertEqual(facts.fonts.filter(\.missing).map(\.key), row["missing"] as? [String])
            guard let expected = row["facts"] as? [String: Any] else { continue }
            XCTAssertEqual(facts.typeId, expected["typeId"] as? String)
            XCTAssertEqual(facts.typeName, expected["typeName"] as? String)
            XCTAssertEqual(facts.size, expected["size"] as? String)
            XCTAssertEqual(facts.pixels, expected["pixels"] as? String)
            XCTAssertEqual(facts.pages, expected["pages"] as? Int)
            XCTAssertEqual(facts.hiddenPages, expected["hiddenPages"] as? Int)
            XCTAssertEqual(facts.seconds, expected["seconds"] as? Double)
            XCTAssertEqual(facts.createdAt, expected["createdAt"] as? Double)
            XCTAssertEqual(facts.updatedAt, expected["updatedAt"] as? Double)
            let fonts = try XCTUnwrap(expected["fonts"] as? [[String: Any]]).map { f in
                DesignFacts.Font(key: f["key"] as? String ?? "", name: f["name"] as? String ?? "",
                                 weights: f["weights"] as? [Int] ?? [], missing: f["missing"] as? Bool ?? false)
            }
            XCTAssertEqual(facts.fonts, fonts)
            XCTAssertEqual(facts.photos, expected["photos"] as? Int)
            XCTAssertEqual(facts.videos, expected["videos"] as? Int)
            XCTAssertEqual(facts.audio, expected["audio"] as? Int)
        }
    }

    func testADesignInPixelsSaysItsSizeOnceAndAStillHasNoLength() throws {
        let fixture = try XCTUnwrap(try SharedFixture.object("design-facts")["pixelDesign"] as? [String: Any])
        let facts = DesignFacts.of(try design(fixture["design"]))
        let expected = try XCTUnwrap(fixture["facts"] as? [String: Any])
        XCTAssertEqual(facts.typeId, expected["typeId"] as? String)
        XCTAssertEqual(facts.typeName, expected["typeName"] as? String)
        XCTAssertEqual(facts.size, expected["size"] as? String)
        XCTAssertNil(facts.pixels)
        XCTAssertNil(facts.seconds)
        XCTAssertEqual(facts.pages, 1)
        XCTAssertEqual(facts.hiddenPages, 0)
        XCTAssertEqual(facts.fonts, [])
        XCTAssertEqual(DesignFacts.subtitle(facts), "Instagram Post · 1080 × 1080 px")
    }

    func testASizeOfItsOwnIsACustomSize() throws {
        let fixture = try XCTUnwrap(try SharedFixture.object("design-facts")["customSize"] as? [String: Any])
        let facts = DesignFacts.of(try design(fixture["design"]))
        let expected = try XCTUnwrap(fixture["facts"] as? [String: Any])
        XCTAssertNil(facts.typeId)
        XCTAssertEqual(facts.typeName, expected["typeName"] as? String)
        XCTAssertEqual(facts.size, expected["size"] as? String)
    }

    func testThePagesLineCountsTheHiddenOnesApart() throws {
        var facts = DesignFacts.of(try design(try SharedFixture.object("design-facts")["design"]))
        XCTAssertEqual(DesignFacts.pagesLine(facts), "2 pages, 1 hidden")
        XCTAssertEqual(DesignFacts.weightsLine(try XCTUnwrap(facts.fonts.first)), "400, 700")
        facts.pages = 1
        facts.hiddenPages = 0
        XCTAssertEqual(DesignFacts.pagesLine(facts), "1 page")
    }

    func testTheBrandKitIsTheFirstWhoseLogoIsPlacedElseWhoseFaceAndColourAreBothUsed() {
        var logo = Element.image("media:logo")
        logo.id = "l"
        var words = Element.text("Hi", fontSize: 40)
        words.id = "t"
        words.fontFamily = "lato"
        words.color = "#FF0000"
        var faces = BrandFonts()
        faces.body = BrandFont(family: "lato", weight: 400)
        let byLogo = BrandKit(id: "a", name: "A", logos: ["media:logo"])
        let byLook = BrandKit(id: "b", name: "B", palettes: [BrandPalette(name: "Colours", colors: ["#ff0000"])], fonts: faces)
        let faceOnly = BrandKit(id: "c", name: "C", fonts: faces)
        var d = Design(title: "Kit", width: 1080, height: 1080)
        d.pages = [Page(elements: [words])]
        XCTAssertEqual(DesignFacts.brandKit(d, kits: [faceOnly, byLogo, byLook])?.id, "b")
        var placed = d
        placed.pages = [Page(elements: [words, logo])]
        XCTAssertEqual(DesignFacts.brandKit(placed, kits: [byLook, byLogo])?.id, "a")
        XCTAssertNil(DesignFacts.brandKit(d, kits: [faceOnly, byLogo]))
    }

    func testTheLastExportIsKeptPerDesignAsTheAndroidTwinKeepsIt() {
        var kept = DesignFacts.exported([:], designId: "d2", DesignFacts.LastExport(at: 200, type: "pdf"))
        kept["d1"] = DesignFacts.LastExport(at: 100, type: "png")
        let text = DesignFacts.encodeLastExports(kept)
        XCTAssertEqual(text, #"{"d1":{"at":100,"type":"png"},"d2":{"at":200,"type":"pdf"}}"#)
        XCTAssertEqual(DesignFacts.decodeLastExports(text), kept)
        XCTAssertEqual(DesignFacts.decodeLastExports(#"{"ok":{"at":5,"type":"mp4"},"bad":{"at":"5"},"worse":3}"#),
                       ["ok": DesignFacts.LastExport(at: 5, type: "mp4")])
        XCTAssertEqual(DesignFacts.exportType("png"), "PNG")
        XCTAssertEqual(DesignFacts.exportType("print"), "Print")
        let many = (1...205).reduce(into: [String: DesignFacts.LastExport]()) { acc, i in
            acc = DesignFacts.exported(acc, designId: "d\(i)", DesignFacts.LastExport(at: Int64(i), type: "png"))
        }
        XCTAssertEqual(many.count, DesignFacts.maxLastExports)
        XCTAssertNil(many["d5"])
    }

    /// One that failed is kept with why, after its type and with the type
    /// it had before — the Android twin's DesignFactsTest row.
    func testAFailedExportIsKeptWithWhyItFailedAsTheAndroidTwinKeepsIt() throws {
        let before = ["d1": DesignFacts.LastExport(at: 100, type: "png")]
        let failed = DesignFacts.failedExport(before, designId: "d1",
                                              failure: ExportFailure.Failure(kind: .noSpace, designIds: ["d1"]), at: 300)
        let text = DesignFacts.encodeLastExports(failed)
        XCTAssertEqual(text, #"{"d1":{"at":300,"type":"png","failure":{"kind":"noSpace","designIds":["d1"]}}}"#)
        XCTAssertEqual(DesignFacts.decodeLastExports(text), failed)
        let first = DesignFacts.failedExport([:], designId: "d2",
                                             failure: ExportFailure.Failure(kind: .codec, designIds: ["d2"]), at: 5)
        XCTAssertEqual(DesignFacts.encodeLastExports(first), #"{"d2":{"at":5,"type":"","failure":{"kind":"codec","designIds":["d2"]}}}"#)
        // A later export that works replaces it.
        let later = DesignFacts.exported(failed, designId: "d1", DesignFacts.LastExport(at: 400, type: "pdf"))
        XCTAssertNil(try XCTUnwrap(later["d1"]).failure)
        // Read leniently: a kind unknown is other, an id not words left out,
        // a failure not an object none.
        let read = DesignFacts.decodeLastExports(
            #"{"a":{"at":1,"type":"pdf","failure":{"kind":"lost","designIds":["x",3]}},"b":{"at":2,"type":"png","failure":"no"}}"#)
        XCTAssertEqual(read, [
            "a": DesignFacts.LastExport(at: 1, type: "pdf", failure: ExportFailure.Failure(kind: .other, designIds: ["x"])),
            "b": DesignFacts.LastExport(at: 2, type: "png"),
        ])
    }

    func testAnExportIsRememberedUnderTheSharedKey() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DesignFactsTests"))
        defaults.removePersistentDomain(forName: "DesignFactsTests")
        DesignFacts.rememberExport("d1", type: "mp4", now: Date(timeIntervalSince1970: 1.5), defaults)
        XCTAssertEqual(defaults.string(forKey: "lastExports"), #"{"d1":{"at":1500,"type":"mp4"}}"#)
        XCTAssertEqual(DesignFacts.lastExports(defaults)["d1"]?.type, "mp4")
    }
}
