// Spelling, checked across the whole document.
//
// A design is read once by its maker and a thousand times by strangers, and
// a misspelt headline is the mistake none of them forgive. UITextChecker is
// the system's own dictionary — offline, in the user's languages — and it
// gives suggestions, so the fix is a tap rather than a retype.

import UIKit

enum Proofreader {

    struct Misspelling: Identifiable, Equatable {
        var id: String { "\(pageIndex)|\(elementId)|\(range.location)" }
        var pageIndex: Int
        var elementId: String
        var range: NSRange
        var word: String
        var suggestions: [String]
    }

    /// Every word the checker does not know, in reading order: page by page,
    /// element by element — text boxes and the words in shapes — left to
    /// right. Words that are not words — numbers, hashtags, addresses,
    /// SHOUTED acronyms — are left alone. Each box is read as it reads,
    /// style marks left out, so "he**llo**" is one word, and each word found
    /// is placed back where it is stored.
    static func misspellings(in design: Design, language: String = Locale.current.identifier,
                             maxSuggestions: Int = 4) -> [Misspelling] {
        let checker = UITextChecker()
        let lang = UITextChecker.availableLanguages.contains(language) ? language
            : (UITextChecker.availableLanguages.first ?? "en_US")
        var found: [Misspelling] = []
        for (p, page) in design.pages.enumerated() {
            for el in page.elements where ShapeText.carriesWords(el) {
                guard let text = el.text, !text.isEmpty else { continue }
                let (plain, rawAt) = RichText.mapped(text)
                let ns = plain as NSString
                var location = 0
                while location < ns.length {
                    let range = checker.rangeOfMisspelledWord(
                        in: plain, range: NSRange(location: location, length: ns.length - location),
                        startingAt: location, wrap: false, language: lang)
                    guard range.location != NSNotFound, range.length > 0 else { break }
                    let word = ns.substring(with: range)
                    if isWorthFlagging(word), let stored = storedRange(range, plain: plain, rawAt: rawAt, in: text) {
                        let guesses = checker.guesses(forWordRange: range, in: plain, language: lang) ?? []
                        found.append(Misspelling(pageIndex: p, elementId: el.id, range: stored,
                                                 word: word, suggestions: Array(guesses.prefix(maxSuggestions))))
                    }
                    location = range.location + range.length
                }
            }
        }
        return found
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
    /// misspelling.
    static func isWorthFlagging(_ word: String) -> Bool {
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
    static func replacing(_ m: Misspelling, in text: String, with replacement: String) -> String {
        guard let r = Range(m.range, in: text) else { return text }
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
    /// letters.
    static func fixed(_ design: Design, _ m: Misspelling, with replacement: String) -> Design? {
        guard design.pages.indices.contains(m.pageIndex),
              let i = design.pages[m.pageIndex].elements.firstIndex(where: { $0.id == m.elementId }),
              let text = design.pages[m.pageIndex].elements[i].text,
              let r = Range(m.range, in: text) else { return nil }
        let start = text.distance(from: text.startIndex, to: r.lowerBound)
        let end = text.distance(from: text.startIndex, to: r.upperBound)
        let (plain, rawAt) = RichText.mapped(text)
        let letters = Array(plain)
        let reads = String(rawAt.indices.filter { (start..<end).contains(rawAt[$0]) }.map { letters[$0] })
        guard reads == m.word else { return nil }
        var out = design
        out.pages[m.pageIndex].elements[i].setText(replacing(m, in: text, with: replacement))
        out.pages[m.pageIndex].elements[i].h = ShapeText.heightForWords(out.pages[m.pageIndex].elements[i])
        return out
    }
}
