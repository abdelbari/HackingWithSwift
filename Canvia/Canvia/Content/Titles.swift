// Designs that name themselves.
//
// A home screen of twelve cards called "Untitled Poster" makes the thumbnail
// the only thing a design has to go by, in a grid of near-identical squares.
// Two rules fix that without asking anyone to name anything. A new design
// never repeats a title already on the shelf; and while its title is still
// one the app chose, a design takes its own headline as its name when that
// headline is edited. The Android twin's Titles (core/content/Titles.kt),
// rule for rule, so a design names itself the same on either phone.

import Foundation

enum Titles {

    /// The words the app itself puts on a page, which no design should be
    /// named after. Compared ignoring case.
    static let placeholders: Set<String> = [
        "your heading", "a subheading", "a little body text", "your text here",
        "add a heading", "add a subheading", "add body text",
        "heading", "subheading", "body text", "text",
    ]

    /// The longest a title taken from a headline gets.
    static let maxLength = 40

    /// `base`, or `base 2`, `base 3`… — the first not already taken, compared
    /// ignoring case, since "poster" and "Poster" side by side are the same
    /// problem.
    static func unique(_ base: String, taken: [String]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let clean = trimmed.isEmpty ? "Untitled design" : trimmed
        let used = Set(taken.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
        guard used.contains(clean.lowercased()) else { return clean }
        var n = 2
        while used.contains("\(clean) \(n)".lowercased()) { n += 1 }
        return "\(clean) \(n)"
    }

    /// The design's headline as a title, or nil when there is none worth a
    /// name.
    static func headline(_ design: Design) -> String? {
        headlineElement(design).flatMap(title(from:))
    }

    /// The text that is the headline: the biggest on the first page — not
    /// the first added, which is rarely what says what the design is — and
    /// the topmost of equals.
    static func headlineElement(_ design: Design) -> Element? {
        let texts = (design.pages.first?.elements ?? []).filter { el in
            el.type == .text && !(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return texts.max { a, b in
            let sizeA = a.fontSize ?? 0, sizeB = b.fontSize ?? 0
            if sizeA != sizeB { return sizeA < sizeB }
            return a.y > b.y
        }
    }

    /// One text's words as a title: its first line, style marks gone, spaces
    /// collapsed, cut at a word before 40 characters. Nil when that would be
    /// a placeholder, a single character, or nothing but punctuation.
    static func title(from text: Element) -> String? {
        let lines = RichText.strip(text.text ?? "").components(separatedBy: .newlines)
        guard let line = lines.map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else {
            return nil
        }
        let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var candidate = collapsed
        if collapsed.count > maxLength {
            let taken = String(collapsed.prefix(maxLength))
            if let space = taken.lastIndex(of: " ") {
                candidate = String(taken[..<space])
            } else {
                candidate = taken
            }
            while candidate.last?.isWhitespace == true { candidate.removeLast() }
        }
        guard candidate.count >= 2,
              candidate.contains(where: { $0.isLetter || $0.isNumber }),
              !placeholders.contains(candidate.lowercased()) else { return nil }
        return candidate
    }
}
