// Brand text styles in full: a role's colour (a hex or one of the kit's
// colours by "palette:<p>:<c>"), letter spacing, line spacing, capitals and
// italic, and the Subtitle and Section header roles. The kit fixture is the
// Android twin's BrandTextStylesTest's, byte for byte.

import XCTest
@testable import Canvia

final class BrandTextStylesTests: XCTestCase {

    /// A kit with the new keys, as both phones write it: keys sorted, every
    /// key optional.
    static let fixture = ##"{"activeId":"kit-1","kits":[{"fonts":{"body":{"family":"serif","lineHeight":1.5,"weight":400},"sectionHeader":{"color":"palette:0:1","family":"sans","letterSpacing":4,"uppercase":true,"weight":600},"subtitle":{"color":"#336699","family":"sans","italic":true,"size":54,"weight":500}},"id":"kit-1","logos":[],"name":"My brand","palettes":[{"colors":["#112233","#e94560"],"name":"Colours"}]}]}"##

    func testTheKitWithTypeSettingsReadsAndWritesAsBothPhonesDo() throws {
        let kits = try XCTUnwrap(BrandKits.read(Data(Self.fixture.utf8)))
        let fonts = kits.active.fonts
        XCTAssertEqual(fonts.subtitle, BrandFont(family: "sans", weight: 500, size: 54, color: "#336699", italic: true))
        XCTAssertEqual(fonts.sectionHeader, BrandFont(family: "sans", weight: 600, color: "palette:0:1",
                                                      letterSpacing: 4, uppercase: true))
        XCTAssertEqual(fonts.body?.lineHeight, 1.5)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(kits), as: UTF8.self), Self.fixture)
    }

    func testAnOldKitReadsUnchanged() throws {
        let kits = try XCTUnwrap(BrandKits.read(Data(BrandKitsTests.fixture.utf8)))
        XCTAssertNil(kits.kits[0].fonts.heading?.color)
        XCTAssertNil(kits.kits[0].fonts.subtitle)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(String(decoding: try encoder.encode(kits), as: UTF8.self), BrandKitsTests.fixture)
    }

    func testTheRolesAreInCanvasOrderAndBySize() {
        XCTAssertEqual(BrandFonts.Role.allCases.map(\.rawValue),
                       ["title", "subtitle", "heading", "subheading", "sectionHeader", "body", "quote", "caption"])
        XCTAssertEqual(BrandFonts.Role.bySize.map(\.rawValue),
                       ["title", "subtitle", "heading", "subheading", "sectionHeader", "body"],
                       "the Android twin's BrandRoles.BY_SIZE")
        XCTAssertEqual(BrandFonts.Role.subtitle.widthFraction, 0.05)
        XCTAssertEqual(BrandFonts.Role.sectionHeader.widthFraction, 0.035)
        XCTAssertEqual(BrandFonts.Role.subtitle.defaultWeight, 500)
        XCTAssertEqual(BrandFonts.Role.sectionHeader.defaultWeight, 600)
        let heading = BrandFont(family: "impact", weight: 800)
        var fonts = BrandFonts()
        fonts.heading = heading
        XCTAssertEqual(fonts.fontFor(.subtitle), heading, "a subtitle falls back to the heading's face")
        XCTAssertEqual(fonts.fontFor(.sectionHeader), heading)
        XCTAssertEqual(fonts.rankedRoles, [.heading])
        fonts.subtitle = BrandFont(family: "lora", weight: 500)
        fonts.caption = BrandFont(family: "inter", weight: 400)
        XCTAssertEqual(fonts.rankedRoles, [.subtitle, .heading], "a subtitle ranks after the title, a caption not at all")
    }

    func testAddedTextTakesEveryTypeSettingTheRoleSets() throws {
        let kits = try XCTUnwrap(BrandKits.read(Data(Self.fixture.utf8)))
        let kit = kits.active
        let subtitle = BrandFonts.element(.subtitle, face: kit.fonts.subtitle, pageWidth: 2160, palettes: kit.palettes)
        XCTAssertEqual(subtitle.fontSize, 108)
        XCTAssertEqual(subtitle.fontWeight, 500)
        XCTAssertEqual(subtitle.color, "#336699")
        XCTAssertEqual(subtitle.italic, true)
        XCTAssertNil(subtitle.uppercase)
        let header = BrandFonts.element(.sectionHeader, face: kit.fonts.sectionHeader, pageWidth: 2160,
                                        palettes: kit.palettes)
        XCTAssertEqual(header.color, "#e94560", "palette 0, colour 1")
        XCTAssertEqual(header.letterSpacing, 8, "4 on a page 1080 wide, scaled as the size is")
        XCTAssertEqual(header.uppercase, true)
        let body = BrandFonts.element(.body, face: kit.fonts.body, pageWidth: 1080, palettes: kit.palettes)
        XCTAssertEqual(body.lineHeight, 1.5)
        XCTAssertEqual(body.letterSpacing, 0, "no spacing set: the new text's own")
    }

    func testASectionHeaderWithNoFaceIsInCapitalsSpacedOut() {
        let header = BrandFonts.element(.sectionHeader, face: nil, pageWidth: 1000)
        XCTAssertEqual(header.fontSize, 35)
        XCTAssertEqual(header.uppercase, true)
        XCTAssertEqual(header.letterSpacing ?? 0, 2.8, accuracy: 1e-9, "0.08 em")
        XCTAssertEqual(header.fontWeight, 600)
    }

    func testAPaletteColourIsReadFromTheKit() {
        let palettes = [BrandPalette(name: "Colours", colors: ["#111111", "#222222"])]
        XCTAssertEqual(BrandFont.resolved("palette:0:1", palettes: palettes), "#222222")
        XCTAssertNil(BrandFont.resolved("palette:1:0", palettes: palettes), "a colour the kit no longer has")
        XCTAssertNil(BrandFont.resolved("palette:x", palettes: palettes))
        XCTAssertEqual(BrandFont.resolved("#abcdef", palettes: palettes), "#abcdef")
        XCTAssertNil(BrandFont.resolved(nil, palettes: palettes))
    }

    func testTheGuidelinesSayTheRestOfARolesType() throws {
        let kit = try XCTUnwrap(BrandKits.read(Data(Self.fixture.utf8))).active
        XCTAssertEqual(BrandGuidelines.attributes(kit, .sectionHeader, kit.fonts.sectionHeader),
                       ["#E94560", "Spacing 12.99", "Uppercase"])
        XCTAssertEqual(BrandGuidelines.attributes(kit, .body, kit.fonts.body), ["Line 1.5"])
        XCTAssertEqual(BrandGuidelines.attributes(kit, .heading, nil), [])
        XCTAssertEqual(BrandGuidelines.number(1.25), "1.25")
        XCTAssertEqual(BrandGuidelines.number(-0.5), "-0.5")
        XCTAssertEqual(BrandGuidelines.number(3), "3")
    }

    /// Shared with the Android twin's BrandTextStylesTest
    /// (Fixtures/brand-text-styles.json, byte for byte): the kit goes round
    /// as it came, and the guidelines say the same of each role, its face as
    /// Add text finds it.
    func testTheSharedKitAndItsGuidelinesReadTheSameOnBothPhones() throws {
        let fixture = try SharedFixture.object("brand-text-styles")
        let kits = try XCTUnwrap(BrandKits.read(SharedFixture.encoded(try XCTUnwrap(fixture["kits"]))))
        let again = try XCTUnwrap(BrandKits.read(JSONEncoder().encode(kits)))
        XCTAssertEqual(again, kits)
        let kit = kits.active
        XCTAssertEqual(kit.fonts.body, BrandFont(family: "serif", weight: 400, letterSpacing: -1.25, lineHeight: 1.5, italic: true))
        let rows = try XCTUnwrap(fixture["attributes"] as? [String: [String]])
        XCTAssertEqual(Set(rows.keys), Set(BrandFonts.Role.allCases.map(\.rawValue)))
        for role in BrandFonts.Role.allCases {
            XCTAssertEqual(BrandGuidelines.attributes(kit, role, kit.fonts.fontFor(role)), rows[role.rawValue], role.rawValue)
        }
    }
}
