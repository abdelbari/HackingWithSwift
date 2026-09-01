// Text effects, mirrored from the web app. Each case knows how to wrap a
// rendered Text view with the appropriate SwiftUI modifiers.

import SwiftUI

enum TextEffect: String, CaseIterable, Identifiable {
    case none, shadow, lift, outline, splice, neon, glitch, highlight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .shadow: return "Shadow"
        case .lift: return "Lift"
        case .outline: return "Hollow"
        case .splice: return "Splice"
        case .neon: return "Neon"
        case .glitch: return "Echo"
        case .highlight: return "Highlight"
        }
    }

    static func from(_ spec: TextEffectSpec?) -> TextEffect {
        TextEffect(rawValue: spec?.type ?? "none") ?? .none
    }

    /// Highlight bar color contrasting the text color (web parity).
    static func highlightColor(for textColor: String) -> Color {
        UIColor(hex: textColor).isLight ? Color(hex: "#1f2430") : Color(hex: "#ffe066")
    }
}

/// Applies an effect around already-styled text content.
struct TextEffectModifier: ViewModifier {
    let effect: TextEffect
    let color: Color
    let fontSize: Double

    func body(content: Content) -> some View {
        switch effect {
        case .none, .outline, .splice, .highlight:
            // outline/splice/highlight are handled inside TextElementView
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
