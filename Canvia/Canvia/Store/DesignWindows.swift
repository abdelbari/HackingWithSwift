// Designs open in windows side by side on iPad, by one rule the Android
// twin's DesignWindows keeps too: a design is edited in the window that
// opened it first; another window opening it while that one holds it shows
// it read-only, under "Open in another window", and stays so until it is
// opened again once the first has let go. A design is held from when its
// window opens it until that window closes it, so only the window that
// holds it saves it and neither overwrites the other's edits.

import Foundation

final class DesignWindows: @unchecked Sendable {

    /// A window, as the registry knows it: one each, kept as the window's
    /// state for as long as it is open.
    final class Window {}

    /// The one registry of the app: every window of it is in it.
    static let shared = DesignWindows()

    private var holders: [String: Window] = [:]
    private let lock = NSLock()

    /// `window` opening design `id`: whether it edits it (it holds it now,
    /// or did already) or only shows it.
    func open(_ id: String, in window: Window) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let holder = holders[id] { return holder === window }
        holders[id] = window
        return true
    }

    /// `window` closing design `id`: let go of, when it held it.
    func close(_ id: String, in window: Window) {
        lock.lock()
        defer { lock.unlock() }
        if holders[id] === window { holders[id] = nil }
    }

    /// Whether some window holds design `id`.
    func isHeld(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return holders[id] != nil
    }
}
