// Lists and indents a line at a time while a box is typed in: the bar over
// the keyboard's List, Indent and Outdent, Return on an empty item and Tab
// or Shift-Tab on a hardware keyboard, each on the lines the choice covers
// (TextLists) as a step of its own, between the words typed before it and
// after — as the Android twin's typing bar sets them. The Text controls set
// every line at once (Element.setListStyle and stepIndent).
//
// Alignment the same way: while a box is typed in, the Align button and
// ⇧⌘L, C, R and J align the lines the choice touches (TextLists.withAlign);
// otherwise every selected text is aligned as a whole (Element.setAlign).

import Foundation

extension DesignStore {

    /// The lines of box `id` that `range` of its stored words covers changed
    /// by `change`, as one step, the box measured again. False, with a buzz,
    /// when that changes nothing — Outdent on a line already at the edge.
    @discardableResult
    func changeLines(_ id: String, covering range: NSRange, _ change: (inout TextParagraph) -> Void) -> Bool {
        // A text box's lines, or a shape's words'.
        guard let el = element(id), ShapeText.carriesWords(el), !el.locked else { return false }
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

    /// The box typed in and the lines its choice touches, while one is
    /// typed in and can be changed; nil otherwise.
    private var typedLines: (box: Element, lines: ClosedRange<Int>)? {
        guard let id = editingTextId, let range = typingSelection, let el = element(id),
              ShapeText.carriesWords(el), !el.locked else { return nil }
        return (el, TextLists.lineRange(el.text ?? "", range))
    }

    /// The Align button, ⇧⌘L, C, R or J: the lines the choice touches in
    /// the box typed in aligned `align`, the rest as they are; with nothing
    /// typed in, every selected text aligned as a whole, each line's own
    /// align given up to it. One step.
    func alignText(_ align: String) {
        if let typed = typedLines {
            let next = TextLists.withAlign(typed.box, typed.lines, align)
            updateSelected { e in
                guard e.id == typed.box.id else { return }
                e = next
            }
            return
        }
        updateSelected { e in
            guard ShapeText.carriesWords(e) else { return }
            e.setAlign(align)
        }
    }

    /// What the Align button shows: the alignment the lines the choice
    /// touches share while a box is typed in, else the one every line of
    /// every selected text shares — nil, Mixed, where they differ.
    var alignShown: String? {
        if let typed = typedLines { return TextLists.sharedAlign(typed.box, lines: typed.lines) }
        return sharedText { TextLists.sharedAlign($0, lines: 0...Int.max) }.flatMap { $0 }
    }
}
