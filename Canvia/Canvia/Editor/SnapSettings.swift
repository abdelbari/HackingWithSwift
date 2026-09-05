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
        (min(size.width, size.height) * margin).rounded()
    }

    /// The spacings offered. Powers of two, because designs are sized in
    /// them (1080, 1920, 2048) and so are the paddings people type.
    static let gridChoices: [Double] = [0, 8, 16, 32, 64]

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
