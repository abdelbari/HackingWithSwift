// The colour system.
//
// Before this file there were 24 raw hex literals spread over 12 files, four
// different purples standing in for "the accent" (#8b3dff, #7c2ae8, #7300e6,
// #7d2ae8), and no dark mode anywhere. Two consequences: the app could not be
// restyled without a find-and-replace across the whole tree, and it read as
// assembled rather than designed, because nothing quite matched anything else.
//
// Neutrals resolve per appearance through UIColor's trait-aware initialiser,
// so dark mode falls out of using the tokens rather than needing a second pass
// over every call site. Anything that is genuinely one fixed colour in both
// appearances — the accent, the magenta snap guide — is declared once.

import SwiftUI
import UIKit

enum Theme {

    // MARK: brand

    /// Canvia's accent. Deliberately not #8b3dff: that is Canva's own brand
    /// purple, and shipping a competitor's exact brand colour in the same
    /// product category is a trademark exposure, not a style choice.
    static let accent = Color(hex: "#5a31f4")
    static let accentPressed = Color(hex: "#4826c9")
    static let accentSubtle = dynamic(light: "#ede7ff", dark: "#241c4a")
    /// Magenta reads clearly against both the accent and any page content.
    static let guide = Color(hex: "#ff2d9e")

    // MARK: surfaces

    /// The workspace behind the page.
    static let workspace = dynamic(light: "#ebecf0", dark: "#0e0f12")
    /// Toolbars and bars.
    static let chrome = dynamic(light: "#ffffff", dark: "#17181c")
    /// Cards and sheets sitting on the workspace.
    static let card = dynamic(light: "#ffffff", dark: "#1e2026")
    /// Separators and the page's own edge.
    static let hairline = dynamic(light: "#00000014", dark: "#ffffff1f")

    // MARK: content

    static let ink = dynamic(light: "#16181d", dark: "#f2f3f5")
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
