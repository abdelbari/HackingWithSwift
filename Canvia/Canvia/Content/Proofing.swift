// Check spelling's writing rules: beside the words the dictionary does not
// know, the simple slips Canva's proofing catches — a word said twice, two
// spaces, a space before a comma, a sentence begun in lower case, "a apple",
// straight quotes, three full stops, a hyphen in a range, a bracket never
// closed. Each finding is the stretch of the words as they read and its one
// fix (none for an unclosed bracket); the Proofreader places them in the
// stored words as it places a misspelling, and fixes them the same way.
//
// The Android twin's Proofing.rules, rule for rule, over the same rows
// (Tests/Fixtures/proofing_rules.json). Settings ▸ Proofing's Typography
// (`typographySetting`, on unless set off) keeps the typographic kinds —
// quotes, ellipsis, range — in the check.

import Foundation

enum Proofing {

    /// The writing rules' kinds, as both phones name them.
    static let spaceBefore = "spaceBefore"
    static let spaces = "spaces"
    static let repeated = "repeat"
    static let capital = "capital"
    static let article = "article"
    static let quotes = "quotes"
    static let ellipsis = "ellipsis"
    static let range = "range"
    static let unbalanced = "unbalanced"

    /// The rules, in the order a finding of one wins over an overlapping
    /// finding of a later one.
    static let rules = [spaceBefore, spaces, repeated, capital, article, quotes, ellipsis, range, unbalanced]

    /// The typographic kinds Settings ▸ Proofing's Typography switches off.
    static let typography: Set<String> = [quotes, ellipsis, range]

    /// The setting that keeps the typographic kinds on — on unless set off
    /// — on both phones.
    static let typographySetting = "proofTypography"

    /// Whether the typographic kinds are checked on this phone.
    static var typographyOn: Bool {
        UserDefaults.standard.object(forKey: typographySetting) as? Bool ?? true
    }

    /// One writing finding in words as they read: `start..<end`, UTF-16,
    /// and what to put there — nil for one with no fix (unbalanced).
    struct Finding: Equatable {
        var kind: String
        var start: Int
        var end: Int
        var replacement: String?
    }

    /// The languages whose sentences start with a capital, by primary
    /// subtag.
    private static let capitalised: Set<String> = ["en", "es", "fr", "de", "pt", "it"]

    /// Abbreviations whose full stop does not end a sentence.
    private static let abbreviations: Set<String> = ["e.g.", "i.e.", "etc.", "vs.", "mr.", "mrs.", "ms.", "dr.", "st."]

    /// Starts of words that take "an" though they start with a consonant
    /// letter, and of words that take "a" though they start with a vowel.
    private static let anWords = ["hour", "honest", "honour", "honor", "heir"]
    private static let aWords = ["uni", "use", "usu", "uti", "eu", "one", "once"]

    /// Opening quotes and brackets that may stand before a sentence's first
    /// word, and closing ones after its last.
    private static let openers: Set<unichar> = units("\"“‘'«„([")
    private static let closers: Set<unichar> = units("\"”’'»)]")

    private static func units(_ text: String) -> Set<unichar> { Set(text.utf16) }

    /// `language`'s primary subtag, lower case; "en" for none.
    static func primary(_ language: String?) -> String {
        let tag = (language ?? "").split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return tag.isEmpty ? "en" : tag.lowercased()
    }

    // MARK: characters, one UTF-16 unit at a time, as the twin reads them

    private static func scalar(_ u: unichar) -> Unicode.Scalar? { Unicode.Scalar(u) }

    private static func isWhitespace(_ u: unichar) -> Bool { scalar(u)?.properties.isWhitespace ?? false }

    private static func isDigit(_ u: unichar) -> Bool { scalar(u)?.properties.numericType == .decimal }

    private static func isLetter(_ u: unichar) -> Bool {
        switch scalar(u)?.properties.generalCategory {
        case .uppercaseLetter?, .lowercaseLetter?, .titlecaseLetter?, .modifierLetter?, .otherLetter?: return true
        default: return false
        }
    }

