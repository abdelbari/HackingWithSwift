// Links on elements: a web address, an email or a phone number on a shape,
// a picture or a line of text, as Canva has them — clickable over the
// element in the exported PDF and SVG, and opened by a tap in the presenter.
// Chosen words can carry a link of their own (see Spans), clickable over
// those words only (WordLinks); the element's link still answers elsewhere.
//
// What is typed is read the way people type it: "canvia.app" is a web
// address, "hello@canvia.app" an email, "+44 1234 567890" a phone number.
// The Android twin reads it the same way (core/content/Links.kt) and keeps
// the link in the same `link` field, so a linked design keeps its links on
// either phone.

import CoreGraphics
import Foundation

enum Links {

    static let schemes = ["https://", "http://", "mailto:", "tel:"]

    /// What was typed, as a link a reader can follow, or nil when it is not
    /// one: an address with its scheme kept, a bare domain made https, an
    /// email address mailto and a phone number tel.
    ///
    /// A scheme typed in capitals — "HTTPS://", or "Mailto:" from a notes
    /// app that capitalised it — is kept in lower case: Android matches a
    /// link's scheme to the app that opens it letter for letter, so there
    /// "Https://canvia.app" opened nothing. The rest is kept as typed.
    static func normalized(_ input: String) -> String? {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty || typed.contains(where: { $0.isWhitespace && $0 != " " }) { return nil }
        let lower = typed.lowercased()
        if let scheme = schemes.first(where: { lower.hasPrefix($0) }) {
            guard typed.count > scheme.count, !typed.contains(" ") else { return nil }
            return scheme + String(typed.dropFirst(scheme.count))
        }
        if typed.contains(" ") {
            return phone(typed, allowing: " +-().")
        }
        if matches(typed, email) { return "mailto:" + typed }
        if let tel = phone(typed, allowing: "+-().") { return tel }
        if matches(typed, domain) { return "https://" + typed }
        return nil
    }

    /// What a link reads as, for a label: the address without its scheme.
    static func shown(_ url: String) -> String {
        var s = url
        for scheme in schemes where s.lowercased().hasPrefix(scheme) {
            s = String(s.dropFirst(scheme.count))
        }
        return s.hasSuffix("/") ? String(s.dropLast()) : s
    }

    /// The link, when it is one to follow: a web address, an email or a
    /// phone number. Typing only ever makes those, but a design file from
    /// anywhere can carry anything in `link` — a file: or javascript: one —
    /// and none of that is opened in Present, made clickable in a PDF or
    /// written into an SVG. The Android twin follows the same four.
    static func followable(_ link: String?) -> String? {
        guard let link, !link.isEmpty else { return nil }
        let lower = link.lowercased()
        return schemes.contains(where: { lower.hasPrefix($0) }) ? link : nil
    }

    /// Every linked element on the page as drawn — the master's first — with
    /// its area on the page, and after each one the lines of its linked
    /// words, which lie over it.
    static func areas(design: Design, page: Page) -> [(rect: CGRect, url: String)] {
        drawn(design: design, page: page).flatMap { el -> [(rect: CGRect, url: String)] in
            var out: [(rect: CGRect, url: String)] = []
            if let url = followable(el.link) { out.append((rect: Geometry.aabb(el), url: url)) }
            for words in WordLinks.areas(of: el) {
                if let url = followable(words.url) { out.append((rect: words.rect, url: url)) }
            }
            return out
        }
    }

    /// The link under `point` on the page: the topmost element with a link
    /// there — its linked words', where the point is on them, else its own,
    /// rotation and all; nil where there is none.
    static func at(design: Design, page: Page, point: CGPoint) -> String? {
        for el in drawn(design: design, page: page).reversed() {
            if let url = followable(WordLinks.link(in: el, at: point)) { return url }
            if let url = followable(el.link), Geometry.hits(el, point: point) { return url }
        }
        return nil
    }

    /// The page's elements as drawn, the page's numbers in its words — so
    /// linked words are found where the page draws them.
    private static func drawn(design: Design, page: Page) -> [Element] {
        let number = (design.pages.firstIndex { $0.id == page.id } ?? 0) + 1
        return design.drawnElements(on: page).map { el in
            var out = el
            if out.type == .text { out.fillPageTokens(number: number, count: design.pages.count) }
            return out
        }
    }

    // MARK: reading what is typed

    private static let email = "^[^@\\s/]+@[^@\\s/]+\\.[a-zA-Z]{2,}$"
    private static let domain = "^[a-zA-Z0-9-]+(\\.[a-zA-Z0-9-]+)*\\.[a-zA-Z]{2,}(:[0-9]+)?([/?#].*)?$"

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isDigit(_ c: Character) -> Bool {
        ("0"..."9").contains(c)
    }

    /// A phone number of at least six digits written with only `allowing`
    /// between them, as a tel link of its digits and plus sign.
    private static func phone(_ text: String, allowing: String) -> String? {
        guard text.allSatisfy({ isDigit($0) || allowing.contains($0) }),
              text.filter(isDigit).count >= 6 else { return nil }
        return "tel:" + text.filter { isDigit($0) || $0 == "+" }
    }
}
