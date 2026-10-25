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
            add(Captions.element(width: pageWidth, height: pageHeight, captions: Captions(source: source, cues: cues)),
                centered: false)
        }
        buzz(.confirm)
    }

    /// The caption box for `source` drawn in `style` (Captions.styles) as
    /// one undo step, its cues kept: "gradient" fills its letters with the
    /// page's colours (Captions.gradientFill), and another style takes
    /// that fill away again.
    func setCaptionStyle(_ source: String, _ style: String) {
        guard let existing = captionsFor(source), var next = existing.captions, next.style != style else { return }
        let was = next.style
        next.style = style
        let fill: Paint? = style == Captions.gradient
            ? Captions.gradientFill(DataGraphics.palette(for: design, page: page)) : nil
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
            var box = Captions.on(page.elements[i], next)
            if style == Captions.gradient || was == Captions.gradient { box.textFill = fill }
            page.elements[i] = box
        }
    }

    /// The caption box for `source` put at `place` (Captions.places) on
    /// this page — "safe" inside the page's safe zone for its size — and
    /// the place kept, as one undo step.
    func setCaptionPlace(_ source: String, _ place: String) {
        guard let existing = captionsFor(source), var next = existing.captions else { return }
        next.place = place
        let size = design.size(for: page)
        let zone = SafeZones.matching(size).first
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
            page.elements[i] = Captions.placed(Captions.on(page.elements[i], next), place, size: size, zone: zone)
        }
    }

    /// The colour the caption box for `source` lights its said words in,
    /// as one undo step; the default colour is no key.
    func setCaptionHighlight(_ source: String, _ hex: String) {
        guard let existing = captionsFor(source), var next = existing.captions else { return }
        let ink = hex.lowercased() == Captions.highlightColour ? nil : hex.lowercased()
        guard next.highlight != ink else { return }
        next.highlight = ink
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
            page.elements[i] = Captions.on(page.elements[i], next)
        }
    }

    /// Where this page starts in the film, in seconds — nought while it is
    /// hidden from it — for timing a track's words to the page.
    var pageStartSeconds: Double { timelinePageStart ?? 0 }
}
