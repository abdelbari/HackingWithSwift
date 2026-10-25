// Show guides and Lock guides, the design's own settings ("guidesHidden"
// and "guidesLocked", written only when true): hidden guides are kept but
// neither drawn nor snapped to; locked ones are drawn and snapped to but
// never dragged, picked up from a ruler or placed, a touch on one going to
// what is under it. Each switch is one undo step, Edit, and adding a guide
// while they are hidden shows them again. The Android twin's guide
// settings.

import CoreGraphics
import Foundation

extension Guides {

    /// The guides drawn and snapped to: none while they are hidden.
    static func shown(_ design: Design) -> [Guide] {
        design.guidesHidden == true ? [] : design.guides
    }

    /// The guide a touch at `point` on the page takes — the nearest within
    /// `reach` page units across it — or nil: always nil while the guides
    /// are hidden or locked, so the touch falls through to the element or
    /// the pan under it.
    static func grabbed(_ design: Design, at point: CGPoint, reach: Double) -> Guide? {
        guard design.guidesLocked != true else { return nil }
        func off(_ guide: Guide) -> Double {
            abs(Double(guide.vertical ? point.x : point.y) - guide.position)
        }
        return shown(design).filter { off($0) <= reach }.min { off($0) < off($1) }
    }
}

extension DesignStore {

    /// Show guides: on unless turned off.
    var guidesShown: Bool { design.guidesHidden != true }

    /// Lock guides: off unless turned on.
    var guidesLocked: Bool { design.guidesLocked == true }

    /// The safe zone shown on this page (SafeZones.shown): its id, or
    /// SafeZones.off.
    var safeZoneChoice: String {
        SafeZones.shown(design, page: page)?.id ?? SafeZones.off
    }

    /// The Snapping and guides sheet's Safe zone: a zone's id, or
    /// SafeZones.off, kept as the design's `safeZone`, as one undo step
    /// named Edit.
    func setSafeZone(_ id: String) {
        guard id != safeZoneChoice else { return }
        // Words being typed are a step of their own.
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Edit")
        apply { $0.safeZone = id }
    }

    /// Show guides turned on or off, as one undo step named Edit.
    func setGuidesShown(_ shown: Bool) {
        guard shown != guidesShown else { return }
        // Words being typed are a step of their own.
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Edit")
        apply { $0.guidesHidden = shown ? nil : true }
    }

    /// Lock guides turned on or off, as one undo step named Edit.
    func setGuidesLocked(_ locked: Bool) {
        guard locked != guidesLocked else { return }
        // Words being typed are a step of their own.
        if hasPendingChanges && (editingTextId != nil || dictationTarget != nil) { commit() }
        namedStep = tr("Edit")
        apply { $0.guidesLocked = locked ? true : nil }
    }

    /// True when the guides are locked, which is then felt and said, with
    /// Unlock (announcementUnlocksGuides), as a locked element is refused.
    @discardableResult
    func refusesLockedGuides() -> Bool {
        guard guidesLocked else { return false }
        buzz(.reject)
        announce(tr("Guides are locked"), undoable: false)
        announcementUnlocksGuides = true
        return true
    }
}
