// Right to left. The app's own controls follow the language — SwiftUI
// mirrors them from the environment, in Arabic — but a design never does:
// its coordinates are the same on every phone, so the canvas, the page
// strip, thumbnails, rulers, the timeline and Present draw it left to
// right whatever the language, as on the Android twin. In Present the
// arrow keys go the way the language reads.

import SwiftUI

enum ReadingDirection {
    /// How a design is laid out, whatever the app reads: left to right.
    static let design = LayoutDirection.leftToRight

    enum Arrow { case left, right }

    /// The pages an arrow key turns Present by: the right arrow goes on
    /// left to right, the left arrow right to left.
    static func presentStep(_ arrow: Arrow, reading: LayoutDirection) -> Int {
        let forward: Arrow = reading == .rightToLeft ? .left : .right
        return arrow == forward ? 1 : -1
    }
}

extension View {
    /// Draws a design left to right under any language.
    func designDirection() -> some View {
        environment(\.layoutDirection, ReadingDirection.design)
    }
}
