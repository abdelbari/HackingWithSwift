// Spelling, checked across the whole document.
//
// A design is read once by its maker and a thousand times by strangers, and
// a misspelt headline is the mistake none of them forgive. UITextChecker is
// the system's own dictionary — offline, in the user's languages — and it
// gives suggestions, so the fix is a tap rather than a retype.
//
// It checks in the design's `language` when it has one, and passes over the
// words Ignore has kept in the design (`spellIgnore`) and the words Add to
// dictionary has kept on this phone (dictionary.json, see
// SpellingDictionary). The Android twin's Proofing keeps the same keys and
// file, by the same rules.
//
// Beside the dictionary's words, the writing rules (Proofing) are checked
// in the same pass over the same words — each finding a Misspelling with
// its `rule` and its one fix — and fixed the same way, spans and markers
// kept. A Doc is checked as its blocks: each text block's words as a box's,
// each table cell's as plain text, a finding in one of kind `doc`.

import UIKit

enum Proofreader {

    struct Misspelling: Identifiable, Equatable {
        var id: String {
            "\(kind.rawValue)|\(pageIndex)|\(elementId)|\(blockId ?? "")|\(row ?? -1)|\(col ?? -1)|\(range.location)|\(rule ?? "")"
        }
        var pageIndex: Int
        var elementId: String
        var range: NSRange
        var word: String
        var suggestions: [String]
        /// Where the word is in the words as they read, for marking it when
        /// shown (DesignStore.TextMatch.plain).
        var plain = NSRange(location: 0, length: 0)
        /// In a box's words, or in the page's speaker notes — then
        /// `elementId` is empty and `range` is `plain`, of the notes — or in
        /// a Doc's block, `blockId`, and a table's cell, `row` and `col`.
        var kind: FindReplace.Kind = .element
        var blockId: String?
        var row: Int?
        var col: Int?
        /// A writing finding's kind (Proofing.rules); nil for a word the
        /// dictionary does not know. Its one fix, if it has one, is its
        /// only suggestion.
        var rule: String?

        /// Whether it is a writing finding rather than a misspelling.
        var isWriting: Bool { rule != nil }

        /// Whether it is in a Doc table's cell.
        var inCell: Bool { kind == .doc && row != nil && col != nil }
    }

    /// Words to check: a box's — or a page's notes, of kind notes with no
    /// element, or a Doc's block or table cell, of kind doc — the words as
    /// they read, and for each of their characters where it is stored in
    /// `text`, as character offsets (RichText.mapped).
    struct Checkable {
        var pageIndex: Int
        var elementId: String
        var text: String
        var plain: String
        var rawAt: [Int]
        var kind: FindReplace.Kind = .element
        var blockId: String?
        var row: Int?
        var col: Int?

        /// Words stored as they read: notes and a table's cells.
        static func plainly(_ words: String, pageIndex: Int, elementId: String = "", kind: FindReplace.Kind,
                            blockId: String? = nil, row: Int? = nil, col: Int? = nil) -> Checkable {
            Checkable(pageIndex: pageIndex, elementId: elementId, text: words, plain: words,
                      rawAt: Array(0..<words.count), kind: kind, blockId: blockId, row: row, col: col)
        }
    }

    /// Everything a check reads, in reading order: page by page, element by
    /// element — text boxes and the words in shapes, not a hidden one or a
    /// caption box's cues — then the page's speaker notes; a locked page
    /// not at all, as no fix may change its words. A Doc is its blocks
    /// instead, in order (docCheckables).
    static func checkables(in design: Design) -> [Checkable] {
        if Docs.isDoc(design) { return docCheckables(design) }
        var out: [Checkable] = []
        for (p, page) in design.pages.enumerated() where !PageLocks.isLocked(page) {
            for el in page.elements where ShapeText.carriesWords(el) && !el.isHidden && el.captions == nil {
                guard let text = el.text, !text.isEmpty else { continue }
                let (plain, rawAt) = RichText.mapped(text)
                out.append(Checkable(pageIndex: p, elementId: el.id, text: text, plain: plain, rawAt: rawAt))
            }
            out.append(.plainly(page.notes ?? "", pageIndex: p, kind: .notes))
        }
        return out
    }

