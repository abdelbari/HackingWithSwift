// Check accessibility: one pass over the design for what keeps people out
// of it, each finding naming its page and element so the sheet can go to it.
//
//  - contrast: text that falls short of WCAG AA on what is behind it —
//    ContrastAudit's measure, unchanged.
//  - altText: a photo, video, sticker or icon with nothing for a screen
//    reader to say, unless it is marked decorative ("decorative": true).
//  - smallText: text under 12 px at export size — the size it is stored
//    at, which is what a PNG comes out at.
//  - flashing: a looping animation that cycles faster than every 0.33 s, or
//    a page held under a third of a second, so pages change more than three
//    times a second.
//  - linkText: a link on something with no words to read and no alt text.
//  - readingOrder: a page whose texts are layered in a different order from
//    the one they read in, top to bottom and left to right.
//
// Findings come page by page; within a page in that order of kinds, and
// within a kind in layer order, back to front. Hidden elements are passed
// over: nobody meets them. The Android twin's AccessibilityAudit, with the
// same rows in its tests.

import Foundation

enum AccessibilityAudit {

    enum Kind: String, CaseIterable {
        case contrast, altText, smallText, flashing, linkText, readingOrder
    }

    /// What a finding's button does.
    enum Fix: String {
        case fixColour = "Fix colour"
        case addAltText = "Add alt text"
        case makeIt12 = "Make it 12"
    }

    /// One thing found: {kind, pageIndex, elementId, message, fix}.
    typealias Finding = AccessibilityFinding

    /// The smallest text that passes, in pixels at export size.
    static let minTextSize = 12.0
    /// A loop or a page change faster than this, in seconds, flashes.
    static let minFlashPeriod = 0.33

    static func findings(_ design: Design) -> [Finding] {
        let contrast = Dictionary(grouping: ContrastAudit.audit(design), by: \.pageIndex)
        var out: [Finding] = []
        let shownPages = design.visiblePageIndices.count
        for (p, page) in design.pages.enumerated() {
            let shown = page.elements.filter { !$0.isHidden }
            for f in contrast[p] ?? [] {
                out.append(Finding(kind: .contrast, pageIndex: p, elementId: f.elementId,
                                   message: String(format: "Hard to read: %.1f:1, needs %.1f:1", f.ratio, f.required),
                                   fix: .fixColour, contrast: f))
            }
            for el in shown where needsAltText(el) {
                out.append(Finding(kind: .altText, pageIndex: p, elementId: el.id,
                                   message: "\(describedKind(el)) with no alt text", fix: .addAltText))
            }
            for el in shown where isSmallText(el) {
                out.append(Finding(kind: .smallText, pageIndex: p, elementId: el.id,
                                   message: "Text at \(Units.format(el.fontSize ?? 0, unit: "px")) px — under 12 px is hard to read",
                                   fix: .makeIt12))
            }
            for el in shown where flashes(el) {
                out.append(Finding(kind: .flashing, pageIndex: p, elementId: el.id,
                                   message: "Moves faster than three times a second"))
            }
            if shownPages > 1, page.hidden != true, hold(of: page, in: design) < minFlashPeriod {
                out.append(Finding(kind: .flashing, pageIndex: p, elementId: nil,
                                   message: "Page changes faster than three times a second"))
            }
            for el in shown where isSilentLink(el) {
                out.append(Finding(kind: .linkText, pageIndex: p, elementId: el.id,
                                   message: "Link with nothing to read", fix: .addAltText))
            }
            if let first = readingOrderMismatch(page, height: Double(design.size(for: page).height)) {
                out.append(Finding(kind: .readingOrder, pageIndex: p, elementId: first,
                                   message: "Layers run in a different order from how the page reads"))
            }
        }
        return out
    }

    // MARK: the rules

