// Triggers for .sensoryFeedback.
//
// SwiftUI fires sensory feedback when the trigger value CHANGES, so the value
// has to represent the event, not the continuous state behind it. Snapping is
// the case that matters: guideX/guideY update on every frame of a drag, but a
// snap either is or is not happening on a given axis, and only the transition
// should be felt. Reducing the coordinates to booleans collapses the frames in
// between, so a drag along a guide taps once on arrival rather than buzzing
// continuously for as long as it stays aligned.

import SwiftUI

struct SnapSignal: Equatable {
    let onX: Bool
    let onY: Bool

    init(x: Double?, y: Double?) {
        self.onX = x != nil
        self.onY = y != nil
    }
}

/// Discrete things worth feeling. The serial makes every event a change,
/// so two deletes in a row both tap.
struct HapticEvent: Equatable {
    enum Kind: Equatable { case undo, redo, grouped, pageAdded, stroke }
    var kind: Kind
    var serial: Int

    var feedback: SensoryFeedback {
        switch kind {
        case .undo, .redo: return .impact(weight: .light)
        case .grouped: return .impact(weight: .medium)
        case .pageAdded: return .success
        case .stroke: return .impact(weight: .light, intensity: 0.6)
        }
    }
}

/// The app's own Vibration switch, as the Android twin has one: on unless
/// turned off, one setting for the whole app — never part of a design —
/// and on top of the system's own haptics switch, which still applies.
enum Haptics {
    static let key = "canvia.haptics"

    static func isOn(_ defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}

/// `.sensoryFeedback`, except when Vibration is off. Read as each event
/// happens, so the switch takes effect at once, everywhere.
struct FeltFeedback<T: Equatable>: ViewModifier {
    let trigger: T
    let feedback: (T, T) -> SensoryFeedback?
    @AppStorage(Haptics.key) private var on = true

    func body(content: Content) -> some View {
        let on = self.on
        let feedback = self.feedback
        return content.sensoryFeedback(trigger: trigger) { old, new in
            on ? feedback(old, new) : nil
        }
    }
}

extension View {
    /// A feeling for every change of `trigger`, when Vibration is on.
    func feel<T: Equatable>(_ feedback: SensoryFeedback, trigger: T) -> some View {
        modifier(FeltFeedback(trigger: trigger, feedback: { _, _ in feedback }))
    }

    /// A feeling chosen from the change, or none, when Vibration is on.
    func feel<T: Equatable>(trigger: T, _ feedback: @escaping (T, T) -> SensoryFeedback?) -> some View {
        modifier(FeltFeedback(trigger: trigger, feedback: feedback))
    }
}
