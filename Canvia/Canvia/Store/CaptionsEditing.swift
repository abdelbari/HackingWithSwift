// Captions as steps: the page's caption box for a clip or a track given
// its cues — or a new box across the lower part of the page — and its
// style; and a clip's captions moved with its trim and speed, so the
// words stay on the frames they were heard in. The pure parts are
// Captions'; the Android twin's EditorViewModel does the same.

import Foundation

extension DesignStore {

    /// This page's caption box for `source` — "video:<id>" or
    /// "audio:<trackId>" — or nil for none yet.
    func captionsFor(_ source: String) -> Element? {
        page.elements.first { $0.captions?.source == source }
    }

    /// The captions for `source` set to `cues` — on the page's caption box
    /// for it, keeping the style it has, or on a new one across the lower
    /// part of the page (Captions.element) — as one undo step; the box is
    /// selected. Nothing goes on a locked page.
    func setCaptions(_ source: String, cues: [CaptionCue]) {
        guard !refusesLockedPage() else { return }
        if let existing = captionsFor(source) {
            var next = existing.captions ?? Captions(source: source)
            next.cues = cues
            applyToPage { page in
                guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
                page.elements[i] = Captions.on(page.elements[i], next)
            }
            selection = [existing.id]
        } else {
            add(Captions.element(width: pageWidth, height: pageHeight,
                                 captions: Captions(source: source, cues: cues, highlight: brandHighlight)),
                centered: false)
        }
        buzz(.confirm)
    }

    /// The caption box for `source` drawn in `style` (Captions.styles) as
    /// one undo step, its cues kept; the brand's accent becomes its
    /// highlight where it has none (Captions.brandAccent). "gradient" is
    /// worked out from the page's palette as it is drawn, so nothing else
    /// is written. Nothing changes on a locked page.
    func setCaptionStyle(_ source: String, _ style: String) {
        guard let existing = captionsFor(source), var next = existing.captions, next.style != style else { return }
        guard !refusesLockedPage() else { return }
        next.style = style
        next.highlight = next.highlight ?? brandHighlight
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
            page.elements[i] = Captions.on(page.elements[i], next)
        }
    }

    /// The caption box for `source` put at `place` (Captions.places) on
    /// this page — "safe" clear of the safe zone the page shows
    /// (SafeZones.shown) — and the place kept, as one undo step. A box
    /// locked in place stays put, and nothing moves on a locked page.
    func setCaptionPlace(_ source: String, _ place: String) {
        guard let existing = captionsFor(source), ElementLock.mode(of: existing) == .unlocked else { return }
        guard !refusesLockedPage() else { return }
        let size = design.size(for: page)
        let safe = SafeZones.shown(design, page: page).map { SafeZones.safeRect($0, size: size) }
        let placed = Captions.placed(existing, place, size: size, safe: safe)
        guard placed != existing else { return }
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
            page.elements[i] = placed
        }
    }

    /// The highlight colour captions take from the brand kit
    /// (Captions.brandAccent); nil with no brand colours.
    var brandHighlight: String? {
        Captions.brandAccent(BrandKit.load().palettes.map(\.colors))
    }

    /// Where this page starts in the film, in seconds — nought while it is
    /// hidden from it — for timing a track's words to the page.
    var pageStartSeconds: Double { timelinePageStart ?? 0 }
}
