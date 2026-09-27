// Bold, italic, underlined or struck words inside one text element, written
// the way people already write them in messages: **bold**, *italic* or
// _italic_, __underline__, ~~strike~~. The markers are stripped for display,
// measurement and export, and the words between them get the style — on the
// canvas, in the SVG's outlines and in the PDF alike. An unmatched marker,
// or one that would split a word (snake_case, 2*3), is left as it is.
//
// The bar over the keyboard puts the markers round chosen words and takes
// them off again (toggling), and a box set in capitals is uppercased here,
// run by run, after the markers are read (inCapitals).

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

    /// The four styles a marker switches, and the marker the typing bar
    /// puts round words for each: one star for italic, which reads the same
    /// as an underscore.
    enum Mark: CaseIterable {
        case bold, italic, underline, strike

        var marker: String {
            switch self {
            case .bold: return "**"
            case .italic: return "*"
            case .underline: return "__"
            case .strike: return "~~"
            }
        }

        func isOn(_ style: Style) -> Bool {
            switch self {
            case .bold: return style.bold
            case .italic: return style.italic
            case .underline: return style.underline
            case .strike: return style.strike
            }
        }

        func turn(_ on: Bool, in style: inout Style) {
            switch self {
            case .bold: style.bold = on
            case .italic: style.italic = on
            case .underline: style.underline = on
            case .strike: style.strike = on
            }
        }
    }

    private static let doubles: [(marker: String, mark: Mark)] = [
        ("**", .bold), ("__", .underline), ("~~", .strike),
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

    /// The words as they read, and for each of their characters where it is
    /// stored in `text`, as character offsets — what the spelling check
    /// reads, so "he**llo**" is one word. The Android twin's `mapped`.
    static func mapped(_ text: String) -> (plain: String, rawAt: [Int]) {
        let scan = parseMapped(text)
        return (scan.parsed.plain, scan.rawAt)
    }

    /// A parse and where everything in it came from.
    private struct Scan {
        var parsed: Parsed
        /// For each plain character, where it is stored in the text, as a
        /// character offset.
        var rawAt: [Int]
        /// For each plain character, the styles it is in.
        var styles: [Style]
        /// Every marker read as one: where it starts, as a character offset,
        /// how many characters it is and which style it switches.
        var markers: [(at: Int, length: Int, mark: Mark)]
    }

    /// The parse, with where each plain character came from in `text`, the
    /// styles each is in, and the markers that set them.
    private static func parseMapped(_ text: String) -> Scan {
        guard hasMarkup(text) else {
            return Scan(parsed: Parsed(plain: text, runs: []), rawAt: Array(0..<text.count),
                        styles: Array(repeating: Style(), count: text.count), markers: [])
        }
        var rawAt: [Int] = []
        var styles: [Style] = []
        var markers: [(at: Int, length: Int, mark: Mark)] = []
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
                let on = d.mark.isOn(style)
                let after = i + 2 < chars.count ? chars[i + 2] : nil
                let before = i > 0 ? chars[i - 1] : nil
                // Opening: something follows that is not a space, and a
                // closing marker exists later. Closing: the run is on and
                // the marker does not sit before a letter of the same word.
                let opens = !on && after != nil && after != " " && rest(from: i + 2).contains(d.marker)
                let closes = on && before != " "
                if opens || closes {
                    closeRun()
                    d.mark.turn(!on, in: &style)
                    markers.append((at: i, length: 2, mark: d.mark))
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
                        markers.append((at: i, length: 1, mark: .italic))
                        i += 1
                        continue
                    }
                } else if !isWord(before), let after, after != " ", after != c,
                          closingItalic(in: chars, from: i + 1, marker: c) {
                    closeRun()
                    style.italic = true
                    markers.append((at: i, length: 1, mark: .italic))
                    i += 1
                    continue
                }
            }
            plain.append(c)
            rawAt.append(i)
            styles.append(style)
            offset += String(c).utf16.count
            i += 1
        }
        closeRun()
        return Scan(parsed: Parsed(plain: plain, runs: runs), rawAt: rawAt, styles: styles, markers: markers)
    }

    /// The text with only its first `count` characters showing — counted as
    /// they read, markers not counted — and the markers still round them, so a
    /// typewriter on `**Sale** today` shows a bold "Sa", never "**Sa". The
    /// text is cut just after the last character shown and the styles that
    /// character is in are closed there; should the result not read back as
    /// the same words in the same styles, the words are shown plain instead.
    /// The Android twin's `RichText.revealed`, step for step.
    static func revealed(_ text: String, count: Int) -> String {
        let scan = parseMapped(text)
        let full = scan.parsed, rawAt = scan.rawAt
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

    // MARK: capitals

    /// The parse in capitals, as a box set in them draws it. Each stretch
    /// between one style change and the next is set in capitals on its own
    /// and the runs moved to match, so a letter that grows — ß to SS — pushes
    /// the words after it along rather than out of their styles.
    static func inCapitals(_ parsed: Parsed) -> Parsed {
        let ns = parsed.plain as NSString
        var cuts: Set<Int> = [0]
        cuts.insert(ns.length)
        for run in parsed.runs {
            cuts.insert(run.range.location)
            cuts.insert(NSMaxRange(run.range))
        }
        let sorted = cuts.sorted()
        var plain = ""
        // Where each cut lands once the stretches before it are capitals.
        var moved: [Int: Int] = [0: 0]
        for (from, to) in zip(sorted, sorted.dropFirst()) {
            plain += ns.substring(with: NSRange(location: from, length: to - from)).uppercased()
            moved[to] = plain.utf16.count
        }
        let runs = parsed.runs.map { run -> Run in
            let start = moved[run.range.location] ?? 0
            let end = moved[NSMaxRange(run.range)] ?? start
            return Run(range: NSRange(location: start, length: end - start), style: run.style)
        }
        return Parsed(plain: plain, runs: runs)
    }

    // MARK: the typing bar

    /// Whether every letter chosen in `text` — spaces aside — is already in
    /// `mark`'s style: what lights the typing bar's button, and makes it take
    /// the style off rather than put it on.
    static func selectionHas(_ mark: Mark, in text: String, selection: NSRange) -> Bool {
        let scan = parseMapped(text)
        let picked = characterBounds(selection, in: Array(text))
        let plain = Array(scan.parsed.plain)
        let letters = scan.rawAt.indices.filter { picked.contains(scan.rawAt[$0]) && !plain[$0].isWhitespace }
        return !letters.isEmpty && letters.allSatisfy { mark.isOn(scan.styles[$0]) }
    }

    /// `text` with `mark` put round the words chosen — or taken off them,
    /// when every one is in that style already — and the same words chosen
    /// in the result. The Android twin's typing bar does the same.
    ///
    /// The markers go hard against the words, never round the spaces at the
    /// ends of the choice, since a marker beside a space is not read as one;
    /// and a choice over several lines is marked a line at a time. Italics
    /// take whole words, as a single marker cannot open or close inside one.
    /// Markers of the same style inside or next to the choice are merged or
    /// split so each stretch is marked once: "**big** sale" made bold whole
    /// is "**big sale**", and "sale" taken out of "**big sale today**" leaves
    /// "**big** sale **today**".
    ///
    /// nil when there is nothing to do — only spaces chosen — or when the
    /// markers could not say it: the result is read back, and anything that
    /// does not read as the same words with just this style changed is
    /// refused rather than left showing stray stars.
    static func toggling(_ mark: Mark, in text: String, selection: NSRange) -> (text: String, selection: NSRange)? {
        let chars = Array(text)
        let before = parseMapped(text)
        let plain = Array(before.parsed.plain)
        let picked = characterBounds(selection, in: chars)
        let chosen = before.rawAt.indices.filter { picked.contains(before.rawAt[$0]) }
        guard let first = chosen.first, let last = chosen.last else { return nil }
        func isWord(_ c: Character) -> Bool { c.isLetter || c.isNumber }
        var lo = first, hi = last
        if mark == .italic {
            while lo > 0, isWord(plain[lo]), isWord(plain[lo - 1]) { lo -= 1 }
            while hi < plain.count - 1, isWord(plain[hi]), isWord(plain[hi + 1]) { hi += 1 }
        }
        let letters = (lo...hi).filter { !plain[$0].isWhitespace }
        guard !letters.isEmpty else { return nil }
        let on = !letters.allSatisfy { mark.isOn(before.styles[$0]) }
        var marked = before.styles.map { mark.isOn($0) }
        for j in lo...hi { marked[j] = on }

        // Each stretch in the style, a line at a time, spaces at its ends
        // left out: where its markers go.
        var opens = Set<Int>(), closes = Set<Int>()
        var k = 0
        while k < plain.count {
            guard marked[k], !plain[k].isNewline else { k += 1; continue }
            var end = k
            while end + 1 < plain.count, marked[end + 1], !plain[end + 1].isNewline { end += 1 }
            var a = k, b = end
            while a <= b, plain[a].isWhitespace { a += 1 }
            while b >= a, plain[b].isWhitespace { b -= 1 }
            if a <= b {
                opens.insert(before.rawAt[a])
                closes.insert(before.rawAt[b])
            }
            k = end + 1
        }

        // The text again, this style's old markers out and its new ones in;
        // every other marker stays where it was.
        var dropped = Set<Int>()
        for m in before.markers where m.mark == mark {
            for j in m.at..<(m.at + m.length) { dropped.insert(j) }
        }
        var out = ""
        for (r, c) in chars.enumerated() where !dropped.contains(r) {
            if opens.contains(r) { out += mark.marker }
            out.append(c)
            if closes.contains(r) { out += mark.marker }
        }
        guard out != text else { return nil }

        let after = parseMapped(out)
        guard after.parsed.plain == before.parsed.plain else { return nil }
        for i in plain.indices where !plain[i].isWhitespace {
            var meant = before.styles[i]
            mark.turn(marked[i], in: &meant)
            guard after.styles[i] == meant else { return nil }
        }
        let outChars = Array(out)
        let from = String(outChars[0..<after.rawAt[first]]).utf16.count
        let to = String(outChars[0...after.rawAt[last]]).utf16.count
        return (out, NSRange(location: from, length: to - from))
    }

    /// Where a caret at `offset` in `old` belongs in `new`, the same words
    /// with their markers changed: before the same character of the words as
    /// they read, or at the very end when it was after all of them. UTF-16
    /// offsets, as a text view counts them.
    static func caret(at offset: Int, from old: String, to new: String) -> Int {
        let oldChars = Array(old), newChars = Array(new)
        let a = parseMapped(old), b = parseMapped(new)
        let at = characterBounds(NSRange(location: offset, length: 1), in: oldChars).lowerBound
        let ahead = a.rawAt.filter { $0 < at }.count
        guard ahead < b.rawAt.count else { return new.utf16.count }
        return String(newChars[0..<b.rawAt[ahead]]).utf16.count
    }

    /// The characters of `chars` that UTF-16 range `range` touches, as
    /// character offsets.
    private static func characterBounds(_ range: NSRange, in chars: [Character]) -> Range<Int> {
        var lo: Int?
        var hi = chars.count
        var offset = 0
        for (i, c) in chars.enumerated() {
            if offset >= NSMaxRange(range) { hi = i; break }
            let next = offset + String(c).utf16.count
            if lo == nil, next > range.location { lo = i }
            offset = next
        }
        let start = lo ?? chars.count
        return start..<max(start, hi)
    }

    /// The plain text with the base attributes, and each run's style on top;
    /// in capitals when `uppercase`, each run still on its own words.
    static func attributed(_ marked: String, base: [NSAttributedString.Key: Any], uppercase: Bool = false,
                           font: (_ bold: Bool, _ italic: Bool) -> UIFont) -> NSAttributedString {
        let parsed = uppercase ? inCapitals(parse(marked)) : parse(marked)
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
