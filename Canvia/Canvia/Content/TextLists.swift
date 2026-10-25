// Lists and indents a paragraph at a time: a heading line and then bullets
// in one box, items nested a level at a time with a marker per level.
//
// A box may set each of its lines on its own in `paragraphs`: one entry per
// line of its words (split at "\n"), each `{"list", "level", "align"}` with
// any left out at its default ("none", 0, the box's own `align`), and
// `paragraphsText`, the words as
// they read that they were made for, guarding them as `spansText` guards the
// spans: words changed by a build that knows nothing of them no longer
// match, and the box-wide `listStyle` and `indent` set every line again. A
// box with no `paragraphs` reads as it always has, so an older file draws the
// same. The Android twin's TextLists keeps the same keys among its extras
// and runs the same rules over the same rows.

import Foundation

/// One line's list, how deep it sits and how it is aligned.
struct TextParagraph: Codable, Equatable, Hashable {
    /// "bullet" | "number" | "letter", or "none".
    var list: String = "none"
    /// 0…TextLists.maxLevel; each level is one and a half ems.
    var level: Int = 0
    /// "left" | "center" | "right" | "justify" of its own; nil is the box's
    /// `align`.
    var align: String?

    init(list: String = "none", level: Int = 0, align: String? = nil) {
        self.list = list
        self.level = level
        self.align = align
    }

    var isListed: Bool { list != "none" }

    private enum CodingKeys: String, CodingKey { case list, level, align }

    // Each key on its own: a list this build does not know is none, and a
    // level out of reach is held to it, never the box lost.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try? c.decode(String.self, forKey: .list)
        list = kind.flatMap { FontLibrary.listStyles.contains($0) ? $0 : nil } ?? "none"
        let level = (try? c.decode(Int.self, forKey: .level))
            ?? (try? c.decode(Double.self, forKey: .level)).flatMap { $0.isFinite ? Int($0) : nil }
            ?? 0
        self.level = min(TextLists.maxLevel, max(0, level))
        // An alignment this build does not know is the box's.
        align = (try? c.decode(String.self, forKey: .align)).flatMap { TextLists.aligns.contains($0) ? $0 : nil }
    }

    /// Defaults are no key at all, as on the Android twin.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if isListed { try c.encode(list, forKey: .list) }
        if level > 0 { try c.encode(level, forKey: .level) }
        try c.encodeIfPresent(align, forKey: .align)
    }
}

enum TextLists {

    static let maxLevel = FontLibrary.maxIndent

    /// The bullets, a level at a time, round again past the third.
    static let bullets = ["•", "◦", "▪"]

    /// The alignments a box or a line may have.
    static let aligns = ["left", "center", "right", "justify"]

    /// A line's list item: its style, the level its marker is drawn for,
    /// and its one-based place in its count.
    struct Item: Equatable {
        var list: String
        var depth: Int
        var index: Int

        var marker: String { TextLists.marker(list, level: depth, index: index) ?? "" }
    }

    // MARK: reading

    /// The box's own paragraphs, one a line, when it has them and they were
    /// made for the words it has now; nil otherwise, and then the box-wide
    /// keys set every line. A list longer or shorter than the lines is
    /// fitted to them: past its end a line is plain.
    static func paragraphsOf(_ el: Element) -> [TextParagraph]? {
        guard let stored = el.paragraphs, let madeFor = el.paragraphsText else { return nil }
        let plain = RichText.strip(el.text ?? "")
        guard madeFor == plain else { return nil }
        let count = plain.components(separatedBy: "\n").count
        return (0..<count).map { i -> TextParagraph in
            guard i < stored.count else { return TextParagraph() }
            var p = stored[i]
            p.level = min(maxLevel, max(0, p.level))
            return p
        }
    }

    /// Whether the box carries paragraphs at all, matched to its words or
    /// not.
    static func stored(_ el: Element) -> Bool {
        el.paragraphs != nil || el.paragraphsText != nil
    }

