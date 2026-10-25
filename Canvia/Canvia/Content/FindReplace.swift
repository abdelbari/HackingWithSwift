// Find and replace's rules, kept pure so both phones run the same rows: where
// a needle is in a box's words, which boxes are searched, and how the sheet's
// Previous and Next and Replace move through the matches. The store finds and
// replaces with these (DesignStore's find and replace); the Android twin's
// core FindReplace.kt holds the same rules over the same test rows.

import Foundation
import UIKit

enum FindReplace {

    /// Where a match or a misspelling is: in a box's words, or in a page's
    /// speaker notes — searched and checked as plain text after the page's
    /// boxes — or in a Doc's block (Docs): a text block's words as a box's,
    /// a table's cell as plain text. The Android twin's kinds, by the same
    /// names.
    enum Kind: String {
        case element, notes, doc
    }

    /// Where `needle` is in `body`, as UTF-16 ranges, left to right and never
    /// overlapping: "aa" is twice in "aaaa", not three times. Case aside
    /// unless `caseSensitive`.
    ///
    /// With `wholeWord`, the occurrences are the same ones, less any with a
    /// letter or a digit (Unicode \p{L} or \p{N}) right before or after it —
    /// the simplest rule: "cat" in "cat, catalog" is found once. A dropped
    /// occurrence is searched again from its second character, since a whole
    /// word may start inside it: "ha ha" in "aha ha ha" is the one at 4.
    static func ranges(of needle: String, in body: String, caseSensitive: Bool, wholeWord: Bool) -> [NSRange] {
        guard !needle.isEmpty, !body.isEmpty else { return [] }
        let ns = body as NSString
        let options: NSString.CompareOptions = caseSensitive ? [.literal] : [.caseInsensitive]
        var found: [NSRange] = []
        var from = 0
        while from < ns.length {
            let hit = ns.range(of: needle, options: options, range: NSRange(location: from, length: ns.length - from))
            guard hit.location != NSNotFound, hit.length > 0 else { break }
            if !wholeWord || standsAlone(hit, in: ns) {
                found.append(hit)
                from = NSMaxRange(hit)
            } else {
                // Not a whole word here; one may start inside it.
                from = hit.location + 1
            }
        }
        return found
    }

    /// Whether neither neighbour of `range` in `text` is a letter or a digit.
    static func standsAlone(_ range: NSRange, in text: NSString) -> Bool {
        !isWordCharacter(scalar(before: range.location, in: text))
            && !isWordCharacter(scalar(at: NSMaxRange(range), in: text))
    }

