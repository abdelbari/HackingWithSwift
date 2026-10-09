// Colours and sizes on chosen words, from the bar over the keyboard while a
// box is typed in: its colour well opens the colour sheet for the words
// chosen, and A− and A+ set them a step smaller or larger. Each is a step of
// its own, between the words typed before it and after, as on the Android
// twin; and the Text controls take every colour and size off the words at
// once. The words themselves are in Spans.

import Foundation

/// Words in one text box: which box, and where among its words as they read.
struct WordRange: Equatable {
    var id: String
    var range: NSRange
}

extension DesignStore {

    /// What the colour well says on letters filled with a gradient, which
    /// colours on words would not show through.
    static let gradientWordsNote = "Word colours don't show on gradient text. Give the text a plain colour first."

    /// The colour well: the typing so far kept as its own step, and the
    /// colour sheet asked for the words chosen — or, on gradient letters,
    /// why not.
    func chooseWordColour(_ id: String, range: NSRange) {
        guard let el = element(id), el.type == .text, !el.locked, range.length > 0 else { return }
        if el.textFill?.kind == "gradient" {
            buzz(.reject)
            announce(Self.gradientWordsNote, undoable: false)
            return
        }
        commit()
        wordColourTarget = WordRange(id: id, range: range)
    }

    /// The colour the words the sheet is open for share — the box's own
    /// where they have none of their own — or nil when they differ.
    var wordColour: String? {
        guard let target = wordColourTarget, let el = element(target.id) else { return nil }
        let shared = Spans.colour(of: el.liveSpans, in: target.range)
        return shared.shared ? (shared.color ?? el.color ?? "#1f2430") : nil
    }

    /// The words the sheet is open for in `hex`, as one step — after any
    /// drag of the colour wheel before it, closed as a step of its own. The
    /// box's own colour takes the words' own away, so they follow the box
    /// again, as on the Android twin.
    func colourWords(_ hex: String) {
        guard let target = wordColourTarget else { return }
        commit()
        updateSelected { el in
            guard el.id == target.id else { return }
            let own = Self.wordHex(hex, in: el)
            Self.restyleWords(&el, target.range) { Spans.colouring($0, range: $1, color: own) }
        }
    }

    /// The same while the colour wheel is dragged; the sheet closing records
    /// the drag as one step.
    func colourWordsTransient(_ hex: String) {
        guard let target = wordColourTarget else { return }
        updateSelectedTransient { el in
            guard el.id == target.id else { return }
            let own = Self.wordHex(hex, in: el)
            Self.restyleWords(&el, target.range) { Spans.colouring($0, range: $1, color: own) }
        }
    }

    /// `hex` as the words' own colour: none when it is the box's.
    static func wordHex(_ hex: String, in el: Element) -> String? {
        hex.lowercased() == el.color?.lowercased() ? nil : hex
    }

    /// A− or A+: the words in `range` of box `id` a step smaller or larger,
    /// as one step, the box measured again.
    func scaleWords(_ id: String, range: NSRange, by factor: Double) {
        guard range.length > 0 else { return }
        updateSelected { el in
            guard el.id == id else { return }
            Self.restyleWords(&el, range) { Spans.scaling($0, range: $1, by: factor) }
        }
    }

    /// Clear word colours and sizes: every word of the selected text back in
    /// the box's own colour and size, as one step.
    func clearWordStyles() {
        updateSelected { el in
            guard el.type == .text, el.spans != nil || el.spansText != nil else { return }
            el.setSpans([])
        }
    }

    /// `el`'s spans changed by `change` over `range` of its words as they
    /// read, kept within the words.
    static func restyleWords(_ el: inout Element, _ range: NSRange,
                             _ change: ([TextSpan], NSRange) -> [TextSpan]) {
        guard el.type == .text else { return }
        let length = (RichText.strip(el.text ?? "") as NSString).length
        let lo = min(max(range.location, 0), length), hi = min(NSMaxRange(range), length)
        guard hi > lo else { return }
        el.setSpans(change(el.liveSpans, NSRange(location: lo, length: hi - lo)))
    }
}
