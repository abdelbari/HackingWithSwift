// Check accessibility: one pass over the design for what keeps people out
// of it, each finding naming its page and element so the sheet can go to it.
//
//  - contrast: text that falls short of WCAG AA on what is behind it —
//    ContrastAudit's measure, unchanged.
//  - altText: a photo, video, sticker or icon with nothing for a screen
//    reader to say, unless it is marked decorative ("decorative": true). An
//    empty photo frame has nothing to describe yet.
//  - smallText: words — a text's or a shape's — under 12 px at export size,
//    the size they are stored at; or, in a design measured on paper, under
//    9 pt there (37.5 px at 300 dpi).
//  - flashing: a looping animation that cycles faster than every 0.33 s, or
//    a page that gives way to the next in less — its hold in the video's
//    timeline — so pages change more than three times a second. The last
//    page gives way to nothing.
//  - linkText: a link on something with no words to read and no alt text.
//  - chartColours: a chart with neither a legend nor value labels, whose
//    colours alone say which is which — but a progress kind or a funnel,
//    which always write their values. Said once, on the chart's lowest
//    element.
//  - readingOrder: a page whose layers, bottom to top, run in another order
//    than the page reads — rows top to bottom, left to right — among what a
//    reader says: words, and pictures with alt text.
//  - headings: a heading a level below the one before it skips one
//    ("Heading levels skip": an h3 after an h1, or a design's first heading
//    an h2), and a design of two or more shown pages with no heading at all
//    ("No heading on a multi-page PDF") — headings as TextRoles and Read as
//    say, read in reading order across the shown pages. Fixes: Fix heading
//    level (the level after the one before) and Make it a heading (the
//    first page's biggest text an h1).
//  - colourVision: text that passes contrast but not as it is seen with a
//    colour vision deficiency, and chart series that look alike so
//    (ColourVision) — each saying which ways of seeing it fails in.
//  - missingLetters: words — a text's or a shape's — with letters their font
//    does not have (FontLibrary.covers), which the phone draws in a
//    stand-in font: Cyrillic in a Latin-only face.
//
// Findings come page by page; within a page in that order of kinds, and
// within a kind in layer order, back to front. Hidden elements and hidden
// pages are passed over: nobody meets them. The Android twin's
// AccessibilityAudit, rule for rule and word for word, with the same rows in
// its tests.

import Foundation

enum AccessibilityAudit {

    enum Kind: String, CaseIterable {
        case contrast, altText, smallText, flashing, linkText, chartColours, readingOrder, headings, colourVision, missingLetters
    }

    /// What a finding's button does.
    enum Fix: String {
        case fixColour = "Fix colour"
        case addAltText = "Add alt text"
        case makeIt12 = "Make it 12"
        case fixHeadingLevel = "Fix heading level"
        case makeHeading = "Make it a heading"
    }

    /// One thing found: {kind, pageIndex, elementId, message, fix}.
    typealias Finding = AccessibilityFinding

    /// Said of letters full of a photo, whose contrast cannot be measured.
    static let photoFilledNote = tr("Contrast can't be measured for photo-filled text")

    /// The smallest text that passes: in pixels at export size, and in
    /// points on paper for a design measured in mm, cm or inches.
    static let minTextSize = 12.0
    static let minTextPoints = 9.0
    /// A loop or a page change faster than this, in seconds, flashes.
    static let minFlashPeriod = 0.33

