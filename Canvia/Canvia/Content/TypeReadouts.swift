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

    /// Left, centre, right, justify and round again: the Align button's turn.
    static func nextAlignment(after align: String?) -> String {
        switch align ?? "center" {
        case "left": return "center"
        case "center": return "right"
        case "right": return "justify"
        default: return "left"
        }
    }

    // MARK: type size

    /// How small and how large type is set.
    static let sizeRange: ClosedRange<Double> = 6...500

    /// The sizes listed under the typed one, as the Android twin lists them.
    static let presetSizes: [Double] = [8, 10, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 48, 56,
                                        64, 72, 80, 96, 120, 144, 200]

    /// A size in whole points, inside the range.
    static func wholeSize(_ size: Double) -> Double {
        min(sizeRange.upperBound, max(sizeRange.lowerBound, size.rounded()))
    }

    /// A size as typed — "24", " 36 ", "12.5" — in whole points inside the
    /// range; nil when what is typed is not a number.
    static func typedSize(_ typed: String) -> Double? {
        let number = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), value.isFinite else { return nil }
        return wholeSize(value)
    }

    /// The size the size control shows: the nearest whole point, as on the
    /// Android twin, or "Mixed".
    static func fontSize(_ size: Double?) -> String {
        size.map { "\(Int($0.rounded()))" } ?? mixed
    }

    // MARK: several texts

    /// What a control says where the texts selected differ.
    static let mixed = "Mixed"

    /// The one value every item has, or nil when they differ or there are
    /// none.
    static func shared<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first, values.allSatisfy({ $0 == first }) else { return nil }
        return first
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
