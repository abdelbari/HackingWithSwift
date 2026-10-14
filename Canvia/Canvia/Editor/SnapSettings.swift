// What the canvas snaps to.
//
// Three sources, each its own switch: the page (edges and centre), the other
// elements on it, and a grid. Off by default for the grid, on for the other
// two, which is how every design tool ships — and stored across launches,
// because a person who turns snapping off means it for the afternoon, not
// the next ten seconds.

import Foundation

struct SnapSettings: Equatable, Codable {
    var toPage = true
    var toElements = true
    /// Grid spacing in page units; 0 is no grid.
    var grid: Double = 0
    var showGrid = false
    /// Page margin as a fraction of the shorter side; 0 is none. Drawn as a
    /// dashed inset and snapped to, so content lands inside a safe area
    /// rather than at the edge.
    var margin: Double = 0
    var showMargins = true

    var gridEnabled: Bool { grid > 0 }
    var marginEnabled: Bool { margin > 0 }

    static let marginChoices: [Double] = [0, 0.02, 0.05, 0.08]

    /// The margin in page units for a design.
    func marginInset(for design: Design) -> Double {
        marginInset(for: design.size)
    }

    func marginInset(for size: CGSize) -> Double {
        (min(Double(size.width), Double(size.height)) * margin).rounded()
    }

    /// The spacings offered. Powers of two, because designs are sized in
    /// them (1080, 1920, 2048) and so are the paddings people type.
    static let gridChoices: [Double] = [0, 8, 16, 32, 64]

    /// What the Grid picker's "Custom…" takes, in pixels.
    static let customGridRange = 2.0...500.0

    /// A spacing typed for Custom…: the number when it is one within
    /// `customGridRange`, else nil — never clamped into a spacing nobody
    /// typed.
    static func customGrid(_ typed: String) -> Double? {
        var text = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasSuffix("px") { text = String(text.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")),
              customGridRange.contains(value) else { return nil }
        return value
    }

    /// "Every 16 px", "Every 12.5 px".
    static func gridLabel(_ step: Double) -> String {
        let number = step == step.rounded() ? String(Int(step)) : String(step)
        return tr("Every %@ px", number)
    }

    /// "Custom: every 24 px": a spacing set with Custom…, as Android's Grid
    /// row says it.
    static func customGridLabel(_ step: Double) -> String {
        let number = step == step.rounded() ? String(Int(step)) : String(step)
        return tr("Custom: every %@ px", number)
    }

    /// Whether `step` is a spacing the picker does not list: one set with
    /// Custom….
    static func isCustomGrid(_ step: Double) -> Bool {
        step > 0 && !gridChoices.contains(step)
    }

    static let key = "canvia.snapping"

    static func load(from defaults: UserDefaults = .standard) -> SnapSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(SnapSettings.self, from: data)
        else { return SnapSettings() }
        return settings
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
