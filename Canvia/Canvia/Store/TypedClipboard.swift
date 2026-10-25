// Paste, and a list started from the keyboard, while a box is typed in:
// each a step of its own between the words typed before and after it, the
// paste named "Paste" for the system's Undo (RichClipboard, TextLists) —
// as the Android twin's pasteTyped and its list typing record them.

import Foundation

extension DesignStore {

    /// `clip` — words copied here — or else `plainText` from another app,
    /// pasted over `selection` of the stored words of box `id` while it is
    /// typed in: one step named Paste, the box measured again and the caret
    /// left after what was pasted. A shape's words take the words and their
    /// bold and italic, never colours or lists. False when nothing could go
    /// in: a locked box or page.
    @discardableResult
    func pasteTyped(_ id: String, selection: NSRange, clip: RichClipboard.Clip?, plainText: String) -> Bool {
        guard !refusesLockedPage() else { return false }
        guard let el = element(id), ShapeText.carriesWords(el), !el.locked else {
            buzz(.reject)
            return false
        }
        let text = el.text ?? ""
        let at = RichText.plainCaret(selection.location, in: text)
        let removed = max(0, RichText.plainCaret(NSMaxRange(selection), in: text) - at)
        var next = el
        if el.type == .shape {
            let plainRange = NSRange(location: at, length: removed)
            if let clip {
                next.setText(RichText.splicing(clip.text, over: plainRange, in: text))
            } else {
                let stored = RichText.storedRange(of: plainRange, in: text)
                next.setText(RichText.typing(plainText, over: stored, in: text, pending: nil).text)
            }
        } else if let clip {
            next = RichClipboard.paste(el, at: at, removed: removed, clip: clip)
        } else {
            next = RichClipboard.paste(el, at: at, removed: removed, plainText: plainText)
        }
        ShapeText.fitWords(&next)
        let words = next.text ?? ""
        let grown = (RichText.strip(words) as NSString).length - (RichText.strip(text) as NSString).length
        // The words typed before are a step of their own.
        commit()
        namedStep = tr("Paste")
        beginGesture()
        if let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == id }) {
            design.pages[pageIndex].elements[i] = next
        }
        commit()
        askTypingSelection(NSRange(location: RichText.rawCaret(at + removed + grown, in: words), length: 0))
        return true
    }

    /// The list `list` started on line `line` of box `id` by the typed
    /// prefix, `prefix` UTF-16 units long, at its start (TextLists.autoStarted):
    /// a step of its own after the step the prefix was typed in, so one Undo
    /// brings the typed characters back. The caret stays where it was among
    /// the words, at the start of the item.
    func autoStartList(_ id: String, line: Int, prefix: Int, list: String) {
        guard !isPageLocked, let el = element(id), ShapeText.carriesWords(el), !el.locked else { return }
        let next = TextLists.autoStarted(el, line: line, prefix: prefix, list: list)
        guard next != el else { return }
        commit()
        beginGesture()
        if let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == id }) {
            design.pages[pageIndex].elements[i] = next
            ShapeText.fitWords(&design.pages[pageIndex].elements[i])
        }
        commit()
        let starts = TextLists.lineStarts(RichText.strip(next.text ?? ""))
        let caret = line < starts.count ? starts[line] : 0
        askTypingSelection(NSRange(location: RichText.rawCaret(caret, in: next.text ?? ""), length: 0))
    }
}
