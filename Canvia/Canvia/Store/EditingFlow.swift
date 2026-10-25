// Round 36's editing on the store: a curved or elbowed line bent by the
// handle in its middle (LineRoutes.bendFor), quick flow's connected copies
// (QuickFlow), and Canva's single keys — R, C and L for a square, a circle
// and a line, the digits for transparency. As the Android twin's
// EditorViewModel does them.

import CoreGraphics
import Foundation

extension DesignStore {

    // MARK: the bend handle

    /// The line whose bend handle shows: one curved or elbowed line
    /// selected alone, shown, and locked in no way.
    var bendLine: Element? {
        guard let el = singleSelection, LineRoutes.keepsLevel(el), !el.holdsPlace, !el.isHidden else { return nil }
        return el
    }

    /// A finger takes the bend handle: the step the drag will be opens.
    func beginLineBend() {
        guard bendLine != nil else { return }
        beginGesture()
        canvasTouchActive = true
    }

    /// The bend handle at `point` on the page: the line bent to it, live
    /// (LineRoutes.bendFor) — the Bend or Corner slider following — and a
    /// detent felt as it settles on a straight middle.
    func dragLineBend(to point: CGPoint) {
        guard let el = bendLine else { return }
        if !canvasTouchActive { beginLineBend() }
        let was = LineRoutes.bend(of: el)
        let next = LineRoutes.bendFor(el, point)
        guard next != was else { return }
        updateSelectedTransient { e in
            if e.id == el.id { e = LineRoutes.withBend(e, next) }
        }
        if next == 0 { buzz(.detent) }
    }

    /// The bend handle let go: the whole drag one step, named Bend —
    /// none when it changed nothing.
    func endLineBend() {
        namedStep = tr("Bend")
        commit()
        canvasTouchActive = false
    }

    /// VoiceOver's Bend more and Bend less: the line bent a tenth further
    /// one way or the other (LineRoutes.bentBy), one step each.
    func bendSelectedLine(more: Bool) {
        guard let el = bendLine, !isPageLocked else { return }
        let next = LineRoutes.bentBy(el, more ? LineRoutes.bendStep : -LineRoutes.bendStep)
        guard next != el else { return }
        namedStep = tr("Bend")
        updateSelected { e in
            if e.id == el.id { e = next }
        }
    }

    // MARK: quick flow

    /// The shape quick flow works from: one shape that takes words — a
    /// sticky note among them — selected alone (QuickFlow.offers), while
    /// nothing is typed in, cropped or picked several at a time.
    var quickFlowSource: Element? {
        guard editingTextId == nil, cropping == nil, graphicCropping == nil, !selectingMultiple,
              let el = singleSelection, QuickFlow.offers(el) else { return nil }
        return el
    }

    /// A + tapped, VoiceOver's Add connected shape, or ⌘⌥ and an arrow: a
    /// copy of the shape `side` of it (QuickFlow.place), joined to it by a
    /// connector, as one step named Add connected shape — the copy
    /// selected and opened for typing. Refused, and said, on a locked page.
    func addConnected(_ side: QuickFlow.Side) {
        guard let source = quickFlowSource, !refusesLockedPage() else { return }
        addConnectedCopy(of: source, at: QuickFlow.place(source, side: side, page: page, frame: pageSize))
    }

    /// A + dragged and let go at `point` on the page: the connector tied to
    /// the element there (QuickFlow.dropTarget), no copy made; over empty
    /// space, the copy centred there.
    func quickFlowDrop(at point: CGPoint) {
        guard let source = quickFlowSource, !refusesLockedPage() else { return }
        guard let target = QuickFlow.dropTarget(page.elements, source: source.id, at: point) else {
            addConnectedCopy(of: source, at: QuickFlow.centred(source, at: point))
            return
        }
        let line = QuickFlow.connector(from: source, to: target, style: QuickFlow.lastConnector(on: page))
        namedStep = QuickFlow.stepName
        applyToPage { $0.elements.append(line) }
        buzz(.confirm)
    }

    /// The copy, then the connector, on top of the page: the connector over
    /// the copy, its ends drawn over the shapes it ties, as Connect lays one
    /// and as the Android twin adds them.
    private func addConnectedCopy(of source: Element, at box: CGRect) {
        let copy = QuickFlow.copy(of: source, at: box)
        let line = QuickFlow.connector(from: source, to: copy, style: QuickFlow.lastConnector(on: page))
        namedStep = QuickFlow.stepName
        applyToPage { $0.elements += [copy, line] }
        guard page.elements.contains(where: { $0.id == copy.id }) else { return }
        selection = [copy.id]
        startTyping(copy.id)
    }

    // MARK: Canva's single keys

    /// What R, C and L add.
    enum KeyShape { case square, circle, line }

    /// R, C or L: a square, a circle or a level line, centred and selected
    /// as T's text box is — onto the next unlocked page from a locked one —
    /// and kept under Add's Recently used, as Add puts them there. The
    /// same sizes as Add's, unrounded, as the Android twin's.
    func addKeyShape(_ kind: KeyShape) {
        let side = min(pageWidth, pageHeight) * 0.28
        switch kind {
        case .square:
            if add(.shape("rect", w: side, h: side)) { ElementSearch.remember(.shape, "rect") }
        case .circle:
            if add(.shape("circle", w: side, h: side)) { ElementSearch.remember(.shape, "circle") }
        case .line:
            if add(.line(w: pageWidth * 0.3)) { ElementSearch.remember(.line, "Line") }
        }
    }

    /// 1 to 9 and 0: the selection's transparency at 10% to 90%, or 100%,
    /// as one step named Transparency — locked things kept as they are —
    /// and said: "Transparency 30%".
    func setTransparencyKey(_ digit: Int) {
        guard (0...9).contains(digit), selectedElements.contains(where: { !$0.locked }) else { return }
        let opacity = digit == 0 ? 1.0 : Double(digit) / 10
        namedStep = tr("Transparency")
        updateSelected { $0.opacity = opacity }
        announce(tr("Transparency %@", "\(digit == 0 ? 100 : digit * 10)%"))
    }
}
