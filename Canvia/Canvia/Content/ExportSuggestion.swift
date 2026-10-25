// The file type the export sheet opens on, read from the design itself —
// Canva's "Suggested" — on both phones by one rule: "html" for a design of
// the Website type, "m4a" for sound over shown pages that never change
// (`audioLed`), "mp4" when a shown page
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
    /// an animated GIF or WebP, or a caption box with cues (Captions.plays);
    /// else "pdf" when more than one page is shown
    /// and the design's type is in `documentCategories`; else "png", or
    /// "jpg" when a photo covers at least `photoCover` of every shown page.
    ///
    /// A page "with autoplay" is one given a transition of its own
    /// (`Page.transition`): the design has no autoplay flag, and a page
    /// timed with its own transition was made to play. A design with every
    /// page hidden has no shown page, and is "png".
    static func suggest(_ design: Design, presets: [SizePreset] = ContentLibrary.sizes) -> String {
        if isWebsite(design, presets: presets) { return "html" }
        // A Doc goes out as its pages (Docs.paginated).
        if Docs.isDoc(design) { return "pdf" }
        let shown = design.visiblePageIndices.map { design.pages[$0] }
        // Sound over pages that never change is the sound: the audio alone.
        if !design.audioTracks.isEmpty && audioLed(design, shown) { return "m4a" }
        if !design.audioTracks.isEmpty || shown.contains(where: { moves(design, $0) }) { return "mp4" }
        if shown.count > 1, let kind = category(design, presets: presets), documentCategories.contains(kind) {
            return "pdf"
        }
        return !shown.isEmpty && shown.allSatisfy({ isPhoto(design, $0) }) ? "jpg" : "png"
    }

    /// Whether `shown` are audio-led: two pages or more, none of which moves
    /// (`moves`), each with something on it and looking exactly as the
    /// first — the same background and the same elements, ids aside — so
    /// nothing visible changes from one page to the next and only the sound
    /// goes on. A single page is never audio-led: a still post with music is
    /// still a video to post; nor are blank pages, a deck not yet made.
    static func audioLed(_ design: Design, _ shown: [Page]) -> Bool {
        guard shown.count >= 2, !shown.contains(where: { moves(design, $0) || $0.elements.isEmpty }),
              let first = shown.first else { return false }
        func look(_ page: Page) -> [Element] {
            page.elements.map { el in
                var anonymous = el
                anonymous.id = ""
                return anonymous
            }
        }
        let elements = look(first)
        return shown.allSatisfy { $0.background == first.background && look($0) == elements }
    }

    /// The web page's layout the sheet suggests for `design`: the slide
    /// player for a design of a Presentations type (`category`), else the
    /// scrolling site.
    static func htmlLayout(_ design: Design, presets: [SizePreset] = ContentLibrary.sizes) -> String {
        category(design, presets: presets) == "Presentations" ? HTMLExporter.slides : HTMLExporter.scroll
    }

    /// The Website type's id.
    static let website = "website"

    /// Whether `design` is a website: of exactly the Website type's size,
    /// the first type in the catalogue of its pixels.
    static func isWebsite(_ design: Design, presets: [SizePreset] = ContentLibrary.sizes) -> Bool {
        presets.first { $0.w == design.width && $0.h == design.height }?.id == website
    }

    /// Whether `page` moves: a clip or an animated picture on it — as a
    /// photo, filling a shape or behind the page — or on the master behind
    /// it, an element that enters or exits, a caption box with cues, or a
    /// transition of its own.
    /// Hidden elements are left out, as the film leaves them out.
    static func moves(_ design: Design, _ page: Page) -> Bool {
        if page.transition != nil { return true }
        if case .image(let src) = page.background, playing(src) { return true }
        return design.drawnElements(on: page).contains {
            playing($0.src) || playing($0.fill?.src) || $0.animation != nil || $0.exitAnimation != nil
                || Captions.plays($0)
        }
    }

    /// Whether `src` is a clip or an animated picture.
    private static func playing(_ src: String?) -> Bool {
        VideoStore.isVideo(src) || AnimStore.isAnim(src) || MotionLibrary.isMotion(src)
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

    /// Whether `page` is a photo: its background is a still picture, or one
    /// shown photo (a frame with a picture in it, as it sits, rotation
    /// aside) covers at least `photoCover` of the page's area.
    static func isPhoto(_ design: Design, _ page: Page) -> Bool {
        if case .image(let src) = page.background,
           !src.trimmingCharacters(in: .whitespaces).isEmpty, !playing(src) { return true }
        let size = design.size(for: page)
        let pageW = Double(size.width), pageH = Double(size.height)
        let area = pageW * pageH
        guard area > 0 else { return false }
        return page.elements.contains { el in
            !el.isHidden && el.type == .image && !PhotoFrames.isEmpty(el)
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
