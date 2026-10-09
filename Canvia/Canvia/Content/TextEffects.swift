// Text effects, mirrored from the web app. Each case knows how to wrap a
// rendered Text view with the appropriate SwiftUI modifiers.
//
// Each effect has settings — offset, direction, blur and the rest — that
// resolve() works out into the numbers the text renderer draws with, at the
// same factors as the Android twin, so a design looks alike on both.

import SwiftUI
import UIKit

enum TextEffect: String, CaseIterable, Identifiable {
    // In the picker's order.
    case none, shadow, lift, outline, splice, echo, glitch, neon, highlight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .shadow: return "Shadow"
        case .lift: return "Lift"
        case .outline: return "Hollow"
        case .splice: return "Splice"
        case .echo: return "Echo"
        case .glitch: return "Glitch"
        case .neon: return "Neon"
        case .highlight: return "Highlight"
        }
    }

    static func from(_ spec: TextEffectSpec?) -> TextEffect {
        TextEffect(rawValue: spec?.type ?? "none") ?? .none
    }

    /// Highlight bar color contrasting the text color (web parity).
    static func highlightColor(for textColor: String) -> Color {
        Color(hex: highlightHex(for: textColor))
    }

    /// The same, as hex: a dark bar under light letters, yellow under dark.
    static func highlightHex(for textColor: String) -> String {
        UIColor(hex: textColor).isLight ? "#1f2430" : "#ffe066"
    }

    // MARK: settings

    /// The settings this effect has sliders for, in the order they are shown.
    var params: [TextEffectParam] {
        switch self {
        case .none: return []
        case .shadow: return [.offset, .direction, .blur, .transparency]
        case .lift, .neon: return [.intensity]
        case .outline: return [.thickness]
        case .splice: return [.thickness, .offset, .direction]
        case .echo, .glitch: return [.offset, .direction]
        case .highlight: return [.spread, .roundness, .transparency]
        }
    }

    /// What a setting reads as when the design does not hold it — the
    /// value that draws the effect as it always was. nil for a setting
    /// this effect does not use.
    func defaultValue(_ param: TextEffectParam) -> Double? {
        guard params.contains(param) else { return nil }
        switch (self, param) {
        case (.shadow, .direction), (.splice, .direction), (.echo, .direction): return 45
        case (.glitch, .direction): return 0
        case (.shadow, .transparency): return 45
        case (.highlight, .roundness), (.highlight, .transparency): return 0
        default: return 50
        }
    }

    /// Whether the effect takes a colour, and whether it has one of its own
    /// (shadow, glitch) or follows the text when none is set ("Auto").
    var takesColor: Bool { [.shadow, .splice, .echo, .glitch, .highlight].contains(self) }
    var defaultColor: String? {
        switch self {
        case .shadow: return "#000000"
        case .glitch: return "#00e5ff"
        default: return nil
        }
    }
    var defaultColor2: String? { self == .glitch ? "#ff2d78" : nil }

    /// A setting as drawn: the stored value as it is, else the default —
    /// not kept in range, so a file draws the same on the Android twin.
    static func value(_ spec: TextEffectSpec?, _ param: TextEffectParam, for effect: TextEffect) -> Double {
        spec?[param] ?? effect.defaultValue(param) ?? 0
    }

    /// The hollow letters' stroke at a thickness: a curve's splice draws
    /// with it too, being a stroke on the outline.
    static func outlineStroke(fontSize: Double, thickness: Double) -> Double {
        max(2.5, 0.035 * fontSize) * max(thickness, 1) / 50
    }

    /// The spec worked out into what is drawn at a type size, for letters
    /// in `ink` (hex). At every default it is exactly the effect as it was
    /// drawn before it had settings.
    static func resolve(_ spec: TextEffectSpec?, fontSize fs: Double, ink: String) -> ResolvedEffect {
        let effect = from(spec)
        func v(_ param: TextEffectParam) -> Double { value(spec, param, for: effect) }
        /// A distance along the direction setting, y growing downwards.
        func along(_ distance: Double) -> (dx: Double, dy: Double) {
            let angle = v(.direction) * .pi / 180
            return (distance * cos(angle), distance * sin(angle))
        }
        var out = ResolvedEffect(type: effect)
        switch effect {
        case .none:
            break
        case .shadow:
            let d = along(0.06 * 2.0.squareRoot() * fs * v(.offset) / 50)
            out.dx = d.dx; out.dy = d.dy
            out.blur = 0.12 * fs * v(.blur) / 50
            out.alpha = 1 - v(.transparency) / 100
            out.color = spec?.color ?? "#000000"
        case .lift:
            let i = v(.intensity)
            out.dy = 0.18 * fs * i / 50
            out.blur = 0.5 * fs * i / 50
            out.alpha = min(1, 0.35 * i / 50)
            out.color = "#000000"
        case .outline:
            out.stroke = outlineStroke(fontSize: fs, thickness: v(.thickness))
        case .splice:
            out.stroke = max(2.5, 0.03 * fs) * max(v(.thickness), 1) / 50
            let d = along(0.08 * 2.0.squareRoot() * fs * v(.offset) / 50)
            out.copies = [ResolvedEffect.Copy(dx: d.dx, dy: d.dy, color: spec?.color ?? ink,
                                              alpha: spec?.color == nil ? 0.45 : 1)]
        case .neon:
            out.blur = 0.35 * fs * max(v(.intensity), 1) / 50
            out.alpha = 0.85
            out.color = ink
        case .glitch:
            let d = along(0.06 * fs * v(.offset) / 50)
            out.copies = [
                ResolvedEffect.Copy(dx: d.dx, dy: d.dy, color: spec?.color ?? "#00e5ff", alpha: 0.85),
                ResolvedEffect.Copy(dx: -d.dx, dy: -d.dy, color: spec?.color2 ?? "#ff2d78", alpha: 0.85),
            ]
        case .echo:
            let step = along(0.06 * 2.0.squareRoot() * fs * v(.offset) / 50)
            let tint = spec?.color ?? ink
            // The farther, fainter copy first, so the nearer lies over it.
            out.copies = [
                ResolvedEffect.Copy(dx: 2 * step.dx, dy: 2 * step.dy, color: tint, alpha: 0.25),
                ResolvedEffect.Copy(dx: step.dx, dy: step.dy, color: tint, alpha: 0.5),
            ]
        case .highlight:
            out.pad = 0.18 * fs * v(.spread) / 50
            out.roundness = v(.roundness) / 100
            out.alpha = 1 - v(.transparency) / 100
            out.color = spec?.color ?? highlightHex(for: ink)
        }
        return out
    }
}

