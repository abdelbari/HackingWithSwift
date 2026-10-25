// Change case: UPPERCASE, lowercase, Title Case and Sentence case rewrite
// the words themselves — the ones chosen, or the whole box with none — in
// the design's language (Proofreader.writingLanguage), so Turkish keeps its
// dotted and dotless i. Unlike capitals (a box's `uppercase`, a span's
// caps), which only draw the words so, the words as typed change, and Find,
// spelling and screen readers read them changed.
//
// The rules both phones share, over the same rows (Fixtures/change-case.json):
// each letter is cased on its own, so a styled letter keeps its style and a
// letter that grows (ß to SS) takes its style with it. Where words and
// sentences start is read from all of the box's words, not just the ones
// chosen:
//  - Title Case: a letter starts a word when the character before it is not
//    a letter or a digit, nor an apostrophe (' or ’) straight after one; it
//    is upper case, every other letter lower case ("don't stop" → "Don't
//    Stop", "say 'hi'" → "Say 'Hi'", "3RD" → "3rd").
//  - Sentence case: going back from a letter over what is not a letter or a
//    digit, the start of the words or a line break comes first, or a ".",
//    "!" or "?" with at least one space between it and the letter: then it
//    starts a sentence and is upper case; every other letter lower case
//    ("...and then" stays as it is; a digit before any letter starts
//    nothing).
// A digit is a decimal digit only (not ² or ½), as on the Android twin.
// Markers (**bold**), the words' own colours, sizes and other spans, and
// each line's list and alignment move with the words.

import Foundation

enum ChangeCase {

    /// The four, in the order the menus list them.
    enum Casing: String, CaseIterable, Identifiable {
        case upper, lower, title, sentence

        var id: String { rawValue }

        /// What the menu calls it, each in its own case.
        var label: String {
            switch self {
            case .upper: return tr("UPPERCASE")
            case .lower: return tr("lowercase")
            case .title: return tr("Title Case")
            case .sentence: return tr("Sentence case")
            }
        }
    }

    /// The name the step takes in Undo.
    static var stepName: String { tr("Change case") }

    /// The locale the design's language cases words in.
    static func locale(_ language: String?) -> Locale {
        Locale(identifier: Proofreader.writingLanguage(language))
    }

    /// A letter or a decimal digit — what joins a word, as the Android
    /// twin's isLetterOrDigit reads it (² and ½ are neither).
    static func joins(_ c: Character) -> Bool {
        c.isLetter || c.unicodeScalars.first?.properties.generalCategory == .decimalNumber
    }

    private static func isApostrophe(_ c: Character) -> Bool { c == "'" || c == "’" }

    /// Whether the letter at `i` starts a word, for Title Case.
    private static func startsWord(_ chars: [Character], _ i: Int) -> Bool {
        guard i > 0 else { return true }
        let before = chars[i - 1]
        if joins(before) { return false }
        if isApostrophe(before), i >= 2, joins(chars[i - 2]) { return false }
        return true
    }

    /// Whether the letter at `i` starts a sentence, for Sentence case.
    private static func startsSentence(_ chars: [Character], _ i: Int) -> Bool {
        var k = i - 1
        var spaced = false
        while k >= 0 {
            let c = chars[k]
            if c == "\n" || c == "\r\n" { return true }
            if c == "." || c == "!" || c == "?" { return spaced }
            if joins(c) { return false }
            if c.isWhitespace { spaced = true }
            k -= 1
        }
        return true
    }

    /// Each character of `chars` cased as `kind` asks — the ones at
    /// `indices` only, the rest as they are — one string a character.
    static func cased(_ chars: [Character], _ kind: Casing, in indices: Range<Int>, locale: Locale) -> [String] {
        chars.enumerated().map { i, c -> String in
            guard indices.contains(i) else { return String(c) }
            let up: Bool
            switch kind {
            case .upper: up = true
            case .lower: up = false
            case .title: up = c.isLetter && startsWord(chars, i)
            case .sentence: up = c.isLetter && startsSentence(chars, i)
            }
            return up ? String(c).uppercased(with: locale) : String(c).lowercased(with: locale)
        }
    }

    /// `plain` with the characters in UTF-16 range `range` (all of it for
    /// nil) cased as `kind` asks: what the shared rows check.
    static func transformed(_ plain: String, _ kind: Casing, range: NSRange? = nil, locale: Locale) -> String {
        let chars = Array(plain)
        return cased(chars, kind, in: characters(of: range, in: chars), locale: locale).joined()
    }

    /// The characters of `chars` UTF-16 range `range` covers — every one
    /// it touches — or all of them for nil.
    static func characters(of range: NSRange?, in chars: [Character]) -> Range<Int> {
        guard let range else { return 0..<chars.count }
        var lo: Int?
        var hi = 0
        var offset = 0
        for (i, c) in chars.enumerated() {
            let width = String(c).utf16.count
            if offset + width > range.location && offset < NSMaxRange(range) {
                if lo == nil { lo = i }
                hi = i + 1
            }
            offset += width
        }
        guard let lo else { return 0..<0 }
        return lo..<hi
    }

    /// `el` with the words in `selection` — a UTF-16 range of its stored
    /// words; nil or empty for all of them — cased as `kind` asks in
    /// `locale`: their markers kept on the same letters, spans moved with
    /// them and each line keeping its list and alignment. Nil when nothing
    /// would change.
    static func changed(_ el: Element, selection: NSRange?, _ kind: Casing, locale: Locale) -> Element? {
        let raw = el.text ?? ""
        let oldPlain = RichText.strip(raw)
        let chars = Array(oldPlain)
        let styles = RichText.styles(of: raw)
        guard !chars.isEmpty, styles.count == chars.count else { return nil }
        let chosen = selection.flatMap { RichText.plainRange(of: $0, in: raw) }
        let indices = characters(of: chosen, in: chars)
        let out = cased(chars, kind, in: indices, locale: locale)
        // Each new character in the style of the one it came from, and where
        // each old character's start lands, for the spans.
        var newChars: [Character] = []
        var newStyles: [RichText.Style] = []
        var moved: [Int: Int] = [:]
        var from = 0, to = 0
        for (i, piece) in out.enumerated() {
            moved[from] = to
            for c in piece {
                newChars.append(c)
                newStyles.append(styles[i])
            }
            from += String(chars[i]).utf16.count
            to += piece.utf16.count
        }
        moved[from] = to
        let newPlain = String(newChars)
        guard newPlain != oldPlain else { return nil }
        let lines = TextLists.paragraphsOf(el)
        let spans = el.liveSpans.compactMap { span -> TextSpan? in
            var shifted = span
            shifted.start = landing(span.start, moved)
            shifted.end = landing(span.end, moved)
            return shifted.end > shifted.start ? shifted : nil
        }
        var result = el
        result.text = RichText.written(newPlain, styles: newStyles)
        result.moveLines(from: oldPlain, lines)
        if el.spans != nil || el.spansText != nil { result.setSpans(spans) }
        return result
    }

    /// Where old offset `offset` lands: its character's start moved, or for
    /// one inside a character, the start of that character's.
    private static func landing(_ offset: Int, _ moved: [Int: Int]) -> Int {
        if let exact = moved[offset] { return exact }
        let before = moved.keys.filter { $0 <= offset }.max() ?? 0
        return moved[before] ?? 0
    }
}
