// Brand kit v2: several kits in brandkits.json, named palettes, a face per
// text role, the single kit of earlier builds migrated, and a kit as a file
// — and its photos, graphics and templates, with the kit file that carries
// them.
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
        XCTAssertEqual(kits.allAssets, ["media:img-1"])

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
                       ["Add a title", "Add a subtitle", "Add a heading", "Add a subheading", "Add a section header",
                        "Add body text", "Add a quote", "Add a caption"])
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
        XCTAssertEqual(BrandFonts.Role.allCases.map(\.defaultWeight), [700, 500, 700, 600, 600, 400, 400, 400])

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

    /// The file the Android twin's kit-file test reads too: a kit file
    /// that does carry a clip, as an earlier build wrote them.
    static let kitCarryingAClip = #"{"format":"canvia-brand","kit":{"id":"kit-7","logos":["media:img-1","video:vid-1","asset:mesh-ocean"],"name":"Clips"},"media":{"img-1":{"data":"AQIDBA==","ext":"png"}},"version":1,"videos":{"vid-1":{"data":"AAAAGGZ0eXA=","ext":"mp4"}}}"#

    /// No kit file carries a clip, on either phone: a clip logo goes out as
    /// its name only, and arrives nowhere — even from a file that does carry
    /// the clip. The photo and the library picture arrive, as on Android.
    func testAKitFileLeavesOutEveryClipLogo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data(Self.kitCarryingAClip.utf8)
        let contents = try JSONDecoder().decode(BrandKitFile.Contents.self, from: data)
        XCTAssertEqual(BrandKitFile.carried(contents), ["media:img-1", "asset:mesh-ocean"])
        var kits = BrandKits.fresh
        let arrived = try BrandKitFile.import(data, into: &kits, mediaDirectory: dir)
        XCTAssertEqual(arrived.name, "Clips")
        XCTAssertEqual(arrived.logos.count, 2)
        XCTAssertTrue(arrived.logos[0].hasPrefix("media:") && arrived.logos[0] != "media:img-1", arrived.logos[0])
        XCTAssertEqual(arrived.logos[1], "asset:mesh-ocean")

        // Going out, a clip logo is its name: neither the clip nor a still.
        let id = try XCTUnwrap(VideoStore.store(Data([0, 0, 0, 24, 102, 116, 121, 112]), ext: "mp4"))
        defer { VideoStore.delete(id) }
        var kit = BrandKit(id: "kit-8", name: "Clips")
        kit.logos = [VideoStore.src(id, at: nil), "asset:sun"]
        let out = BrandKitFile.contents(of: kit, mediaDirectory: dir)
        XCTAssertEqual(out.kit.logos, kit.logos)
        XCTAssertTrue(out.media.isEmpty)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: BrandKitFile.export(kit, mediaDirectory: dir)) as? [String: Any])
        XCTAssertNil(raw["videos"])
    }

    /// The row the Android twin's kit-file test checks: a photo logo the
    /// file does not carry, or a clip logo, is left out, a library picture
    /// is kept as it is.
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

    // MARK: photos, graphics and templates

    /// A kit with photos, graphics and templates, as both phones write it:
    /// each list only when it has something.
    static let assetsFixture = ##"{"activeId":"kit-3","kits":[{"fonts":{},"graphics":["svg:img-2","media:img-3"],"id":"kit-3","logos":[],"name":"Studio","palettes":[],"photos":["media:img-1","asset:mesh-ocean"],"templates":["tpl-1","tpl-2"]}]}"##

    func testPhotosGraphicsAndTemplatesReadAndWriteAsBothPhonesDo() throws {
        let kits = try XCTUnwrap(BrandKits.read(Data(Self.assetsFixture.utf8)))
        let kit = kits.active
        XCTAssertEqual(kit.photos, ["media:img-1", "asset:mesh-ocean"])
        XCTAssertEqual(kit.graphics, ["svg:img-2", "media:img-3"])
        XCTAssertEqual(kit.templates, ["tpl-1", "tpl-2"])
        XCTAssertFalse(kit.isEmpty)
        XCTAssertTrue(kit.showsBrandTab)
        XCTAssertEqual(kits.allAssets, ["media:img-1", "asset:mesh-ocean", "media:img-2", "media:img-3"],
                       "an SVG graphic kept as the media file it is")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(kits), as: UTF8.self), Self.assetsFixture)
    }

    /// Missing keys are empty lists, so every earlier kit file still reads
    /// — and is written back as it was, with no empty lists added.
    func testAKitWithoutTheNewKeysStillReads() throws {
        let kits = try XCTUnwrap(BrandKits.read(Data(Self.fixture.utf8)))
        for kit in kits.kits {
            XCTAssertEqual(kit.photos, [])
            XCTAssertEqual(kit.graphics, [])
            XCTAssertEqual(kit.templates, [])
        }
        let odd = ##"{"kits":[{"id":"a","name":"A","logos":[],"photos":3,"graphics":[true],"templates":"tpl-1"}]}"##
        let lenient = try XCTUnwrap(BrandKits.read(Data(odd.utf8)))
        XCTAssertEqual(lenient.active.photos, [], "a list of another type reads as none")
        XCTAssertEqual(lenient.active.graphics, [])
        XCTAssertEqual(lenient.active.templates, [])
        let written = String(decoding: try JSONEncoder().encode(lenient.active), as: UTF8.self)
        XCTAssertFalse(written.contains("photos") || written.contains("graphics") || written.contains("templates"),
                       written)
    }

    func testTheBrandTabShowsWhatTheKitHasAndTemplatesLeadInKitOrder() {
        var kit = BrandKit(id: "k", name: "Studio")
        XCTAssertFalse(kit.showsBrandTab)
        kit.templates = ["tpl-2"]
        XCTAssertFalse(kit.showsBrandTab, "templates alone lead the Templates panel instead")
        XCTAssertFalse(kit.isEmpty)
        kit.add("media:img-1", to: \.photos)
        kit.add("media:img-1", to: \.photos)
        XCTAssertEqual(kit.photos, ["media:img-1"], "once")
        XCTAssertTrue(kit.showsBrandTab)
        XCTAssertTrue(BrandKit(fonts: BrandFonts(body: BrandFont(family: "lora"))).showsBrandTab)

        XCTAssertEqual(kit.templatesTitle, "From Studio")
        kit.templates = ["tpl-2", "tpl-gone", "tpl-1"]
        let entries = ["tpl-1", "tpl-2", "tpl-3"].map {
            UserTemplate(id: $0, name: $0, category: "Personal", width: 1080, height: 1080, pageCount: 1, updatedAt: 0)
        }
        XCTAssertEqual(kit.templateEntries(entries).map(\.id), ["tpl-2", "tpl-1"],
                       "in the kit's order; an id with no template here passed over")
        XCTAssertEqual(kit.otherEntries(entries).map(\.id), ["tpl-3"], "Your templates: the rest, once each")
    }

    /// A brand colour tapped in the Brand tab: the rows of the Android
    /// twin's BrandColourTest. Nothing selected, it is the page's
    /// background; selected, what is unlocked takes it, the background left;
    /// the same again is no step; a locked page keeps its background.
    @MainActor
    func testABrandColourPaintsTheSelectionElseTheBackground() {
        var text = Element.text("Sale")
        text.color = "#000000"
        var locked = Element.shape("rect")
        locked.locked = true
        let shape = Element.shape("rect")
        var design = Design(title: "Brand", width: 1000, height: 1000)
        design.pages[0].elements = [text, shape, locked]
        let store = DesignStore(design: design)
        store.paintBrandColour("#e94560")
        XCTAssertEqual(store.page.background, .color("#e94560"))
        store.paintBrandColour("#e94560")
        store.undo()
        XCTAssertEqual(store.page.background, design.pages[0].background, "the same colour again was no step")

        store.select(text.id)
        store.select(shape.id, additive: true)
        store.select(locked.id, additive: true)
        store.paintBrandColour("#112233")
        XCTAssertEqual(store.page.elements[0].color, "#112233")
        XCTAssertNil(store.page.elements[0].textFill)
        XCTAssertEqual(store.page.elements[1].fill, .solid("#112233"))
        XCTAssertEqual(store.page.elements[2].fill, locked.fill)
        XCTAssertEqual(store.page.background, design.pages[0].background, "the background left as it was")

        design.pages[0].locked = true
        let shut = DesignStore(design: design)
        shut.paintBrandColour("#e94560")
        XCTAssertEqual(shut.page.background, design.pages[0].background)
        XCTAssertFalse(shut.canUndo)
    }

    func testDeletingATemplateTakesItOutOfEveryKit() {
        var kits = BrandKits.fresh
        kits.kits[0].templates = ["tpl-1", "tpl-2"]
        var other = kits.addKit()
        other.templates = ["tpl-2"]
        kits.update(other)
        XCTAssertTrue(kits.removeTemplate("tpl-2"))
        XCTAssertEqual(kits.kits.map(\.templates), [["tpl-1"], []])
        XCTAssertFalse(kits.removeTemplate("tpl-9"), "no kit had it: nothing to save")
    }

    func testAPictureIsAddedFromTheDesignButNotAClipACodeOrAnEmptyFrame() {
        XCTAssertEqual(BrandKit.picture(of: Element.image("media:img-1")), "media:img-1")
        XCTAssertEqual(BrandKit.picture(of: Element.image("asset:sun")), "asset:sun")
        XCTAssertNil(BrandKit.picture(of: Element.image("")))
        XCTAssertNil(BrandKit.picture(of: Element.image(VideoStore.src("vid-1", at: nil))))
        XCTAssertNil(BrandKit.picture(of: Element.text("Words")))
        XCTAssertEqual(BrandKit.svgID("svg:img-2"), "img-2")
        XCTAssertNil(BrandKit.svgID("media:img-2"))
        XCTAssertNil(BrandKit.svgID("svg:"))
        XCTAssertEqual(BrandKit.mediaSource("svg:img-2"), "media:img-2")
        XCTAssertEqual(BrandKit.mediaSource("asset:sun"), "asset:sun")
    }

    /// The kit file both phones' tests read (BrandKitsTest on Android): a
    /// logo, two photos it carries and one it does not, an SVG graphic and
    /// a picture graphic, and a template's id.
    static let kitFileWithAssets = ##"{"format":"canvia-brand","kit":{"fonts":{"heading":{"family":"anton","weight":400}},"graphics":["svg:img-g1","media:img-g2"],"id":"kit-5","logos":["media:img-l1"],"name":"Studio","palettes":[{"colors":["#e94560"],"name":"Colours"}],"photos":["media:img-p1","asset:mesh-ocean","media:img-gone"],"templates":["tpl-1"]},"media":{"img-g1":{"data":"PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCAxMCAxMCI+PHJlY3Qgd2lkdGg9IjEwIiBoZWlnaHQ9IjEwIiBmaWxsPSIjZTk0NTYwIi8+PC9zdmc+","ext":"svg"},"img-g2":{"data":"iVBORw==","ext":"png"},"img-l1":{"data":"iVBORw==","ext":"png"},"img-p1":{"data":"/9j/4A==","ext":"jpg"}},"version":1}"##

    func testAKitFileWithPhotosAndGraphicsArrivesFromTheOtherPhone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var kits = BrandKits.fresh
        let arrived = try BrandKitFile.import(Data(Self.kitFileWithAssets.utf8), into: &kits, mediaDirectory: dir)
        XCTAssertEqual(arrived.name, "Studio")
        XCTAssertEqual(kits.activeId, arrived.id)
        XCTAssertEqual(arrived.templates, ["tpl-1"], "a template's id travels as it is")
        XCTAssertEqual(arrived.fonts.heading, BrandFont(family: "anton", weight: 400))

        func file(_ src: String, _ ext: String) throws -> Data {
            XCTAssertTrue(src.hasPrefix("media:"), src)
            return try Data(contentsOf: dir.appendingPathComponent("\(src.dropFirst(6)).\(ext)"))
        }
        XCTAssertEqual(arrived.logos.count, 1)
        XCTAssertNotEqual(arrived.logos[0], "media:img-l1", "under a fresh id")
        XCTAssertEqual(try file(arrived.logos[0], "png"), Data([0x89, 0x50, 0x4e, 0x47]))

        XCTAssertEqual(arrived.photos.count, 2, "the photo the file does not carry is left out")
        XCTAssertEqual(try file(arrived.photos[0], "jpg"), Data([0xff, 0xd8, 0xff, 0xe0]))
        XCTAssertEqual(arrived.photos[1], "asset:mesh-ocean")

        XCTAssertEqual(arrived.graphics.count, 2)
        let svg = try XCTUnwrap(BrandKit.svgID(arrived.graphics[0]), arrived.graphics[0])
        XCTAssertNotEqual(svg, "img-g1")
        let text = String(decoding: try Data(contentsOf: dir.appendingPathComponent("\(svg).svg")), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("<svg"), text)
        XCTAssertNotNil(SvgImport.graphic(text, pageWidth: 1080, pageHeight: 1080), "placed through SvgImport")
        XCTAssertEqual(try file(arrived.graphics[1], "png"), Data([0x89, 0x50, 0x4e, 0x47]))
    }

    func testAKitsPhotosAndGraphicsTravelInsideItsFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4"/></svg>"#.utf8)
        try svg.write(to: dir.appendingPathComponent("img_s.svg"))
        try Data([0xff, 0xd8, 0xff, 0xe0, 1]).write(to: dir.appendingPathComponent("img_p.jpg"))
        try Data([0x89, 0x50, 0x4e, 0x47, 2]).write(to: dir.appendingPathComponent("img_l.png"))

        var kit = BrandKit(id: "kit-6", name: "Studio")
        kit.logos = ["media:img_l"]
        kit.photos = ["media:img_p", VideoStore.src("vid-1", at: nil)]
        kit.graphics = ["svg:img_s"]
        kit.templates = ["tpl-1"]
        let contents = BrandKitFile.contents(of: kit, mediaDirectory: dir)
        XCTAssertEqual(contents.kit.graphics, ["svg:img_s"], "an SVG graphic keeps its source")
        XCTAssertEqual(contents.media["img_s"]?.ext, "svg")
        XCTAssertEqual(contents.media["img_s"]?.data, svg)
        XCTAssertEqual(contents.media["img_p"]?.ext, "jpg")
        XCTAssertEqual(contents.media["img_l"]?.ext, "png")
        XCTAssertEqual(contents.kit.templates, ["tpl-1"])

        var kits = BrandKits.fresh
        let arrived = try BrandKitFile.import(BrandKitFile.export(kit, mediaDirectory: dir), into: &kits,
                                             mediaDirectory: dir)
        XCTAssertEqual(arrived.photos.count, 1, "a clip is in no kit file")
        XCTAssertEqual(arrived.logos.count, 1)
        let id = try XCTUnwrap(BrandKit.svgID(arrived.graphics.first ?? ""))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("\(id).svg")), svg)
    }
}