/// The numeric settings, in the Android twin's words. Each runs 0–100
/// but direction, which is degrees from pointing right, 90 pointing down.
enum TextEffectParam: String, CaseIterable, Identifiable {
    case offset, direction, blur, transparency, intensity, thickness, roundness, spread

    var id: String { rawValue }

    var label: String {
        switch self {
        case .offset: return "Offset"
        case .direction: return "Direction"
        case .blur: return "Blur"
        case .transparency: return "Transparency"
        case .intensity: return "Intensity"
        case .thickness: return "Thickness"
        case .roundness: return "Roundness"
        case .spread: return "Spread"
        }
    }

    var range: ClosedRange<Double> { self == .direction ? -180...180 : 0...100 }
}

/// A text effect in the numbers the renderers draw with, in points at the
/// drawn type size. Which fields mean anything depends on the type:
/// shadow, lift and neon cast (dx, dy, blur, color, alpha); outline and
/// splice stroke; splice, glitch and echo lay copies behind the letters;
/// highlight pads its bars, rounds them and tints them (color, alpha).
struct ResolvedEffect: Equatable {
    /// A copy of the letters, shifted, in a colour at an alpha.
    struct Copy: Equatable {
        var dx: Double
        var dy: Double
        var color: String
        var alpha: Double
    }

    var type: TextEffect
    var dx: Double = 0
    var dy: Double = 0
    var blur: Double = 0
    var color: String = "#000000"
    var alpha: Double = 1
    var stroke: Double = 0
    /// Drawn in this order, before the letters.
    var copies: [Copy] = []
    /// Highlight: the bar's reach past the words on either side.
    var pad: Double = 0
    /// Highlight: 0 square, 1 fully round ends.
    var roundness: Double = 0

    /// Whether the letters cast a shadow or glow.
    var casts: Bool { type == .shadow || type == .lift || type == .neon }

    /// A highlight bar's corner radius at its height.
    func radius(barHeight: Double) -> Double {
        barHeight / 2 * roundness
    }
}

/// Applies an effect around already-styled text content.
struct TextEffectModifier: ViewModifier {
    let effect: TextEffect
    let color: Color
    let fontSize: Double

    func body(content: Content) -> some View {
        switch effect {
        case .none, .outline, .splice, .echo, .highlight:
            // outline/splice/echo/highlight are handled inside TextElementView
            // (they change how the string itself is drawn).
            content
        case .shadow:
            content.shadow(color: .black.opacity(0.55),
                           radius: fontSize * 0.06,
                           x: fontSize * 0.06, y: fontSize * 0.06)
        case .lift:
            content.shadow(color: .black.opacity(0.35),
                           radius: fontSize * 0.25, x: 0, y: fontSize * 0.18)
        case .neon:
            content
                .shadow(color: color.opacity(0.9), radius: fontSize * 0.06)
                .shadow(color: color.opacity(0.7), radius: fontSize * 0.22)
                .shadow(color: color.opacity(0.5), radius: fontSize * 0.5)
        case .glitch:
            content
                .shadow(color: Color(hex: "#00e5ff").opacity(0.85),
                        radius: 0, x: fontSize * 0.06, y: 0)
                .shadow(color: Color(hex: "#ff2d78").opacity(0.85),
                        radius: 0, x: -fontSize * 0.06, y: 0)
        }
    }
}
