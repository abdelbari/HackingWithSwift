// Whiteboards (Whiteboards): Expand to whiteboard and Collapse from the page
// menus, and sticky notes from Add. The bounds themselves follow every step
// in commit.

import CoreGraphics
import Foundation

extension DesignStore {

    /// Whether the page on screen is expanded to a whiteboard.
    var isWhiteboard: Bool { Whiteboards.isExpanded(page) }

    /// The page on screen expanded to a whiteboard, or collapsed back to
    /// its frame, as one step — what lies wholly outside the frame kept but
    /// hidden by a collapse, and that selection let go. How many things the
    /// collapse hid; nil, with nothing recorded, on a locked page or one
    /// already that way. The Android twin's DesignStore.setWhiteboard.
    @discardableResult
    func setWhiteboard(_ expanded: Bool) -> Int? {
        guard !isPageLocked, isWhiteboard != expanded else { return nil }
        let frame = pageSize
        let hiding: Set<String> = expanded ? [] : Set(Whiteboards.outside(page, frame: frame).filter { !$0.isHidden }.map(\.id))
        if !expanded {
            endTextEdit()
            finishCrop()
        }
        applyToPage { page in
            page = expanded ? Whiteboards.expanded(page, frame: frame) : Whiteboards.collapsed(page, frame: frame)
        }
        if !selection.isDisjoint(with: hiding) { selection.subtract(hiding) }
        return hiding.count
    }

    /// The page menus' Expand to whiteboard and Collapse: refused, and
    /// said, on a locked page; felt; the view fitted afresh; and a collapse
    /// that hid what lay outside the frame says how much, with Undo.
    func toggleWhiteboard() {
        guard !refusesLockedPage() else { return }
        let expanding = !isWhiteboard
        guard let hidden = setWhiteboard(expanding) else { return }
        buzz(.confirm)
        requestCanvas(.fit)
        if !expanding && hidden > 0 { announce(Whiteboards.hiddenNote(hidden)) }
    }

    /// A sticky note of `paper` (StickyNotes), selected, as one step: on a
    /// whiteboard in the middle of what is on screen, else in the middle of
    /// the page.
    func addStickyNote(_ paper: String) {
        let note = StickyNotes.note(paper)
        guard isWhiteboard, viewport.width > 0, viewport.height > 0, !isPageLocked else {
            add(note)
            return
        }
        add(StickyNotes.placed(note, at: CGPoint(x: viewport.midX, y: viewport.midY)), centered: false)
    }
}
