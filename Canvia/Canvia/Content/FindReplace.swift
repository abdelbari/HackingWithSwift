// Find and replace's rules, kept pure so both phones run the same rows: where
// a needle is in a box's words, which boxes are searched, and how the sheet's
// Previous and Next and Replace move through the matches. The store finds and
// replaces with these (DesignStore's find and replace); the Android twin's
// core FindReplace.kt holds the same rules over the same test rows.

import Foundation

enum FindReplace {

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
    /// (Lock; a position lock still takes new words). The same rule on the
    /// Android twin.
    static func searches(_ el: Element) -> Bool {
        ShapeText.carriesWords(el) && !el.isHidden
            && ElementLock.allows(ElementLock.mode(of: el), ElementLock.Action.editText)
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
        return "\(min(max(current, 0), count - 1) + 1) of \(count)"
    }
}
