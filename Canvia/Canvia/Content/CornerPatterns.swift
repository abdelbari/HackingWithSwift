// Which corners of a rectangle round: all four, a side's, or two opposite —
// the Corners menu's patterns. Stored in `corners` as four radii (top-left,
// top-right, bottom-right, bottom-left); none means `radius` on all four.
// The same reading and writing as the Android twin's Corners.

import Foundation

enum CornerPatterns {
    struct Pattern: Equatable {
        var name: String
        var rounds: [Bool]
    }

    static let choices: [Pattern] = [
        Pattern(name: "All corners", rounds: [true, true, true, true]),
        Pattern(name: "Top only", rounds: [true, true, false, false]),
        Pattern(name: "Bottom only", rounds: [false, false, true, true]),
        Pattern(name: "Left only", rounds: [true, false, false, true]),
        Pattern(name: "Right only", rounds: [false, true, true, false]),
        Pattern(name: "Opposite corners", rounds: [true, false, true, false]),
    ]

    /// The pattern an element's corners make: All corners for a plain
    /// radius, nil for none rounded or radii of its own that differ.
    static func pattern(of el: Element) -> Pattern? {
        guard let radii = el.corners, radii.count == 4, radii.contains(where: { $0 > 0 }) else {
            return (el.radius ?? 0) > 0 ? choices[0] : nil
        }
        let rounds = radii.map { $0 > 0 }
        guard let first = radii.first(where: { $0 > 0 }),
              !radii.contains(where: { $0 > 0 && $0 != first }) else { return nil }
        return choices.first { $0.rounds == rounds }
    }

    /// The element with `pattern`'s corners rounded: at its radius, or at a
    /// fifth of its shorter side when it had none, so a pattern can be
    /// chosen from square. All corners is the plain radius and no list.
    static func apply(_ pattern: Pattern, to el: inout Element) {
        let current = el.radius ?? 0
        let radius = current > 0 ? current : min(el.w, el.h) * 0.2
        setRadius(radius, keeping: pattern, on: &el)
    }

    /// The element's corners at `radius`, keeping which of them round —
    /// the pattern read once as a slider drag begins, so a drag through
    /// zero does not lose it.
    static func setRadius(_ radius: Double, keeping pattern: Pattern?, on el: inout Element) {
        el.radius = radius
        if let pattern, !pattern.rounds.allSatisfy({ $0 }) {
            el.corners = pattern.rounds.map { $0 ? radius : 0 }
        } else {
            el.corners = nil
        }
    }
}
