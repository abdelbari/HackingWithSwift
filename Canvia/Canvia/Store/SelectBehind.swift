// Select behind: reaching a buried thing from where it lies, as Canva's
// Alt-click and its mobile Layers list of what overlaps do. A still hold
// where two or more things lie under the finger brings up the hold menu
// with Select behind, which lists them (Layers.hitStack); Alt+Tab steps
// down them from the last tap; VoiceOver has Select what is behind on the
// selected element. Nothing is written: only the selection changes.

import CoreGraphics
import Foundation

extension DesignStore {

    /// What lies under a fingertip at `point` on the page worked, top-most
    /// first, a group as one row (Layers.hitStack), at the touch target's
    /// size at the zoom shown.
    func hitStack(at point: CGPoint) -> [LayerRows.Row] {
        Layers.hitStack(page.elements, point, touchRadius: hitRadius)
    }

    /// One of Select behind's rows chosen: what a tap on it selects — a
    /// group whole, hidden members too, as on the Android twin; a locked one
    /// selected but not free to move. Nothing on a locked page.
    func selectStackRow(_ row: LayerRows.Row) {
        holdMenuAt = nil
        guard let first = row.elements.first else { return }
        select(first.id)
    }

    /// Whether Select behind has anything to step to: one thing (or one
    /// whole group) selected, on an unlocked page, with something else
    /// under it — the Android twin's canSelectBehind.
    var canSelectBehind: Bool {
        guard let at = behindPoint else { return false }
        return canStepBehind(at: at)
    }

    /// Alt+Tab, and VoiceOver's Select what is behind: with one thing (or
    /// one group) selected, what lies just under it at the last tap — when
    /// the selection lies under it, else at the middle of the selection —
    /// round again to the top past the bottom (Layers.behind). Refused,
    /// with a buzz, when the selection is not one row or nothing else lies
    /// there.
    func selectBehind() {
        guard let at = behindPoint, canStepBehind(at: at),
              let next = Layers.behind(hitStack(at: at), selection: selection) else {
            buzz(.reject)
            return
        }
        selectStackRow(next)
        revealSelection()
    }

    /// Where Select behind looks: the last tap, when the selection lies
    /// under it, else the selection's middle (Layers.behindPoint); nil
    /// with nothing selected.
    private var behindPoint: CGPoint? {
        Layers.behindPoint(page.elements, selection: selection, lastTap: lastTapAt, touchRadius: hitRadius)
    }

    private func canStepBehind(at point: CGPoint) -> Bool {
        guard !isPageLocked else { return false }
        return Layers.canStepBehind(page.elements, selection: selection, at: point, touchRadius: hitRadius)
    }

    /// Half the touch target, in page units at the zoom shown: how far
    /// round a fingertip hitStack reaches.
    private var hitRadius: Double {
        Touch.pageUnits(Touch.minTarget, zoom: zoom) / 2
    }
}