    /// Each line's list and level as the box sets it: its own paragraphs,
    /// or the box-wide style and indent on every line.
    static func lines(_ el: Element) -> [TextParagraph] {
        if let own = paragraphsOf(el) { return own }
        let style = el.listStyle.flatMap { FontLibrary.listStyles.contains($0) ? $0 : nil } ?? "none"
        let box = TextParagraph(list: style, level: FontLibrary.indentLevel(of: el))
        return Array(repeating: box, count: (el.text ?? "").components(separatedBy: "\n").count)
    }

    /// Whether any line is a list item: the box-wide style, or any of its
    /// own paragraphs'.
    static func isList(_ el: Element) -> Bool {
        lines(el).contains { $0.isListed }
    }

    /// Each line's list item, or nil for none. Box-wide, every non-blank
    /// line is an item, numbered on past blank lines, drawn at the first
    /// level whatever the indent — as a box always has been. Paragraph by
    /// paragraph, the rule both phones share: a blank line has no marker and
    /// counts for nothing; a line with no list ends every list above it, so
    /// the next item starts again at 1; an item numbers on from the last
    /// item at its level, starting again when that one was in another style
    /// or a shallower item has come between (an item ends every deeper
    /// level's count).
    static func items(_ el: Element) -> [Item?] {
        let raw = (el.text ?? "").components(separatedBy: "\n")
        func blank(_ line: String) -> Bool { line.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let own = paragraphsOf(el) else {
            let style = lines(el).first?.list ?? "none"
            var n = 0
            return raw.map { line -> Item? in
                guard style != "none", !blank(line) else { return nil }
                n += 1
                return Item(list: style, depth: 0, index: n)
            }
        }
        var counts = Array(repeating: 0, count: maxLevel + 1)
        var styles: [String?] = Array(repeating: nil, count: maxLevel + 1)
        return raw.enumerated().map { i, line -> Item? in
            let p = i < own.count ? own[i] : TextParagraph()
            guard p.isListed else {
                counts = Array(repeating: 0, count: maxLevel + 1)
                styles = Array(repeating: nil, count: maxLevel + 1)
                return nil
            }
            guard !blank(line) else { return nil }
            for deeper in (p.level + 1)..<(maxLevel + 1) {
                counts[deeper] = 0
                styles[deeper] = nil
            }
            if styles[p.level] != p.list { counts[p.level] = 0 }
            styles[p.level] = p.list
            counts[p.level] += 1
            return Item(list: p.list, depth: p.level, index: counts[p.level])
        }
    }

    /// Each line's marker (items), or nil for none.
    static func markers(_ el: Element) -> [String?] {
        items(el).map { $0?.marker }
    }

    // MARK: alignment a line at a time

    /// The box's own alignment: its `align`, centred when it has none.
    static func boxAlign(_ el: Element) -> String {
        el.align.flatMap { aligns.contains($0) ? $0 : nil } ?? "center"
    }

    /// How line `line` (zero-based) is aligned: its own paragraph's align,
    /// else the box's — the box's too when the paragraphs are missing or
    /// were made for other words, so an older file reads the same.
    static func alignOf(_ el: Element, _ line: Int) -> String {
        guard let own = paragraphsOf(el), own.indices.contains(line), let align = own[line].align else {
            return boxAlign(el)
        }
        return align
    }

    /// Every line's alignment (alignOf), one a line of the words.
    static func alignments(_ el: Element) -> [String] {
        let count = (el.text ?? "").components(separatedBy: "\n").count
        return (0..<count).map { alignOf(el, $0) }
    }

    /// The alignment the lines in `lines` share, or nil when they differ —
    /// what the Align button shows while typing, Mixed for nil.
    static func sharedAlign(_ el: Element, lines: ClosedRange<Int>) -> String? {
        let all = alignments(el)
        let covered = all.indices.filter { lines.contains($0) }.map { all[$0] }
        guard let first = covered.first else { return boxAlign(el) }
        return covered.allSatisfy { $0 == first } ? first : nil
    }

    /// `el` with the lines in `lineRange` (zero-based, both ends in) aligned
    /// `align`, the rest as they are: the Align button and ⇧⌘L, C, R and J
    /// while typing. A line aligned as the box is keeps no align of its own,
    /// and lines all aligned alike make that the box's align (setLines) —
    /// so a range taking in every line is the box-wide set.
    static func withAlign(_ el: Element, _ lineRange: ClosedRange<Int>, _ align: String) -> Element {
        guard aligns.contains(align) else { return el }
        var out = el
        out.changeLines(lineRange) { $0.align = align }
        return out
    }

    // MARK: markers

    /// The look line `line`'s marker takes, the rule both phones share: the
    /// colour, size, font, weight and slant of the span (Spans) in force at
    /// the first character of the line's words that is not a space or a
    /// tab — not its link, highlight, script or capitals, which are the
    /// words' alone — as a span of nothing (start and end 0); nil for the
    /// box's own, where no span is there or it sets none of them, or the
    /// line has no words.
    static func markerStyle(_ el: Element, _ line: Int) -> TextSpan? {
        let spans = el.liveSpans
        guard !spans.isEmpty else { return nil }
        let plain = RichText.strip(el.text ?? "")
        let words = plain.components(separatedBy: "\n")
        let starts = lineStarts(plain)
        guard words.indices.contains(line), starts.indices.contains(line) else { return nil }
        let ns = words[line] as NSString
        var i = 0
        while i < ns.length, ns.character(at: i) == 0x20 || ns.character(at: i) == 0x09 { i += 1 }
        guard i < ns.length else { return nil }
        let at = starts[line] + i
        guard let span = spans.first(where: { $0.start <= at && at < $0.end }) else { return nil }
        let look = TextSpan(start: 0, end: 0, color: span.color, scale: span.scale, font: span.font,
                            weight: span.weight, italic: span.italic)
        return look.says ? look : nil
    }

    /// The prefix an item gets, by style, its `level` and its one-based place
    /// among its level's items: bullets go • ◦ ▪ by level, numbers 1. a. i.
    /// by level and letters a. i. 1. — each round again past the third
    /// level. Letters run a…z, then aa, ab… so the 27th item is neither a
    /// crash nor "{".
    static func marker(_ style: String?, level: Int, index: Int) -> String? {
        switch style {
        case "bullet":
            return bullets[max(0, level) % bullets.count] + "  "
        case "number", "letter":
            switch counting(style ?? "number", level: level) {
            case 0: return "\(index).  "
            case 1: return letters(index) + ".  "
            default: return roman(index) + ".  "
            }
        default:
            return nil
        }
    }

    /// How a numbered item at `level` counts: 0 in numbers, 1 in letters, 2
    /// in Roman numerals.
    static func counting(_ style: String, level: Int) -> Int {
        (max(0, level) + (style == "letter" ? 1 : 0)) % 3
    }

    /// a…z, then aa, ab…
    static func letters(_ index: Int) -> String {
        var n = index, s = ""
        while n > 0 {
            n -= 1
            s = String(UnicodeScalar(UInt8(97 + n % 26))) + s
            n /= 26
        }
        return s
    }

    /// Lower-case Roman numerals: i, ii, iv, ix, xl…
    static func roman(_ index: Int) -> String {
        let numerals: [(Int, String)] = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"),
                                         (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"),
                                         (5, "v"), (4, "iv"), (1, "i")]
        var n = index, s = ""
        for (value, numeral) in numerals {
            while n >= value {
                s += numeral
                n -= value
            }
        }
        return s
    }

    // MARK: changing

    /// Paragraphs made for `oldPlain` moved onto `newPlain` by a line diff,
    /// the rule both phones share: the lines both share at the start and at
    /// the end keep theirs; of the lines between, each new one takes the old
    /// one in its place, and those past the old ones copy the last of them —
    /// the line they were split from. Lines put in where none was replaced
    /// copy the line before them (Return at a line's end), or at the very
    /// top the line after.
    static func remap(_ oldPlain: String, _ newPlain: String, _ paragraphs: [TextParagraph]) -> [TextParagraph] {
        let old = oldPlain.components(separatedBy: "\n")
        let new = newPlain.components(separatedBy: "\n")
        let entries = old.indices.map { $0 < paragraphs.count ? paragraphs[$0] : TextParagraph() }
        let shorter = min(old.count, new.count)
        var prefix = 0
        while prefix < shorter, old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix, old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let replaced = old.count - prefix - suffix
        return new.indices.map { i -> TextParagraph in
            if i < prefix { return entries[i] }
            if i >= new.count - suffix { return entries[i - new.count + old.count] }
            if replaced > 0 { return entries[prefix + min(i - prefix, replaced - 1)] }
            if prefix > 0 { return entries[prefix - 1] }
            return prefix < entries.count ? entries[prefix] : TextParagraph()
        }
    }

    /// The lines, zero-based and both ends in, that `range` of `text` — UTF-16
    /// offsets into the words as stored — touches: the caret's own line when
    /// nothing is chosen.
    static func lineRange(_ text: String, _ range: NSRange) -> ClosedRange<Int> {
        let ns = text as NSString
        let from = min(max(range.location, 0), ns.length)
        let to = min(max(NSMaxRange(range), from), ns.length)
        func breaks(before end: Int) -> Int {
            var n = 0
            for i in 0..<end where ns.character(at: i) == 0x0A { n += 1 }
            return n
        }
        return breaks(before: from)...breaks(before: to)
    }

    // MARK: lists from the keyboard and from a paste

    /// The setting that starts a list from a typed "- " or "1. " (on
    /// unless turned off in Settings; in a backup's settings.json as
    /// "autoLists").
    static let autoListsKey = "canvia.autoLists"

    /// Whether typed prefixes start lists on this phone.
    static var autoListsOn: Bool {
        UserDefaults.standard.object(forKey: autoListsKey) as? Bool ?? true
    }

    /// The list a line starts once a space is typed, `caret` UTF-16 units
    /// into `plainLine` (the line's words as they read, the space in): when
    /// everything before the caret is "-", "*" or "•" and the space — a
    /// bullet — one or more digits then "." or ")" and the space — numbers
    /// — or one letter a to z then "." or ")" and the space — letters. Nil
    /// otherwise. The rule both phones share; the caller asks only for a
    /// line not listed yet.
    static func autoStart(_ plainLine: String, caret: Int) -> String? {
        let ns = plainLine as NSString
        guard caret >= 2, caret <= ns.length else { return nil }
        let typed = ns.substring(to: caret)
        let rules: [(pattern: String, list: String)] = [
            ("^[-*•] $", "bullet"), ("^[0-9]+[.)] $", "number"), ("^[a-z][.)] $", "letter"),
        ]
        return rules.first { typed.range(of: $0.pattern, options: .regularExpression) != nil }?.list
    }

    /// `el` with the list `list` started on line `line` (zero-based) by a
    /// typed prefix `prefix` UTF-16 units long at the line's start: the
    /// prefix taken out and the line made the first level of the list —
    /// what autoStart asked for, as one step after the prefix was typed, so
    /// an Undo straight away brings the typed characters back.
    static func autoStarted(_ el: Element, line: Int, prefix: Int, list: String) -> Element {
        let text = el.text ?? ""
        let plain = RichText.strip(text)
        let starts = lineStarts(plain)
        guard starts.indices.contains(line) else { return el }
        var out = el
        let gone = NSRange(location: starts[line], length: prefix)
        out.setText(FindReplace.replacing(gone, in: text, with: ""))
        out.changeLines(line...line) { p in
            p.list = list
            p.level = 0
        }
        return out
    }

    /// Where each line of `plain` starts, as UTF-16 offsets.
    static func lineStarts(_ plain: String) -> [Int] {
        var starts = [0]
        for (i, unit) in plain.utf16.enumerated() where unit == 0x0A { starts.append(i + 1) }
        return starts
    }

    /// Backspace at the very start of a listed line: one level shallower
    /// while it is deeper than the first, else no list — the line is not
    /// joined to the one above. The rule both phones share.
    static func backspaced(_ p: inout TextParagraph) {
        if p.level > 0 {
            p.level -= 1
        } else {
            p.list = "none"
        }
    }

    /// `el` after Backspace at the start of line `line`, when that line is
    /// listed (backspaced); nil when it is not, and the key joins the lines
    /// as ever.
    static func backspaceAtItemStart(_ el: Element, line: Int) -> Element? {
        let now = lines(el)
        guard now.indices.contains(line), now[line].isListed else { return nil }
        var out = el
        out.changeLines(line...line, backspaced)
        return out
    }

    /// A line pasted with a list item's prefix: its indent (tabs, or
    /// spaces two a level), then a bullet ("•", "◦", "▪", "-" or "*"), a
    /// number or a letter and "." or ")", then spaces or tabs.
    private static let pastedItem = try! NSRegularExpression(
        pattern: "^(\\t*| *)(?:([-*•◦▪])|([0-9]+)[.)]|([a-z])[.)])[ \\t]+")

    /// Text from outside — a paste, a share — as a list: each line with a
    /// bullet, number or letter prefix (`pastedItem`) loses it and becomes
    /// an item of that list, at the level its leading tabs (one each) or
    /// spaces (two each) give, to the deepest; every other line is kept as
    /// it is, no list. When `firstStartsLine` is false — pasted within a
    /// line, whose list the first line cannot take — the first line is
    /// kept as it is too, its bullet or number still in its words. The
    /// rule both phones share.
    static func fromPasted(_ text: String, firstStartsLine: Bool = true) -> (text: String, paragraphs: [TextParagraph]) {
        var lines: [String] = []
        var paragraphs: [TextParagraph] = []
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let ns = line as NSString
            let all = NSRange(location: 0, length: ns.length)
            guard index > 0 || firstStartsLine,
                  let m = pastedItem.firstMatch(in: line, options: [], range: all) else {
                lines.append(line)
                paragraphs.append(TextParagraph())
                continue
            }
            let indent = ns.substring(with: m.range(at: 1)) as NSString
            let level = indent.hasPrefix("\t") ? indent.length : indent.length / 2
            let list: String
            if m.range(at: 2).location != NSNotFound {
                list = "bullet"
            } else if m.range(at: 3).location != NSNotFound {
                list = "number"
            } else {
                list = "letter"
            }
            lines.append(ns.substring(from: NSMaxRange(m.range)))
            paragraphs.append(TextParagraph(list: list, level: min(level, maxLevel)))
        }
        return (lines.joined(separator: "\n"), paragraphs)
    }