    static func findings(_ design: Design) -> [Finding] {
        let contrast = Dictionary(grouping: ContrastAudit.audit(design), by: \.pageIndex)
        let holds = filmHolds(design)
        let seen = Dictionary(grouping: ColourVision.textFindings(design), by: \.contrast.pageIndex)
        let charts = Dictionary(grouping: ColourVision.chartFindings(design), by: \.pageIndex)
        let headings = Dictionary(grouping: headingFindings(design), by: \.pageIndex)
        var out: [Finding] = []
        for (p, page) in design.pages.enumerated() where page.hidden != true {
            let shown = page.elements.filter { !$0.isHidden }
            for f in contrast[p] ?? [] {
                out.append(Finding(kind: .contrast, pageIndex: p, elementId: f.elementId,
                                   message: tr("Hard to read: %@:1, needs %@:1", String(format: "%.1f", f.ratio),
                                               String(format: "%.1f", f.required)),
                                   fix: .fixColour, contrast: f))
            }
            // Letters full of a photo have no one ink to measure: said, with
            // nothing to fix, as on the Android twin.
            for el in shown where el.type == .text && el.textFill?.isPhoto == true && el.opacity > 0.05 {
                out.append(Finding(kind: .contrast, pageIndex: p, elementId: el.id, message: photoFilledNote))
            }
            for el in shown where needsAltText(el) {
                out.append(Finding(kind: .altText, pageIndex: p, elementId: el.id,
                                   message: missingAltText(el), fix: .addAltText))
            }
            for el in shown where isSmallText(el, in: design) {
                out.append(Finding(kind: .smallText, pageIndex: p, elementId: el.id,
                                   message: smallMessage(el, in: design), fix: .makeIt12))
            }
            if let hold = holds[p], hold < minFlashPeriod {
                out.append(Finding(kind: .flashing, pageIndex: p, elementId: nil,
                                   message: tr("Gives way to the next page faster than three times a second")))
            }
            for el in shown where flashes(el) {
                out.append(Finding(kind: .flashing, pageIndex: p, elementId: el.id,
                                   message: tr("Moves faster than three times a second")))
            }
            for el in shown where isSilentLink(el) {
                out.append(Finding(kind: .linkText, pageIndex: p, elementId: el.id,
                                   message: tr("A link with no words and no alt text"), fix: .addAltText))
            }
            for id in colourOnlyCharts(shown) {
                out.append(Finding(kind: .chartColours, pageIndex: p, elementId: id,
                                   message: tr("Chart colours carry meaning")))
            }
            if let first = readingOrderMismatch(page, height: Double(design.size(for: page).height)) {
                out.append(Finding(kind: .readingOrder, pageIndex: p, elementId: first,
                                   message: tr("The layers are in a different order from how the page reads")))
            }
            out += headings[p] ?? []
            for f in seen[p] ?? [] {
                out.append(Finding(kind: .colourVision, pageIndex: p, elementId: f.contrast.elementId,
                                   message: tr("Hard to read in %@ view: %@:1", ColourVision.names(f.kinds),
                                               String(format: "%.1f", f.contrast.ratio)),
                                   fix: .fixColour, contrast: f.contrast))
            }
            for f in charts[p] ?? [] {
                out.append(Finding(kind: .colourVision, pageIndex: p, elementId: f.elementId,
                                   message: tr("Chart colours look alike in %@ view", ColourVision.names(f.kinds)),
                                   part: "\(f.first)-\(f.second)"))
            }
            for el in shown where lacksLetters(el) {
                out.append(Finding(kind: .missingLetters, pageIndex: p, elementId: el.id,
                                   message: missingLettersNote))
            }
        }
        return out
    }

    /// What a box whose font lacks some of its letters is said to have.
    static let missingLettersNote = tr("Letters missing from the font")

    /// Whether `el`'s words have letters their font does not
    /// (FontLibrary.covers): the words set in a font of their own (spans)
    /// checked in it, the rest in the box's font — the Android twin's rule.
    static func lacksLetters(_ el: Element) -> Bool {
        guard ShapeText.carriesWords(el), let text = el.text, !text.isEmpty else { return false }
        let plain = RichText.strip(text) as NSString
        let spans = el.type == .text ? el.liveSpans : []
        let own = spans.filter { $0.font != nil && 0 <= $0.start && $0.start <= $0.end && $0.end <= plain.length }
        for span in own {
            let words = plain.substring(with: NSRange(location: span.start, length: span.end - span.start))
            if !FontLibrary.covers(span.font, words) { return true }
        }
        let rest = NSMutableString(string: plain as String)
        for span in own where span.end > span.start {
            rest.replaceCharacters(in: NSRange(location: span.start, length: span.end - span.start),
                                   with: String(repeating: " ", count: span.end - span.start))
        }
        return !FontLibrary.covers(el.fontFamily, rest as String)
    }

    // MARK: the rules

    /// The lowest element of each chart among `elements` that has neither
    /// a legend nor values, nor is a kind that writes its values anyway.
    static func colourOnlyCharts(_ elements: [Element]) -> [String] {
        var seen: Set<String> = []
        return elements.compactMap { el in
            // A kind this build does not know is skipped, as Android skips it.
            guard let spec = el.chart, el.chartPart != nil, let kind = DataGraphics.ChartKind(rawValue: spec.kind),
                  seen.insert(spec.id).inserted else { return nil }
            let says = spec.legend || spec.values || kind.isProgress || kind == .funnel
            return says ? nil : el.id
        }
    }

