// Setting a photo dial exactly — the Android twin's DialPrecision, rule for
// rule, with the same test rows.
//
// A dial reads in whole steps: -100…100, or 0…100 for one that only goes
// one way (vignette, fade, grain, blur, pixelate; a filter's strength).
// Its readout opens a number to type, held to that range; a value within 2
// of the dial's rest (0, or 100 for a strength) is the rest, felt once as
// it is reached; VoiceOver moves it 5 at a time. Reset puts one dial back,
// and each group's Reset — Light, Colour (selective colour with it),
// Texture — only that group's dials, the adjustments gone when nothing is
// left moved. No JSON changes: the dials are the Adjustments they were.

import Foundation

enum DialPrecision {

    /// Within this many steps of its rest a dial is at rest.
    static let snapReach = 2.0
    /// How far VoiceOver's increment and decrement move a dial.
    static let step = 5.0

    /// A dial's range in steps, from its range in the model (-1…1 or 0…1).
    static func steps(_ model: ClosedRange<Double>) -> ClosedRange<Double> {
        (model.lowerBound * 100).rounded()...(model.upperBound * 100).rounded()
    }

    /// A dial's value as it lands: in whole steps, inside `range`, and at
    /// `rest` within snapReach of it.
    static func snapped(_ value: Double, rest: Double = 0, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return rest }
        let whole = min(max(value.rounded(), range.lowerBound), range.upperBound)
        return abs(whole - rest) <= snapReach ? rest : whole
    }

    /// Whether a move from `old` to `new` reached the rest — what the
    /// light tick is felt for, once each time.
    static func reachedRest(from old: Double, to new: Double, rest: Double = 0) -> Bool {
        new == rest && old != rest
    }

    /// A typed number as the dial's value: "+20", "-5", " 37 ", "12.6" and
    /// "40%" read; held to `range` and whole; nil for anything else.
    static func typed(_ text: String, in range: ClosedRange<Double>) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasSuffix("%") { cleaned.removeLast() }
        cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "\u{2212}", with: "-")
        if cleaned.hasPrefix("+") { cleaned.removeFirst() }
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return min(max(value.rounded(), range.lowerBound), range.upperBound)
    }

    /// VoiceOver's step up or down from `value`, held to `range`.
    static func stepped(_ value: Double, up: Bool, in range: ClosedRange<Double>) -> Double {
        min(max(value + (up ? step : -step), range.lowerBound), range.upperBound)
    }

    /// How a dial's value is read out: signed for a two-way dial ("+20",
    /// "0", "-5"), plain for a one-way one ("40").
    static func readout(_ value: Double, in range: ClosedRange<Double>) -> String {
        let whole = Int(value.rounded())
        guard range.lowerBound < 0, whole > 0 else { return "\(whole)" }
        return "+\(whole)"
    }

    // MARK: groups

    /// The three groups of the Adjust dials, as the sheet heads them.
    enum DialGroup: String, CaseIterable {
        case light, colour, texture

        var keys: [WritableKeyPath<Adjustments, Double>] {
            switch self {
            case .light: return [\.brightness, \.contrast, \.highlights, \.shadows, \.whites, \.blacks]
            case .colour: return [\.saturation, \.vibrance, \.warmth, \.tint]
            case .texture: return [\.clarity, \.sharpness, \.vignette, \.fade]
            }
        }
    }

    /// Whether any of `group`'s dials is moved — selective colour counting
    /// for Colour.
    static func isMoved(_ adjustments: Adjustments?, _ group: DialGroup) -> Bool {
        guard let adjustments else { return false }
        if group == .colour, !HueBands.kept(adjustments.hsl).isEmpty { return true }
        return group.keys.contains { adjustments[keyPath: $0] != 0 }
    }

    /// `adjustments` with `group`'s dials back at rest (Colour's hue bands
    /// too) and the rest kept; nil when nothing is left moved.
    static func cleared(_ adjustments: Adjustments?, _ group: DialGroup) -> Adjustments? {
        guard var out = adjustments else { return nil }
        for key in group.keys { out[keyPath: key] = 0 }
        if group == .colour { out.hsl = [:] }
        return out.isNeutral ? nil : out
    }

    /// `adjustments` with one dial back at rest; nil when nothing is left
    /// moved.
    static func reset(_ adjustments: Adjustments?, _ key: WritableKeyPath<Adjustments, Double>) -> Adjustments? {
        guard var out = adjustments else { return nil }
        out[keyPath: key] = 0
        return out.isNeutral ? nil : out
    }
}
