// Colours, sizes, fonts and links on chosen words, from the bar over the
// keyboard while a box is typed in: its colour well opens the colour sheet
// for the words chosen, A- and A+ set them a step smaller or larger, Aa opens
// the font sheet for them and Link asks for a link, as the element's own Link
// does. Each is a step of its own, between the words typed before it and
// after, as on the Android twin; and the Text controls take every colour,
// size and font off the words at once. The words themselves are in Spans.

import Foundation

/// Words in one text box: which box, and where among its words as they read.
struct WordRange: Equatable {
    var id: String
    var range: NSRange
}

extension DesignStore {

    /// What the colour well says on letters filled with a gradient, which
    /// colours on words would not show through.
    static let gradientWordsNote = "Gradient letters colour every word. Choose a colour for the text to colour words on their own."

    /// What the colour sheet says over its colours when it is open for the
    /// words chosen, in the words the Android twin's colour panel uses.
    static let wordColourNote = "Colouring the selected words. The box's own colour gives them back to it."

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

    /// A- or A+: the words in `range` of box `id` a step smaller or larger,
    /// as one step, the box measured again.
    func scaleWords(_ id: String, range: NSRange, by factor: Double) {
        guard range.length > 0 else { return }
        updateSelected { el in
            guard el.id == id else { return }
            Self.restyleWords(&el, range) { Spans.scaling($0, range: $1, by: factor) }
        }
    }

    /// Clear word colours and sizes: every word of the selected text back in
    /// the box's own colour, size and face, as one step. Links stay: a link
    /// is not a look, and it has its own Remove.
    func clearWordStyles() {
        updateSelected { el in
            guard el.type == .text, el.spans != nil || el.spansText != nil else { return }
            el.setSpans(Spans.linksOnly(el.liveSpans))
        }
    }

    // MARK: fonts on words

    /// What the font sheet says over its fonts when it is open for the words
    /// chosen, in the words the Android twin's font sheet uses.
    static let wordFontNote = "For the selected words"

    /// Aa on the typing bar: the typing so far kept as its own step, and the
    /// font sheet asked for the words chosen.
    func chooseWordFont(_ id: String, range: NSRange) {
        guard let el = element(id), el.type == .text, !el.locked, range.length > 0 else { return }
        commit()
        wordFontTarget = WordRange(id: id, range: range)
    }

    /// The face the words the sheet is open for share — the box's own where
    /// they have none of their own — or nil when they differ.
    var wordFont: String? {
        guard let target = wordFontTarget, let el = element(target.id) else { return nil }
        let shared = Spans.font(of: el.liveSpans, in: target.range)
        return shared.shared ? (shared.font ?? el.fontFamily ?? "sans") : nil
    }

    /// The words the sheet is open for in face `key`, as one step, the box
    /// measured again. The box's own face takes the words' own away.
    func fontWords(_ key: String) {
        guard let target = wordFontTarget else { return }
        updateSelected { el in
            guard el.id == target.id else { return }
            let own = Self.wordFontKey(key, in: el)
            Self.restyleWords(&el, target.range) { Spans.fonting($0, range: $1, font: own) }
        }
    }

    /// `key` as the words' own face: none when it is the box's, an old name
    /// counting as the family it means.
    static func wordFontKey(_ key: String, in el: Element) -> String? {
        FontLibrary.resolve(key) == FontLibrary.resolve(el.fontFamily) ? nil : key
    }

    // MARK: links on words

    /// Link on the typing bar: the typing so far kept as its own step, and
    /// the link asked for the words chosen.
    func chooseWordLink(_ id: String, range: NSRange) {
        guard let el = element(id), el.type == .text, !el.locked, range.length > 0 else { return }
        commit()
        wordLinkTarget = WordRange(id: id, range: range)
    }

    /// The link every word in `target` has, if they share one.
    func sharedLink(of target: WordRange) -> String? {
        guard let el = element(target.id) else { return nil }
        let shared = Spans.link(of: el.liveSpans, in: target.range)
        return shared.shared ? shared.link : nil
    }

    /// The words in `target` linked to `link` — as Links reads what was
    /// typed — or unlinked with nil, as one step.
    func linkWords(_ link: String?, in target: WordRange) {
        let url = link.flatMap(Links.normalized)
        updateSelected { el in
            guard el.id == target.id else { return }
            Self.restyleWords(&el, target.range) { Spans.linking($0, range: $1, link: url) }
        }
    }
}
