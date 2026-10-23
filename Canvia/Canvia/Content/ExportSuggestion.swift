// The file type the export sheet opens on, read from the design itself —
// Canva's "Suggested" — on both phones by one rule: "mp4" when a shown page
// moves or sounds, "pdf" for a document of several pages, else "png", or
// "jpg" for a design that is a photo. The sheet puts a remembered choice
// before it and the Settings default after (see ExportSheet's precedence).
// The Android twin's core/content/ExportSuggestion.kt, with the shared
// fixture Tests/Fixtures/export-suggestion.json.

import Foundation

enum ExportSuggestion {

    /// How much of a page a photo must cover for the page to be a photo.
    static let photoCover = 0.9

    /// The design types whose several pages are a document, not a set of
    /// posts: the categories of the Design types sheet.
    static let documentCategories: Set<String> = ["Documents", "Print", "Presentations"]

    /// "mp4" if any shown page has a clip, an audio track, an element
    /// animation (an entrance or an exit), a page transition of its own or
    /// an animated GIF or WebP; else "pdf" when more than one page is shown
    /// and the design's type is in `documentCategories`; else "png", or
    /// "jpg" when a photo covers at least `photoCover` of every shown page.
    ///
    /// A page "with autoplay" is one given a transition of its own
    /// (`Page.transition`): the design has no autoplay flag, and a page
    /// timed with its own transition was made to play. A design with every
    /// page hidden has no shown page, and is "png".
    static func suggest(_ design: Design, presets: [SizePreset] = ContentLibrary.sizes) -> String {
        let shown = design.visiblePageIndices.map { design.pages[$0] }
        if !design.audioTracks.isEmpty || shown.contains(where: { moves(design, $0) }) { return "mp4" }
        if shown.count > 1, let kind = category(design, presets: presets), documentCategories.contains(kind) {
            return "pdf"
        }
        return !shown.isEmpty && shown.allSatisfy({ isPhoto(design, $0) }) ? "jpg" : "png"
    }

    /// Whether `page` moves: a clip on it or behind it, an animated
    /// picture, an element that enters or exits, or a transition of its
    /// own.
    static func moves(_ design: Design, _ page: Page) -> Bool {
        if page.transition != nil { return true }
        let elements = design.masterElements(behind: page) + page.elements
        return elements.contains {
            VideoStore.isVideo($0.src) || AnimStore.isAnim($0.src) || $0.animation != nil || $0.exitAnimation != nil
        }
    }

    /// The category of the design's type: the first preset of exactly its
    /// pixel size, else the first of its size the other way round — a
    /// design turned landscape is still an A4, but a 1920 × 1080 is a
    /// Presentation before it is an Instagram Story turned — or nil for a
    /// size of its own. The simplest rule both phones can share; a custom
    /// size is never a document.
    static func category(_ design: Design, presets: [SizePreset] = ContentLibrary.sizes) -> String? {
        let w = design.width, h = design.height
        let upright = presets.first { $0.w == w && $0.h == h }
        return (upright ?? presets.first { $0.w == h && $0.h == w })?.category
    }

    /// Whether `page` is a photo: its background is a picture, or one photo
    /// (a frame with a picture in it, as it sits, rotation aside) covers at
    /// least `photoCover` of the page's area.
    static func isPhoto(_ design: Design, _ page: Page) -> Bool {
        if case .image(let src) = page.background,
           !src.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        let size = design.size(for: page)
        let pageW = Double(size.width), pageH = Double(size.height)
        let area = pageW * pageH
        guard area > 0 else { return false }
        return page.elements.contains { el in
            el.type == .image && !PhotoFrames.isEmpty(el)
                && covered(el, pageW: pageW, pageH: pageH) / area >= photoCover
        }
    }

    /// The area of `el`'s box that lies on a page `pageW` × `pageH`.
    private static func covered(_ el: Element, pageW: Double, pageH: Double) -> Double {
        let left = max(0, el.x), top = max(0, el.y)
        let right = min(pageW, el.x + el.w), bottom = min(pageH, el.y + el.h)
        return max(0, right - left) * max(0, bottom - top)
    }
}
