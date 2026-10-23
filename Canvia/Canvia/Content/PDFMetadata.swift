// What an exported PDF says about itself, the same on both phones: its
// title, who made it, its language, a bookmark for each page and the alt
// text of its pictures — so a reader shows the design's name in its title
// bar, a screen reader knows what language to read it in, and the pages
// are navigable by name. Core Graphics is given the title as it starts the
// file; the rest is appended to the finished file as an incremental update
// (PDFUpdate), as the Android twin appends it (core/content/PdfMetadata.kt,
// PdfLinks.kt). The shared fixture is Tests/Fixtures/pdf-metadata.json.

import Foundation

enum PDFMetadata {

    /// The /Creator: the app that made the design.
    static let creator = "Canvia"

    /// The /Producer, "Canvia 1.4": the app, at the version that wrote the
    /// file.
    static func producer(_ version: String) -> String {
        let v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? creator : "\(creator) \(v)"
    }

    /// This build's version, as the Producer names it.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// The /Lang: the design's spelling language, else the app's own,
    /// `appLanguage` — both BCP-47 — else English.
    static func language(_ design: Design, appLanguage: String) -> String {
        if let own = Proofreader.languageTag(design.language) { return own }
        let app = appLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        return app.isEmpty ? "en" : app
    }

    /// The document information, in the order it is written: Title (the
    /// design's), Creator and Producer.
    static func info(_ design: Design, version: String) -> [(key: String, value: String)] {
        [("Title", design.title), ("Creator", creator), ("Producer", producer(version))]
    }

    /// The outline entry for page number `number` (from 1, as the design
    /// counts its pages): the page's own title, else "Page N".
    static func bookmarkTitle(_ page: Page, number: Int) -> String {
        if let title = page.title, let kept = PageTitles.kept(title) {
            return kept.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return tr("Page %d", number)
    }

    /// One bookmark per exported page, in `indices`' order, each titled by
    /// its page: what the outline lists. A notes page that follows a page
    /// gets no entry of its own; the page's leads to it.
    static func bookmarks(_ design: Design, indices: [Int]) -> [String] {
        indices.compactMap { i in design.pages.indices.contains(i) ? bookmarkTitle(design.pages[i], number: i + 1) : nil }
    }

    /// A picture on a page with something to say: where it sits, in page
    /// units from the top left, and its alt text.
    struct Figure: Equatable {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var alt: String
    }

    /// The pictures of `page` a screen reader is told about — photos,
    /// icons and stickers that are not decorative and have alt text, the
    /// master's behind it too, the hidden ones left out — in reading order
    /// (CanvasAccessibility.readingOrder), each with its alt text.
    static func figures(_ design: Design, page: Page) -> [Figure] {
        let elements = design.masterElements(behind: page) + page.elements.filter { !$0.isHidden }
        let byId = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let order = CanvasAccessibility.readingOrder(elements, pageHeight: Double(design.size(for: page).height))
        return order.compactMap { id -> Figure? in
            guard let el = byId[id], AccessibilityAudit.isPicture(el), el.decorative != true else { return nil }
            let alt = (el.altText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !alt.isEmpty else { return nil }
            return Figure(x: el.x, y: el.y, w: el.w, h: el.h, alt: alt)
        }
    }
}