    private static func isLower(_ u: unichar) -> Bool { scalar(u)?.properties.isLowercase ?? false }

    private static func isUpper(_ u: unichar) -> Bool { scalar(u)?.properties.isUppercase ?? false }

    private static func isLetterOrDigit(_ u: unichar) -> Bool { isLetter(u) || isDigit(u) }

    private static func at(_ text: [unichar], _ i: Int) -> unichar? {
        i >= 0 && i < text.count ? text[i] : nil
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    // MARK: the rules

    /// The writing rules over `text`, words as they read, in `language`
    /// (BCP-47, nil for English) — in reading order. The typographic kinds
    /// only with `typography`. Findings never overlap: of two that would,
    /// the kind earlier in `rules` stays.
    ///
    /// - spaceBefore: spaces after a word and before , . ; : ! ? — removed;
    ///   but not before a full stop that starts a number (".5"), nor in
    ///   French before ; : ! ?, which take a space there.
    /// - spaces: two or more spaces between words on a line — one.
    /// - repeat: a word said twice, only spaces or tabs between, case aside
    ///   ("the the") — the second, and the spaces before it, removed.
    /// - capital: a lower-case letter starting the text or a sentence (after
    ///   . ! ? … and whitespace, not after an abbreviation's full stop), in
    ///   a word with no capitals of its own that is not part of an address
    ///   or a handle — in en, es, fr, de, pt and it — upper-cased.
    /// - article (English): "a" before a vowel — "an"; "an" before a
    ///   consonant — "a"; by the next word's first letter, except words
    ///   starting as `anWords` do ("an hour") and as `aWords` do ("a
    ///   university"); not before a word in capitals, of one letter, or
    ///   joined to a digit, hyphen or apostrophe. Its capital kept.
    /// - quotes: a straight ' or " — curly: ' between letters is ’; else
    ///   opening at the start or after whitespace, ( [ { or a dash, closing
    ///   elsewhere — “ ” and ‘ ’; in French « » and ‘ ’, in German „ “ and
    ///   ‚ ‘, in Japanese 「 」 and 『 』 — there, with no spaces to tell
    ///   by, each kind opening and closing in turn.
    /// - ellipsis: exactly three full stops in a row — …
    /// - range: a hyphen between two numbers ("10-20") — an en dash; not
    ///   inside a longer run of numbers and hyphens (a date, a phone number).
    /// - unbalanced: a ( [ or “ that nothing after it closes — no fix.
    static func findings(_ text: String, language: String? = nil, typography: Bool = true) -> [Finding] {
        let code = primary(language)
        let chars = Array(text.utf16)
        var found: [Finding] = []
        found += spacing(text, chars: chars, code: code)
        let words = matches("[\\p{L}\\p{M}]+", in: text).map(\.range)
        found += repeats(words, chars: chars)
        if capitalised.contains(code) { found += capitals(words, chars: chars) }
        if code == "en" { found += articles(words, chars: chars) }
        if typography { found += typographic(text, chars: chars, code: code) }
        found += unclosed(chars)
        // By rule, each rule's findings in the order they were made.
        let ranked = found.enumerated().sorted { (order($0.element.kind), $0.offset) < (order($1.element.kind), $1.offset) }
        var kept: [Finding] = []
        for f in ranked.map(\.element) where !kept.contains(where: { $0.start < f.end && f.start < $0.end }) {
            kept.append(f)
        }
        return kept.sorted { ($0.start, order($0.kind)) < ($1.start, order($1.kind)) }
    }

    private static func order(_ kind: String) -> Int { rules.firstIndex(of: kind) ?? rules.count }

    /// spaceBefore and spaces.
    private static func spacing(_ text: String, chars: [unichar], code: String) -> [Finding] {
        var out: [Finding] = []
        for m in matches("(?<=\\S)( +)([,.;:!?])", in: text) {
            let mark = chars[m.range(at: 2).location]
            if mark == 0x2E, let next = at(chars, NSMaxRange(m.range)), isDigit(next) { continue }
            if code == "fr", units(";:!?").contains(mark) { continue }
            let gap = m.range(at: 1)
            out.append(Finding(kind: spaceBefore, start: gap.location, end: NSMaxRange(gap), replacement: ""))
        }
        for m in matches("(?<=\\S) {2,}(?=\\S)", in: text) {
            out.append(Finding(kind: spaces, start: m.range.location, end: NSMaxRange(m.range), replacement: " "))
        }
        return out
    }

    private static func word(_ chars: [unichar], _ r: NSRange) -> String {
        String(utf16CodeUnits: Array(chars[r.location..<NSMaxRange(r)]), count: r.length)
    }

    /// repeat.
    private static func repeats(_ words: [NSRange], chars: [unichar]) -> [Finding] {
        var out: [Finding] = []
        for k in words.indices.dropFirst() {
            let a = words[k - 1], b = words[k]
            let gap = chars[NSMaxRange(a)..<b.location]
            guard !gap.isEmpty, gap.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) else { continue }
            if word(chars, a).lowercased() == word(chars, b).lowercased() {
                out.append(Finding(kind: repeated, start: NSMaxRange(a), end: NSMaxRange(b), replacement: ""))
            }
        }
        return out
    }

