// The colour system, checked against WCAG rather than against taste.
//
// Contrast is the part of a palette that quietly rots. Someone nudges a
// neutral to look better in light mode, dark mode goes unreadable, and nobody
// notices until a user with low vision does. These are arithmetic, so they can
// be asserted.
//
// Floors used: 4.5:1 for body-sized text, 3:1 for large text and for the
// boundary of a UI component (WCAG 2.2, 1.4.3 and 1.4.11).

import XCTest
import SwiftUI
import UIKit
@testable import Canvia

final class ThemeTests: XCTestCase {

    private let light = UITraitCollection(userInterfaceStyle: .light)
    private let dark = UITraitCollection(userInterfaceStyle: .dark)

    /// WCAG relative luminance of a colour, resolved for one appearance.
    private func luminance(_ color: Color, _ traits: UITraitCollection) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        func linear(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private func contrast(_ a: Color, on b: Color, _ traits: UITraitCollection) -> Double {
        let (x, y) = (luminance(a, traits), luminance(b, traits))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private func hex(_ color: Color, _ traits: UITraitCollection) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x",
                      Int((r * 255).rounded()), Int((g * 255).rounded()),
                      Int((b * 255).rounded()))
    }

    // MARK: text

    func testPrimaryInkIsReadableOnEverySurface() {
        for (name, traits) in [("light", light), ("dark", dark)] {
            for surface in [Theme.chrome, Theme.card, Theme.workspace] {
                XCTAssertGreaterThanOrEqual(contrast(Theme.ink, on: surface, traits), 4.5,
                                            "primary text, \(name)")
            }
        }
    }

    /// Secondary text is still text. It is the labels under every control in
    /// the toolbar, which are the smallest type in the app.
    func testSecondaryInkIsReadableOnEverySurface() {
        for (name, traits) in [("light", light), ("dark", dark)] {
            for surface in [Theme.chrome, Theme.card, Theme.workspace] {
                XCTAssertGreaterThanOrEqual(contrast(Theme.inkSecondary, on: surface, traits), 4.5,
                                            "secondary text, \(name)")
            }
        }
    }

    // MARK: the accent

    /// The accent marks the selected page, the active control and the button
    /// that adds anything at all — it has to clear the component floor in both
    /// appearances, and it did not in dark mode when it was one fixed colour.
    func testAccentClearsTheComponentFloorInBothAppearances() {
        for (name, traits) in [("light", light), ("dark", dark)] {
            XCTAssertGreaterThanOrEqual(contrast(Theme.accent, on: Theme.workspace, traits), 3,
                                        "accent on workspace, \(name)")
            XCTAssertGreaterThanOrEqual(contrast(Theme.accent, on: Theme.chrome, traits), 3,
                                        "accent on chrome, \(name)")
        }
    }

    /// The insert button is a white glyph on the accent.
    func testWhiteGlyphsAreLegibleOnTheAccent() {
        for (name, traits) in [("light", light), ("dark", dark)] {
            XCTAssertGreaterThanOrEqual(contrast(.white, on: Theme.accent, traits), 3,
                                        "white on accent, \(name)")
            XCTAssertGreaterThanOrEqual(contrast(.white, on: Theme.accentPressed, traits), 3,
                                        "white on pressed accent, \(name)")
        }
    }

    /// Pressing has to be visible, but a jump reads as a different control.
    func testPressedAccentIsDistinctFromTheAccent() {
        for (name, traits) in [("light", light), ("dark", dark)] {
            let shift = contrast(Theme.accent, on: Theme.accentPressed, traits)
            XCTAssertGreaterThan(shift, 1.15, "pressed state invisible, \(name)")
            XCTAssertLessThan(shift, 2.5, "pressed state too loud, \(name)")
        }
    }

