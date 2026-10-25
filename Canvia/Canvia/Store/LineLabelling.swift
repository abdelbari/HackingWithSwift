// Words on a line (LineLabels) as the editor changes them: Style ▸ Add
// text, or a double tap on a selected line, types on it — the label made at
// its middle as typing starts (startTyping), the words its label's while
// typed (typeWords), and the label gone, the line kept, when they are left
// empty (endTextEdit) — in the typing's own bursts; a drag slides it along
// the line as one step; and the line's controls set its face, size,
// colour, weight, slant and gap, one step a change.

import CoreGraphics
import Foundation

extension DesignStore {

    /// The one line selected that takes words: one not fully locked — a
    /// position lock still takes typing (ElementLock.allows), as on Android;
    /// nil otherwise. A locked page is refused by startTyping, which says
    /// so.
    var labelledLine: Element? {
        guard let el = singleSelection, el.type == .line, !el.locked else { return nil }
        return el
    }

    /// The labelled line whose words a drag slides: one not locked either
    /// way, on an unlocked page; nil otherwise.
    var slidableLabelLine: Element? {
        guard let el = labelledLine, !el.holdsPlace, !isPageLocked else { return nil }
        return el
    }

    /// Typing on the selected line, its label made at the middle when it has
    /// none: Style ▸ Add text, and a double tap on it.
    func typeLineLabel() {
        guard let line = labelledLine else { return }
        startTyping(line.id)
    }

    /// The selected line's label dragged to `point` on the page: slid along
    /// the line to its nearest point, held on the middle (LineLabels.slid),
    /// the whole drag one step, closed by commit().
    func slideLabel(to point: CGPoint) {
        guard let line = slidableLabelLine, line.label != nil else { return }
        let at = LineLabels.slid(line, toward: point)
        guard at != line.label?.at else { return }
        updateSelectedTransient { el in
            if el.type == .line { el.label?.at = at }
        }
    }

    /// The selected lines' labels changed by `change`, as one step; a line
    /// with none is left as it is.
    func changeLineLabel(_ change: (inout LineLabel) -> Void) {
        updateSelected { el in
            guard el.type == .line, var label = el.label else { return }
            change(&label)
            el.label = label
        }
    }

    /// The same live, under a finger, closed by commit() as it lifts.
    func changeLineLabelTransient(_ change: (inout LineLabel) -> Void) {
        updateSelectedTransient { el in
            guard el.type == .line, var label = el.label else { return }
            change(&label)
            el.label = label
        }
    }

    /// ⌘B and ⌘I while a label is typed: its weight Bold or Regular, its
    /// slant on or off; the other switches are a text box's.
    func toggleLabel(_ toggle: TextToggle) {
        switch toggle {
        case .bold: changeLineLabel { $0.weight = $0.weight >= 700 ? 400 : 700 }
        case .italic: changeLineLabel { $0.italic.toggle() }
        default: break
        }
    }
}