    /// capital.
    private static func capitals(_ words: [NSRange], chars: [unichar]) -> [Finding] {
        var out: [Finding] = []
        for w in words {
            let first = chars[w.location]
            guard isLower(first), !chars[(w.location + 1)..<NSMaxRange(w)].contains(where: isUpper) else { continue }
            // A word on its own, not part of an address or a handle.
            if let before = at(chars, w.location - 1), !isWhitespace(before), !openers.contains(before) { continue }
            if let after = at(chars, NSMaxRange(w)) {
                if after == 0x40 || after == 0x2F || isDigit(after) { continue }
                if after == 0x2E, let next = at(chars, NSMaxRange(w) + 1), isLetterOrDigit(next) { continue }
            }
            guard startsSentence(chars, at: w.location) else { continue }
            let upper = String(utf16CodeUnits: [first], count: 1).uppercased()
            out.append(Finding(kind: capital, start: w.location, end: w.location + 1, replacement: upper))
        }
        return out
    }

    /// article.
    private static func articles(_ words: [NSRange], chars: [unichar]) -> [Finding] {
        var out: [Finding] = []
        let joined = units("-'’")
        for k in words.indices.dropLast() {
            let a = words[k], b = words[k + 1]
            let said = word(chars, a)
            let lower = said.lowercased()
            guard lower == "a" || lower == "an" else { continue }
            guard b.location == NSMaxRange(a) + 1, chars[NSMaxRange(a)] == 0x20 else { continue }
            if let before = at(chars, a.location - 1), isLetterOrDigit(before) || joined.contains(before) { continue }
            if let after = at(chars, NSMaxRange(b)), isDigit(after) || joined.contains(after) { continue }
            let next = word(chars, b)
            guard next.utf16.count >= 2, next != next.uppercased() else { continue }
            let nextLower = next.lowercased()
            let wantsAn: Bool
            if anWords.contains(where: { nextLower.hasPrefix($0) }) {
                wantsAn = true
            } else if aWords.contains(where: { nextLower.hasPrefix($0) }) {
                wantsAn = false
            } else {
                wantsAn = "aeiou".contains(nextLower.first ?? " ")
            }
            let want = wantsAn ? "an" : "a"
            guard lower != want else { continue }
            let capitalFirst = isUpper(chars[a.location])
            let fix = capitalFirst ? want.prefix(1).uppercased() + want.dropFirst() : want
            out.append(Finding(kind: article, start: a.location, end: NSMaxRange(a), replacement: fix))
        }
        return out
    }

