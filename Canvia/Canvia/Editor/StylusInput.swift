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

    fileprivate func note(_ touch: UITouch) {
        isPencil = touch.type == .pencil
        let most = touch.maximumPossibleForce
        pressure = isPencil && most > 0 ? Double(touch.force / most) : nil
        if isPencil && !UserDefaults.standard.bool(forKey: Self.seenKey) {
            UserDefaults.standard.set(true, forKey: Self.seenKey)
        }
    }
}

/// Reads each touch on the canvas into StylusInput, and never recognises:
/// it holds up and cancels nothing.
final class TouchKindRecognizer: UIGestureRecognizer {

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { StylusInput.shared.note(touch) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if let touch = touches.first { StylusInput.shared.note(touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}
