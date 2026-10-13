// Brand kit v2: several kits in brandkits.json, named palettes, a face per
// text role, the single kit of earlier builds migrated, and a kit as a file.
// The fixtures are the Android twin's BrandKitsTest's, byte for byte, and
// the size, rank and Add text rows are its rows.

import XCTest
@testable import Canvia

final class BrandKitsTests: XCTestCase {

    /// brandkits.json as both phones write it: keys sorted, a role left
    /// unset not written, a size only where one is set.
    static let fixture = ##"{"activeId":"kit-2","kits":[{"fonts":{"body":{"family":"serif","weight":400},"heading":{"family":"impact","weight":800}},"id":"kit-1","logos":["media:img-1"],"name":"My brand","palettes":[{"colors":["#112233","#e94560"],"name":"Colours"}]},{"fonts":{"caption":{"family":"mono","weight":400},"title":{"family":"didone","size":120,"weight":700}},"id":"kit-2","logos":[],"name":"Autumn","palettes":[{"colors":["#5c3d2e"],"name":"Primary"},{"colors":["#e0824b","#f2d8c2"],"name":"Accents"}]}]}"##

    /// The single kit an earlier build kept in brandkit.json, as both
    /// phones wrote it.
    static let legacy = ##"{"bodyFamily":"serif","bodyWeight":400,"colors":["#E94560","#1a1a2e"],"headingFamily":"impact","headingWeight":800,"logos":["media:img-1"]}"##

    func testTheKitsFileReadsAndWritesAsBothPhonesDo() throws {
        let kits = try XCTUnwrap(BrandKits.read(Data(Self.fixture.utf8)))
        XCTAssertEqual(kits.kits.map(\.name), ["My brand", "Autumn"])
        XCTAssertEqual(kits.active.id, "kit-2")
        XCTAssertEqual(kits.active.palettes.map(\.name), ["Primary", "Accents"])
        XCTAssertEqual(kits.active.fonts.title, BrandFont(family: "didone", weight: 700, size: 120))
        XCTAssertNil(kits.active.fonts.heading)
        XCTAssertEqual(kits.kits[0].fonts.heading, BrandFont(family: "impact", weight: 800))
        XCTAssertEqual(kits.active.colors, ["#5c3d2e", "#e0824b", "#f2d8c2"])
        XCTAssertEqual(kits.active.themePalettes.map(\.name), ["Accents"], "a palette of one is no theme")
        XCTAssertEqual(kits.allLogos, ["media:img-1"])

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
        XCTAssertEqual(kit.palettes, [BrandPalette(name: "Colours", colors: ["#e94560", "#1a1a2e"])],
                       "each colour written one way, as the Android twin migrates it")
        XCTAssertEqual(kit.fonts.heading, BrandFont(family: "impact", weight: 800))
        XCTAssertEqual(kit.fonts.body, BrandFont(family: "serif", weight: 400))
        XCTAssertNil(kit.fonts.title)
        XCTAssertEqual(kit.logos, ["media:img-1"])

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
        // Rows both phones check: role, the kit's size (set on a page 1080
        // wide, scaled with the page), the page width, the size added.
        let rows: [(role: BrandFonts.Role, size: Double?, width: Double, expected: Double)] = [
            (.title, nil, 1080, 119),
            (.heading, nil, 1080, 86),
            (.subheading, nil, 1080, 49),
            (.body, nil, 1080, 30),
            (.quote, nil, 1080, 43),
            (.caption, nil, 1080, 24),
            (.heading, 64, 1080, 64),
            (.heading, 64, 1920, 114),
            (.heading, 96, 2160, 192),
            (.body, nil, 1920, 54),
        ]
        for row in rows {
            let el = BrandFonts.element(row.role, face: BrandFont(family: "serif", weight: 600, size: row.size),
                                        pageWidth: row.width)
            XCTAssertEqual(el.fontSize, row.expected, "\(row.role) at \(row.width)")
            XCTAssertEqual(el.text, row.role.addLabel)
            XCTAssertEqual(el.fontFamily, "serif")
            XCTAssertEqual(el.fontWeight, 600)
            XCTAssertEqual(el.w, (row.width * 0.72).rounded())
        }
        XCTAssertEqual(BrandFonts.Role.allCases.map(\.defaultWeight), [700, 700, 600, 400, 400, 400])

        // No face: the role's own size and weight, in the default face.
        let title = BrandFonts.element(.title, face: nil, pageWidth: 1080)
        XCTAssertEqual(title.fontSize, 119, "0.11 of 1080, whole")
        XCTAssertEqual(title.fontWeight, 700)
        XCTAssertEqual(title.fontFamily, Element.text("x").fontFamily)
    }

    func testABrandStyleSetsTheFaceAndTheSizeOnlyWhenTheKitHasOne() {
        var text = Element.text("Words", fontSize: 30)
        text.fontFamily = "sans"
        text.fontWeight = 400
        var heading = text
        BrandFonts.apply(BrandFont(family: "impact", weight: 800), to: &heading, pageWidth: 1080)
        XCTAssertEqual(heading.fontFamily, "impact")
        XCTAssertEqual(heading.fontWeight, 800)
        XCTAssertEqual(heading.fontSize, 30)
        var sized = text
        BrandFonts.apply(BrandFont(family: "didone", weight: 700, size: 96), to: &sized, pageWidth: 1080)
        XCTAssertEqual(sized.fontSize, 96)
        BrandFonts.apply(BrandFont(family: "didone", weight: 700, size: 96), to: &sized, pageWidth: 2160)
        XCTAssertEqual(sized.fontSize, 192, "the kit's size scaled with the page, as Add text scales it")
        let shape = Element.shape("rect")
        var same = shape
        BrandFonts.apply(BrandFont(family: "impact"), to: &same, pageWidth: 1080)
        XCTAssertEqual(same, shape)
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
        // A caption is not a rank: with a heading, every size is the heading's.
        let impact = BrandFont(family: "impact", weight: 800)
        XCTAssertEqual(DesignStore.brandFaces(sizes: [96, 24],
                                              fonts: BrandFonts(heading: impact, caption: BrandFont(family: "mono"))),
                       [96: impact, 24: impact])

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

    /// The row the Android twin's kit-file test checks: a photo or clip logo
    /// the file does not carry is left out, a library picture is kept as
    /// it is.
    func testAKitFileKeepsALibraryLogoAndDropsOneNotCarried() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var kit = BrandKit(id: "kit-9", name: "My brand")
        kit.logos = ["media:img-1", "video:vid-1", "asset:mesh-ocean", "media:img-gone"]
        let contents = BrandKitFile.Contents(kit: kit, media: ["img-1": DesignPackage.Media(ext: "png", data: Data([1, 2, 3, 4]))])
        XCTAssertEqual(BrandKitFile.carried(contents), ["media:img-1", "asset:mesh-ocean"])

        var kits = BrandKits.fresh
        let arrived = try BrandKitFile.import(try JSONEncoder().encode(contents), into: &kits, mediaDirectory: dir)
        XCTAssertEqual(arrived.logos.count, 2)
        XCTAssertTrue(arrived.logos[0].hasPrefix("media:") && arrived.logos[0] != "media:img-1", arrived.logos[0])
        XCTAssertEqual(arrived.logos[1], "asset:mesh-ocean")
    }
}