    /// quotes, ellipsis and range.
    private static func typographic(_ text: String, chars: [unichar], code: String) -> [Finding] {
        var out: [Finding] = []
        let marks: [String]
        switch code {
        case "fr": marks = ["«", "»", "‘", "’"]
        case "de": marks = ["„", "“", "‚", "‘"]
        case "ja": marks = ["「", "」", "『", "』"]
        default: marks = ["“", "”", "‘", "’"]
        }
        let openAfter = units("([{—–-")
        var seen: [unichar: Int] = [:]
        for (i, c) in chars.enumerated() where c == 0x22 || c == 0x27 {
            let before = at(chars, i - 1), after = at(chars, i + 1)
            // Japanese has no spaces to tell by: the quotes alternate.
            let earlier = seen[c] ?? 0
            seen[c] = earlier + 1
            let opening = code == "ja" ? earlier % 2 == 0 : before.map { isWhitespace($0) || openAfter.contains($0) } ?? true
            let mark: String
            if c == 0x27, let before, let after, isLetter(before), isLetter(after) {
                mark = "’"
            } else if c == 0x27 {
                mark = opening ? marks[2] : marks[3]
            } else {
                mark = opening ? marks[0] : marks[1]
            }
            out.append(Finding(kind: quotes, start: i, end: i + 1, replacement: mark))
        }
        for m in matches("(?<!\\.)\\.\\.\\.(?!\\.)", in: text) {
            out.append(Finding(kind: ellipsis, start: m.range.location, end: NSMaxRange(m.range), replacement: "…"))
        }
        // Digits as the twin's pattern reads them: 0 to 9.
        for m in matches("(?<![0-9-])[0-9]+-[0-9]+(?![0-9-])", in: text) {
            guard let dash = chars[m.range.location..<NSMaxRange(m.range)].firstIndex(of: 0x2D) else { continue }
            out.append(Finding(kind: range, start: dash, end: dash + 1, replacement: "–"))
        }
        return out
    }

    /// unbalanced: ( [ and “ nothing after them closes.
    private static func unclosed(_ chars: [unichar]) -> [Finding] {
        let pairs: [unichar: unichar] = [0x29: 0x28, 0x5D: 0x5B, 0x201D: 0x201C]
        var open: [(mark: unichar, at: Int)] = []
        for (i, c) in chars.enumerated() {
            if c == 0x28 || c == 0x5B || c == 0x201C {
                open.append((c, i))
            } else if let opener = pairs[c], let last = open.lastIndex(where: { $0.mark == opener }) {
                open.remove(at: last)
            }
        }
        return open.map { Finding(kind: unbalanced, start: $0.at, end: $0.at + 1, replacement: nil) }
    }

    /// Whether a word at `at` starts the text or a sentence: nothing but
    /// opening quotes before it, or . ! ? … then whitespace — closing quotes
    /// and brackets between them allowed — and that full stop not an
    /// abbreviation's.
    private static func startsSentence(_ chars: [unichar], at: Int) -> Bool {
        var i = at - 1
        while i >= 0, openers.contains(chars[i]) { i -= 1 }
        if i < 0 { return true }
        guard isWhitespace(chars[i]) else { return false }
        while i >= 0, isWhitespace(chars[i]) { i -= 1 }
        if i < 0 { return true }
        while i >= 0, closers.contains(chars[i]) { i -= 1 }
        guard i >= 0, units(".!?…").contains(chars[i]) else { return false }
        if chars[i] == 0x2E {
            let breaks: Set<unichar> = [0x20, 0x0A, 0x09]
            var start = i
            while start > 0, !breaks.contains(chars[start - 1]) { start -= 1 }
            let word = String(utf16CodeUnits: Array(chars[start...i]), count: i - start + 1).lowercased()
            if abbreviations.contains(word) { return false }
        }
        return true
    }

    /// What the Writing section calls a finding's kind.
    static func ruleName(_ kind: String) -> String {
        switch kind {
        case spaceBefore: return tr("Space before punctuation")
        case spaces: return tr("Extra spaces")
        case repeated: return tr("Repeated word")
        case capital: return tr("Capital letter")
        case article: return tr("A or an")
        case quotes: return tr("Curly quotes")
        case ellipsis: return tr("Ellipsis")
        case range: return tr("Dash in a range")
        case unbalanced: return tr("Unclosed bracket or quote")
        default: return tr("Grammar")
        }
    }
}
