// Which page a view is drawing, for the things a page needs to know about
// itself: its number, and how many there are.

import SwiftUI

struct PageNumberKey: EnvironmentKey {
    static let defaultValue: (number: Int, count: Int)? = nil
}

/// Seconds into the page for previews and video frames, and the page's
/// hold so Ken Burns knows how far along it is. nil draws everything
/// settled — the editor's normal state.
struct AnimationTimeKey: EnvironmentKey {
    static let defaultValue: (time: Double, hold: Double)? = nil
}

extension EnvironmentValues {
    var pageNumber: (number: Int, count: Int)? {
        get { self[PageNumberKey.self] }
        set { self[PageNumberKey.self] = newValue }
    }

    var animationTime: (time: Double, hold: Double)? {
        get { self[AnimationTimeKey.self] }
        set { self[AnimationTimeKey.self] = newValue }
    }
}