    /// A letter or a digit, of any script: what Whole words will not have
    /// touching a match. A combining accent, a dash, an underscore or a mark
    /// of punctuation is none.
    static func isWordCharacter(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    /// The character that ends just before UTF-16 offset `index`.
    private static func scalar(before index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index > 0, index <= text.length else { return nil }
        let low = text.character(at: index - 1)
        if UTF16.isTrailSurrogate(low), index > 1 {
            let high = text.character(at: index - 2)
            if UTF16.isLeadSurrogate(high) { return pair(high, low) }
        }
        return Unicode.Scalar(low)
    }

    /// The character that starts at UTF-16 offset `index`.
    private static func scalar(at index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index >= 0, index < text.length else { return nil }
        let high = text.character(at: index)
        if UTF16.isLeadSurrogate(high), index + 1 < text.length {
            let low = text.character(at: index + 1)
            if UTF16.isTrailSurrogate(low) { return pair(high, low) }
        }
        return Unicode.Scalar(high)
    }

    private static func pair(_ high: UInt16, _ low: UInt16) -> Unicode.Scalar? {
        Unicode.Scalar(0x10000 + ((UInt32(high) - 0xD800) << 10) + (UInt32(low) - 0xDC00))
    }

    /// Whether a box's words are searched and replaced: a text box's, or the
    /// words a shape carries, unless it is hidden or locked against typing
    /// (Lock; a position lock still takes new words), or a caption box, whose
    /// words are its cues, drawn one at a time, and changed in Edit
    /// captions. A chart's words are searched, all of them; a replacement
    /// in its labels and legend changes its data too
    /// (DataGraphics.keepingLabel). The same rule on the Android twin.
    static func searches(_ el: Element) -> Bool {
        ShapeText.carriesWords(el) && !el.isHidden && el.captions == nil
            && ElementLock.allows(ElementLock.mode(of: el), ElementLock.Action.editText)
    }

    /// Whether a box's words found (searches) are replaced: not a chart's
    /// value labels and axis numbers, which its data draws — found, as the
    /// Android twin finds them, but never changed, nor counted as replaced.
    static func replaces(_ el: Element) -> Bool {
        searches(el) && !(el.chart != nil && derivedParts.contains(el.chartPart ?? ""))
    }

    /// A chart's parts drawn from its numbers, never replaced.
    static let derivedParts: Set<String> = ["value", "axis"]

    // MARK: the words as they read

    /// Where `needle` is in `text` as it reads — its style markers left out,
    /// as the spelling check reads it, so "Big sale" is found in
    /// "**Big** sale" — each match as a range of the words as they read and
    /// as the stored range it is placed at (RichText.storedRange: the markers
    /// between it and the words beside it taken in, 0..12 there). Match case
    /// and Whole words as `ranges` has them, on the words as they read.
    static func matches(of needle: String, in text: String, caseSensitive: Bool,
                        wholeWord: Bool) -> [(plain: NSRange, stored: NSRange)] {
        let plain = RichText.strip(text)
        let hits = ranges(of: needle, in: plain, caseSensitive: caseSensitive, wholeWord: wholeWord)
        guard !hits.isEmpty else { return [] }
        // The words' map worked out once for every match, not once each.
        let units = RichText.typedUnits(text)
        let stored = text as NSString
        return hits.map { hit in
            (plain: hit, stored: RichText.storedRange(of: hit, units: units, stored: stored))
        }
    }

    /// `text` with the words in `range` — of the words as they read —
    /// replaced, as a spelling fix keeps the styling round a word: the new
    /// words in the style of the first one they replace, every marker wholly
    /// outside them left as it was, and those among them taken out and
    /// written again round the new words (RichText.replacing). "**Big**
    /// sale" with "Big sale" replaced by "huge deal" is "**huge deal**".
    /// Where the markers cannot say it, the stored characters are replaced
    /// as they are. The replacement reads exactly as typed: its stars and
    /// underscores are escaped (RichText.escapeLiteral), never styling.
    static func replacing(_ range: NSRange, in text: String, with replacement: String) -> String {
        let style = RichText.styleAt(range.location, in: text)
        if let out = RichText.replacing(range, in: text, with: replacement, style: style) { return out }
        let stored = RichText.storedRange(of: range, in: text)
        return (text as NSString).replacingCharacters(in: stored, with: RichText.escapeLiteral(replacement))
    }

    // MARK: the match showing

    /// What the match's letters are marked by while they are laid out.
    private static let matchKey = "find-match"

    /// The letters of words `range` — of the words as they read — in `el`,
    /// as the canvas draws them: a rectangle for each word of them on each
    /// line, as WordLinks finds a link's, in the element's own space on the
    /// page's side of its flip (its top-left the origin, y down, before its
    /// turn) — a shape's words in the box they sit in — for Find to mark
    /// the match it is showing. None for words round a curve, along a path,
    /// down a column or beside a drop cap, which are drawn another way; the
    /// canvas marks the whole box there.
    static func letterRects(of range: NSRange, in el: Element) -> [CGRect] {
        if el.type == .shape {
            guard ShapeText.takesText(el) else { return [] }
            let box = ShapeText.shownBox(for: el)
            return letterRects(of: range, inWords: ShapeText.textElement(for: el)).map {
                $0.offsetBy(dx: box.minX, dy: box.minY)
            }
        }
        let w = CGFloat(el.w), h = CGFloat(el.h)
        return letterRects(of: range, inWords: el).map { rect in
            CGRect(x: el.flipH ? w - rect.maxX : rect.minX, y: el.flipV ? h - rect.maxY : rect.minY,
                   width: rect.width, height: rect.height)
        }
    }

    /// The same in a text box's own space, before any flip.
    private static func letterRects(of range: NSRange, inWords el: Element) -> [CGRect] {
        guard el.w > 0, range.length > 0, !TextOutliner.followsAPath(el) else { return [] }
        var drawn = el
        if el.fitText == true { drawn.fontSize = FontLibrary.fittingFontSize(for: el) }
        if TextEffect.from(el.effect) == .none, FontLibrary.dropCapLayout(for: drawn) != nil { return [] }
        // The words as drawn — past a list's markers, in capitals — found
        // as a span on them is (FontLibrary.displaySpans).
        var probe = drawn
        probe.setSpans([TextSpan(start: range.location, end: NSMaxRange(range), scale: 2)])
        let marked = FontLibrary.markedDisplayText(for: probe, pageNumber: nil, pageCount: nil)
        // In capitals as the box draws them: its own, or its words' (caps).
        let shown = FontLibrary.capitalised(drawn, marked: marked,
                                            spans: FontLibrary.displaySpans(for: probe, marked: marked)).spans
        let text = NSMutableAttributedString(attributedString: FontLibrary.attributedString(for: drawn))
        text.removeAttribute(Spans.linkKey, range: NSRange(location: 0, length: text.length))
        for span in shown {
            let lo = min(max(span.start, 0), text.length), hi = min(span.end, text.length)
            guard hi > lo else { continue }
            text.addAttribute(Spans.linkKey, value: matchKey, range: NSRange(location: lo, length: hi - lo))
        }
        let top = CGFloat(SVGExporter.textTop(el))
        return WordLinks.wordRects(text, width: el.w)
            .filter { $0.url == matchKey }
            .map { $0.rect.offsetBy(dx: 0, dy: top) }
    }

    // MARK: stepping through the matches

    /// Previous (-1) or Next (+1) from match `current` of `count`, going
    /// round at either end; 0 when there are none.
    static func step(from current: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let at = min(max(current, 0), count - 1)
        return ((at + delta) % count + count) % count
    }

    /// The readout between Previous and Next: "3 of 12" for the third of
    /// twelve; empty with none.
    static func position(_ current: Int, of count: Int) -> String {
        guard count > 0 else { return "" }
        return tr("%d of %d", min(max(current, 0), count - 1) + 1, count)
    }
}