    /// A Doc's words to check: each text block's as a box's, and each
    /// table cell's, row by row, as plain text.
    static func docCheckables(_ design: Design) -> [Checkable] {
        Docs.blocks(design).flatMap { block -> [Checkable] in
            if Docs.textTypes.contains(block.type) {
                guard !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
                let (plain, rawAt) = RichText.mapped(block.text)
                return [Checkable(pageIndex: 0, elementId: "", text: block.text, plain: plain, rawAt: rawAt,
                                  kind: .doc, blockId: block.id)]
            }
            guard block.type == Docs.table else { return [] }
            return Docs.tableRows(block).rows.enumerated().flatMap { r, row in
                row.enumerated().compactMap { c, cell -> Checkable? in
                    cell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil
                        : .plainly(cell, pageIndex: 0, kind: .doc, blockId: block.id, row: r, col: c)
                }
            }
        }
    }

    /// Where a Doc's word is, as Check spelling says it: the block's place
    /// among the Doc's blocks, from 1 — "Doc, paragraph N".
    static func docPlace(_ design: Design, blockId: String?) -> Int {
        (Docs.blocks(design).firstIndex { $0.id == blockId } ?? -1) + 1
    }

    /// Every word the checker does not know, in reading order: page by page,
    /// element by element — text boxes and the words in shapes — left to
    /// right, then the page's speaker notes, read as plain text. Words that
    /// are not words — numbers, hashtags, addresses,
    /// SHOUTED acronyms — are left alone. Each box is read as it reads,
    /// style marks left out, so "he**llo**" is one word, and each word found
    /// is placed back where it is stored.
    /// In `language` — BCP-47 ("en-GB") or a UITextChecker language
    /// ("en_US") — when one is given, else the design's own, as the checker
    /// has it (checkerLanguage). A word in `skip`
    /// (lower-cased) is passed over: the design's Ignore list and this
    /// phone's dictionary (skipped).
    static func misspellings(in design: Design, language: String? = nil, skip: Set<String> = [],
                             maxSuggestions: Int = 4) -> [Misspelling] {
        let checker = UITextChecker()
        let lang = checkerLanguage(language ?? design.language)
        var found: [Misspelling] = []
        for item in checkables(in: design) {
            for miss in unknownWords(in: item.plain, checker: checker, language: lang, skip: skip,
                                     maxSuggestions: maxSuggestions) {
                guard let stored = storedRange(miss.range, plain: item.plain, rawAt: item.rawAt, in: item.text) else { continue }
                found.append(misspelling(item, range: stored, word: miss.word, suggestions: miss.suggestions,
                                         plain: miss.range))
            }
        }
        return found
    }

    /// A finding in `item`: stored at `range`, reading `word`.
    private static func misspelling(_ item: Checkable, range: NSRange, word: String, suggestions: [String],
                                    plain: NSRange, rule: String? = nil) -> Misspelling {
        Misspelling(pageIndex: item.pageIndex, elementId: item.elementId, range: range, word: word,
                    suggestions: suggestions, plain: plain, kind: item.kind, blockId: item.blockId,
                    row: item.row, col: item.col, rule: rule)
    }

    /// Every writing finding (Proofing.findings) across `design`, in the
    /// order its words are checked (checkables), in `language` — the
    /// design's own when nil, and the phone's when the design has none
    /// (writingLanguage) — each placed in its stored words, its one fix
    /// its only suggestion. The typographic kinds only with `typography`.
    static func writing(in design: Design, language: String? = nil,
                        typography: Bool = Proofing.typographyOn) -> [Misspelling] {
        let lang = writingLanguage(language ?? design.language)
        return checkables(in: design).flatMap { item -> [Misspelling] in
            let plain = item.plain as NSString
            return Proofing.findings(item.plain, language: lang, typography: typography).compactMap { f in
                let range = NSRange(location: f.start, length: f.end - f.start)
                guard f.start >= 0, f.end <= plain.length, f.start < f.end,
                      let stored = storedRange(range, plain: item.plain, rawAt: item.rawAt, in: item.text) else { return nil }
                return misspelling(item, range: stored, word: plain.substring(with: range),
                                   suggestions: f.replacement.map { [$0] } ?? [], plain: range, rule: f.kind)
            }
        }
    }

