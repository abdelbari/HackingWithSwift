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
//    a letter, a digit or an apostrophe (' or ’); it is upper case, every
//    other letter lower case ("don't stop" → "Don't Stop", "3RD" → "3rd").
//  - Sentence case: every letter lower case but the first letter of the
//    words, of each line, and the first after ".", "!" or "?" and then a
//    space; a digit before any letter starts nothing.
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

    /// Each character of `chars` cased as `kind` asks — the ones at
    /// `indices` only, the rest as they are — one string a character.
    static func cased(_ chars: [Character], _ kind: Casing, in indices: Range<Int>, locale: Locale) -> [String] {
        func upper(_ c: Character) -> String { String(c).uppercased(with: locale) }
        func lower(_ c: Character) -> String { String(c).lowercased(with: locale) }
        var out: [String] = []
        var sentenceStart = true
        var sentenceEnded = false
        for (i, c) in chars.enumerated() {
            let shown: String
            switch kind {
            case .upper: shown = upper(c)
            case .lower: shown = lower(c)
            case .title:
                let before: Character? = i > 0 ? chars[i - 1] : nil
                let joined = before.map { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "’" } ?? false
                shown = c.isLetter && !joined ? upper(c) : lower(c)
            case .sentence:
                shown = c.isLetter && sentenceStart ? upper(c) : lower(c)
            }
            // Where the next sentence starts.
            if c.isLetter || c.isNumber {
                sentenceStart = false
                sentenceEnded = false
            } else if c == "\n" || c == "\r\n" {
                sentenceStart = true
            } else if c == "." || c == "!" || c == "?" {
                sentenceEnded = true
            } else if c.isWhitespace, sentenceEnded {
                sentenceStart = true
            }
            out.append(indices.contains(i) ? shown : String(c))
        }
        return out
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
