// The system's undo, handed to the design's history.
//
// An iPhone undoes with three fingers — a swipe left, a swipe right, a
// double tap — with the edit bar those bring up, and with a shake, which
// asks "Undo Move?". All of them find the first responder's undoManager
// and work that. The typing field has one of its own (TypingUndo) while
// words are typed; the rest of the time nothing had one, and the gestures
// did nothing. Now the editor keeps a view of its own as the first
// responder whenever no text field has the keyboard (UndoHost), and its
// undoManager is a DesignUndo: Undo and Redo are the store's — the same
// steps, the same reselect and the same haptic as the bar's buttons — and
// they are named by what the step did (History.label), so the shake's
// alert and the edit bar say "Undo Move" or "Redo Delete".
//
// Shake to Undo is the system's default (applicationSupportsShakeToEdit),
// left on. The Android twin has no such gestures; its help says the
// iPhone's map to the same history.

import SwiftUI
import UIKit

/// An UndoManager that is the store's history. Nothing is ever registered
/// with it: what the system asks of it, the store does.
final class DesignUndo: UndoManager {
    weak var store: DesignStore?

    override var canUndo: Bool {
        guard let store else { return false }
        switch mode {
        case .design: return store.canUndo
        case .crop: return false
        case .eraser: return !store.eraserBusy && !store.eraserStrokes.isEmpty
        case .brush: return (store.brushing?.painted ?? 0) > 0
        }
    }
    override var canRedo: Bool { mode == .design && (store?.canRedo ?? false) }

    /// Under the eraser or a brush, Undo takes back the last stroke, as
    /// ⌘Z and the bar's Undo stroke do; in crop mode it does nothing, as
    /// ⌘Z does there. The design's history waits until the mode is put down.
    override func undo() {
        guard let store else { return }
        switch mode {
        case .design: store.undo()
        case .crop: break
        case .eraser:
            if !store.eraserBusy, !store.eraserStrokes.isEmpty { store.eraserStrokes.removeLast() }
        case .brush: store.undoBrushStroke()
        }
    }
    override func redo() {
        guard mode == .design else { return }
        store?.redo()
    }
    override var undoActionName: String { mode == .design ? (store?.undoLabel ?? "") : "" }
    override var redoActionName: String { mode == .design ? (store?.redoLabel ?? "") : "" }

    private enum UndoRoute { case design, crop, eraser, brush }

    private var mode: UndoRoute {
        guard let store else { return .design }
        if store.cropping != nil { return .crop }
        if store.brushing != nil { return .brush }
        if store.erasing != nil { return .eraser }
        return .design
    }
}

/// A view that takes the first responder for the editor, so the system's
/// undo gestures and shake reach the design's history. Nothing to see.
final class UndoHostView: UIView {
    let designUndo = DesignUndo()

    override var canBecomeFirstResponder: Bool { true }
    override var undoManager: UndoManager? { designUndo }

    /// First responder — once in a window, and only while no text field
    /// has the keyboard, which the host (UndoHost.live) is the judge of.
    func claim() {
        guard window != nil, !isFirstResponder else { return }
        becomeFirstResponder()
    }
}

/// The editor's undo host, in its background: first responder as the
/// editor appears and again each time typing, the title, a sheet or an
/// alert lets the keyboard go (`claim` counts those), while `live`.
struct UndoHost: UIViewRepresentable {
    let store: DesignStore
    var live: Bool
    var claim: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UndoHostView {
        let view = UndoHostView()
        view.designUndo.store = store
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: UndoHostView, context: Context) {
        view.designUndo.store = store
        guard live, context.coordinator.claimed != claim else { return }
        context.coordinator.claimed = claim
        // After whatever let the keyboard go has finished letting it go.
        DispatchQueue.main.async { view.claim() }
    }

    final class Coordinator {
        var claimed = -1
    }
}
