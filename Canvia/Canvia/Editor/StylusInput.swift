// The Apple Pencil while drawing: which kind of touch the stroke under way
// is, and how hard it presses — what SwiftUI's drag does not say. A
// recogniser on the canvas reads each touch as it lands and moves, and never
// claims one, so every other gesture goes on as before.
//
// After the first Pencil stroke the Draw bar offers Draw with stylus only
// (onlyKey, kept on this phone): then the Pencil alone draws and one finger
// pans the page, as on the Android twin with an S Pen. A Pencil's double
// tap still takes the pen up or puts it down.

import UIKit
import UIKit.UIGestureRecognizerSubclass

final class StylusInput {

    static let shared = StylusInput()

    /// The settings keys, on this phone only: Draw with stylus only, and
    /// whether a Pencil has drawn here, which offers it.
    static let onlyKey = "drawStylusOnly"
    static let seenKey = "drawStylusSeen"

    /// Whether the touch under way is a Pencil's.
    private(set) var isPencil = false
    /// How hard it presses, 0…1 of the most it can; nil for a finger.
    private(set) var pressure: Double?

    /// The stroke under way is a Pencil's, pressing with `pressure`, or a
    /// finger's (nil pressure, not a Pencil).
    fileprivate func note(pencil: Bool, pressure: Double?) {
        isPencil = pencil
        self.pressure = pencil ? pressure : nil
        if pencil && !UserDefaults.standard.bool(forKey: Self.seenKey) {
            UserDefaults.standard.set(true, forKey: Self.seenKey)
        }
    }
}

/// Reads each touch on the canvas into StylusInput, and never recognises:
/// it holds up and cancels nothing. A Pencil touch is followed by its own
/// identity while it is down, so a palm or finger resting or moving beside
/// it neither stops its stroke (with Draw with stylus only) nor changes its
/// pressure; a finger counts only while no Pencil is down.
final class TouchKindRecognizer: UIGestureRecognizer {

    /// The Pencil touch under way, if one is.
    private weak var pencil: UITouch?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first(where: { $0.type == .pencil }) {
            pencil = touch
            note(touch)
        } else if pencil == nil, let touch = touches.first {
            note(touch)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let pencil {
            // A finger's moves while the Pencil is down are not the stroke's.
            if touches.contains(pencil) { note(pencil) }
        } else if let touch = touches.first {
            note(touch)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        lifted(touches, event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        lifted(touches, event)
    }

    /// `touches` up: the Pencil let go of when it is among them, and the
    /// recogniser done once no touch is left down, so a Pencil coming back
    /// beside a resting palm is still read.
    private func lifted(_ touches: Set<UITouch>, _ event: UIEvent) {
        if let pencil, touches.contains(pencil) { self.pencil = nil }
        let down = (event.allTouches ?? []).contains { $0.phase != .ended && $0.phase != .cancelled && !touches.contains($0) }
        if !down { state = .failed }
    }

    override func reset() {
        super.reset()
        pencil = nil
    }

    private func note(_ touch: UITouch) {
        let isPencil = touch.type == .pencil
        let most = touch.maximumPossibleForce
        StylusInput.shared.note(pencil: isPencil, pressure: isPencil && most > 0 ? Double(touch.force / most) : nil)
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
