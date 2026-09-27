// Which of the fill picker's gradients, patterns and photo fills is the one
// already there — ringed and said to be chosen, and not recorded again when
// tapped — as the Android twin's pickers mark theirs.

import Foundation

enum FillChoices {
    /// The same gradient: kind, angle, shape and every stop.
    static func isGradient(_ current: Paint?, _ candidate: Paint) -> Bool {
        GradientPreset.same(current, candidate)
    }

    /// The same pattern, by name — its colour follows the swatches.
    static func isPattern(_ current: Paint?, named name: String) -> Bool {
        current?.kind == "pattern" && current?.pattern == name
    }

    /// The same photo pouring into the shape.
    static func isPhoto(_ current: Paint?, src: String) -> Bool {
        current?.kind == "image" && current?.src == src
    }

    /// Whether patterns and photo fills are worth offering: only a shape
    /// draws them. Text draws a colour or a gradient and nothing else, so
    /// offering it a pattern saved a fill that never showed.
    static func offersPatterns(for elements: [Element]) -> Bool {
        elements.contains { $0.type == .shape && !Freehand.isStroke($0) }
    }
}
