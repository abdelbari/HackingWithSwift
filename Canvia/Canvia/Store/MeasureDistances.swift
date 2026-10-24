// Show distances: what a move, or a finger held still on what is selected,
// measures — from the selection's box to its nearest neighbours and the
// page's edges (Geometry.nearestDistances) — drawn as thin guide-colour
// lines with their lengths in the design's unit, and said to VoiceOver by
// the selection's Distances action. Settings ▸ Editing's Show distances
// (AccessibilityPrefs.showDistancesKey) turns it off. Nothing of the design.

import CoreGraphics
import Foundation

extension DesignStore {

    /// What distances are measured to: the boxes of the shown elements but
    /// `ids`, those more than a screen beyond what shows left out.
    func distanceNeighbours(excluding ids: Set<String>) -> [CGRect] {
        let boxes = page.elements.filter { !ids.contains($0.id) && !$0.isHidden }.map(Geometry.aabb)
        guard viewport.width > 0, viewport.height > 0 else { return boxes }
        let reach = viewport.insetBy(dx: -viewport.width, dy: -viewport.height)
        return boxes.filter { $0.intersects(reach) }
    }

    /// Whether the selection is one thing to measure from: one element, or
    /// the whole of an outermost group (Groups.whole) — not part of one. The
    /// Android twin's EditorViewModel.measurable.
    var selectionIsMeasurable: Bool {
        selection.count == 1 || Groups.whole(page.elements, selection: selection) != nil
    }

    /// The box the selection measures and frames from: its upright box, or
    /// for a whole group turned as one the upright box round its turned
    /// frame (turnedGroupFrame) — the Android twin's selectionBounds.
    var selectionMeasureBox: CGRect? {
        if let frame = turnedGroupFrame { return Geometry.aabb(frame.element) }
        return selectionBox
    }

    /// The selection's distances, as it stands.
    var selectionDistances: [Geometry.Distance] {
        guard let box = selectionMeasureBox else { return [] }
        return Geometry.nearestDistances(moving: box, others: distanceNeighbours(excluding: selection), page: pageSize)
    }

    /// Hold to measure: the selection's distances shown while a finger
    /// rests on it (`on`), and gone as it lifts. Nothing while Show
    /// distances is off.
    func measureSelection(_ on: Bool) {
        let next = on && AccessibilityPrefs.showsDistances() ? selectionDistances : []
        if distanceMarks != next { distanceMarks = next }
    }

    /// A distance's length as its pill reads it: "24 px", "6.4 mm".
    func distanceText(_ distance: Double) -> String {
        Units.readout(distance, design) + Units.suffix(design)
    }

    /// What the selection's Distances action says: "Left 24 px, top 10 px,
    /// right 300 px, bottom 12 px" — a side past the page's edge left out.
    var spokenDistances: String {
        let parts = selectionDistances.map { d -> String in
            let length = distanceText(d.distance)
            switch d.side {
            case .left: return tr("Left %@", length)
            case .top: return tr("Top %@", length)
            case .right: return tr("Right %@", length)
            case .bottom: return tr("Bottom %@", length)
            }
        }
        return parts.isEmpty ? tr("No distances to measure") : parts.joined(separator: ", ")
    }
}
