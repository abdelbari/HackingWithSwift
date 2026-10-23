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
            let was = existing.captions ?? Captions(source: source)
            applyToPage { page in
                guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
                page.elements[i] = Captions.on(page.elements[i], Captions(source: was.source, cues: cues, style: was.style))
            }
            selection = [existing.id]
        } else {
            add(Captions.element(width: pageWidth, height: pageHeight, captions: Captions(source: source, cues: cues)),
                centered: false)
        }
        buzz(.confirm)
    }

    /// The caption box for `source` drawn in `style` — plain, box or
    /// highlightWord — as one undo step.
    func setCaptionStyle(_ source: String, _ style: String) {
        guard let existing = captionsFor(source), let was = existing.captions, was.style != style else { return }
        applyToPage { page in
            guard let i = page.elements.firstIndex(where: { $0.id == existing.id }) else { return }
            page.elements[i] = Captions.on(page.elements[i], Captions(source: was.source, cues: was.cues, style: style))
        }
    }

    /// Where this page starts in the film, in seconds — nought while it is
    /// hidden from it — for timing a track's words to the page.
    var pageStartSeconds: Double { timelinePageStart ?? 0 }
}