    /// The words of `plain` worth flagging that the checker does not know,
    /// left to right, with its suggestions for each.
    private static func unknownWords(in plain: String, checker: UITextChecker, language lang: String,
                                     skip: Set<String>, maxSuggestions: Int)
        -> [(range: NSRange, word: String, suggestions: [String])] {
        let ns = plain as NSString
        var out: [(range: NSRange, word: String, suggestions: [String])] = []
        var location = 0
        while location < ns.length {
            let range = checker.rangeOfMisspelledWord(
                in: plain, range: NSRange(location: location, length: ns.length - location),
                startingAt: location, wrap: false, language: lang)
            guard range.location != NSNotFound, range.length > 0 else { break }
            let word = ns.substring(with: range)
            if isWorthFlagging(word, skip: skip) {
                let guesses = checker.guesses(forWordRange: range, in: plain, language: lang) ?? []
                out.append((range: range, word: word, suggestions: Array(guesses.prefix(maxSuggestions))))
            }
            location = range.location + range.length
        }
        return out
    }

    /// A range of the plain reading text, as the stored text's own range:
    /// from where its first character is stored to just after its last.
    static func storedRange(_ range: NSRange, plain: String, rawAt: [Int], in text: String) -> NSRange? {
        guard let r = Range(range, in: plain) else { return nil }
        let start = plain.distance(from: plain.startIndex, to: r.lowerBound)
        let end = plain.distance(from: plain.startIndex, to: r.upperBound)
        guard start < end, end <= rawAt.count else { return nil }
        let rawStart = rawAt[start], rawEnd = rawAt[end - 1] + 1
        guard rawEnd <= text.count else { return nil }
        let lower = text.index(text.startIndex, offsetBy: rawStart)
        let upper = text.index(text.startIndex, offsetBy: rawEnd)
        return NSRange(lower..<upper, in: text)
    }

    /// Whether a word the dictionary rejects is one a person would call a
    /// misspelling: not a single letter, a number, a hashtag, a handle, an
    /// address, or an acronym or brand set in capitals — nor a word in
    /// `skip`, lower-cased: the design's Ignore list and this phone's own
    /// dictionary together (skipped).
    static func isWorthFlagging(_ word: String, skip: Set<String> = []) -> Bool {
        if skip.contains(word.lowercased()) { return false }
        guard word.count > 1 else { return false }
        if word.contains(where: \.isNumber) { return false }
        if word.hasPrefix("#") || word.hasPrefix("@") || word.contains("/") || word.contains(".") { return false }
        // All caps of three or more is an acronym or a brand set in caps.
        if word.count >= 3, word == word.uppercased(), word != word.lowercased() { return false }
        return true
    }

    /// The text with one range replaced.
    static func replacing(_ range: NSRange, in text: String, with replacement: String) -> String {
        let ns = text as NSString
        guard range.location + range.length <= ns.length else { return text }
        return ns.replacingCharacters(in: range, with: replacement)
    }

