// Named brand colours: a palette's optional "names", keyed by upper-case
// "#RRGGBB", over the shared Fixtures/brand-kit-names.json the Android
// twin's BrandKitsTest reads.

import XCTest
@testable import Canvia

final class BrandColourNamesTests: XCTestCase {

    /// Shared: the file reads, and is written back with the same names —
    /// none for a palette without them.
    func testTheSharedKitRoundTripsWithItsNames() throws {
        let data = try SharedFixture.data("brand-kit-names")
        let kits = try JSONDecoder().decode(BrandKits.self, from: data)
        let kit = try XCTUnwrap(kits.kits.first)
        XCTAssertEqual(kit.palettes[0].names, ["#1A6BFF": "Ocean", "#F2D6A2": "Sand"])
        XCTAssertTrue(kit.palettes[1].names.isEmpty)
        let written = try JSONEncoder().encode(kits)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: written) as? [String: Any])
        let palettes = try XCTUnwrap(((json["kits"] as? [[String: Any]])?.first)?["palettes"] as? [[String: Any]])
        XCTAssertEqual(palettes[0]["names"] as? [String: String], ["#1A6BFF": "Ocean", "#F2D6A2": "Sand"])
        XCTAssertNil(palettes[1]["names"])
        XCTAssertEqual(try JSONDecoder().decode(BrandKits.self, from: written), kits)
        // The kit's readouts in the brand's words.
        XCTAssertEqual(kit.colourName("#1a6bff"), "Ocean")
        XCTAssertNil(kit.colourName("#0b1f33"))
        XCTAssertEqual(kit.swapLabel(from: "#1A6BFF", to: "#f2d6a2"), "Ocean → Sand")
        XCTAssertEqual(kit.swapLabel(from: "#0b1f33", to: "#1a6bff"), "#0B1F33 → Ocean")
        XCTAssertEqual(BrandGuidelines.describe("#1a6bff", name: kit.colourName("#1a6bff")).split(separator: "\n").first, "Ocean")
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
        XCTAssertEqual(kit.gradientName(paint), "Ocean to Sand")
        kit.palettes[0].setName(nil, of: "#f2d6a2")
        XCTAssertNil(kit.gradientName(paint))
        XCTAssertEqual(kit.brandColourLabel("#1a6bff"), "Ocean, brand colour")
    }
}
