// Whole pages on the system pasteboard.
//
// Copying a page from one design into another — a title slide, a closing
// page, a layout that worked — needs the page to survive leaving the
// editor, which the in-memory element clipboard does not. The system
// pasteboard does, across designs and across launches, and it costs nothing
// to use: a page is a few kilobytes of JSON under a private type.

import UIKit

enum PageClipboard {

    static let type = "com.canvia.page"
    /// Several pages at once, in order (Pages). Written beside `type`, which
    /// keeps the first of them for builds that read one page only.
    static let pagesType = "com.canvia.pages"

    /// What travels: the page, the size of the page it came from, so a
    /// paste into a differently sized design can scale it to fit, and the
    /// records of the fonts of your own on it (CustomFonts.carried) — none
    /// from a build that did not write them.
    struct Payload: Codable {
        var page: Page
        var width: Double
        var height: Double
        var fonts: [CustomFonts.Record]?
    }

    /// One page of several, and the size of the page it came from.
    struct CopiedPage: Codable, Equatable {
        var page: Page
        var width: Double
        var height: Double
    }

    /// What several pages carry, the Android twin's clipboard/pages.json:
    /// {"pages":[{"page":…,"width":…,"height":…}],"fonts":[…]} — the
    /// pages in order, and the records of the fonts of your own on any of
    /// them; none from a file that has no "fonts".
    struct Pages: Codable, Equatable {
        var pages: [CopiedPage]
        var fonts: [CustomFonts.Record]

        init(pages: [CopiedPage], fonts: [CustomFonts.Record] = []) {
            self.pages = pages
            self.fonts = fonts
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pages = try c.decode([CopiedPage].self, forKey: .pages)
            fonts = (try? c.decode([CustomFonts.Record].self, forKey: .fonts)) ?? []
        }
    }

    static func copy(_ page: Page, width: Double, height: Double, fonts: [CustomFonts.Record] = [],
                     to pasteboard: UIPasteboard = .general) {
        let payload = Payload(page: page, width: width, height: height, fonts: fonts.isEmpty ? nil : fonts)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        pasteboard.setData(data, forPasteboardType: type)
        copied = (pasteboard.name.rawValue, pasteboard.changeCount, 1)
    }

    /// Several pages copied as one: all of them, in order, under
    /// `pagesType`, and the first under `type` for a build that reads one.
    static func copy(_ pages: Pages, to pasteboard: UIPasteboard = .general) {
        guard let first = pages.pages.first,
              let many = try? JSONEncoder().encode(pages) else { return }
        let one = Payload(page: first.page, width: first.width, height: first.height,
                          fonts: pages.fonts.isEmpty ? nil : pages.fonts)
        guard let single = try? JSONEncoder().encode(one) else { return }
        pasteboard.setItems([[pagesType: many, type: single]])
        copied = (pasteboard.name.rawValue, pasteboard.changeCount, pages.pages.count)
    }

    /// The pasteboard, its count of changes and how many pages, as this app
    /// last copied them: so the menus can say Paste pages without reading
    /// the pasteboard, which would bring up the paste prompt.
    private static var copied: (board: String, change: Int, count: Int)?

    /// How many pages are on the pasteboard, when this app put them there
    /// and nothing has been copied since; nil when that is not known.
    static func copiedCount(in pasteboard: UIPasteboard = .general) -> Int? {
        guard let copied, copied.board == pasteboard.name.rawValue, copied.change == pasteboard.changeCount else {
            return nil
        }
        return copied.count
    }

    static func hasPage(in pasteboard: UIPasteboard = .general) -> Bool {
        pasteboard.contains(pasteboardTypes: [pagesType, type])
    }

    static func paste(from pasteboard: UIPasteboard = .general) -> Payload? {
        guard let data = pasteboard.data(forPasteboardType: type) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// Every page on the pasteboard, in order: the several under
    /// `pagesType`, or — from a build that copies one page — that page.
    static func pastePages(from pasteboard: UIPasteboard = .general) -> Pages? {
        if let data = pasteboard.data(forPasteboardType: pagesType),
           let pages = try? JSONDecoder().decode(Pages.self, from: data), !pages.pages.isEmpty {
            return pages
        }
        guard let one = paste(from: pasteboard) else { return nil }
        return Pages(pages: [CopiedPage(page: one.page, width: one.width, height: one.height)], fonts: one.fonts ?? [])
    }

    /// The pages as they land in a design of `width` × `height`, in order:
    /// each fitted as one page is (fitted), with fresh ids and its arrows
    /// joined to the copies.
    static func landed(_ pages: Pages, width: Double, height: Double) -> [Page] {
        pages.pages.map { entry in
            fitted(Payload(page: entry.page, width: entry.width, height: entry.height), width: width, height: height)
        }
    }

    /// The page as it should land in a design of `width` × `height`: fresh
    /// ids (a paste next to its source must not share them), groups under
    /// new keys and arrows joined to the copies (see Copies), and scaled to
    /// fit when the sizes differ, centred on the shorter axis — the same
    /// rule resizing a design uses, for the same reason.
    static func fitted(_ payload: Payload, width: Double, height: Double) -> Page {
        var page = Copies.of(payload.page)
        guard payload.width > 0, payload.height > 0,
              payload.width != width || payload.height != height else { return page }
        let scale = min(width / payload.width, height / payload.height)
        let dx = (width - payload.width * scale) / 2
        let dy = (height - payload.height * scale) / 2
        for i in page.elements.indices {
            page.elements[i].x = page.elements[i].x * scale + dx
            page.elements[i].y = page.elements[i].y * scale + dy
            page.elements[i].w *= scale
            page.elements[i].h *= scale
            if let fs = page.elements[i].fontSize { page.elements[i].fontSize = fs * scale }
            if let t = page.elements[i].thickness { page.elements[i].thickness = max(1, t * scale) }
            // The same rule resizing a design uses: every page-unit distance scales.
            if let ls = page.elements[i].letterSpacing { page.elements[i].letterSpacing = ls * scale }
            if let r = page.elements[i].radius { page.elements[i].radius = r * scale }
            if let c = page.elements[i].corners { page.elements[i].corners = c.map { $0 * scale } }
            if let sw = page.elements[i].strokeWidth { page.elements[i].strokeWidth = sw * scale }
            page.elements[i].table = TableCell.scaledPad(page.elements[i].table, by: scale)
        }
        return page
    }
}
