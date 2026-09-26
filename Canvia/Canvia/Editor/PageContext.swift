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

/// Whether the page is being played live — Present, or Play in the editor
/// — rather than rendered for export. Live, a clip shows the latest frame
/// it has while the next is decoded off the main thread, and never makes
/// the screen wait; an export, which has nobody watching it, waits for
/// every frame so no frame of a movie is a stale one.
struct LiveVideoKey: EnvironmentKey {
    static let defaultValue = false
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

    var liveVideo: Bool {
        get { self[LiveVideoKey.self] }
        set { self[LiveVideoKey.self] = newValue }
    }
}
