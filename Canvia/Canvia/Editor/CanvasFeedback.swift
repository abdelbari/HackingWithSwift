// Triggers for .sensoryFeedback.
//
// SwiftUI fires sensory feedback when the trigger value CHANGES, so the value
// has to represent the event, not the continuous state behind it. Snapping is
// the case that matters: guideX/guideY update on every frame of a drag, but a
// snap either is or is not happening on a given axis, and only the transition
// should be felt. Reducing the coordinates to booleans collapses the frames in
// between, so a drag along a guide taps once on arrival rather than buzzing
// continuously for as long as it stays aligned.

import Foundation

struct SnapSignal: Equatable {
    let onX: Bool
    let onY: Bool

    init(x: Double?, y: Double?) {
        self.onX = x != nil
        self.onY = y != nil
    }
}
