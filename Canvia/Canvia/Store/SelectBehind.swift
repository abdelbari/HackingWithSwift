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
        let target = Touch.pageUnits(Touch.minTarget, zoom: zoom)
        return Layers.hitStack(page.elements, point, touchRadius: target / 2)
    }

    /// One of Select behind's rows chosen: what it stands for selected —
    /// a group whole, an element alone; a locked one selected but not free
    /// to move, as a tap on it in Layers leaves it. Nothing on a locked
    /// page.
    func selectStackRow(_ row: LayerRows.Row) {
        holdMenuAt = nil
        selectLayers(Set(row.elements.map(\.id)))
    }

    /// Alt+Tab: with one thing (or one group) selected, what lies just
    /// under it at the last tap — when the selection lies under it, else
    /// at the middle of the selection — round again to the top past the
    /// bottom (Layers.behind). Nothing changes when nothing else lies there.
    func selectBehind() {
        let held = selection
        let tapped = lastTapAt.flatMap { tap in
            hitStack(at: tap).contains { row in row.elements.contains { held.contains($0.id) } } ? tap : nil
        }
        stepBehind(at: tapped)
    }

    /// VoiceOver's Select what is behind on element `id`: it selected, then
    /// what lies under its middle, as Alt+Tab steps.
    func selectWhatIsBehind(_ id: String) {
        guard let el = element(id) else { return }
        if !selection.contains(id) { select(id) }
        stepBehind(at: el.center)
    }

    private func stepBehind(at point: CGPoint?) {
        guard let box = selectionBox else { return }
        let at = point ?? CGPoint(x: box.midX, y: box.midY)
        guard let next = Layers.behind(hitStack(at: at), selection: selection) else { return }
        selectStackRow(next)
        revealSelection()
    }
}
