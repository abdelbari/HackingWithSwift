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
//
// A link can also go to a page of this design: "page:<page id>", by the
// page's own id, so moving pages about keeps the link on its page. It is
// followed only while that page is in the design — a page deleted leaves
// the link dangling, said as "Page removed" and left out of every export —
// jumping to the page in Present, as a GoTo link in the PDF, a slide jump
// in PowerPoint and an anchor on the web page.

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
    ///
    /// A page link ("page:<id>") is kept when `design` has that page; with
    /// no design — a file being read — when it names one at all, so it
    /// comes back to the phone that wrote it unchanged.
    static func normalized(_ input: String, in design: Design? = nil) -> String? {
        let typed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.lowercased().hasPrefix(pageScheme) {
            guard let id = pageId(typed) else { return nil }
            if let design, !design.pages.contains(where: { page in page.id == id }) { return nil }
            return pageLink(id)
        }
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

    // MARK: links to pages

    /// What a link to a page of this design starts with.
    static let pageScheme = "page:"

    /// The link to the page `id`.
    static func pageLink(_ id: String) -> String { pageScheme + id }

    /// The id of the page a page link names; nil for any other link.
    static func pageId(_ link: String?) -> String? {
        guard let link, link.lowercased().hasPrefix(pageScheme) else { return nil }
        let id = String(link.dropFirst(pageScheme.count))
        return id.isEmpty || id.contains(where: \.isWhitespace) ? nil : id
    }

    /// Where in `design` the page a page link names is; nil for another
    /// link, or a page no longer there.
    static func pageIndex(_ link: String?, in design: Design) -> Int? {
        guard let id = pageId(link) else { return nil }
        return design.pages.firstIndex { $0.id == id }
    }

    /// Whether `link` is one to follow in `design`: a web address, email
    /// or phone number (followable), or a page of it still there.
    static func isFollowable(_ link: String?, in design: Design) -> Bool {
        followable(link) != nil || pageIndex(link, in: design) != nil
    }

    /// Whether `link` goes to a page `design` no longer has.
    static func isDangling(_ link: String?, in design: Design) -> Bool {
        pageId(link) != nil && pageIndex(link, in: design) == nil
    }

    /// A link as the link sheet and the toolbar show it: "Page 3 · Pricing"
    /// for a page, "Page removed" for one gone, else the address (shown).
    static func label(_ link: String, in design: Design) -> String {
        guard pageId(link) != nil else { return shown(link) }
        guard let index = pageIndex(link, in: design) else { return tr("Page removed") }
        return PageTitles.named(index + 1, title: design.pages[index].title)
    }

    /// A link as VoiceOver reads it: "Link to page 3, Pricing", "Link to
    /// page 3" untitled, "Page removed" gone, "Link to canvia.app".
    static func spoken(_ link: String, in design: Design) -> String {
        guard pageId(link) != nil else { return tr("Link to %@", shown(link)) }
        guard let index = pageIndex(link, in: design) else { return tr("Page removed") }
        let said = tr("Link to page %d", index + 1)
        guard let title = design.pages[index].title.flatMap(PageTitles.kept) else { return said }
        return said + ", " + title
    }

    /// Where an exported link goes: an address, or a page of the file, by
    /// its id.
    enum ExportTarget: Equatable {
        case address(String)
        case page(String)
    }

    /// A link as an export writes it, among `pages` — the ids of the pages
    /// the file holds: an address, or the page, only when that page is in
    /// the file; nil for anything else, a dangling page link among them.
    static func target(_ link: String?, in design: Design, pages: Set<String>) -> ExportTarget? {
        if let url = followable(link) { return .address(url) }
        guard pageIndex(link, in: design) != nil, let id = pageId(link), pages.contains(id) else { return nil }
        return .page(id)
    }

    /// Every link on `page` as an export of `pages` writes it (target), over
    /// its area — the master's first, each element's linked words after it.
    static func exportAreas(design: Design, page: Page, pages: Set<String>) -> [(rect: CGRect, target: ExportTarget)] {
        areas(design: design, page: page).compactMap { area in
            target(area.url, in: design, pages: pages).map { (rect: area.rect, target: $0) }
        }
    }

    /// Every linked element on the page as drawn — the master's first — with
    /// its area on the page, and after each one its linked words, a word
    /// each, which lie over it: each link one to follow in `design`
    /// (isFollowable), page links included.
    static func areas(design: Design, page: Page) -> [(rect: CGRect, url: String)] {
        drawn(design: design, page: page).flatMap { el -> [(rect: CGRect, url: String)] in
            var out: [(rect: CGRect, url: String)] = []
            if let url = el.link, isFollowable(url, in: design) { out.append((rect: Geometry.aabb(el), url: url)) }
            for words in WordLinks.areas(of: el) where isFollowable(words.url, in: design) {
                out.append((rect: words.rect, url: words.url))
            }
            return out
        }
    }

    /// The link under `point` on the page: the topmost element with a link
    /// there — its linked words', where the point is on them, else its own,
    /// rotation and all; nil where there is none.
    static func at(design: Design, page: Page, point: CGPoint) -> String? {
        for el in drawn(design: design, page: page).reversed() {
            if let url = WordLinks.link(in: el, at: point), isFollowable(url, in: design) { return url }
            if let url = el.link, isFollowable(url, in: design), Geometry.hits(el, point: point) { return url }
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
