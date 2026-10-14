// Two locks, as in Canva: Lock, which keeps an element exactly as it is, and
// Lock position, which pins where it sits, its size and its turn while its
// words, colours, crop and picture can still be changed — what a template's
// furniture wants. Kept as the element's `locked` and `lockPosition` — the
// second written only when true — under the keys the Android twin uses (its
// core ElementLock), so a design locked on either phone opens locked the same on
// the other. A build that knows only `locked` reads a position lock as none.

import Foundation

enum ElementLock {

    /// How an element is locked. Full wins when both keys are set.
    enum Mode: Hashable {
        case unlocked, position, full
    }

    /// What can be done to an element, for asking what a lock allows — the
    /// same list, in the same order, as the Android twin's ElementLock.Action.
    enum Action: CaseIterable {
        case move, resize, rotate, nudge, align, distribute, tidy
        case editText, recolour, crop, replace, delete
    }

    static func mode(of el: Element) -> Mode {
        if el.locked { return .full }
        return el.lockPosition == true ? .position : .unlocked
    }

    /// `el` locked by `mode`: the other key cleared, and the position key
    /// left off rather than false.
    static func with(_ el: Element, _ mode: Mode) -> Element {
        var out = el
        out.locked = mode == .full
        out.lockPosition = mode == .position ? true : nil
        return out
    }

    /// Whether an element locked by `mode` takes `action`. Nothing is done
    /// to a full lock. A position lock refuses whatever would move, size or
    /// turn it, and takes the rest: typing, colour, a crop's pan and zoom
    /// inside the frame that stays put, Replace, and Delete — after asking
    /// first, since someone pinned it on purpose.
    static func allows(_ mode: Mode, _ action: Action) -> Bool {
        switch mode {
        case .unlocked:
            return true
        case .full:
            return false
        case .position:
            switch action {
            case .move, .resize, .rotate, .nudge, .align, .distribute, .tidy:
                return false
            case .editText, .recolour, .crop, .replace, .delete:
                return true
            }
        }
    }

    /// The Lock menu's words for a mode, as both phones show them.
    static func name(_ mode: Mode) -> String {
        switch mode {
        case .unlocked: return tr("Unlock")
        case .position: return tr("Lock position")
        case .full: return tr("Lock")
        }
    }

    /// The badge's symbol on a locked element: a padlock in outline for a
    /// position lock, a filled one for a full lock, as on the Android twin.
    static func symbol(_ mode: Mode) -> String {
        mode == .position ? "lock" : "lock.fill"
    }
}