    /// The stored text with a misspelt word replaced. Style marks inside the
    /// word ("he**llo**") stay, after the new word, so the styling round it
    /// is never left half open — except a mark that opens a style running on
    /// past the word ("he**lo world**"), which goes before it: after the
    /// word it would stand before a space, where it cannot open, and show as
    /// typed. The Android twin's rules, step for step.
    static func replacing(_ m: Misspelling, in text: String, with suggestion: String) -> String {
        guard let r = Range(m.range, in: text) else { return text }
        // A suggestion reads as typed: any star in it is a star.
        let replacement = RichText.escapeLiteral(suggestion)
        let chars = Array(text)
        let start = text.distance(from: text.startIndex, to: r.lowerBound)
        let end = text.distance(from: text.startIndex, to: r.upperBound)
        guard start < end, end <= chars.count else { return text }
        let head = String(chars[..<start]), tail = String(chars[end...])
        if String(chars[start..<end]) == m.word { return head + replacement + tail }
        let (plain, rawAt) = RichText.mapped(text)
        let inside = rawAt.indices.filter { (start..<end).contains(rawAt[$0]) }
        let kept = Set(inside.map { rawAt[$0] })
        var marks = (start..<end).filter { !kept.contains($0) }.map { chars[$0] }
        guard let firstInside = inside.first, let lastInside = inside.last else {
            return head + replacement + String(marks) + tail
        }
        let runs = RichText.parse(text).runs
        let letters = Array(plain)
        func styleAt(_ i: Int) -> RichText.Style {
            let offset = String(letters[..<i]).utf16.count
            return runs.first { NSLocationInRange(offset, $0.range) }?.style ?? RichText.Style()
        }
        let first = styleAt(firstInside), last = styleAt(lastInside)
        var lead: [Character] = []
        func moveToLead(at index: Int, length: Int) {
            lead += marks[index..<(index + length)]
            marks.removeSubrange(index..<(index + length))
        }
        let doubles: [(on: (RichText.Style) -> Bool, marker: String)] = [
            ({ $0.bold }, "**"), ({ $0.underline }, "__"), ({ $0.strike }, "~~"),
        ]
        for double in doubles {
            let own = markTokens(marks).filter { $0.text == double.marker }
            if double.on(last) && !double.on(first) && own.count % 2 == 1, let final = own.last {
                moveToLead(at: final.at, length: 2)
            }
        }
        if last.italic && !first.italic {
            let singles = markTokens(marks).filter { $0.text.count == 1 }
            if singles.count % 2 == 1, let final = singles.last { moveToLead(at: final.at, length: 1) }
        }
        return head + String(lead) + replacement + String(marks) + tail
    }

    /// The style marks in `marks` as the parser reads them, left to right:
    /// a doubled one before a single, so "***" is bold then italic.
    private static func markTokens(_ marks: [Character]) -> [(at: Int, text: String)] {
        var out: [(at: Int, text: String)] = []
        var i = 0
        while i < marks.count {
            if i + 1 < marks.count, marks[i] == marks[i + 1], ["*", "_", "~"].contains(marks[i]) {
                out.append((i, String(marks[i...(i + 1)])))
                i += 2
            } else if marks[i] == "*" || marks[i] == "_" {
                out.append((i, String(marks[i])))
                i += 1
            } else {
                i += 1
            }
        }
        return out
    }

    /// The design with one misspelling fixed and its box measured again — a
    /// shape grown when its words need it — or nil when the word no longer
    /// reads where it was found, so a stale row never rewrites the wrong
    /// letters, or its page has been locked since.
    static func fixed(_ design: Design, _ m: Misspelling, with replacement: String) -> Design? {
        if m.kind == .doc { return fixedInDoc(design, m, with: replacement) }
        guard design.pages.indices.contains(m.pageIndex),
              !PageLocks.isLocked(design.pages[m.pageIndex]) else { return nil }
        if m.kind == .notes {
            // The notes are plain text: the word replaced as it is.
            let notes = (design.pages[m.pageIndex].notes ?? "") as NSString
            guard NSMaxRange(m.range) <= notes.length, notes.substring(with: m.range) == m.word else { return nil }
            var out = design
            out.pages[m.pageIndex].notes = notes.replacingCharacters(in: m.range, with: replacement)
            return out
        }
        guard let i = design.pages[m.pageIndex].elements.firstIndex(where: { $0.id == m.elementId }),
              let text = design.pages[m.pageIndex].elements[i].text,
              let r = Range(m.range, in: text) else { return nil }
        let start = text.distance(from: text.startIndex, to: r.lowerBound)
        let end = text.distance(from: text.startIndex, to: r.upperBound)
        let (plain, rawAt) = RichText.mapped(text)
        let letters = Array(plain)
        let reads = String(rawAt.indices.filter { (start..<end).contains(rawAt[$0]) }.map { letters[$0] })
        guard reads == m.word else { return nil }
        var out = design
        let before = out.pages[m.pageIndex].elements[i]
        out.pages[m.pageIndex].elements[i].setText(replacing(m, in: text, with: replacement))
        ShapeText.fitWords(&out.pages[m.pageIndex].elements[i])
        // A chart's label keeps its new word through the chart's Update.
        DataGraphics.keepingLabel(&out.pages[m.pageIndex], was: before, now: out.pages[m.pageIndex].elements[i])
        return out
    }

