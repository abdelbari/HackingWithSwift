// Brand kit v2: several kits in brandkits.json, named palettes, a face per
// text role, the single kit of earlier builds migrated, and a kit as a file.
// The fixtures are the Android twin's, byte for byte.

import XCTest
@testable import Canvia

final class BrandKitsTests: XCTestCase {

    /// brandkits.json as both phones write it: keys sorted, a role left
    /// unset not written, a size only where one is set.
    static let fixture = ##"{"activeId":"kit-2","kits":[{"fonts":{"body":{"family":"lora","weight":400},"heading":{"family":"playfair-display","weight":700}},"id":"kit-1","logos":["media:img_logo"],"name":"My brand","palettes":[{"colors":["#1f2430","#ff6b6b"],"name":"Colours"}]},{"fonts":{"caption":{"family":"lora","weight":400},"title":{"family":"anton","size":120,"weight":400}},"id":"kit-2","logos":[],"name":"Autumn","palettes":[{"colors":["#c2410c","#facc15","#14532d"],"name":"Leaves"},{"colors":["#ffffff"],"name":"Accents"}]}]}"##

    /// The single kit an earlier build kept in brandkit.json.
    static let legacy = ##"{"bodyFamily":"lora","bodyWeight":400,"colors":["#ff0000","#00ff00"],"headingFamily":"anton","headingWeight":800,"logos":["media:img_a"]}"##

