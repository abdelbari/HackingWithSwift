// The colour system.
//
// Before this file there were 24 raw hex literals spread over 12 files, four
// different purples standing in for "the accent" (#8b3dff, #7c2ae8, #7300e6,
// #7d2ae8), and no dark mode anywhere. Two consequences: the app could not be
// restyled without a find-and-replace across the whole tree, and it read as
// assembled rather than designed, because nothing quite matched anything else.
//
// Colours resolve per appearance through UIColor's trait-aware initialiser,
// so dark mode falls out of using the tokens rather than needing a second pass
// over every call site. Only the magenta snap guide is one fixed colour in
// both appearances: it is drawn over page content, not over app chrome, so it
// has no appearance to adapt to.

import SwiftUI
import UIKit

enum Theme {

    // MARK: brand

    /// Canvia's accent. Deliberately not #8b3dff: that is Canva's own brand
    /// purple, and shipping a competitor's exact brand colour in the same
    /// product category is a trademark exposure, not a style choice.
    ///
    /// Lifted in dark mode. #5a31f4 on the dark workspace is 2.9:1, under the
    /// 3:1 WCAG floor for a UI component — which is not a detail on the one
    /// colour that marks every selected page, every active control and the
    /// button that adds anything at all. The lighter value is 5.2:1 there,
    /// and still carries white glyphs at 3.7:1.
    static let accent = dynamic(light: brandHex, dark: "#8f6bff")

    /// The brand purple itself, unadapted. Used where the surface is already
    /// its own dark plane in both appearances — the home hero — and so has no
    /// appearance to follow.
    static let brand = Color(hex: brandHex)
    private static let brandHex = "#5a31f4"
    static let accentPressed = dynamic(light: "#4826c9", dark: "#6f4ae0")
    static let accentSubtle = dynamic(light: "#ede7ff", dark: "#241c4a")
    /// Magenta reads clearly against both the accent and any page content.
    /// Fixed in both appearances: it is drawn over the page, which has its own
    /// background, so there is no app appearance for it to adapt to.
    static let guide = Color(hex: "#ff2d9e")

    /// The home hero. A tight indigo-to-violet ramp rather than a rainbow, so
    /// it reads as one deliberate colour, starting from the brand purple.
    ///
    /// Fixed in both appearances. Built from the appearance-aware accent it
    /// lightened in dark mode — the accent is lifted there to carry against a
    /// near-black workspace — and the hero is not on that workspace, it is its
    /// own purple slab with white type on it. Lightening it only pushed that
    /// type from 6.6:1 to 3.7:1.
    static let heroStops: [Color] = [brand, Color(hex: "#7b4dff"), Color(hex: "#3d1fa8")]
    static let heroGradient = LinearGradient(colors: heroStops,
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing)

    // MARK: surfaces

    /// The workspace behind the page.
    static let workspace = dynamic(light: "#ebecf0", dark: "#0e0f12")
    /// Toolbars and bars. In dark mode this has to sit far enough above the
    /// workspace to read as a separate plane — at 1.08:1 the bars dissolved
    /// into the canvas and only their hairline divider gave them an edge.
    static let chrome = dynamic(light: "#ffffff", dark: "#1c1d23")
    /// Cards and sheets, which sit above the chrome and so are lighter again.
    static let card = dynamic(light: "#ffffff", dark: "#24262e")
    /// Separators and the page's own edge.
    static let hairline = dynamic(light: "#00000014", dark: "#ffffff1f")

    // MARK: content

    static let ink = dynamic(light: "#16181d", dark: "#f2f3f5")
    /// For text drawn on the page rather than on app chrome. Fixed in both
    /// appearances because the page has its own background: an appearance-
    /// aware neutral would go pale-on-white the moment the app was in dark
    /// mode. This grey clears 4.5:1 against white and 3.9:1 against a
    /// near-black page, which is the range a page background can span.
    static let onPage = Color(hex: "#6b7280")
    static let inkSecondary = dynamic(light: "#5f6b7a", dark: "#9aa4b2")

    // MARK: type

    /// Relative styles, so the bar honours Dynamic Type instead of pinning
    /// labels at 9.5pt — below Apple's 11pt floor and unable to scale.
    static let controlLabel = Font.system(.caption2, design: .default).weight(.medium)
    static let controlGlyph = Font.system(.body)

    // MARK: helpers

    /// A colour that resolves per appearance. Alpha is optional: an 8-digit
    /// hex carries it, which is how the hairlines stay translucent.
    private static func dynamic(light: String, dark: String) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
