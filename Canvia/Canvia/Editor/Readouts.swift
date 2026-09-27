// What the badge under a selection says while it is dragged, sized or
// turned — in the Android twin's words, part by part, so a snapped axis or
// an equal gap can be picked out in the guide colour.

import Foundation

/// One stretch of a readout; `accent` ones are drawn in the guide colour.
struct BadgeRun: Equatable {
    var text: String
    var accent = false
}

enum Readouts {

    /// "x 120  ·  y 48", each axis a guide is holding marked with a dot,
    /// then the gaps made equal: "  ↔ 24" across, "  ↕ 24" down, both when
    /// both are.
    static func move(x: Double, y: Double, heldX: Bool, heldY: Bool,
                     gapX: Double?, gapY: Double?) -> [BadgeRun] {
        var runs: [BadgeRun] = []
        if heldX { runs.append(BadgeRun(text: "● ", accent: true)) }
        runs.append(BadgeRun(text: "x \(Int(x.rounded()))"))
        runs.append(BadgeRun(text: "  ·  "))
        if heldY { runs.append(BadgeRun(text: "● ", accent: true)) }
        runs.append(BadgeRun(text: "y \(Int(y.rounded()))"))
        if let gapX { runs.append(BadgeRun(text: "  ↔ \(Int(gapX.rounded()))", accent: true)) }
        if let gapY { runs.append(BadgeRun(text: "  ↕ \(Int(gapY.rounded()))", accent: true)) }
        return runs
    }

    /// Type being scaled from a corner reads as its size, not its box.
    static func typeSize(_ size: Double) -> String {
        "Size \(tenths(size))"
    }

    /// To one decimal, with no ".0": 42, 42.5.
    static func tenths(_ value: Double) -> String {
        let t = Int((value * 10).rounded())
        let whole = t / 10, rest = abs(t % 10)
        return rest == 0 ? "\(whole)" : "\(whole).\(rest)"
    }

    /// "45°", in the guide colour while the angle is held on a snap.
    static func angle(_ degrees: Double, snapped: Bool) -> [BadgeRun] {
        [BadgeRun(text: "\(Int(degrees) % 360)°", accent: snapped)]
    }

    /// The runs as one line, for the plain badge and for VoiceOver.
    static func text(_ runs: [BadgeRun]) -> String {
        runs.map(\.text).joined()
    }
}
