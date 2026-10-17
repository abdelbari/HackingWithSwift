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
        inCapitals(parsed, spans: []).parsed
    }

    /// The same, with colours and sizes on words (see Spans) over the plain
    /// text: their ends are cut at too, and they move with the capitals as
    /// the runs do — the Android twin maps them the same way.
    static func inCapitals(_ parsed: Parsed, spans: [TextSpan]) -> (parsed: Parsed, spans: [TextSpan]) {
        let ns = parsed.plain as NSString
        var cuts: Set<Int> = [0]
        cuts.insert(ns.length)
        for run in parsed.runs {
            cuts.insert(run.range.location)
            cuts.insert(NSMaxRange(run.range))
        }
        for span in spans {
            cuts.insert(min(max(span.start, 0), ns.length))
            cuts.insert(min(max(span.end, 0), ns.length))
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
        let shifted = spans.compactMap { span -> TextSpan? in
            let start = moved[min(max(span.start, 0), ns.length)] ?? 0
            let end = moved[min(max(span.end, 0), ns.length)] ?? start
            guard end > start else { return nil }
            var out = span
            out.start = start
            out.end = end
            return out
        }
        return (Parsed(plain: plain, runs: runs), shifted)
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
    /// in capitals when `uppercase`, each run still on its own words. Then
    /// the colours, sizes, fonts and links on words, `spans` over the plain
    /// text before capitals (see Spans): a face of its own from `face` —
    /// for a span with a font, a weight or a slant of its own — bold and
    /// italic as the run under each letter has them; a colour in place
    /// of the base one; a size as the letter's font scaled, and the lines of
    /// a paragraph with larger words in it given room for them (makeRoom);
    /// and a link underlined, in the link colour unless the words have a
    /// colour of their own or `linkColour` is false (letters in a gradient
    /// keep the text's ink) — as the Android twin sets them.
    static func attributed(_ marked: String, base: [NSAttributedString.Key: Any], uppercase: Bool = false,
                           spans: [TextSpan] = [], linkColour: Bool = true,
                           face: ((_ span: TextSpan, _ bold: Bool, _ italic: Bool) -> UIFont)? = nil,
                           font: (_ bold: Bool, _ italic: Bool) -> UIFont) -> NSAttributedString {
        var parsed = parse(marked)
        var spans = spans
        if uppercase {
            let capitals = inCapitals(parsed, spans: spans)
            parsed = capitals.parsed
            spans = capitals.spans
        }
        let out = NSMutableAttributedString(string: parsed.plain, attributes: base)
        for run in parsed.runs {
            var attrs: [NSAttributedString.Key: Any] = [:]
            if run.style.bold || run.style.italic { attrs[.font] = font(run.style.bold, run.style.italic) }
            if run.style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if run.style.strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            out.addAttributes(attrs, range: run.range)
        }
        let length = out.length
        if let face {
            for span in spans where span.setsFace {
                setFaces(span, in: out, runs: parsed.runs, from: span.start, to: span.end, face: face)
            }
        }
        for span in spans {
            let start = min(max(span.start, 0), length), end = min(span.end, length)
            guard end > start else { continue }
            let range = NSRange(location: start, length: end - start)
            if let color = span.color {
                out.addAttribute(.foregroundColor, value: UIColor(hex: color), range: range)
                out.addAttribute(Spans.colourKey, value: color, range: range)
            }
            if let link = span.link {
                out.addAttribute(Spans.linkKey, value: link, range: range)
                out.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                if span.color == nil && linkColour {
                    out.addAttribute(.foregroundColor, value: UIColor(hex: Spans.linkColour), range: range)
                    out.addAttribute(Spans.colourKey, value: Spans.linkColour, range: range)
                }
            }
            if let scale = span.scale {
                out.enumerateAttribute(.font, in: range) { value, part, _ in
                    guard let font = value as? UIFont else { return }
                    out.addAttribute(.font, value: font.withSize(font.pointSize * scale), range: part)
                }
                if scale > 1 { makeRoom(in: out, for: range, scale: scale) }
            }
        }
        return out
    }

    /// Letters `from..<to` of `out` in `span`'s face, cut where the runs'
    /// styles change so a **bold** word in the face stays bold.
    private static func setFaces(_ span: TextSpan, in out: NSMutableAttributedString, runs: [Run],
                                 from: Int, to: Int,
                                 face: (_ span: TextSpan, _ bold: Bool, _ italic: Bool) -> UIFont) {
        let start = min(max(from, 0), out.length), end = min(to, out.length)
        guard end > start else { return }
        var cuts: Set<Int> = [start, end]
        for run in runs {
            for edge in [run.range.location, NSMaxRange(run.range)] where edge > start && edge < end {
                cuts.insert(edge)
            }
        }
        let sorted = cuts.sorted()
        for (lo, hi) in zip(sorted, sorted.dropFirst()) {
            let style = runs.first { NSLocationInRange(lo, $0.range) }?.style ?? Style()
            out.addAttribute(.font, value: face(span, style.bold, style.italic),
                             range: NSRange(location: lo, length: hi - lo))
        }
    }

    /// The lines of the paragraphs `range` is in allowed to grow to fit
    /// words `scale` times the size: each line its own height, at least the
    /// pitch and at most the pitch times the paragraph's largest scale. A
    /// paragraph with no larger word keeps the pitch exactly. As the Android
    /// twin's ExactLineHeight sets them.
    static func makeRoom(in out: NSMutableAttributedString, for range: NSRange, scale: Double) {
        let paragraphs = (out.string as NSString).paragraphRange(for: range)
        out.enumerateAttribute(.paragraphStyle, in: paragraphs) { value, part, _ in
            guard let style = value as? NSParagraphStyle, style.maximumLineHeight > 0,
                  let roomier = style.mutableCopy() as? NSMutableParagraphStyle else { return }
            roomier.maximumLineHeight = max(style.maximumLineHeight, style.minimumLineHeight * scale)
            out.addAttribute(.paragraphStyle, value: roomier.copy(), range: part)
        }
    }

    // MARK: words as they read, and as they are typed

    /// For each UTF-16 unit of the words as they read, where it is stored in
    /// `text`, as a UTF-16 offset: what takes colours and sizes, counted in
    /// the words as they read, onto the words as typed, markers and all —
    /// and a choice made among the typed words back again.
    static func typedUnits(_ text: String) -> [Int] {
        units(of: parseMapped(text), in: text)
    }

    /// typedUnits from a parse of `text` already made.
    private static func units(of scan: Scan, in text: String) -> [Int] {
        let chars = Array(text)
        var startOf: [Int] = []
        var offset = 0
        for c in chars {
            startOf.append(offset)
            offset += String(c).utf16.count
        }
        var out: [Int] = []
        for at in scan.rawAt {
            let width = String(chars[at]).utf16.count
            for k in 0..<width { out.append(startOf[at] + k) }
        }
        return out
    }

    /// The words chosen by UTF-16 range `selection` of `text`, as a range of
    /// the words as they read; nil when it takes in none of them — nothing
    /// chosen, or only markers.
    static func plainRange(of selection: NSRange, in text: String) -> NSRange? {
        guard selection.location != NSNotFound, selection.length > 0 else { return nil }
        let units = typedUnits(text)
        let inside = units.indices.filter { NSLocationInRange(units[$0], selection) }
        guard let first = inside.first, let last = inside.last else { return nil }
        return NSRange(location: first, length: last + 1 - first)
    }

    /// Where `range` of the words as they read is stored in the typed text
    /// whose `typedUnits` are `units`: one range for each stretch the
    /// markers do not break.
    static func typedRanges(of range: NSRange, units: [Int]) -> [NSRange] {
        var out: [NSRange] = []
        let end = min(NSMaxRange(range), units.count)
        var u = max(0, range.location)
        while u < end {
            let from = units[u]
            var to = from + 1
            u += 1
            while u < end, units[u] == to { to += 1; u += 1 }
            out.append(NSRange(location: from, length: to - from))
        }
        return out
    }

    // MARK: typing the words as they read

    // The field typed in on the canvas shows the words as they read, the
    // markers kept in what is stored but drawn as nothing (InlineTextField).
    // A caret or a choice among the words as they read is placed among the
    // stored characters by these rules, and what is typed is put in by them,
    // so the styles carry on as Canva's do. The Android twin's inline field
    // maps its offsets by the same rules over the same test rows.

    /// Where a caret `offset` UTF-16 units into the words as they read
    /// stands in `text`, as a UTF-16 offset: just after the character before
    /// it — inside any style that character is in, so what is typed there
    /// takes that style — or, at the very start, just before the first
    /// character, inside its style. "**Sale** today": 0 is 2, 4 is 6 (inside
    /// the bold) and 5 is 9.
    static func rawCaret(_ offset: Int, in text: String) -> Int {
        rawCaret(offset, units: typedUnits(text), length: (text as NSString).length)
    }

    private static func rawCaret(_ offset: Int, units: [Int], length: Int) -> Int {
        guard let first = units.first else { return length }
        guard offset > 0 else { return first }
        return units[min(offset, units.count) - 1] + 1
    }

    /// How many UTF-16 units of the words as they read are stored before
    /// UTF-16 offset `offset` of `text`: where a caret there stands among
    /// the words, whichever side of a marker it is.
    static func plainCaret(_ offset: Int, in text: String) -> Int {
        plainCaret(offset, units: typedUnits(text))
    }

    private static func plainCaret(_ offset: Int, units: [Int]) -> Int {
        units.firstIndex { $0 >= offset } ?? units.count
    }

    /// The style of the character `offset` UTF-16 units into the words as
    /// they read; plain past the end.
    static func styleAt(_ offset: Int, in text: String) -> Style {
        style(of: parse(text).runs, at: offset)
    }

    /// Where words `range` — UTF-16, of the words as they read — are stored
    /// in `text`: from just after the character before them, or the start,
    /// to just before the character after them, or the end, so the markers
    /// between them and the words beside them are taken in: "Big sale" in
    /// "**Big** sale" is 0..12. Find's matches are placed by this rule.
    static func storedRange(of range: NSRange, in text: String) -> NSRange {
        storedRange(of: range, units: typedUnits(text), length: (text as NSString).length)
    }

    /// storedRange, from `text`'s typedUnits and stored length already
    /// worked out — for many ranges of the same words, each in one step
    /// rather than a fresh pass over all of them.
    static func storedRange(of range: NSRange, units: [Int], length: Int) -> NSRange {
        let lo = min(max(range.location, 0), units.count)
        let hi = min(max(NSMaxRange(range), lo), units.count)
        let start = lo == 0 ? 0 : units[lo - 1] + 1
        let end = hi == units.count ? length : units[hi]
        return NSRange(location: start, length: max(0, end - start))
    }

    /// A choice in `text` kept off the markers, which are drawn as nothing:
    /// a caret where rawCaret puts it, and a choice of words from just
    /// before the first of them to just after the last — a caret when it
    /// takes in only markers. A caret moved one unit on from `was` and still
    /// among the same markers goes on past the next character, so the arrow
    /// keys step over them rather than stopping on them.
    static func snapped(_ selection: NSRange, in text: String, was: NSRange?) -> NSRange {
        let scan = parseMapped(text)
        let units = Self.units(of: scan, in: text)
        let length = (text as NSString).length
        let lo = plainCaret(selection.location, units: units)
        let hi = plainCaret(NSMaxRange(selection), units: units)
        guard hi > lo else {
            var at = lo
            if let was, was.length == 0, selection.length == 0, selection.location == was.location + 1,
               plainCaret(was.location, units: units) == lo, lo < units.count {
                at = NSMaxRange((scan.parsed.plain as NSString).rangeOfComposedCharacterSequence(at: lo))
            }
            return NSRange(location: rawCaret(at, units: units, length: length), length: 0)
        }
        let start = units[lo], end = units[hi - 1] + 1
        return NSRange(location: start, length: end - start)
    }

    /// A style waiting for what is typed next: armed by Bold, Italic,
    /// Underline or Strikethrough on the typing bar with no words chosen, or
    /// carried by spaces typed at the end of styled words, which no marker
    /// can hold — "**Big **" does not read — so the next word takes the
    /// style, and the spaces with it: "**Big sale**". `from` is where the
    /// waiting began, in UTF-16 units of the words as they read.
    struct Pending: Equatable {
        var style: Style
        var from: Int
    }

    /// What typing makes: the words as stored, the caret in them, and any
    /// style still waiting.
    struct Typed: Equatable {
        var text: String
        var caret: Int
        var pending: Pending?
    }

    /// `typed` put over UTF-16 range `range` of `text` — a key, a paste, a
    /// correction or a backspace — as the words read, never into a marker:
    ///
    /// - what is typed takes the style of the character before it, so
    ///   characters typed at the end of a styled word go inside its closing
    ///   marker and the style carries on; at the very start, the style of
    ///   the first character; over chosen words, the style of the first;
    ///   and `pending`, while one waits, before all of these;
    /// - a backspace just after markers, which are drawn as nothing, takes
    ///   the character before them, never a marker;
    /// - the markers round the words typed are written again (replacing),
    ///   every other one left where it was.
    ///
    /// Where the markers cannot say it, the stored characters are changed
    /// as they are, as a plain text field would.
    static func typing(_ typed: String, over range: NSRange, in text: String, pending: Pending?) -> Typed {
        let scan = parseMapped(text)
        let units = Self.units(of: scan, in: text)
        let shown = scan.parsed.plain as NSString
        let runs = scan.parsed.runs
        var lo = plainCaret(range.location, units: units)
        let hi: Int
        if typed.isEmpty, range.length > 0, plainCaret(NSMaxRange(range), units: units) == lo {
            // Only markers in the way: the character before them goes.
            guard lo > 0 else {
                return Typed(text: text, caret: rawCaret(0, units: units, length: (text as NSString).length))
            }
            let before = shown.rangeOfComposedCharacterSequence(at: lo - 1)
            lo = before.location
            hi = NSMaxRange(before)
        } else {
            hi = plainCaret(NSMaxRange(range), units: units)
        }
        var start = lo
        var words = typed
        let style: Style
        if hi > lo {
            style = Self.style(of: runs, at: lo)
        } else if let pending, pending.from <= lo {
            style = pending.style
            words = shown.substring(with: NSRange(location: pending.from, length: lo - pending.from)) + typed
            start = pending.from
        } else {
            style = Self.style(of: runs, at: max(lo - 1, 0))
        }
        guard let out = replacing(NSRange(location: start, length: hi - start), in: text,
                                  with: words, style: style) else {
            let plainly = (text as NSString).replacingCharacters(in: range, with: typed)
            return Typed(text: plainly, caret: range.location + (typed as NSString).length)
        }
        let after = parseMapped(out)
        let caretAt = start + (words as NSString).length
        let caret = rawCaret(caretAt, units: Self.units(of: after, in: out), length: (out as NSString).length)
        // Spaces typed after styled words that could not take the style:
        // the style waits for the next word, the spaces with it.
        var carried: Pending?
        if !style.isPlain, typed.last?.isWhitespace == true, caretAt > 0,
           Self.style(of: after.parsed.runs, at: caretAt - 1) != style {
            let now = after.parsed.plain as NSString
            var from = caretAt
            while from > start, isSpace(now.character(at: from - 1)) { from -= 1 }
            carried = Pending(style: style, from: from)
        }
        return Typed(text: out, caret: caret, pending: carried)
    }

    /// Whether UTF-16 unit `unit` is a space or a line break.
    private static func isSpace(_ unit: unichar) -> Bool {
        Unicode.Scalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
    }

    /// `text` with the words in `range` — UTF-16, of the words as they read
    /// — replaced by `replacement` in `style`. Every marker wholly outside
    /// them stays where it was; those among them are taken out and the new
    /// words wrapped in markers again: closing the styles of the words
    /// before that the new ones do not have, opening theirs, and the same
    /// again into the words after. The markers go hard against letters —
    /// spaces beside the words replaced are written again with them, and
    /// the markers round them — as a marker beside a space is not read as
    /// one. nil when the result would not read as the same words with the
    /// new ones in `style`, letters outside them in their own.
    static func replacing(_ range: NSRange, in text: String, with replacement: String, style: Style) -> String? {
        let scan = parseMapped(text)
        let chars = Array(text)
        let plain = Array(scan.parsed.plain)
        var a = characterIndex(range.location, in: plain, up: false)
        var b = max(a, characterIndex(NSMaxRange(range), in: plain, up: true))
        var lead = "", trail = ""
        while a > 0, plain[a - 1].isWhitespace {
            a -= 1
            lead = String(plain[a]) + lead
        }
        while b < plain.count, plain[b].isWhitespace {
            trail.append(plain[b])
            b += 1
        }
        let start = a == 0 ? 0 : scan.rawAt[a - 1] + 1
        let end = b == plain.count ? chars.count : scan.rawAt[b]
        let open = a == 0 ? Style() : scan.styles[a - 1]
        let close = b == plain.count ? Style() : scan.styles[b]
        let words = lead + replacement + trail
        let head = String(chars[..<start]), tail = String(chars[end...])
        // What it must read as: the letters before and after in their own
        // styles, the new ones in `style`; spaces in whatever they can be.
        let meant = String(plain[..<a]) + words + String(plain[b...])
        var styles: [Style?] = plain[..<a].indices.map { Optional(scan.styles[$0]) }
        styles += words.map { $0.isWhitespace ? nil : style }
        styles += plain[b...].indices.map { Optional(scan.styles[$0]) }
        for italic in ["*", "_"] {
            let middle = wrapped(words, from: open, as: style, to: close, italic: italic)
            let candidate = head + middle + tail
            let back = parseMapped(candidate)
            guard String(back.parsed.plain) == meant, back.styles.count == styles.count else { continue }
            let kept = zip(back.styles, zip(styles, Array(meant))).allSatisfy { got, want in
                want.1.isWhitespace || want.0 == nil || want.0 == got
            }
            if kept { return candidate }
        }
        return nil
    }

    /// `words` with the markers that take the words before — in `open` —
    /// into `style`, and `style` into the words after, in `close`: closing
    /// markers just after the last letter they close, opening ones just
    /// before the first letter they open, spaces outside them.
    private static func wrapped(_ words: String, from open: Style, as style: Style, to close: Style,
                                italic: String) -> String {
        let chars = Array(words)
        var lo = 0, hi = chars.count
        while lo < hi, chars[lo].isWhitespace { lo += 1 }
        while hi > lo, chars[hi - 1].isWhitespace { hi -= 1 }
        guard hi > lo else {
            return closers(open, leaving: close, italic) + words + openers(close, after: open, italic)
        }
        let into = closers(open, leaving: style, italic) + String(chars[..<lo]) + openers(style, after: open, italic)
        let outOf = closers(style, leaving: close, italic) + String(chars[hi...]) + openers(close, after: style, italic)
        return into + String(chars[lo..<hi]) + outOf
    }

    /// The markers that end each style `from` has and `to` has not, the
    /// single italic one first.
    private static func closers(_ from: Style, leaving to: Style, _ italic: String) -> String {
        var out = ""
        if from.italic && !to.italic { out += italic }
        if from.bold && !to.bold { out += "**" }
        if from.underline && !to.underline { out += "__" }
        if from.strike && !to.strike { out += "~~" }
        return out
    }

    /// The markers that begin each style `to` has and `from` has not, the
    /// single italic one last.
    private static func openers(_ to: Style, after from: Style, _ italic: String) -> String {
        var out = ""
        if to.strike && !from.strike { out += "~~" }
        if to.underline && !from.underline { out += "__" }
        if to.bold && !from.bold { out += "**" }
        if to.italic && !from.italic { out += italic }
        return out
    }

    /// The character of `chars` that UTF-16 offset `offset` falls at: the
    /// one starting there, or — inside one — that one, or the next with
    /// `up`.
    private static func characterIndex(_ offset: Int, in chars: [Character], up: Bool) -> Int {
        var units = 0
        for (i, c) in chars.enumerated() {
            if units >= offset { return i }
            units += String(c).utf16.count
            if units > offset { return up ? i + 1 : i }
        }
        return chars.count
    }
}
