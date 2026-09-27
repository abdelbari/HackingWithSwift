// How long the editor's toasts and tips stay up.
//
// A line that times out is gone before a screen reader has finished saying
// it, and before someone moving through the screen by swipe can reach its
// Undo. The Android twin keeps its undo snackbar up while TalkBack is on and
// lets the phone's accessibility settings stretch a tip's nine seconds; this
// is the same on the iPhone, read from whether VoiceOver is running.

import Foundation

enum ToastTiming {

    /// Seconds an undo toast stays: four, or until it is dismissed (nil)
    /// while VoiceOver runs — it has an Undo to reach and an X to close it.
    static func undoToast(voiceOver: Bool) -> Double? {
        voiceOver ? nil : 4
    }

    /// Seconds a tip stays: nine, or long enough to be read out and its
    /// close button found while VoiceOver runs.
    static func tip(voiceOver: Bool) -> Double {
        voiceOver ? 30 : 9
    }
}