    /// A photo, video, sticker or icon that is not decorative and has no
    /// alt text.
    static func needsAltText(_ el: Element) -> Bool {
        guard el.decorative != true, isPicture(el) else { return false }
        return !hasAltText(el)
    }

    /// Alt text with something in it: spaces alone are none.
    static func hasAltText(_ el: Element) -> Bool {
        !(el.altText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A photo or video — not an empty frame, which has nothing to describe
    /// yet — a sticker or an icon.
    static func isPicture(_ el: Element) -> Bool {
        switch el.type {
        case .image: return !(el.src ?? "").trimmingCharacters(in: .whitespaces).isEmpty
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

    /// "Photo has no alt text", and so on for describedKind's others.
    static func missingAltText(_ el: Element) -> String {
        switch describedKind(el) {
        case "Video": return tr("Video has no alt text")
        case "Photo": return tr("Photo has no alt text")
        case "Sticker": return tr("Sticker has no alt text")
        default: return tr("Icon has no alt text")
        }
    }

    /// The smallest type a design should have, in its own pixels: 12, or
    /// 9 pt on paper at its dpi (37.5 px at 300 dpi).
    static func smallest(_ design: Design) -> Double {
        design.physicalUnit != nil ? minTextPoints * design.effectiveDPI / 72 : minTextSize
    }

    /// What Make it 12 sets the type to: 12 px, or 12 pt on paper (50 px at
    /// 300 dpi).
    static func legibleSize(_ design: Design) -> Double {
        design.physicalUnit != nil ? 12 * design.effectiveDPI / 72 : minTextSize
    }

    /// Words — a text's or a shape's — smaller than `smallest`.
    static func isSmallText(_ el: Element, in design: Design) -> Bool {
        hasWords(el) && (el.fontSize ?? 42) < smallest(design) - 1e-9
    }

    /// "Text is 8 px, under 12 px", or on paper "Text is 7 pt, under 9 pt".
    static func smallMessage(_ el: Element, in design: Design) -> String {
        let size = el.fontSize ?? 42
        guard design.physicalUnit != nil else { return tr("Text is %d px, under 12 px", Int(size.rounded())) }
        return tr("Text is %d pt, under 9 pt", Int((size * 72 / design.effectiveDPI).rounded()))
    }

    /// A loop that cycles faster than every 0.33 s.
    static func flashes(_ el: Element) -> Bool {
        guard let period = el.animation?.period else { return false }
        return period < minFlashPeriod
    }

    /// Each shown page's hold in the video's timeline, frames over the frame
    /// rate, by its index in the design — all but the last, which gives way
    /// to nothing.
    static func filmHolds(_ design: Design) -> [Int: Double] {
        let settings = MovieExporter.Settings(design.motion)
        let pages = design.visiblePageIndices
        let timeline = MovieExporter.timeline(design: design, pages: pages, settings: settings)
        var holds: [Int: Double] = [:]
        for (index, timing) in zip(pages, timeline).dropLast() {
            holds[index] = Double(timing.frames) / Double(max(settings.fps, 1))
        }
        return holds
    }

    /// A link on something with no words of its own and no alt text.
    static func isSilentLink(_ el: Element) -> Bool {
        guard let link = el.link, !link.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !hasAltText(el) && !hasWords(el)
    }

    /// Words a reader can see: a text's, or a shape's own.
    static func hasWords(_ el: Element) -> Bool {
        guard ShapeText.carriesWords(el) else { return false }
        return !RichText.strip(el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Whether a reader says something for the element: its words, or a
    /// picture's alt text.
    static func isRead(_ el: Element) -> Bool {
        hasWords(el) || (isPicture(el) && el.decorative != true && hasAltText(el))
    }

    /// Where the page's layers and its reading order part: the first
    /// element, in reading order, whose place differs between the two,
    /// among those a reader says; nil when they agree.
    static func readingOrderMismatch(_ page: Page, height: Double) -> String? {
        let read = page.elements.filter { !$0.isHidden && isRead($0) }
        let layered = read.map(\.id)
        let reading = CanvasAccessibility.readingOrder(read, pageHeight: height)
        for (a, b) in zip(reading, layered) where a != b { return a }
        return nil
    }

    // MARK: headings

    /// `el`'s heading level for a reader, 1 to 3, or nil when it is not a
    /// heading: its Read as, else its role (TextRoles).
    static func headingLevel(_ el: Element, in design: Design) -> Int? {
        if let read = TextRoles.readAs(el) {
            switch read {
            case TextRoles.h1: return 1
            case TextRoles.h2: return 2
            case TextRoles.h3: return 3
            default: return nil
            }
        }
        return TextRoles.level(TextRoles.of(el, in: design))
    }

    /// The shown pages' words, page by page in reading order, each with its
    /// page's index.
    private static func readText(_ design: Design) -> [(page: Int, el: Element)] {
        design.pages.enumerated().flatMap { p, page -> [(page: Int, el: Element)] in
            guard page.hidden != true else { return [] }
            let shown = page.elements.filter { !$0.isHidden && hasWords($0) }
            let byId = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let order = CanvasAccessibility.readingOrder(shown, pageHeight: Double(design.size(for: page).height))
            return order.compactMap { id in byId[id].map { (page: p, el: $0) } }
        }
    }

    /// The headings findings: each heading more than one level below the
    /// heading before it in reading order (the first heading after an
    /// imagined level 0), and, for a design of two or more shown pages with
    /// no heading, one for the whole design on its first shown page, about
    /// that page's biggest text when it has any — the Android twin's rule.
    static func headingFindings(_ design: Design) -> [Finding] {
        let read = readText(design)
        var out: [Finding] = []
        var previous = 0
        for (p, el) in read {
            guard let level = headingLevel(el, in: design) else { continue }
            if level > previous + 1 {
                out.append(Finding(kind: .headings, pageIndex: p, elementId: el.id,
                                   message: tr("Heading levels skip"), fix: .fixHeadingLevel))
            }
            previous = level
        }
        let shownPages = design.visiblePageIndices
        if shownPages.count >= 2, let first = shownPages.first,
           !read.contains(where: { headingLevel($0.el, in: design) != nil }) {
            // The biggest first, the first of those in reading order.
            var biggest: Element?
            for item in read where item.page == first {
                if (item.el.fontSize ?? 42) > (biggest?.fontSize ?? 42) || biggest == nil { biggest = item.el }
            }
            out.append(Finding(kind: .headings, pageIndex: first, elementId: biggest?.id,
                               message: tr("No heading on a multi-page PDF"), fix: biggest == nil ? nil : .makeHeading))
        }
        return out
    }

    /// The role a headings fix gives element `id`: Make it a heading an h1,
    /// Fix heading level the level after the heading before it.
    static func headingFix(_ design: Design, id: String) -> String {
        var previous = 0
        for item in readText(design) {
            if item.el.id == id { return TextRoles.heading(previous + 1) }
            previous = headingLevel(item.el, in: design) ?? previous
        }
        return TextRoles.h1
    }

    /// A headings fix: the role written and any Read as taken away, so the
    /// role is what is read.
    static func withHeading(_ el: Element, role: String) -> Element {
        TextRoles.withReadAs(TextRoles.with(el, role), nil)
    }

    // MARK: the sheet's words

    /// "5 things on 3 pages", "1 thing on 1 page"; nothing is "Nothing to
    /// fix".
    static func summary(_ findings: [Finding]) -> String {
        guard !findings.isEmpty else { return tr("Nothing to fix") }
        let pages = Set(findings.map(\.pageIndex)).count
        return trn("%d thing on %@|%d things on %@", findings.count, trn("%d page|%d pages", pages))
    }

    /// The Export sheet's row: "3 accessibility suggestions" — the
    /// findings counted as the sheet counts them (`summary`), in the
    /// Android twin's words.
    static func suggestions(_ findings: [Finding]) -> String {
        trn("%d accessibility suggestion|%d accessibility suggestions", findings.count)
    }

    /// The findings on `pages` alone, in their order.
    static func onPages(_ findings: [Finding], _ pages: Set<Int>) -> [Finding] {
        findings.filter { pages.contains($0.pageIndex) }
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
    /// type at `legibleSize` — a text's box measured again for it, a
    /// shape's left as it is. Anything else is unchanged — alt text has to
    /// be written.
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
            el.fontSize = legibleSize(design)
            if el.type == .text { el.h = FontLibrary.layoutHeight(for: el) }
        case .some(.fixHeadingLevel), .some(.makeHeading):
            // A locked page keeps its words as they are.
            guard !PageLocks.isLocked(design.pages[f.pageIndex]) else { return design }
            el = withHeading(el, role: headingFix(design, id: id))
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
    var contrast: ContrastAudit.Finding? = nil
    /// Which of several findings of a kind on one element: a chart's two
    /// series, "1-2", for colourVision; nil for the one.
    var part: String? = nil

    var id: String { "\(kind.rawValue)|\(pageIndex)|\(elementId ?? "page")" + (part.map { "|" + $0 } ?? "") }
}
