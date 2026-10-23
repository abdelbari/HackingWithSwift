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
    static let gradientWordsNote = tr("Gradient letters colour every word. Choose a colour for the text to colour words on their own.")

    /// What the colour sheet says over its colours when it is open for the
    /// words chosen, in the words the Android twin's colour panel uses.
    static let wordColourNote = tr("Colouring the selected words. The box's own colour gives them back to it.")

    /// The colour well: the typing so far kept as its own step, and the
    /// colour sheet asked for the words chosen — or, on gradient letters,
    /// why not.
    func chooseWordColour(_ id: String, range: NSRange) {
        guard let el = element(id), el.type == .text, !el.locked, range.length > 0 else { return }
        // A photo in the letters colours every word too, as a gradient does.
        if FontLibrary.paintsLetters(el) {
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
    /// the box's own colour, size, face, weight and slant, as one step.
    /// Links stay: a link is not a look, and it has its own Remove.
    func clearWordStyles() {
        updateSelected { el in
            guard el.type == .text, el.spans != nil || el.spansText != nil else { return }
            el.setSpans(Spans.linksOnly(el.liveSpans))
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

    // MARK: fonts on words

    /// What the font sheet says over its fonts when it is open for the words
    /// chosen, in the words the Android twin's font sheet uses.
    static let wordFontNote = tr("For the selected words")

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

    /// The font the selected words' Weight row lists: theirs when they
    /// share one, else the box's own — as the Android twin's WordsFace.
    var wordFace: String {
        if let font = wordFont { return font }
        return FontLibrary.resolve(wordFontTarget.flatMap { element($0.id) }?.fontFamily)
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

    // MARK: weight and slant on words

    /// The weight the words the font sheet is open for share — the box's
    /// own (FontLibrary.weight(of:)) where they have none of their own —
    /// or nil when they differ ("Mixed"). The Android twin's Spans.weightOf.
    var wordWeight: Int? {
        guard let target = wordFontTarget, let el = element(target.id) else { return nil }
        let shared = Spans.weight(of: el.liveSpans, in: target.range)
        return shared.shared ? (shared.weight ?? FontLibrary.weight(of: el)) : nil
    }

    /// Whether the words the font sheet is open for are all slanted — the
    /// box's own slant for words with none of their own — or nil when they
    /// differ ("Mixed"). The Android twin's Spans.italicOf.
    var wordItalic: Bool? {
        guard let target = wordFontTarget, let el = element(target.id) else { return nil }
        let shared = Spans.italic(of: el.liveSpans, in: target.range)
        return shared.shared ? (shared.italic ?? FontLibrary.isItalic(el)) : nil
    }

    /// The words the sheet is open for at `weight`, as one step, the box
    /// measured again. The box's own weight takes the words' own away, so
    /// they follow the box again, as on the Android twin.
    func weightWords(_ weight: Int) {
        guard let target = wordFontTarget else { return }
        updateSelected { el in
            guard el.id == target.id else { return }
            let own: Int? = weight == FontLibrary.weight(of: el) ? nil : weight
            Self.restyleWords(&el, target.range) { Spans.weighting($0, range: $1, weight: own) }
        }
    }

    /// The words the sheet is open for slanted or upright, as one step. The
    /// box's own slant takes the words' own away.
    func italicWords(_ italic: Bool) {
        guard let target = wordFontTarget else { return }
        updateSelected { el in
            guard el.id == target.id else { return }
            let own: Bool? = italic == FontLibrary.isItalic(el) ? nil : italic
            Self.restyleWords(&el, target.range) { Spans.italicising($0, range: $1, italic: own) }
        }
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
