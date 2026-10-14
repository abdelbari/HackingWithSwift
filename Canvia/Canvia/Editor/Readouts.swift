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
        move(x: x, y: y, heldX: heldX, heldY: heldY, gapX: gapX, gapY: gapY, in: nil)
    }

    /// The same in `design`'s unit when it has a physical one — "x 12.5 mm
    /// ·  y 40 mm" (Units.readout); whole pixels without one, or with no
    /// design.
    static func move(x: Double, y: Double, heldX: Bool, heldY: Bool,
                     gapX: Double?, gapY: Double?, in design: Design?) -> [BadgeRun] {
        func length(_ px: Double) -> String { design.map { Units.readout(px, $0) + Units.suffix($0) } ?? String(Int(px.rounded())) }
        var runs: [BadgeRun] = []
        if heldX { runs.append(BadgeRun(text: "● ", accent: true)) }
        runs.append(BadgeRun(text: "x " + length(x)))
        runs.append(BadgeRun(text: "  ·  "))
        if heldY { runs.append(BadgeRun(text: "● ", accent: true)) }
        runs.append(BadgeRun(text: "y " + length(y)))
        if let gapX { runs.append(BadgeRun(text: "  ↔ " + length(gapX), accent: true)) }
        if let gapY { runs.append(BadgeRun(text: "  ↕ " + length(gapY), accent: true)) }
        return runs
    }

    /// Type being scaled from a corner reads as its size, not its box.
    static func typeSize(_ size: Double) -> String {
        tr("Size %@", tenths(size))
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
