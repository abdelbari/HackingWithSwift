// Warp on the selected text, from the Effects sheet's Shape row: a preset
// bends the letters (TextWarp), the Amount slider how far, and Edit shape
// puts its eight handles on the canvas to drag — any drag makes it a custom
// warp. Text set along a path gets the path's own points to drag instead,
// written back as the path's data. A warp takes any curve, path or column
// away, as those take each other's; each change is a step, a drag one step
// when it lets go. A locked box or page is left as it is.

import Foundation
import CoreGraphics

extension DesignStore {

    /// The selected text warped to `kind`, at the amount it had — or no
    /// warp, with nil — as one step.
    func warpSelected(_ kind: String?) {
        guard !refusesLockedPage() else { return }
        updateSelected { el in
            guard el.type == .text else { return }
            guard let kind else {
                el.warp = nil
                return
            }
            el.warp = TextWarpSpec(kind: kind, amount: el.warp?.amount ?? 50)
            el.curve = nil
            el.textPath = nil
            el.vertical = nil
        }
        if kind == nil { shapeEditingId = nil }
    }

    /// How far the warp bends, while the slider moves; letting go closes
    /// the step (commit).
    func warpAmountTransient(_ amount: Double) {
        guard !isPageLocked else { return }
        updateSelectedTransient { el in
            guard var warp = el.warp else { return }
            warp.amount = min(max(amount, -100), 100).rounded()
            el.warp = warp
        }
    }

    /// Whether Edit shape has something to move on the selection: a warp,
    /// or a path whose points can be dragged (TextWarp.pathPoints).
    var canEditShape: Bool {
        guard let el = singleSelection, el.type == .text, !el.locked, !isPageLocked else { return false }
        if TextWarp.isWarped(el) { return true }
        return el.textPath.flatMap(TextWarp.pathPoints) != nil
    }

    /// Edit shape on or off for the selected text.
    func toggleShapeEditing() {
        guard let el = singleSelection, canEditShape else {
            shapeEditingId = nil
            return
        }
        shapeEditingId = shapeEditingId == el.id ? nil : el.id
    }

    /// The handles Edit shape draws, where they stand on the page: the
    /// warp's eight, or the path's points, turned and flipped with the box.
    var shapeHandles: [CGPoint] {
        guard let el = singleSelection, el.id == shapeEditingId, canEditShape else { return [] }
        return Self.shapeUnits(el).map { Self.pagePoint(el, unit: $0) }
    }

    /// The handles in the box's units, 0…1 across and down.
    static func shapeUnits(_ el: Element) -> [CGPoint] {
        if TextWarp.isWarped(el), let warp = el.warp { return TextWarp.handles(warp) }
        return (el.textPath.flatMap(TextWarp.pathPoints) ?? []).map { CGPoint(x: $0.x / 100, y: $0.y / 100) }
    }

    /// A point in `el`'s box units on the page.
    static func pagePoint(_ el: Element, unit: CGPoint) -> CGPoint {
        var x = Double(unit.x) * el.w, y = Double(unit.y) * el.h
        if el.flipH { x = el.w - x }
        if el.flipV { y = el.h - y }
        return Geometry.rotate(CGPoint(x: el.x + x, y: el.y + y), around: el.center, degrees: el.rotation)
    }

    /// A page point in `el`'s box units.
    static func unitPoint(_ el: Element, page: CGPoint) -> CGPoint {
        let p = Geometry.rotate(page, around: el.center, degrees: -el.rotation)
        var x = Double(p.x) - el.x, y = Double(p.y) - el.y
        if el.flipH { x = el.w - x }
        if el.flipV { y = el.h - y }
        return CGPoint(x: el.w > 0 ? x / el.w : 0, y: el.h > 0 ? y / el.h : 0)
    }

    /// Handle `index` dragged to `page`: the warp made custom with it
    /// there, or the path's point moved — live; letting go closes the step.
    func dragShapeHandle(_ index: Int, to page: CGPoint) {
        guard !isPageLocked, let el = singleSelection, el.id == shapeEditingId, !el.locked else { return }
        let unit = Self.unitPoint(el, page: page)
        updateSelectedTransient { e in
            guard e.id == el.id else { return }
            if TextWarp.isWarped(e), let warp = e.warp {
                e.warp = TextWarp.moved(warp, handle: index, to: unit)
            } else if let data = e.textPath,
                      let moved = TextWarp.movingPathPoint(data, index: index,
                                                           to: CGPoint(x: unit.x * 100, y: unit.y * 100)) {
                e.textPath = moved
            }
        }
    }
}