    /// Read straight out of the catalog rather than through
    /// Color.accentColor, which resolves against a view's environment and
    /// outside one can answer with the system default instead of the app's.
    private func assetAccent() throws -> Color {
        Color(try XCTUnwrap(UIColor(named: "AccentColor"),
                            "the app has no AccentColor in its asset catalog"))
    }

    /// Canva's own brand purple, which this app deliberately does not ship —
    /// including from the asset catalog, where it outlived the Swift code and
    /// went on tinting every system control in the app.
    func testAccentIsNotACompetitorsBrandColor() throws {
        let asset = try assetAccent()
        for (name, traits) in [("light", light), ("dark", dark)] {
            XCTAssertNotEqual(hex(Theme.accent, traits), "#8b3dff", name)
            XCTAssertNotEqual(hex(asset, traits), "#8b3dff", name)
        }
    }

    /// The asset catalog's AccentColor tints every system control — menus,
    /// alerts, the text cursor. It drifting from Theme.accent is exactly how
    /// an app ends up with two nearly identical purples on one screen.
    func testAssetCatalogAccentMatchesTheThemeAccent() throws {
        let asset = try assetAccent()
        XCTAssertEqual(hex(asset, light), hex(Theme.accent, light))
        XCTAssertEqual(hex(asset, dark), hex(Theme.accent, dark))
    }

    /// Drawn on the page, which is the user's document and can be any colour
    /// at all — so this one is checked against the extremes rather than
    /// against a token: white paper at one end, a near-black background at
    /// the other.
    func testOnPageInkReadsAgainstAnyPageBackground() {
        for traits in [light, dark] {
            XCTAssertGreaterThanOrEqual(contrast(Theme.onPage, on: .white, traits), 4.5)
            XCTAssertGreaterThanOrEqual(contrast(Theme.onPage, on: Color(hex: "#0d1216"), traits), 3)
        }
    }

    /// It is fixed on purpose: resolving per appearance would make it pale on
    /// white paper the moment the app itself was in dark mode.
    func testOnPageInkDoesNotFollowTheAppearance() {
        XCTAssertEqual(hex(Theme.onPage, light), hex(Theme.onPage, dark))
    }

    // MARK: the hero

    /// The hero is a purple slab carrying white type, including the size
    /// labels on its preset tiles, which are the smallest text on the screen.
    func testWhiteTypeIsReadableOnEveryHeroStop() {
        for (index, stop) in Theme.heroStops.enumerated() {
            XCTAssertGreaterThanOrEqual(contrast(.white, on: stop, light), 4.5,
                                        "hero stop \(index)")
        }
    }

    /// Fixed in both appearances on purpose: it is its own dark surface, so
    /// following the app's appearance only lightened it and cost the white
    /// type its contrast.
    func testTheHeroDoesNotFollowTheAppearance() {
        for stop in Theme.heroStops {
            XCTAssertEqual(hex(stop, light), hex(stop, dark))
        }
    }

    // MARK: surfaces

    /// Chrome has to read as a distinct plane from the workspace behind it,
    /// or the toolbars dissolve into the canvas.
    func testChromeSeparatesFromTheWorkspace() {
        for (name, traits) in [("light", light), ("dark", dark)] {
            XCTAssertGreaterThan(contrast(Theme.chrome, on: Theme.workspace, traits), 1.1,
                                 "chrome indistinguishable from workspace, \(name)")
        }
    }

    /// Sheets sit on top of the toolbars, so they have to be a step lighter
    /// again in dark mode — otherwise a sheet and the bar behind it are the
    /// same plane and the sheet has no edge.
    func testCardSitsAboveChrome() {
        XCTAssertGreaterThan(contrast(Theme.card, on: Theme.chrome, dark), 1.05)
    }

    func testNeutralsActuallyChangeBetweenAppearances() {
        for token in [Theme.workspace, Theme.chrome, Theme.card, Theme.ink, Theme.inkSecondary] {
            XCTAssertNotEqual(hex(token, light), hex(token, dark))
        }
    }
}
