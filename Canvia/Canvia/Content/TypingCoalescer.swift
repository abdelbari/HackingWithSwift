// What typed in place is one Undo: a burst of typing, roughly a word, as
// Canva takes typing back — not a whole visit to the box, which lost a
// paragraph to one Undo for a typo fixed at its end. Kept pure so both
// phones run the same rows; the Android twin's core TypingCoalescer holds
// the same rules.
//
// A step closes after a space or a mark of punctuation typed after letters
// typed in it ("Hello " is one), on a pause of `pause` seconds or more
// before the next change, and on a caret moved elsewhere before it. A style
// from the typing bar is a step of its own already (close). Backspaces and
// corrections join the step they fall in.

import Foundation

struct TypingCoalescer {

    /// A pause this long, in seconds, between two changes closes the step
    /// before the second.
    static let pause = 1.0

    /// What one change does to the steps: whether the step open closes
    /// before it — the change opening a step of its own — and whether its
    /// own step closes after it.
    struct Verdict: Equatable {
        var closeFirst: Bool
        var closeAfter: Bool
    }

    /// Whether a step is open, holding changes.
    private(set) var open = false
    /// Whether letters were typed in the open step.
    private var letters = false
    /// When the last change came, in seconds.
    private var last = 0.0

    /// The words changed from `old` to `new` at `time` seconds, the caret
    /// `jumped` elsewhere since the change before.
    mutating func change(from old: String, to new: String, at time: Double, jumped: Bool = false) -> Verdict {
        let closeFirst = open && (jumped || time - last >= Self.pause)
        if closeFirst { letters = false }
        open = true
        last = time
        let typed = Self.typed(from: old, to: new)
        if typed.contains(where: { $0.isLetter || $0.isNumber }) { letters = true }
        let ends = typed.last.map { $0.isWhitespace || $0.isPunctuation } ?? false
        let closeAfter = letters && ends
        if closeAfter { close() }
        return Verdict(closeFirst: closeFirst, closeAfter: closeAfter)
    }

    /// The step closed from outside — a style from the bar, an Undo, the
    /// words set again: the next change opens a new one.
    mutating func close() {
        open = false
        letters = false
    }

    /// What `new` has that `old` has not: the characters typed, pasted or
    /// corrected in, between the start and the end the two share. Empty for
    /// a backspace.
    static func typed(from old: String, to new: String) -> String {
        let a = Array(old), b = Array(new)
        var head = 0
        while head < a.count, head < b.count, a[head] == b[head] { head += 1 }
        var tail = 0
        while tail < a.count - head, tail < b.count - head, a[a.count - 1 - tail] == b[b.count - 1 - tail] {
            tail += 1
        }
        return String(b[head..<(b.count - tail)])
    }
}
