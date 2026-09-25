// Bold, italic, underlined or struck words inside one text element, written
// the way people already write them in messages: **bold**, *italic* or
// _italic_, __underline__, ~~strike~~. The markers are stripped for display,
// measurement and export, and the words between them get the style — on the
// canvas, in the SVG's outlines and in the PDF alike. An unmatched marker,
// or one that would split a word (snake_case, 2*3), is left as it is.

import Foundation
import UIKit

enum RichText {

    struct Style: Equatable, Hashable {
        var bold = false
        var italic = false
        var underline = false
        var strike = false
        var isPlain: Bool { !bold && !italic && !underline && !strike }
    }

    struct Run: Equatable {
        /// UTF-16 offsets into the plain text, as NSAttributedString counts.
        var range: NSRange
        var style: Style
    }

    struct Parsed: Equatable {
        var plain: String
        var runs: [Run]
    }

    private static let doubles: [(marker: String, toggle: (inout Style) -> Void, isOn: (Style) -> Bool)] = [
        ("**", { $0.bold.toggle() }, { $0.bold }),
        ("__", { $0.underline.toggle() }, { $0.underline }),
        ("~~", { $0.strike.toggle() }, { $0.strike }),
    ]

    static func hasMarkup(_ text: String) -> Bool {
        text.contains("*") || text.contains("_") || text.contains("~")
    }

    static func strip(_ text: String) -> String {
        hasMarkup(text) ? parse(text).plain : text
    }

    static func parse(_ text: String) -> Parsed {
        parseMapped(text).parsed
    }

    /// The parse, with where each plain character came from in `text`, as
    /// character offsets.
    private static func parseMapped(_ text: String) -> (parsed: Parsed, rawAt: [Int]) {
        guard hasMarkup(text) else { return (Parsed(plain: text, runs: []), Array(0..<text.count)) }
        var rawAt: [Int] = []
        let chars = Array(text)
        var plain = ""
        var style = Style()
        var runs: [Run] = []
        var runStart = 0           // utf16 offset where the current style began
        var offset = 0             // utf16 length of plain so far
        var i = 0

        func closeRun() {
            if !style.isPlain, offset > runStart {
                runs.append(Run(range: NSRange(location: runStart, length: offset - runStart), style: style))
            }
            runStart = offset
        }
        func isWord(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }
        func rest(from j: Int) -> String { String(chars[j...]) }
        func at(_ j: Int, _ marker: String) -> Bool {
            let m = Array(marker)
            guard j + m.count <= chars.count else { return false }
            return Array(chars[j..<(j + m.count)]) == m
        }

        while i < chars.count {
            var consumed = false
            // Double markers first, so ** is bold and not two italics.
            for d in doubles where at(i, d.marker) {
                let on = d.isOn(style)
                let after = i + 2 < chars.count ? chars[i + 2] : nil
                let before = i > 0 ? chars[i - 1] : nil
                // Opening: something follows that is not a space, and a
                // closing marker exists later. Closing: the run is on and
                // the marker does not sit before a letter of the same word.
                let opens = !on && after != nil && after != " " && rest(from: i + 2).contains(d.marker)
                let closes = on && before != " "
                if opens || closes {
                    closeRun()
                    d.toggle(&style)
                    i += 2
                    consumed = true
                    break
                }
            }
            if consumed { continue }

            let c = chars[i]
            if c == "*" || c == "_" {
                let before = i > 0 ? chars[i - 1] : nil
                let after = i + 1 < chars.count ? chars[i + 1] : nil
                if style.italic {
                    // Closing italic: not inside a word, and not a space before.
                    if before != " " && !(isWord(before) && isWord(after)) && before != nil {
                        closeRun()
                        style.italic = false
                        i += 1
                        continue
                    }
                } else if !isWord(before), let after, after != " ", after != c,
                          closingItalic(in: chars, from: i + 1, marker: c) {
                    closeRun()
                    style.italic = true
                    i += 1
                    continue
                }
            }
            plain.append(c)
            rawAt.append(i)
            offset += String(c).utf16.count
            i += 1
        }
        closeRun()
        return (Parsed(plain: plain, runs: runs), rawAt)
    }

    /// The text with only its first `count` characters showing — counted as
    /// they read, markers not counted — and the markers still round them, so a
    /// typewriter on `**Sale** today` shows a bold "Sa", never "**Sa". The
    /// text is cut just after the last character shown and the styles that
    /// character is in are closed there; should the result not read back as
    /// the same words in the same styles, the words are shown plain instead.
    /// The Android twin's `RichText.revealed`, step for step.
    static func revealed(_ text: String, count: Int) -> String {
        let (full, rawAt) = parseMapped(text)
        let plain = Array(full.plain)
        guard count < plain.count else { return text }
        guard count > 0 else { return "" }
        let shown = String(plain.prefix(count))
        guard !full.runs.isEmpty else { return shown }
        let lastOffset = String(plain.prefix(count - 1)).utf16.count
        let open = style(of: full.runs, at: lastOffset)
        let chars = Array(text)
        let head = String(chars[0...rawAt[count - 1]])
        var body = head
        while body.hasSuffix(" ") { body.removeLast() }
        let spaces = String(repeating: " ", count: head.count - body.count)
        func closers(_ italic: String) -> String {
            var out = ""
            if open.italic { out += italic }
            if open.bold { out += "**" }
            if open.underline { out += "__" }
            if open.strike { out += "~~" }
            return out
        }
        for italic in ["*", "_"] {
            let candidate = body + closers(italic) + spaces
            if reads(parse(candidate), as: shown, runs: full.runs) { return candidate }
            if !open.italic { break }
        }
        return shown
    }

    private static func style(of runs: [Run], at offset: Int) -> Style {
        runs.first { NSLocationInRange(offset, $0.range) }?.style ?? Style()
    }

    /// Whether `parsed` is `plain` with every character but trailing spaces
    /// in the style `runs` give it there.
    private static func reads(_ parsed: Parsed, as plain: String, runs: [Run]) -> Bool {
        guard parsed.plain == plain else { return false }
        var words = plain
        while words.hasSuffix(" ") { words.removeLast() }
        var offset = 0
        for c in words {
            if style(of: parsed.runs, at: offset) != style(of: runs, at: offset) { return false }
            offset += String(c).utf16.count
        }
        return true
    }

    /// Whether a single marker later in the text can close an italic run:
    /// preceded by a non-space and not splitting a word.
    private static func closingItalic(in chars: [Character], from start: Int, marker: Character) -> Bool {
        var j = start
        while j < chars.count {
            if chars[j] == marker, j > start {
                let before = chars[j - 1], after = j + 1 < chars.count ? chars[j + 1] : nil
                let isWord = { (c: Character?) in c.map { $0.isLetter || $0.isNumber } ?? false }
                if before != " " && !(isWord(before) && isWord(after)) { return true }
            }
            j += 1
        }
        return false
    }

    /// The plain text with the base attributes, and each run's style on top.
    static func attributed(_ marked: String, base: [NSAttributedString.Key: Any],
                           font: (_ bold: Bool, _ italic: Bool) -> UIFont) -> NSAttributedString {
        let parsed = parse(marked)
        let out = NSMutableAttributedString(string: parsed.plain, attributes: base)
        for run in parsed.runs {
            var attrs: [NSAttributedString.Key: Any] = [:]
            if run.style.bold || run.style.italic { attrs[.font] = font(run.style.bold, run.style.italic) }
            if run.style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.style.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            out.addAttributes(attrs, range: run.range)
        }
        return out
    }
}
