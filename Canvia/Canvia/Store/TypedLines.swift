// Lists and indents a line at a time while a box is typed in: the bar over
// the keyboard's List, Indent and Outdent, Return on an empty item and Tab
// or Shift-Tab on a hardware keyboard, each on the lines the choice covers
// (TextLists) as a step of its own, between the words typed before it and
// after — as the Android twin's typing bar sets them. The Text controls set
// every line at once (Element.setListStyle and stepIndent).

import Foundation

extension DesignStore {

    /// The lines of box `id` that `range` of its stored words covers changed
    /// by `change`, as one step, the box measured again. False, with a buzz,
    /// when that changes nothing — Outdent on a line already at the edge.
    @discardableResult
    func changeLines(_ id: String, covering range: NSRange, _ change: (inout TextParagraph) -> Void) -> Bool {
        guard let el = element(id), el.type == .text, !el.locked else { return false }
        var next = el
        next.changeLines(TextLists.lineRange(el.text ?? "", range), change)
        guard TextLists.lines(next) != TextLists.lines(el) else {
            buzz(.reject)
            return false
        }
        updateSelected { e in
            guard e.id == id else { return }
            e = next
        }
        buzz(.tick)
        return true
    }
}
