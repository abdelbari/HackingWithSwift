// Links on elements: a web address, an email or a phone number on a shape,
// a picture or a line of text, as Canva has them — clickable over the
// element in the exported PDF and SVG, and opened by a tap in the presenter.
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
    /// its area on the page.
    static func areas(design: Design, page: Page) -> [(rect: CGRect, url: String)] {
        (design.masterElements(behind: page) + page.elements).compactMap { el in
            guard let url = followable(el.link) else { return nil }
            return (Geometry.aabb(el), url)
        }
    }

    /// The link under `point` on the page: the topmost linked element holding
    /// it, rotation and all; nil where there is none.
    static func at(design: Design, page: Page, point: CGPoint) -> String? {
        let drawn = design.masterElements(behind: page) + page.elements
        let hit = drawn.last { el in
            followable(el.link) != nil && Geometry.hits(el, point: point)
        }
        return followable(hit?.link)
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