    func testTheKitsFileReadsAndWritesAsBothPhonesDo() throws {
        let kits = try XCTUnwrap(BrandKits.read(Data(Self.fixture.utf8)))
        XCTAssertEqual(kits.kits.map(\.name), ["My brand", "Autumn"])
        XCTAssertEqual(kits.active.id, "kit-2")
        XCTAssertEqual(kits.active.palettes.map(\.name), ["Leaves", "Accents"])
        XCTAssertEqual(kits.active.fonts.title, BrandFont(family: "anton", weight: 400, size: 120))
        XCTAssertNil(kits.active.fonts.heading)
        XCTAssertEqual(kits.active.colors, ["#c2410c", "#facc15", "#14532d", "#ffffff"])
        XCTAssertEqual(kits.active.themePalettes.map(\.name), ["Leaves"], "a palette of one is no theme")
        XCTAssertEqual(kits.allLogos, ["media:img_logo"])

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(kits), as: UTF8.self), Self.fixture)
    }

    func testAnEarlierBuildsKitBecomesKitOneMyBrand() throws {
        let kits = try XCTUnwrap(BrandKits.migrated(Data(Self.legacy.utf8)))
        XCTAssertEqual(kits.activeId, "kit-1")
        XCTAssertEqual(kits.kits.count, 1)
        let kit = kits.kits[0]
        XCTAssertEqual(kit.id, "kit-1")
        XCTAssertEqual(kit.name, "My brand")
        XCTAssertEqual(kit.palettes, [BrandPalette(name: "Colours", colors: ["#ff0000", "#00ff00"])])
        XCTAssertEqual(kit.fonts.heading, BrandFont(family: "anton", weight: 800))
        XCTAssertEqual(kit.fonts.body, BrandFont(family: "lora", weight: 400))
        XCTAssertNil(kit.fonts.title)
        XCTAssertEqual(kit.logos, ["media:img_a"])

        // No colours: no palette; no weights: 700 and 400.
        let bare = try XCTUnwrap(BrandKits.migrated(Data(#"{"headingFamily":"anton","bodyFamily":"lora"}"#.utf8)))
        XCTAssertEqual(bare.kits[0].palettes, [])
        XCTAssertEqual(bare.kits[0].fonts.heading?.weight, 700)
        XCTAssertEqual(bare.kits[0].fonts.body?.weight, 400)

        // Loading: the new file wins; without it the old one migrates.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let new = dir.appendingPathComponent("brandkits.json")
        let old = dir.appendingPathComponent("brandkit.json")
        try Data(Self.legacy.utf8).write(to: old)
        XCTAssertEqual(BrandKits.load(from: new, legacy: old).active.name, "My brand")
        try Data(Self.fixture.utf8).write(to: new)
        XCTAssertEqual(BrandKits.load(from: new, legacy: old).active.name, "Autumn")
    }

    func testAKitThatDoesNotReadIsPassedOverAndTheActiveOneIsAlwaysThere() throws {
        let json = ##"{"activeId":"gone","kits":[{"id":"a","name":"A","palettes":[{"colors":["#000000"]}],"fonts":{"title":{"weight":700},"body":{"family":"lora"}}},42]}"##
        let kits = try XCTUnwrap(BrandKits.read(Data(json.utf8)))
        XCTAssertEqual(kits.kits.map(\.id), ["a"])
        XCTAssertEqual(kits.activeId, "a", "an active id no kit has is the first kit")
        XCTAssertEqual(kits.active.palettes.first?.name, "Colours", "a palette with no name is Colours")
        XCTAssertNil(kits.active.fonts.title, "a face with no family is no face")
        XCTAssertEqual(kits.active.fonts.body?.weight, 400)
        XCTAssertEqual(BrandKits.read(Data(#"{"kits":[]}"#.utf8)), BrandKits.fresh)
        XCTAssertNil(BrandKits.read(Data("[]".utf8)))
    }

    func testKitsAreAddedRenamedAndRemovedButNeverTheLast() {
        var kits = BrandKits.fresh
        let added = kits.addKit()
        XCTAssertEqual(added.name, "Brand kit")
        XCTAssertEqual(kits.activeId, added.id, "a new kit is the kit in use")
        let second = kits.addKit()
        XCTAssertEqual(second.name, "Brand kit 2")
        kits.removeKit(second.id)
        XCTAssertEqual(kits.kits.count, 2)
        XCTAssertEqual(kits.activeId, "kit-1", "the kit in use gone, the first left is in use")
        kits.removeKit(added.id)
        kits.removeKit("kit-1")
        XCTAssertEqual(kits.kits.map(\.id), ["kit-1"], "the last kit stays")
    }

    func testColoursGoIntoTheirPaletteNewestFirstTwelveAtMost() {
        var kit = BrandKit()
        kit.palettes = [BrandPalette(name: "Colours", colors: []), BrandPalette(name: "Accents", colors: [])]
        for i in 0..<14 { kit.addColor(String(format: "#0000%02x", i), palette: 1) }
        XCTAssertTrue(kit.palettes[0].colors.isEmpty)
        XCTAssertEqual(kit.palettes[1].colors.count, 12)
        XCTAssertEqual(kit.palettes[1].colors.first, "#00000d")
        kit.addColor("#ffffff", palette: 5)
        XCTAssertFalse(kit.colors.contains("#ffffff"), "no such palette: nothing added")
    }

    // MARK: text roles

    func testAddTextOffersTheThreeAlwaysAndTheRolesTheKitSets() {
        var fonts = BrandFonts()
        XCTAssertEqual(fonts.addTextRoles, [.heading, .subheading, .body])
        fonts.caption = BrandFont(family: "lora")
        fonts.title = BrandFont(family: "anton")
        XCTAssertEqual(fonts.addTextRoles, [.title, .heading, .subheading, .body, .caption])
        XCTAssertEqual(BrandFonts.Role.allCases.map(\.addLabel),
                       ["Add a title", "Add a heading", "Add a subheading", "Add body text", "Add a quote", "Add a caption"])
    }

    func testARoleTextTakesTheKitsFaceAndItsSizeScaledFromTenEighty() {
        let face = BrandFont(family: "anton", weight: 400, size: 96)
        let big = BrandFonts.element(.heading, face: face, pageWidth: 2160)
        XCTAssertEqual(big.text, "Add a heading")
        XCTAssertEqual(big.fontFamily, "anton")
        XCTAssertEqual(big.fontWeight, 400)
        XCTAssertEqual(big.fontSize, 192)
        XCTAssertEqual(big.w, 1555)

        // No face: the role's own size and weight, in the default face.
        let body = BrandFonts.element(.body, face: nil, pageWidth: 1080)
        XCTAssertEqual(body.fontSize, 30, "0.028 of 1080, whole")
        XCTAssertEqual(body.fontWeight, 400)
        XCTAssertEqual(body.fontFamily, Element.text("x").fontFamily)
        // A face with no size: the role's size, the face's weight.
        let title = BrandFonts.element(.title, face: BrandFont(family: "lora", weight: 700), pageWidth: 1080)
        XCTAssertEqual(title.fontSize, 108)
        XCTAssertEqual(title.fontWeight, 700)
        XCTAssertEqual(BrandFonts.element(.title, face: nil, pageWidth: 1080).fontWeight, 800)
    }

    /// The theme's rule: sizes, largest first, take the kit's ranked roles
    /// in turn; every size past the last role takes the last.
    func testTheThemeGivesTextSizesTheBrandFacesByRank() {
        var fonts = BrandFonts()
        XCTAssertTrue(DesignStore.brandFaces(sizes: [96, 24], fonts: fonts).isEmpty)
        fonts.quote = BrandFont(family: "caveat")
        XCTAssertTrue(DesignStore.brandFaces(sizes: [96, 24], fonts: fonts).isEmpty, "a quote is not a rank")

        let title = BrandFont(family: "anton", weight: 400)
        let body = BrandFont(family: "lora", weight: 400)
        fonts.title = title
        fonts.body = body
        let rows: [(sizes: [Double], expected: [Double: BrandFont])] = [
            ([96, 48, 48, 24, 18], [96: title, 48: body, 24: body, 18: body]),
            ([40], [40: title]),
            ([], [:]),
        ]
        for row in rows {
            XCTAssertEqual(DesignStore.brandFaces(sizes: row.sizes, fonts: fonts), row.expected, "\(row.sizes)")
        }
        let heading = BrandFont(family: "playfair-display", weight: 700)
        let sub = BrandFont(family: "lora", weight: 600)
        let three = BrandFonts(heading: heading, subheading: sub, body: body)
        XCTAssertEqual(DesignStore.brandFaces(sizes: [18, 96, 24, 48], fonts: three),
                       [96: heading, 48: sub, 24: body, 18: body])

        var d = Design(title: "Theme")
        var big = Element.text("Big", fontSize: 96, w: 800)
        big.fontFamily = "sans"
        let small = Element.text("Small", fontSize: 24, w: 800)
        d.pages = [Page(elements: [big]), Page(elements: [small])]
        let themed = DesignStore.themed(d, palette: nil, pairing: nil, brandFonts: fonts)
        XCTAssertEqual(themed.pages[0].elements[0].fontFamily, "anton")
        XCTAssertEqual(themed.pages[0].elements[0].fontSize, 96, "sizes stay as they are")
        XCTAssertEqual(themed.pages[1].elements[0].fontFamily, "lora", "ranked across every page")
    }

    // MARK: a kit as a file

    func testAKitTravelsAsAFileWithItsLogosInside() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let bytes = Data([0xff, 0xd8, 0xff, 0xe0, 9, 8, 7])
        try bytes.write(to: dir.appendingPathComponent("img_logo.jpg"))

        var kit = BrandKit(id: "kit-1", name: "My brand")
        kit.addColor("#123456")
        kit.fonts.heading = BrandFont(family: "anton", weight: 400, size: 80)
        kit.logos = ["media:img_logo", "asset:sun"]
        let data = try BrandKitFile.export(kit, mediaDirectory: dir)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(raw["format"] as? String, "canvia-brand")
        XCTAssertEqual(raw["version"] as? Int, 1)

        var kits = BrandKits.fresh
        let arrived = try BrandKitFile.import(data, into: &kits, mediaDirectory: dir)
        XCTAssertNotEqual(arrived.id, "kit-1", "a kit of its own")
        XCTAssertEqual(arrived.name, "My brand 2", "under a name no kit here has")
        XCTAssertEqual(kits.activeId, arrived.id)
        XCTAssertEqual(arrived.palettes, kit.palettes)
        XCTAssertEqual(arrived.fonts, kit.fonts)
        XCTAssertEqual(arrived.logos.count, 2)
        let moved = arrived.logos[0]
        XCTAssertTrue(moved.hasPrefix("media:") && moved != "media:img_logo", moved)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("\(moved.dropFirst(6)).jpg")), bytes)
        XCTAssertEqual(arrived.logos[1], "asset:sun", "a library picture this app cannot draw stays a reference")

        var refused = false
        do {
            try BrandKitFile.import(Data("{}".utf8), into: &kits, mediaDirectory: dir)
        } catch {
            refused = true
        }
        XCTAssertTrue(refused, "not a kit")
        XCTAssertEqual(kits.kits.count, 2)
    }
}