    /// The typing bar's List: the next of none, bullets and numbers after
    /// `current` — letters go on to none.
    static func nextList(_ current: String) -> String {
        switch current {
        case "none": return "bullet"
        case "bullet": return "number"
        default: return "none"
        }
    }
}

extension Element {

    /// The box with its lines set as `lines` — one a line, fitted to its
    /// words. Every line aligned alike, however their lists differ, makes
    /// that the box's `align` and no line keeps its own — the rule both
    /// phones share. Lines all alike are written as the box-wide keys
    /// instead and the paragraphs dropped, when they read the same that way:
    /// no list, or a list at the first level (deeper, a paragraph's marker
    /// follows its level, where the box-wide list's marker never does).
    /// Otherwise `paragraphs` and `paragraphsText`, the box-wide list and
    /// indent gone.
    mutating func setLines(_ lines: [TextParagraph]) {
        let plain = RichText.strip(text ?? "")
        let count = plain.components(separatedBy: "\n").count
        let current = TextLists.boxAlign(self)
        // Each line's align as it would read: its own, or the box's.
        let reads = (0..<count).map { i -> String in
            guard i < lines.count, let own = lines[i].align, TextLists.aligns.contains(own) else { return current }
            return own
        }
        if let shared = reads.first, shared != current, reads.allSatisfy({ $0 == shared }) { align = shared }
        let box = TextLists.boxAlign(self)
        let fitted = (0..<count).map { i -> TextParagraph in
            guard i < lines.count else { return TextParagraph() }
            var p = lines[i]
            p.level = min(TextLists.maxLevel, max(0, p.level))
            // An align the box has already is no align of its own.
            if p.align == box || !TextLists.aligns.contains(p.align ?? box) { p.align = nil }
            return p
        }
        paragraphs = nil
        paragraphsText = nil
        listStyle = nil
        indent = nil
        let first = fitted[0]
        if fitted.allSatisfy({ $0 == first }) && (!first.isListed || first.level == 0) {
            if first.isListed { listStyle = first.list }
            if first.level > 0 { indent = first.level }
        } else {
            paragraphs = fitted
            paragraphsText = plain
        }
    }

