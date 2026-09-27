// The words the type controls say — beside a slider, and to VoiceOver — and
// the ranges they run over, as the Android twin's text panel has them.

import Foundation

enum TypeReadouts {

    /// Line spacing, as a multiple of the type size.
    static let lineHeightRange: ClosedRange<Double> = 0.7...2.5
    /// Paragraph spacing, in ems after each line break.
    static let paragraphSpacingRange: ClosedRange<Double> = 0...2

    /// Letter spacing from a tenth of the type size tighter to half of it
    /// looser — never narrower than -2…20, which the iPhone always allowed,
    /// and always wide enough for what the box already has. Worked out once
    /// per box and size, so it never moves under a drag.
    static func letterSpacingRange(size: Double, current: Double) -> ClosedRange<Double> {
        min(-0.1 * size, -2, current)...max(0.5 * size, 20, current)
    }

    /// Letter spacing as a share of the size the type is drawn at: "12%".
    static func letterSpacing(_ value: Double, size: Double) -> String {
        "\(Int((value / max(size, 1) * 100).rounded()))%"
    }

    /// "1.25": two places, always.
    static func lineHeight(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// "None", or "0.4 em".
    static func paragraphSpacing(_ value: Double) -> String {
        value < 0.01 ? "None" : "\(Double((value * 10).rounded()) / 10) em"
    }

    /// The alignment as a word, for VoiceOver.
    static func alignment(_ align: String?) -> String {
        switch align ?? "center" {
        case "left": return "Left"
        case "right": return "Right"
        case "justify": return "Justify"
        default: return "Center"
        }
    }

    /// The list style as the List menu names it.
    static func listStyle(_ style: String?) -> String {
        switch style {
        case "bullet": return "Bullets"
        case "number": return "Numbers"
        case "letter": return "Letters"
        default: return "No list"
        }
    }
}