    /// A Doc's word fixed: in a cell as plain text, in a text block as a
    /// box's (`replacing`), its spans moved with it (Docs.withText).
    private static func fixedInDoc(_ design: Design, _ m: Misspelling, with replacement: String) -> Design? {
        guard Docs.isDoc(design), let block = Docs.blocks(design).first(where: { $0.id == m.blockId }) else { return nil }
        var next = block
        if let row = m.row, let col = m.col {
            var rows = Docs.tableRows(block).rows
            let header = Docs.tableRows(block).header
            guard rows.indices.contains(row), rows[row].indices.contains(col) else { return nil }
            let cell = rows[row][col] as NSString
            guard NSMaxRange(m.range) <= cell.length, cell.substring(with: m.range) == m.word else { return nil }
            rows[row][col] = cell.replacingCharacters(in: m.range, with: replacement)
            next.table = DocTable(rows: rows, header: header)
        } else {
            let text = block.text
            guard Docs.textTypes.contains(block.type), let r = Range(m.range, in: text) else { return nil }
            let start = text.distance(from: text.startIndex, to: r.lowerBound)
            let end = text.distance(from: text.startIndex, to: r.upperBound)
            let (plain, rawAt) = RichText.mapped(text)
            let letters = Array(plain)
            let reads = String(rawAt.indices.filter { (start..<end).contains(rawAt[$0]) }.map { letters[$0] })
            guard reads == m.word else { return nil }
            next = Docs.withText(block, replacing(m, in: text, with: replacement))
        }
        return Docs.withBlocks(design, Docs.blocks(design).map { $0.id == block.id ? next : $0 })
    }

    /// Every finding in `found` fixed — Fix all of a writing rule's kind —
    /// each by its one fix, the last in each box first so the ones before
    /// it still stand where they were found; one with no fix, or no longer
    /// where it was found, is passed over. Nil when nothing changed. The
    /// caller makes it one undo step.
    static func fixedAll(_ design: Design, _ found: [Misspelling]) -> Design? {
        func place(_ m: Misspelling) -> String {
            "\(m.kind.rawValue)|\(m.elementId)|\(m.blockId ?? "")|\(m.row ?? -1)|\(m.col ?? -1)"
        }
        let ordered = found.sorted { a, b in
            if a.pageIndex != b.pageIndex { return a.pageIndex < b.pageIndex }
            if place(a) != place(b) { return place(a) < place(b) }
            return a.range.location > b.range.location
        }
        var next = design
        var changed = false
        for m in ordered {
            guard let fix = m.suggestions.first, let made = fixed(next, m, with: fix) else { continue }
            next = made
            changed = true
        }
        return changed ? next : nil
    }

    // MARK: ignored words, the dictionary and the language

    /// The file this phone's own dictionary — Add to dictionary's words — is
    /// kept in, in Documents and in a backup, on both phones.
    static let dictionaryFile = "dictionary.json"

    /// `words` as both lists keep them: lower-cased, trimmed, each once,
    /// sorted, none blank.
    static func tidied<Words: Sequence>(_ words: Words) -> [String] where Words.Element == String {
        let kept = words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        return Array(Set(kept)).sorted()
    }

    /// The words Ignore has passed over in `design`, lower-cased and sorted.
    static func ignored(in design: Design) -> [String] {
        tidied(design.spellIgnore ?? [])
    }

