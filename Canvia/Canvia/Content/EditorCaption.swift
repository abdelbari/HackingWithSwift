// The words around a design's name in the editor's top bar: the size and
// page line under it, and what a rename comes to.

import Foundation

enum EditorCaption {

    /// "1080 × 1920 · Page 2 of 5": the page on screen at its own size, and
    /// where it sits in the deck. `page` is zero-based.
    static func text(width: Double, height: Double, page: Int, of pages: Int) -> String {
        text(width: width, height: height, unit: nil, dpi: nil, page: page, of: pages)
    }

    /// The same in the design's unit: "210 × 297 mm · Page 1 of 2".
    static func text(width: Double, height: Double, unit: String?, dpi: Double?, page: Int, of pages: Int) -> String {
        "\(Units.dimensions(width: width, height: height, unit: unit, dpi: dpi)) · Page \(page + 1) of \(max(pages, 1))"
    }

    /// The name a rename leaves, trimmed; nil when there is nothing to
    /// record — a name emptied out (the old one stays) or one unchanged.
    static func renamed(_ typed: String, was old: String) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != old else { return nil }
        return trimmed
    }
}
