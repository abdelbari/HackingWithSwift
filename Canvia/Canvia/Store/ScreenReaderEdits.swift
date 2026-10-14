// The canvas transforms that otherwise need a drag, for VoiceOver and
// Switch Control: Make larger, Make smaller, Turn clockwise and Turn
// anticlockwise, as the Android twin's TalkBack actions. Each selects the
// element first and is one undo step; something locked, or locked in
// position, is left as it is, as a move leaves it.

import Foundation

extension DesignStore {

    /// `id` made larger (or smaller) by a tenth about its centre
    /// (CanvasAccessibility.scaled); refused, and felt, at its least size.
    /// True when it changed.
    @discardableResult
    func resizeForScreenReader(_ id: String, larger: Bool) -> Bool {
        guard let el = element(id), !el.holdsPlace else { return false }
        select(id)
        guard let scaled = CanvasAccessibility.scaled(el, larger: larger) else {
            buzz(.reject)
            return false
        }
        applyToPage { page in
            if let i = page.elements.firstIndex(where: { $0.id == id }) { page.elements[i] = scaled }
        }
        return true
    }

    /// `id` turned 15 degrees clockwise (or anticlockwise), onto a multiple
    /// of 15 (CanvasAccessibility.turned); never an elbowed or curved
    /// line, which stays level (LineRoutes.keepsLevel). True when it
    /// changed.
    @discardableResult
    func turnForScreenReader(_ id: String, clockwise: Bool) -> Bool {
        guard let el = element(id), !el.holdsPlace, !LineRoutes.keepsLevel(el) else { return false }
        select(id)
        let angle = CanvasAccessibility.turned(el.rotation, clockwise: clockwise)
        applyToPage { page in
            if let i = page.elements.firstIndex(where: { $0.id == id }) { page.elements[i].rotation = angle }
        }
        return true
    }
}
