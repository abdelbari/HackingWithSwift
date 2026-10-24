// What a text box is in the document's outline — a title, a heading at a
// level, body text, a quote or a caption — which a tagged PDF (PdfTags), a
// web page's headings (HTMLExporter.textLayer) and VoiceOver's heading trait
// all take from here, the same on both phones (the Android twin's
// TextRoles).
//
// Kept in the element as both phones write it, "textRole": one of `roles`.
// Absent, the role is inferred by size (`of`): Add ▸ Text writes the role it
// adds (`forBrandRole`), so only older text and text sized by hand is
// guessed at.
//
// A second, optional key, "a11yRole" ("h1", "h2", "h3", "p" or "artifact"),
// is the Text panel's Read as: how a screen reader takes the box in an
// exported PDF, whatever it looks like — "artifact" leaves it out.

import Foundation

enum TextRoles {

    static let title = "title"
    static let h1 = "h1"
    static let h2 = "h2"
    static let h3 = "h3"
    static let body = "body"
    static let quote = "quote"
    static let caption = "caption"

    /// Every role, in the order the Text panel's Role row offers them
    /// (after Auto).
    static let roles = [title, h1, h2, h3, body, quote, caption]

    static let readP = "p"
    static let readArtifact = "artifact"

    /// Read as, after Auto, in the order the row offers them.
    static let readChoices = [h1, h2, h3, readP, readArtifact]

    /// The role written on `el`, or nil for none that reads.
    static func stored(_ el: Element) -> String? {
        el.textRole.flatMap { roles.contains($0) ? $0 : nil }
    }

    /// The Read as written on `el`, or nil for none that reads.
    static func readAs(_ el: Element) -> String? {
        el.a11yRole.flatMap { readChoices.contains($0) ? $0 : nil }
    }

    /// Whether `el` carries words a role applies to: a text box, or a shape
    /// with words in it.
    static func hasRole(_ el: Element) -> Bool {
        el.type == .text || (el.type == .shape && ShapeText.words(of: el) != nil)
    }

    /// `el`'s role: the one written, else inferred by size rank. The rule
    /// both phones share: the distinct type sizes of the design's words at
    /// or above DesignStore.headingSize (the Android twin's
    /// Themes.HEADING_SIZE), biggest first, take the brand kit's heading and
    /// subheading in turn — "h1", then "h2" — and every smaller heading size
    /// "h3"; anything under it is "body". A title, a quote and a caption are
    /// what a text says, not how big it is, so they are never guessed, only
    /// written. Nil for an element that has no words.
    static func of(_ el: Element, in design: Design) -> String? {
        guard hasRole(el) else { return nil }
        if let own = stored(el) { return own }
        return inferred(el.fontSize ?? 42, headingSizes: headingSizes(design))
    }

    /// The design's heading sizes, biggest first, once each.
    static func headingSizes(_ design: Design) -> [Double] {
        var seen: Set<Double> = []
        var sizes: [Double] = []
        for el in design.pages.flatMap(\.elements) where hasRole(el) {
            let size = el.fontSize ?? 42
            if size >= DesignStore.headingSize && seen.insert(size).inserted { sizes.append(size) }
        }
        return sizes.sorted(by: >)
    }

    /// The role a size takes among `headingSizes` (biggest first).
    static func inferred(_ size: Double, headingSizes: [Double]) -> String {
        guard size >= DesignStore.headingSize else { return body }
        switch headingSizes.firstIndex(of: size) ?? 0 {
        case 0: return h1
        case 1: return h2
        default: return h3
        }
    }

    /// A heading's level, 1 to 3 — a title is a first-level heading — or
    /// nil for a role that is not a heading.
    static func level(_ role: String?) -> Int? {
        guard let role else { return nil }
        switch role {
        case title, h1: return 1
        case h2: return 2
        case h3: return 3
        default: return nil
        }
    }

    /// The heading role at `level` (1 to 3).
    static func heading(_ level: Int) -> String {
        switch min(max(level, 1), 3) {
        case 1: return h1
        case 2: return h2
        default: return h3
        }
    }

    /// The role Add ▸ Text writes for a brand kit role.
    static func forBrandRole(_ role: BrandFonts.Role) -> String {
        switch role {
        case .title: return title
        case .heading: return h1
        case .subheading: return h2
        // A subtitle and a section header are read as body text, as on
        // the Android twin.
        case .subtitle, .sectionHeader, .body: return body
        case .quote: return quote
        case .caption: return caption
        }
    }

    /// `el` with `role` written, or the key taken away for nil (Auto).
    static func with(_ el: Element, _ role: String?) -> Element {
        var out = el
        out.textRole = role.flatMap { roles.contains($0) ? $0 : nil }
        return out
    }

    /// `el` with Read as `choice` written, or taken away for nil (Auto).
    static func withReadAs(_ el: Element, _ choice: String?) -> Element {
        var out = el
        out.a11yRole = choice.flatMap { readChoices.contains($0) ? $0 : nil }
        return out
    }

    /// The Role row's name for a role; nil is "Auto".
    static func name(_ role: String?) -> String {
        guard let role else { return tr("Auto") }
        switch role {
        case title: return tr("Title")
        case h1: return tr("Heading 1")
        case h2: return tr("Heading 2")
        case h3: return tr("Heading 3")
        case body: return tr("Body")
        case quote: return tr("Quote")
        case caption: return tr("Caption")
        default: return role
        }
    }

    /// The Read as row's name for a choice; nil is "Auto".
    static func readAsName(_ choice: String?) -> String {
        guard let choice else { return tr("Auto") }
        switch choice {
        case h1: return tr("Heading 1")
        case h2: return tr("Heading 2")
        case h3: return tr("Heading 3")
        case readP: return tr("Paragraph")
        case readArtifact: return tr("Not read")
        default: return choice
        }
    }

    /// Whether VoiceOver should hear `el` as a heading: its Read as says a
    /// heading, or, with none, its role does.
    static func isHeading(_ el: Element, in design: Design) -> Bool {
        if let read = readAs(el) { return read == h1 || read == h2 || read == h3 }
        return level(of(el, in: design)) != nil
    }
}
