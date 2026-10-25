// Named brand colours: a palette's optional "names", keyed by upper-case
// "#RRGGBB", over the shared Fixtures/brand-kit-names.json the Android
// twin's BrandColourNamesTest reads.

import XCTest
@testable import Canvia

final class BrandColourNamesTests: XCTestCase {

    private func fixture() throws -> (json: [String: Any], kit: BrandKit) {
        let json = try SharedFixture.object("brand-kit-names")
        let kit = try JSONDecoder().decode(BrandKit.self, from: SharedFixture.encoded(XCTUnwrap(json["kit"])))
        return (json, kit)
    }

    /// Shared: the kit reads, and is written back with the same names —
    /// none for a palette without them.
    func testTheSharedKitRoundTripsWithItsNames() throws {
        let (_, kit) = try fixture()
        XCTAssertEqual(kit.palettes[0].names, ["#1A6BFF": "Ocean", "#F2D7A0": "Sand"])
        XCTAssertTrue(kit.palettes[1].names.isEmpty)
        let written = try JSONEncoder().encode(kit)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        let palettes = try XCTUnwrap(json["palettes"] as? [[String: Any]])
        XCTAssertEqual(palettes[0]["names"] as? [String: String], ["#1A6BFF": "Ocean", "#F2D7A0": "Sand"])
        XCTAssertNil(palettes[1]["names"])
        XCTAssertEqual(try JSONDecoder().decode(BrandKit.self, from: written), kit)
    }

    /// Shared: each colour by its brand name, else its hue's.
    func testEachColourReadsByItsNameOrItsHue() throws {
        let (json, kit) = try fixture()
        let rows = try XCTUnwrap(json["names"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let hex = try XCTUnwrap(row["hex"] as? String)
            XCTAssertEqual(kit.colourName(hex), row["name"] as? String, hex)
            XCTAssertEqual(kit.spokenColour(hex), row["spoken"] as? String, hex)
        }
    }

    /// Shared: 'Rename colour…' from the kit as it is.
    func testRenamingAColour() throws {
        let (json, kit) = try fixture()
        let rows = try XCTUnwrap(json["rename"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            var out = kit
            let palette = try XCTUnwrap(row["palette"] as? Int)
            out.palettes[palette].setName(row["to"] as? String, of: try XCTUnwrap(row["hex"] as? String))
            XCTAssertEqual(out.palettes[palette].keptNames, row["names"] as? [String: String], row["name"] as? String ?? "")
        }
    }

    /// Shared: a colour taken out, or pushed out by newer ones, has no
    /// name — not even when added back.
    func testAColourGoneFromThePaletteHasNoName() throws {
        let (json, kit) = try fixture()
        let rows = try XCTUnwrap(json["gone"] as? [[String: Any]])
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let label = row["name"] as? String ?? ""
            var out = kit
            if let hex = row["remove"] as? String { out.removeColor(hex, palette: 0) }
            for hex in try XCTUnwrap(row["add"] as? [String]) { out.addColor(hex, palette: 0) }
            XCTAssertEqual(out.palettes[0].names, row["names"] as? [String: String], label)
            XCTAssertEqual(out.colourName(try XCTUnwrap(row["probe"] as? String)), row["said"] as? String, label)
        }
    }

    /// Shared: a swap and a guidelines swatch in the brand's words.
    func testSwapsAndGuidelinesSayTheBrandsWords() throws {
        let (json, kit) = try fixture()
        let swaps = try XCTUnwrap(json["swap"] as? [[String: Any]])
        for row in swaps {
            let said = kit.swapLabel(from: try XCTUnwrap(row["from"] as? String), to: try XCTUnwrap(row["to"] as? String))
            XCTAssertEqual(said, row["said"] as? String)
        }
        let swatches = try XCTUnwrap(json["describe"] as? [[String: Any]])
        for row in swatches {
            let words = BrandGuidelines.describe(try XCTUnwrap(row["hex"] as? String), name: row["name"] as? String)
            XCTAssertEqual(words.components(separatedBy: "\n").first, row["first"] as? String)
        }
    }

    func testNamesAreKeyedInCapitalsTrimmedCutAndOnlyForTheColoursThePaletteHas() throws {
        var palette = BrandPalette(name: "Colours", colors: ["#1a6bff", "#abc"])
        palette.setName("  Ocean  ", of: "1a6bff")
        palette.setName(String(repeating: "x", count: 50), of: "#AABBCC")
        palette.setName("Ghost", of: "#000000")
        XCTAssertEqual(palette.name(of: "#1A6BFF"), "Ocean")
        XCTAssertEqual(palette.name(of: "#aabbcc")?.count, BrandPalette.nameLimit)
        XCTAssertNil(palette.keptNames["#000000"], "not one of the palette's colours")
        palette.setName("   ", of: "#1a6bff")
        XCTAssertNil(palette.name(of: "#1a6bff"), "a blank takes the name away")
        // Lowercase keys from another build read as capitals.
        let other = "{\"name\":\"C\",\"colors\":[\"#1a6bff\"],\"names\":{\"#1a6bff\":\"Ocean\",\"#1A6BFF \":7}}"
        let read = try JSONDecoder().decode(BrandPalette.self, from: Data(other.utf8))
        XCTAssertEqual(read.names, ["#1A6BFF": "Ocean"])
    }

    func testABrandGradientIsNamedByItsStops() {
        var kit = BrandKit(id: "k", name: "Sea", palettes: [
            BrandPalette(name: "Colours", colors: ["#1a6bff", "#f2d6a2"], names: ["#1A6BFF": "Ocean", "#F2D6A2": "Sand"]),
        ], fonts: BrandFonts())
        let paint = Paint(kind: "gradient", color: nil, angle: 90,
                          stops: [GradientStop(offset: 0, color: "#1a6bff"), GradientStop(offset: 1, color: "#f2d6a2")])
        XCTAssertEqual(kit.gradientName(paint), "Ocean, Sand")
        kit.palettes[0].setName(nil, of: "#f2d6a2")
        XCTAssertEqual(kit.gradientName(paint), "Ocean, \(ElementNames.spokenColour("#f2d6a2"))")
        XCTAssertEqual(kit.brandColourLabel("#1a6bff"), "Ocean, brand colour")
    }
}
