// The Position sheet's nudge arrows, held: the first step at once, then
// after a pause a step every 80 ms, quickening to every 40 ms after twenty —
// the pace of a key held down — with a tick felt every ten steps. The whole
// hold is one Undo. The Android twin's NudgeButton keeps the same numbers.

import Foundation

enum NudgeRepeat {

    /// The pause before the second step, in seconds.
    static let firstDelay = 0.4
    /// The pause between steps after that, and after `quickAfter` steps.
    static let interval = 0.08
    static let quickInterval = 0.04
    static let quickAfter = 20
    /// A tick is felt every this many steps.
    static let tickEvery = 10

    /// The pause, in seconds, before the next step of a hold that has made
    /// `steps` so far (the first is made as the finger lands).
    static func delay(afterSteps steps: Int) -> Double {
        if steps <= 1 { return firstDelay }
        return steps < quickAfter ? interval : quickInterval
    }

    /// Whether the step numbered `step` (from 1) is felt.
    static func ticks(at step: Int) -> Bool {
        step > 0 && step % tickEvery == 0
    }
}