    /// The lines in `range` (zero-based, both ends in) changed by `change` —
    /// the typing bar's List and Indent on the lines the choice covers, and
    /// Return or Tab on the caret's.
    mutating func changeLines(_ range: ClosedRange<Int>, _ change: (inout TextParagraph) -> Void) {
        var now = TextLists.lines(self)
        for i in now.indices where range.contains(i) { change(&now[i]) }
        setLines(now)
    }

    /// Every line in `style` — the Text controls' list: the whole box's
    /// list, its own paragraphs' lists given up to it, their levels kept.
    mutating func setListStyle(_ style: String) {
        if TextLists.paragraphsOf(self) != nil {
            setLines(TextLists.lines(self).map { TextParagraph(list: style, level: $0.level, align: $0.align) })
        } else {
            dropParagraphs()
            listStyle = style == "none" ? nil : style
        }
    }

    /// Every line `by` levels deeper, or shallower for a negative one — the
    /// Text controls' Indent and Outdent: the box-wide indent, or each of
    /// the box's own paragraphs, kept within 0 to the deepest.
    mutating func stepIndent(by delta: Int) {
        if TextLists.paragraphsOf(self) != nil {
            setLines(TextLists.lines(self).map {
                TextParagraph(list: $0.list, level: min(TextLists.maxLevel, max(0, $0.level + delta)), align: $0.align)
            })
        } else {
            dropParagraphs()
            let level = min(TextLists.maxLevel, max(0, FontLibrary.indentLevel(of: self) + delta))
            indent = level == 0 ? nil : level
        }
    }

    /// Every line aligned `align` — the Align button with nothing typed in,
    /// Several texts, a text style: the box's `align`, and no line keeps an
    /// align of its own.
    mutating func setAlign(_ new: String) {
        align = new
        guard let own = TextLists.paragraphsOf(self), own.contains(where: { $0.align != nil }) else { return }
        setLines(own.map { TextParagraph(list: $0.list, level: $0.level) })
    }

    /// No paragraphs of its own, its box-wide keys as they are.
    mutating func dropParagraphs() {
        paragraphs = nil
        paragraphsText = nil
    }

    /// Its own paragraphs moved from the words `oldPlain` onto the words it
    /// has now (TextLists.remap) — written back as they were, not tidied
    /// into box-wide keys, so typing never changes how the box is kept —
    /// or dropped when they were made for other words.
    mutating func moveLines(from oldPlain: String, _ before: [TextParagraph]?) {
        guard paragraphs != nil || paragraphsText != nil else { return }
        guard let before else {
            dropParagraphs()
            return
        }
        let plain = RichText.strip(text ?? "")
        paragraphs = TextLists.remap(oldPlain, plain, before)
        paragraphsText = plain
    }
}
