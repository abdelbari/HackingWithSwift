// What an Undo or a Redo changed, so the editor can select it and bring it
// into view, as Canva does — rather than leave you guessing what just came
// back. The Android twin's History.changedIds, with the same tests.

import Foundation

enum History {

    /// The ids of the elements that differ between two states of a page:
    /// added, removed, or there in both but not the same.
    static func changedIds(before: Page, after: Page) -> Set<String> {
        let old = Dictionary(before.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(after.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = Set<String>()
        for (id, el) in new where old[id] != el { changed.insert(id) }
        for id in old.keys where new[id] == nil { changed.insert(id) }
        return changed
    }

    /// What a step did, in a word, for the system's undo gestures and
    /// shake to name — "Undo Move", "Redo Delete" (DesignUndo) — and the
    /// toolbar's Undo and Redo (undoTitle). Read from
    /// the two states rather than told by every edit: a page added, taken
    /// away or moved first; then, over what the step changed, anything
    /// taken away is a Delete, anything new an Add, words changed are Edit
    /// text, anything else about an element Edit — and only when every
    /// change is to where things sit, how big they are or how far they are
    /// turned does it read Move, Resize or Rotate, that order winning when
    /// they mix. A step with nothing else to it — a page's background — is
    /// Edit.
    static func label(before: Design, after: Design) -> String {
        if after.pages.count > before.pages.count { return tr("Add page") }
        if after.pages.count < before.pages.count { return tr("Delete page") }
        if before.pages.map(\.id) != after.pages.map(\.id) { return tr("Move page") }
        var added = false, removed = false, typed = false, styled = false
        var moved = false, resized = false, turned = false
        for (was, now) in zip(before.pages, after.pages) {
            let old = Dictionary(was.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let new = Dictionary(now.elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, el) in new {
                guard let prior = old[id] else { added = true; continue }
                guard prior != el else { continue }
                switch change(from: prior, to: el) {
                case .moved: moved = true
                case .resized: resized = true
                case .turned: turned = true
                case .typed: typed = true
                case .styled: styled = true
                }
            }
            if old.keys.contains(where: { new[$0] == nil }) { removed = true }
        }
        if removed { return tr("Delete") }
        if added { return tr("Add") }
        if typed { return tr("Edit text") }
        if styled { return tr("Edit") }
        if turned { return tr("Rotate") }
        if resized { return tr("Resize") }
        if moved { return tr("Move") }
        return audioLabel(before, after) ?? tr("Edit")
    }

    /// Move audio or Trim audio, when the same tracks differ only in where
    /// they start — and for a trim, what of their file they play — as a lane
    /// dragged on the timeline leaves them. The Android twin's audioLabel.
    private static func audioLabel(_ before: Design, _ after: Design) -> String? {
        let was = before.audioTracks, now = after.audioTracks
        guard was != now, was.map(\.id) == now.map(\.id) else { return nil }
        let pairs = zip(was, now).filter { $0.0 != $0.1 }
        func same(_ a: AudioTrack, _ b: AudioTrack, trim: Bool) -> Bool {
            var a = a
            a.start = b.start
            if trim {
                a.trimStart = b.trimStart
                a.trimEnd = b.trimEnd
            }
            return a == b
        }
        if pairs.allSatisfy({ same($0.0, $0.1, trim: false) }) { return tr("Move audio") }
        if pairs.allSatisfy({ same($0.0, $0.1, trim: true) }) { return tr("Trim audio") }
        return nil
    }

    /// What Undo is called, by VoiceOver and the toolbar: "Undo Move" for
    /// the step it would take back, or plain "Undo" with no name for it.
    static func undoTitle(_ label: String?) -> String {
        label.map { tr("Undo %@", $0) } ?? tr("Undo")
    }

    /// What Redo is called: "Redo Delete page", or plain "Redo".
    static func redoTitle(_ label: String?) -> String {
        label.map { tr("Redo %@", $0) } ?? tr("Redo")
    }

    private enum Change { case moved, resized, turned, typed, styled }

    /// How one element differs from how it was: only in place, only in
    /// place and size (a text's type and tracking scale with its box), only
    /// in those and its turn, in its words, or in anything else.
    private static func change(from before: Element, to after: Element) -> Change {
        var a = before, b = after
        a.x = 0; b.x = 0; a.y = 0; b.y = 0
        if a == b { return .moved }
        a.w = 0; b.w = 0; a.h = 0; b.h = 0
        a.fontSize = nil; b.fontSize = nil; a.letterSpacing = nil; b.letterSpacing = nil
        if a == b { return .resized }
        // A whole group's turn is recorded on each member too: part of turning.
        a.rotation = 0; b.rotation = 0; a.groupTurn = nil; b.groupTurn = nil
        if a == b { return .turned }
        return before.text != after.text ? .typed : .styled
    }
}