    /// `design` with `word` added to its Ignore list — kept sorted and
    /// lower-cased, and no key at all while it has no words. The same design
    /// when the word is there already.
    static func ignoring(_ design: Design, _ word: String) -> Design {
        let now = tidied(ignored(in: design) + [word])
        var out = design
        out.spellIgnore = now.isEmpty ? nil : now
        return out
    }

    /// The language the writing rules run in: `language` (BCP-47), or the
    /// phone's own for none — as spelling falls back to it
    /// (checkerLanguage), and as the Android twin's writing check does.
    static func writingLanguage(_ language: String?) -> String {
        languageTag(language) ?? Locale.current.identifier(.bcp47)
    }

    /// A language as the design keeps it: trimmed, nil for none.
    static func languageTag(_ language: String?) -> String? {
        let tag = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tag.isEmpty ? nil : tag
    }

    /// `design` in `language` (BCP-47), or the phone's own for nil — the
    /// key gone.
    static func withLanguage(_ design: Design, _ language: String?) -> Design {
        var out = design
        out.language = languageTag(language)
        return out
    }

    /// The languages the spelling sheet offers, by tag and name, in the
    /// order both phones list them; the phone's own comes first, as nil.
    static let languages: [(tag: String, name: String)] = [
        ("en-GB", tr("English (UK)")),
        ("en-US", tr("English (US)")),
        ("en-AU", tr("English (Australia)")),
        ("fr-FR", tr("French")),
        ("de-DE", tr("German")),
        ("es-ES", tr("Spanish")),
        ("it-IT", tr("Italian")),
        ("pt-BR", tr("Portuguese (Brazil)")),
        ("nl-NL", tr("Dutch")),
    ]

    /// What the picker calls the phone's own language.
    static let phoneLanguage = tr("This phone's language")

    /// The name the picker gives `language`: its own from `languages`, the
    /// tag itself for one it does not list, or the phone's own for nil.
    static func languageName(_ language: String?) -> String {
        guard let language else { return phoneLanguage }
        return languages.first { $0.tag == language }?.name ?? language
    }

    /// The UITextChecker language a check runs in for `language`, BCP-47
    /// ("en-GB") or the checker's own ("en_GB"): the checker's for it when
    /// it has one, else its first of the same language ("en" for "en-NZ"),
    /// else the phone's own, else the first it has — as the Android twin
    /// falls back to the phone's own when there is no checker for it.
    static func checkerLanguage(_ language: String?) -> String {
        let available = UITextChecker.availableLanguages
        func found(_ tag: String) -> String? {
            let wanted = tag.replacingOccurrences(of: "-", with: "_")
            if available.contains(wanted) { return wanted }
            let base = String(wanted.prefix { $0 != "_" })
            return available.first { $0 == base || $0.hasPrefix(base + "_") }
        }
        if let language = languageTag(language), let own = found(language) { return own }
        return found(Locale.current.identifier) ?? available.first ?? "en_US"
    }

    /// The words a check skips: the design's Ignore list and this phone's
    /// `dictionary`, lower-cased.
    static func skipped(_ design: Design, dictionary: [String]) -> Set<String> {
        Set(ignored(in: design) + tidied(dictionary))
    }

    /// One entry of a word list, read leniently: nil for one that is not a
    /// string.
    struct LenientWord: Decodable {
        var word: String?

        init(from decoder: Decoder) throws {
            word = try? decoder.singleValueContainer().decode(String.self)
        }
    }

    /// The dictionary file's words: a JSON array of strings, any other entry
    /// passed over; none for anything else.
    static func decodeDictionary(_ data: Data?) -> [String] {
        guard let data, let words = try? JSONDecoder().decode([LenientWord].self, from: data) else { return [] }
        return tidied(words.compactMap(\.word))
    }

    /// The dictionary file for `words`, tidied: ["canvia","zorb"].
    static func encodeDictionary(_ words: [String]) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(tidied(words))) ?? Data("[]".utf8)
    }
}
