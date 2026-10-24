// A pinch that starts on the selection scales it, and a twist of the two
// fingers turns it, as Canva does for stickers, photos and words too small
// for their corner handles (CanvasGestures.pinchesSelection). The whole
// gesture is one undo step — Resize, or Turn when only the angle changed —
// and the turn snaps at 45° as a turn handle's does. Position snapping is
// off while it lasts. The Android twin's EditorViewModel pinch.

import CoreGraphics
import Foundation

extension DesignStore {

    /// A pinch under way: what was selected as the fingers landed, the
    /// point it scales and turns about, and the angle the snap is taken on
    /// — one thing's turn, a whole group's, or none for several things.
    struct PinchSession {
        var originals: [Element]
        var centre: CGPoint
        var baseTurn: Double
        /// The scale and the turn last applied.
        var scale = 1.0
        var turn = 0.0
    }

    /// Whether the editor is in a mode a pinch never works the selection
    /// in: cropping, typing, drawing, erasing or brushing.
    var pinchBusy: Bool {
        cropping != nil || graphicCropping != nil || editingTextId != nil || drawing != nil || erasing != nil
            || brushing != nil
    }

    /// The pinch begins: the step opens and the selection is kept as it is
    /// now. Nil when there is nothing it may work.
    func beginPinch() -> PinchSession? {
        let members = selectedElements
        guard !members.isEmpty, !pinchBusy, !isPageLocked,
              !members.contains(where: \.holdsPlace) else { return nil }
        beginGesture()
        canvasTouchActive = true
        if members.count == 1, let el = members.first {
            return PinchSession(originals: members, centre: el.center, baseTurn: el.rotation)
        }
        if let frame = turnedGroupFrame {
            return PinchSession(originals: members, centre: frame.center, baseTurn: frame.angle)
        }
        let box = Geometry.union(members.map(Geometry.aabb))
        return PinchSession(originals: members, centre: CGPoint(x: box.midX, y: box.midY),
                            baseTurn: selectedGroupTurn ?? 0)
    }

    /// The fingers `scale` times as far apart as they landed, and their
    /// line turned `turn` degrees: the selection scaled and turned with
    /// them, its angle held on a 45° snap within 4° (felt through
    /// rotationSnapped), the size and angle read out.
    func pinchSelection(_ session: inout PinchSession, scale: Double, turn: Double) {
        let free = Groups.normalisedTurn(session.baseTurn + turn)
        let snapped = Geometry.snapAngle(free, step: 45, threshold: 4)
        rotationSnapped = snapped != free
        let angle = Groups.normalisedTurn((snapped * 10).rounded() / 10)
        let delta = Groups.normalisedTurn(angle - session.baseTurn)
        let pinched = Geometry.pinched(session.originals, centre: session.centre, scale: scale, turnDeg: delta)
        replaceTransient(pinched)
        session.scale = scale
        session.turn = delta
        setBadge(Readouts.pinch(size: Self.pinchedSize(pinched, angle: angle), degrees: angle,
                                snapped: rotationSnapped, in: design))
    }

    /// The pinch let go: one step, named Resize — or Turn when only the
    /// angle changed — and nothing at all when nothing did.
    func endPinch(_ session: PinchSession) {
        namedStep = abs(session.scale - 1) < 0.001 && session.turn != 0 ? tr("Turn") : tr("Resize")
        commit()
        rotationSnapped = false
        badge = nil
        badgeRuns = nil
        canvasTouchActive = false
    }

    /// The size the readout gives: one thing's own box; a group's frame in
    /// its own axes; several things' box round them.
    private static func pinchedSize(_ elements: [Element], angle: Double) -> CGSize {
        if elements.count == 1, let el = elements.first { return CGSize(width: el.w, height: el.h) }
        return Geometry.groupFrame(elements, angle: angle).size
    }
}
