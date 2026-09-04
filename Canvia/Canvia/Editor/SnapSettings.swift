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

    var gridEnabled: Bool { grid > 0 }

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
