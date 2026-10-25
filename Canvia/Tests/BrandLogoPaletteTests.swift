// Brand colours from a logo, and the palette new charts, tables and icons
// take, from the fixture both phones read (Fixtures/brand_logo_palette.json
// and its logo, brand_logo.png, which Tools/generate_brand_logo.py draws —
// the Android twin's BrandLogoPaletteTest).

import UIKit
import XCTest
@testable import Canvia

final class BrandLogoPaletteTests: XCTestCase {

    private func fixture() throws -> [String: Any] { try SharedFixture.object("brand_logo_palette") }

    private func strings(_ key: String, _ o: [String: Any]) throws -> [String] {
        try XCTUnwrap(o[key] as? [String], key)
    }

    /// "#aarrggbb" as RGBA bytes.
    private func rgba(_ hex: String) throws -> [UInt8] {
        let v = try XCTUnwrap(UInt32(hex.dropFirst(), radix: 16), hex)
        return [UInt8((v >> 16) & 0xff), UInt8((v >> 8) & 0xff), UInt8(v & 0xff), UInt8(v >> 24)]
    }

    func testALogosColoursLeaveOutItsClearBackgroundAndALittleWhiteOrBlack() throws {
        for row in try XCTUnwrap(try fixture()["extract"] as? [[String: Any]]) {
            var pixels: [UInt8] = []
            for run in try XCTUnwrap(row["pixels"] as? [[Any]]) {
                let one = try rgba(try XCTUnwrap(run[0] as? String))
                for _ in 0..<(try XCTUnwrap(run[1] as? Int)) { pixels += one }
            }
            XCTAssertEqual(PhotoPalette.logo(pixels), try strings("colors", row), row["name"] as? String ?? "")
        }
    }

    func testTheGeneratedLogoGivesItsNavyAndOrange() throws {
        let png = try XCTUnwrap(try fixture()["png"] as? [String: Any])
        let name = try XCTUnwrap(png["file"] as? String)
        let image = try XCTUnwrap(UIImage(data: try SharedFixture.data(String(name.dropLast(4)), ext: "png")))
        XCTAssertEqual(PhotoPalette.logo(from: image), try strings("colors", png))
    }

    func testNewChartsTakeTheDesignsColoursElseTheKitsElseTheLibrarys() throws {
        for row in try XCTUnwrap(try fixture()["palette"] as? [[String: Any]]) {
            var page = Page(background: .color(try XCTUnwrap(row["background"] as? String)))
            page.elements = try strings("fills", row).map { hex in
                var el = Element.shape("rect")
                el.fill = .solid(hex)
                return el
            }
            let kit = try (row["kit"] as? [[String: Any]]).map { palettes in
                BrandKit(palettes: try palettes.map { p in
                    BrandPalette(name: try XCTUnwrap(p["name"] as? String), colors: try strings("colors", p))
                })
            }
            var design = Design(title: "t", width: 1080, height: 1080)
            design.pages = [page]
            XCTAssertEqual(DataGraphics.palette(for: design, page: page, brand: kit), try strings("colors", row),
                           row["name"] as? String ?? "")
        }
    }

    func testALogosColoursBecomeAPaletteThatSaysWhereTheyCameFrom() throws {
        for row in try XCTUnwrap(try fixture()["logoPalette"] as? [[String: Any]]) {
            var kit = BrandKit()
            kit.addLogoPalette(logo: "media:img-logo1", name: row["name"] as? String, colors: try strings("colors", row))
            let expected = try XCTUnwrap(row["palette"] as? [String: Any])
            let palette = try XCTUnwrap(kit.palettes.last)
            XCTAssertEqual(palette.name, expected["name"] as? String)
            XCTAssertEqual(palette.colors, try strings("colors", expected))
            XCTAssertEqual(palette.source, expected["source"] as? String)
        }
        var bare = BrandKit()
        let before = bare
        bare.addLogoPalette(logo: "media:img-logo1", name: "Acme", colors: [])
        XCTAssertEqual(bare, before)
    }

    func testSourceIsWrittenOnlyWhenSetAndReadBack() throws {
        let plain = String(decoding: try JSONEncoder().encode(BrandPalette(name: "Primary", colors: ["#123456"])),
                           as: UTF8.self)
        XCTAssertFalse(plain.contains("source"))
        let fromLogo = BrandPalette(name: "Acme colours", colors: ["#123456"], source: "logo:img-1")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        let written = String(decoding: try encoder.encode(fromLogo), as: UTF8.self)
        XCTAssertTrue(written.contains("\"source\":\"logo:img-1\""), written)
        XCTAssertEqual(try JSONDecoder().decode(BrandPalette.self, from: Data(written.utf8)), fromLogo)
        XCTAssertNil(try JSONDecoder().decode(BrandPalette.self, from: Data(plain.utf8)).source)
        // A kit carries it through its file and a backup, which write the kit as it is.
        let kits = BrandKits(activeId: "k", kits: [BrandKit(id: "k", palettes: [fromLogo])])
        let read = try XCTUnwrap(BrandKits.read(try JSONEncoder().encode(kits)))
        XCTAssertEqual(read.active.palettes.first?.source, "logo:img-1")
        XCTAssertEqual(BrandKit.logoSource("media:img-9"), "logo:img-9")
    }
}
