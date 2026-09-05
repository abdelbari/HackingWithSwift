// Document themes, blend modes and motion settings.

import XCTest
import SwiftUI
@testable import Canvia

@MainActor
final class ThemeApplyTests: XCTestCase {

    private func pairing() -> FontPairing {
        FontPairing(name: "Test",
                    heading: PairingSpec(fontFamily: "serif", fontWeight: 700, fontSize: 48,
                                         letterSpacing: -1, text: "Heading"),
                    body: PairingSpec(fontFamily: "mono", fontWeight: 400, fontSize: 18,
                                      letterSpacing: nil, text: "Body"))
    }

    private func design() -> Design {
        var d = Design(title: "theme", width: 800, height: 600)
        var big = Element.text("Big", fontSize: 60, w: 400); big.color = "#111111"
        var small = Element.text("small", fontSize: 18, w: 400); small.color = "#eeeeee"
        var rect = Element.shape("rect"); rect.fill = .solid("#ff0000")
        d.pages = [Page(background: .color("#ffffff"), elements: [big, rect]),
                   Page(background: .color("#000000"), elements: [small])]
        return d
    }

    func testThePairingSplitsHeadingsFromBodyBySize() {
        let themed = DesignStore.themed(design(), palette: nil, pairing: pairing())
        let big = themed.pages[0].elements[0], small = themed.pages[1].elements[0]
        XCTAssertEqual(big.fontFamily, "serif"); XCTAssertEqual(big.fontWeight, 700)
        XCTAssertEqual(big.letterSpacing, -1)
        XCTAssertEqual(small.fontFamily, "mono"); XCTAssertEqual(small.fontWeight, 400)
        XCTAssertEqual(big.fontSize, 60, "the pairing changes faces, not the sizes the design chose")
        XCTAssertEqual(themed.pages[0].elements[1].fill, .solid("#ff0000"), "no palette: colours untouched")
    }

    func testThePaletteRecoloursEveryPage() {
        let palette = ["#101010", "#505050", "#a0a0a0", "#f0f0f0"]
        let themed = DesignStore.themed(design(), palette: palette, pairing: nil)
        var seen = Set<String>()
        for page in themed.pages {
            if case .color(let c) = page.background { seen.insert(c) }
            for el in page.elements {
                if let c = el.color { seen.insert(c) }
                if let f = el.fill?.color { seen.insert(f) }
            }
        }
        XCTAssertTrue(seen.isSubset(of: Set(palette)), "\(seen) not all from the palette")
        XCTAssertGreaterThan(seen.count, 1, "the whole design collapsed to one colour")
    }

    func testApplyingIsOneUndoStepAcrossPages() {
        let original = design()
        let s = DesignStore(design: original)
        s.applyTheme(palette: ["#123456", "#abcdef"], pairing: pairing())
        XCTAssertEqual(s.design.pages[1].elements[0].fontFamily, "mono")
        XCTAssertEqual(s.announcement, "Applied theme to all 2 pages")
        s.undo()
        XCTAssertEqual(s.design, original, "one undo restores every page")
    }

    func testANoOpThemeRecordsNothing() {
        let s = DesignStore(design: design())
        s.applyTheme(palette: nil, pairing: nil)
        XCTAssertFalse(s.canUndo)
    }

    // MARK: blend modes

    func testBlendModeNamesRoundTripAndUnknownIsNormal() throws {
        XCTAssertEqual(BlendModes.mode("multiply").swiftUI, .multiply)
        XCTAssertEqual(BlendModes.mode("nonsense").id, "normal")
        XCTAssertTrue(BlendModes.isNormal(nil))
        XCTAssertEqual(BlendModes.svgStyle("screen"), " style=\"mix-blend-mode:screen\"")
        XCTAssertEqual(BlendModes.svgStyle(nil), "")

        var el = Element.shape("rect")
        el.blendMode = "overlay"
        let data = try JSONEncoder().encode(el)
        let back = try JSONDecoder().decode(Element.self, from: data)
        XCTAssertEqual(back.blendMode, "overlay")
    }

    func testTheSVGCarriesTheBlendMode() {
        var d = Design(title: "blend", width: 200, height: 200)
        var el = Element.shape("rect")
        el.blendMode = "multiply"
        d.pages[0].elements = [el]
        let svg = SVGExporter.svg(design: d, page: d.pages[0])
        XCTAssertTrue(svg.contains("mix-blend-mode:multiply"), svg)
    }

    // MARK: motion

    func testMotionSettingsDriveTheExporter() throws {
        var m = MotionSettings()
        m.secondsPerPage = 4
        m.fps = 60
        m.movement = false
        m.crossfade = false
        let s = MovieExporter.Settings(m)
        XCTAssertEqual(s.secondsPerPage, 4)
        XCTAssertEqual(s.fps, 60)
        XCTAssertEqual(s.zoom, 0)
        XCTAssertEqual(s.crossfade, 0)

        let short = MovieExporter.Settings({ var x = MotionSettings(); x.secondsPerPage = 0.5; return x }())
        XCTAssertLessThanOrEqual(short.crossfade, 0.25, "a fade cannot outlast half its page")

        let defaults = MovieExporter.Settings(nil)
        XCTAssertEqual(defaults.secondsPerPage, MovieExporter.Settings().secondsPerPage)
        XCTAssertEqual(defaults.fps, MovieExporter.Settings().fps)

        var d = Design(title: "m", width: 100, height: 100)
        d.motion = m
        let back = try JSONDecoder().decode(Design.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.motion, m, "motion settings are saved with the design")
    }
}
