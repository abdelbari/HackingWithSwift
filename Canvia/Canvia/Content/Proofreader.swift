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
    /// element by element, left to right. Words that are not words —
    /// numbers, hashtags, addresses, SHOUTED acronyms — are left alone.
    static func misspellings(in design: Design, language: String = Locale.current.identifier,
                             maxSuggestions: Int = 4) -> [Misspelling] {
        let checker = UITextChecker()
        let lang = UITextChecker.availableLanguages.contains(language) ? language
            : (UITextChecker.availableLanguages.first ?? "en_US")
        var found: [Misspelling] = []
        for (p, page) in design.pages.enumerated() {
            for el in page.elements where el.type == .text {
                guard let text = el.text, !text.isEmpty else { continue }
                let ns = text as NSString
                var location = 0
                while location < ns.length {
                    let range = checker.rangeOfMisspelledWord(
                        in: text, range: NSRange(location: location, length: ns.length - location),
                        startingAt: location, wrap: false, language: lang)
                    guard range.location != NSNotFound else { break }
                    let word = ns.substring(with: range)
                    if isWorthFlagging(word) {
                        let guesses = checker.guesses(forWordRange: range, in: text, language: lang) ?? []
                        found.append(Misspelling(pageIndex: p, elementId: el.id, range: range,
                                                 word: word, suggestions: Array(guesses.prefix(maxSuggestions))))
                    }
                    location = range.location + range.length
                }
            }
        }
        return found
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
}