    /// A photo, video, sticker or icon that is not decorative and has no
    /// alt text. An empty photo frame has nothing to describe yet.
    static func needsAltText(_ el: Element) -> Bool {
        guard el.decorative != true, isPicture(el) else { return false }
        return (el.altText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isPicture(_ el: Element) -> Bool {
        switch el.type {
        case .image: return el.src != nil
        case .sticker: return true
        case .shape: return el.iconId != nil
        case .text, .line: return false
        }
    }

    /// "Photo", "Video", "Sticker" or "Icon".
    static func describedKind(_ el: Element) -> String {
        switch el.type {
        case .image: return VideoStore.isVideo(el.src) ? "Video" : "Photo"
        case .sticker: return "Sticker"
        default: return "Icon"
        }
    }

    /// Text with words whose size is under 12 px.
    static func isSmallText(_ el: Element) -> Bool {
        guard el.type == .text, hasWords(el) else { return false }
        return (el.fontSize ?? 42) < minTextSize
    }

    /// A loop that cycles faster than every 0.33 s.
    static func flashes(_ el: Element) -> Bool {
        guard let period = el.animation?.period else { return false }
        return period < minFlashPeriod
    }

    /// How long a page holds in Present and the video.
    static func hold(of page: Page, in design: Design) -> Double {
        page.holdSeconds ?? (design.motion ?? MotionSettings()).secondsPerPage
    }

    /// A link on something with no words of its own and no alt text.
    static func isSilentLink(_ el: Element) -> Bool {
        guard let link = el.link, !link.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        let alt = (el.altText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return alt.isEmpty && !hasWords(el)
    }

    /// Words a reader can see: a text's, or a shape's own.
    static func hasWords(_ el: Element) -> Bool {
        guard ShapeText.carriesWords(el) else { return false }
        return !RichText.strip(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The first text, in layer order, that is not where reading order puts
    /// it — nil when the page's texts are layered as they read, or there
    /// are fewer than two.
    static func readingOrderMismatch(_ page: Page, height: Double) -> String? {
        let texts = page.elements.filter { !$0.isHidden && $0.type == .text && hasWords($0) }
        guard texts.count > 1 else { return nil }
        let layered = texts.map(\.id)
        let read = CanvasAccessibility.readingOrder(texts, pageHeight: height)
        for (a, b) in zip(layered, read) where a != b { return a }
        return nil
    }

    // MARK: the sheet's words

    /// "5 things on 3 pages", "1 thing on 1 page"; nothing is "Nothing to
    /// fix".
    static func summary(_ findings: [Finding]) -> String {
        guard !findings.isEmpty else { return "Nothing to fix" }
        let pages = Set(findings.map(\.pageIndex)).count
        let things = findings.count == 1 ? "1 thing" : "\(findings.count) things"
        return "\(things) on \(pages == 1 ? "1 page" : "\(pages) pages")"
    }

    /// One page's findings, for a section of the sheet.
    struct PageGroup: Identifiable, Equatable {
        var pageIndex: Int
        var findings: [Finding]
        var id: Int { pageIndex }
    }

    /// The findings by page, pages in order.
    static func byPage(_ findings: [Finding]) -> [PageGroup] {
        let grouped = Dictionary(grouping: findings, by: \.pageIndex)
        return grouped.keys.sorted().map { PageGroup(pageIndex: $0, findings: grouped[$0] ?? []) }
    }

    // MARK: fixes

    /// The design with a finding's own fix made: the contrast colour, or the
    /// text at 12 px (and its box measured again). Anything else is
    /// unchanged — alt text has to be written.
    static func fixed(_ design: Design, _ f: Finding) -> Design {
        guard design.pages.indices.contains(f.pageIndex), let id = f.elementId,
              let i = design.pages[f.pageIndex].elements.firstIndex(where: { $0.id == id }) else { return design }
        var out = design
        var el = out.pages[f.pageIndex].elements[i]
        switch f.fix {
        case .some(.fixColour):
            guard let c = f.contrast else { return design }
            el = ContrastAudit.fixed(el, for: c)
        case .some(.makeIt12):
            el.fontSize = minTextSize
            el.h = FontLibrary.layoutHeight(for: el)
        case .some(.addAltText), .none:
            return design
        }
        out.pages[f.pageIndex].elements[i] = el
        return out
    }

    /// Every contrast finding fixed at once: Fix all contrast, one step.
    static func fixedAllContrast(_ design: Design, _ findings: [Finding]) -> Design {
        findings.filter { $0.kind == .contrast }.reduce(design) { fixed($0, $1) }
    }

    /// The element marked decorative, so it is not asked about again and a
    /// screen reader passes it by.
    static func markedDecorative(_ design: Design, pageIndex: Int, elementId: String) -> Design {
        guard design.pages.indices.contains(pageIndex),
              let i = design.pages[pageIndex].elements.firstIndex(where: { $0.id == elementId }) else { return design }
        var out = design
        out.pages[pageIndex].elements[i].decorative = true
        return out
    }
}

/// A finding of Check accessibility (AccessibilityAudit.Finding).
struct AccessibilityFinding: Identifiable, Equatable {
    var kind: AccessibilityAudit.Kind
    var pageIndex: Int
    /// The element it is about; nil for the page as a whole.
    var elementId: String?
    var message: String
    var fix: AccessibilityAudit.Fix?
    /// For a contrast finding, what Fix colour applies.
    var contrast: ContrastAudit.Finding?

    var id: String { "\(kind.rawValue)|\(pageIndex)|\(elementId ?? "page")" }
}
