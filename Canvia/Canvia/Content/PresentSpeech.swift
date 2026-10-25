// What VoiceOver finds on the slide up in Present — TalkBack on the Android
// twin — so a blind presenter or viewer can follow the deck: the page's
// header, then what is on it, one stop each, in the order a sighted reader
// takes it in. The rule both phones share (Tests/Fixtures/present_speech.json,
// the Android twin's PresentSpeech). Nothing here changes a design.

import Foundation

enum PresentSpeech {

    static let heading = "heading"
    static let text = "text"
    static let image = "image"
    static let chart = "chart"
    static let table = "table"
    static let link = "link"

    /// One stop: the element it is read from (a chart's id for a chart —
    /// all of its parts are one stop), its kind, what is said, and for a
    /// link, where it goes.
    struct Stop: Equatable, Identifiable {
        var id: String
        var kind: String
        var label: String
        var url: String?
    }

    /// The header a page change says, and the stop the page's turn actions
    /// are on: "Page 2 of 5, Results", counted among the pages shown, the
    /// title left out when the page has none.
    static func header(_ design: Design, index: Int) -> String {
        let visible = design.visiblePageIndices
        let number = (visible.firstIndex(of: index) ?? index) + 1
        let count = visible.firstIndex(of: index) == nil ? design.pages.count : visible.count
        let title = design.pages.indices.contains(index) ? design.pages[index].title.flatMap(PageTitles.kept) : nil
        guard let title else { return tr("Page %d of %d", number, count) }
        return tr("Page %d of %d, %@", number, count, title)
    }

    /// What a page change announces: the header, then the page's first
    /// heading when it has one.
    static func announcement(_ design: Design, index: Int) -> String {
        let said = header(design, index: index)
        guard design.pages.indices.contains(index),
              let first = items(design.pages[index], in: design).first(where: { $0.kind == heading }) else { return said }
        return tr("%@, %@", said, first.label)
    }

    /// `page`'s stops, in reading order (CanvasAccessibility.readingOrder).
    /// Only the page's own shown elements: hidden ones are not on the slide,
    /// and the master's, behind every page alike, are left out so each slide
    /// is read for what it adds.
    ///
    /// - A text box, or a shape's words: its words, list markers read and
    ///   page numbers filled in, the rich text's markers removed — a
    ///   "heading" when it reads as one (PdfTags.textRole H1 to H3), else
    ///   "text"; one read as an artifact, or with no words, is left out.
    /// - A chart: one "chart" stop for all its parts, ChartSpeech's summary.
    /// - A table: a "table" stop a cell, row by row, each
    ///   DataGraphics.spokenCell, read from the cell's words (its shape
    ///   behind is not a stop).
    /// - A photo, video, sticker or icon: an "image", AltText.spoken; one
    ///   marked decorative with no alt text is left out.
    /// - Anything with a link to follow is a "link" whatever it is, said as
    ///   it would be otherwise (a picture with no words of its own by its
    ///   name), with the link it opens — as a tap on it opens it, so only a
    ///   link a tap follows (Links.isFollowable).
    /// - Shapes with no words and lines say nothing.
    static func items(_ page: Page, in design: Design) -> [Stop] {
        let elements = page.elements.filter { $0.hidden != true }
        let byId = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let number = (design.pages.firstIndex { $0.id == page.id } ?? 0) + 1
        var charts: Set<String> = []
        var tables: Set<String> = []
        var out: [Stop] = []
        for id in CanvasAccessibility.readingOrder(elements, pageHeight: Double(design.size(for: page).height)) {
            guard let el = byId[id] else { continue }
            if let cell = el.table {
                if tables.insert(cell.id).inserted { out += tableItems(elements, id: cell.id) }
                continue
            }
            if let spec = el.chart, el.chartPart != nil {
                if charts.insert(spec.id).inserted, let summary = ChartSpeech.summary(of: el) {
                    out.append(Stop(id: spec.id, kind: chart, label: summary))
                }
                continue
            }
            guard var item = said(el, in: design, page: number) else { continue }
            if let url = el.link, Links.isFollowable(url, in: design) {
                item.kind = link
                item.url = url
            }
            out.append(item)
        }
        return out
    }

    /// What `el` says on its own, on page `number`, or nil for nothing.
    private static func said(_ el: Element, in design: Design, page number: Int) -> Stop? {
        if AccessibilityAudit.hasWords(el) {
            guard let role = PdfTags.textRole(el, in: design) else { return nil }
            let words = el.type == .text
                ? FontLibrary.markedDisplayText(for: el, pageNumber: number, pageCount: design.pages.count)
                : (el.text ?? "").replacingOccurrences(of: "{page}", with: String(number))
                    .replacingOccurrences(of: "{pages}", with: String(design.pages.count))
            let label = RichText.strip(words).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return nil }
            let isHeading = role == PdfTags.h1 || role == PdfTags.h2 || role == PdfTags.h3
            return Stop(id: el.id, kind: isHeading ? heading : text, label: label)
        }
        if AccessibilityAudit.isPicture(el) || el.type == .image {
            if el.decorative == true && !AccessibilityAudit.hasAltText(el) { return nil }
            return Stop(id: el.id, kind: image, label: AltText.spoken(el))
        }
        // A linked shape or line still opens its link.
        if let url = el.link, Links.isFollowable(url, in: design) {
            return Stop(id: el.id, kind: link, label: AltText.spoken(el))
        }
        return nil
    }

    /// A table's cells, row by row, each said with its place and header.
    private static func tableItems(_ elements: [Element], id: String) -> [Stop] {
        let cells = DataGraphics.tableMembers(elements, id: id)
            .filter { $0.type == .text }
            .compactMap { el in el.table.map { (el: el, cell: $0) } }
            .sorted { a, b in a.cell.row != b.cell.row ? a.cell.row < b.cell.row : a.cell.col < b.cell.col }
        return cells.compactMap { pair in
            DataGraphics.spokenCell(elements, id: id, row: pair.cell.row, col: pair.cell.col)
                .map { Stop(id: pair.el.id, kind: table, label: $0) }
        }
    }
}
