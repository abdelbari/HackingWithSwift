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

    /// What travels: the page, and the size of the page it came from, so a
    /// paste into a differently sized design can scale it to fit.
    struct Payload: Codable {
        var page: Page
        var width: Double
        var height: Double
    }

    static func copy(_ page: Page, width: Double, height: Double,
                     to pasteboard: UIPasteboard = .general) {
        guard let data = try? JSONEncoder().encode(Payload(page: page, width: width, height: height))
        else { return }
        pasteboard.setData(data, forPasteboardType: type)
    }

    static func hasPage(in pasteboard: UIPasteboard = .general) -> Bool {
        pasteboard.contains(pasteboardTypes: [type])
    }

    static func paste(from pasteboard: UIPasteboard = .general) -> Payload? {
        guard let data = pasteboard.data(forPasteboardType: type) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    /// The page as it should land in a design of `width` × `height`: fresh
    /// ids (a paste next to its source must not share them), and scaled to
    /// fit when the sizes differ, centred on the shorter axis — the same
    /// rule resizing a design uses, for the same reason.
    static func fitted(_ payload: Payload, width: Double, height: Double) -> Page {
        var page = payload.page
        page.id = UID.make("page")
        page.elements = page.elements.map { el in
            var e = el
            e.id = UID.make()
            return e
        }
        // Groups keep their members together, under new keys.
        var groups: [String: String] = [:]
        for i in page.elements.indices {
            if let g = page.elements[i].group {
                if groups[g] == nil { groups[g] = UID.make("grp") }
                page.elements[i].group = groups[g]
            }
        }
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
        }
        return page
    }
}
