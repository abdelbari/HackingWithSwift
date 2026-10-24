// The Doc design type: a continuous document of blocks — headings,
// paragraphs, lists, quotes, dividers, images, tables, charts and page
// breaks — edited as a list that reflows to the phone, and laid out on
// pages only for a PDF, a print, a thumbnail or Convert to design
// (`paginated`). The Android twin's Docs, rule for rule.
//
// Kept in the design as both phones write it: "kind": "doc", "blocks":
// [{"id", "type", "text", "src", "alt", "table", "chart", "checked"}] — a
// block writes only the keys it has, `text` in RichText markup as a text box
// keeps it, `table` as {"rows": [[…]], "header": true}, `chart` the ChartSpec
// JSON a chart's elements keep under "chart" — and "docPage": {"size": "a4"
// | "letter", "margins": 72}, the margins in points. The design's own size is
// its page's, in pixels at 96 dpi.

import CoreGraphics
import Foundation

/// A table block's words, the first row the header unless said otherwise.
struct DocTable: Codable, Equatable {
    var rows: [[String]] = []
    var header = true

    init(rows: [[String]] = [], header: Bool = true) {
        self.rows = rows
        self.header = header
    }

    private enum CodingKeys: String, CodingKey { case rows, header }

    /// Lenient, as the twin reads it: a cell that is not a string is empty,
    /// a header that is not true or false is on.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let read = (try? c.decode([[Lossy<String>]].self, forKey: .rows)) ?? []
        rows = read.map { row in row.map { $0.value ?? "" } }
        header = (try? c.decode(Bool.self, forKey: .header)) ?? true
    }
}

/// One block of a Doc (Docs).
struct DocBlock: Codable, Equatable, Identifiable {
    var id: String
    var type: String
    var text = ""
    var src: String?
    var alt: String?
    var table: DocTable?
    var chart: ChartSpec?
    var checked: Bool?

    init(id: String = Docs.newId(), type: String, text: String = "", src: String? = nil, alt: String? = nil,
         table: DocTable? = nil, chart: ChartSpec? = nil, checked: Bool? = nil) {
        self.id = id
        self.type = type
        self.text = text
        self.src = src
        self.alt = alt
        self.table = table
        self.chart = chart
        self.checked = checked
    }

    private enum CodingKeys: String, CodingKey { case id, type, text, src, alt, table, chart, checked }

    /// A type this build does not know is no block; one with no id is given
    /// one, as the twin gives it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        guard Docs.types.contains(type) else {
            throw DecodingError.dataCorrupted(.init(codingPath: c.codingPath, debugDescription: "Not a block"))
        }
        self.type = type
        id = (try? c.decode(String.self, forKey: .id)).flatMap { $0.isEmpty ? nil : $0 } ?? Docs.newId()
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        src = try? c.decode(String.self, forKey: .src)
        alt = try? c.decode(String.self, forKey: .alt)
        table = try? c.decode(DocTable.self, forKey: .table)
        chart = try? c.decode(ChartSpec.self, forKey: .chart)
        checked = try? c.decode(Bool.self, forKey: .checked)
    }

    /// Id, type, then only the keys it has: words for a block that is typed
    /// in, and a checklist item's tick, always.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        if Docs.textTypes.contains(type) || !text.isEmpty { try c.encode(text, forKey: .text) }
        try c.encodeIfPresent(src, forKey: .src)
        try c.encodeIfPresent(alt, forKey: .alt)
        try c.encodeIfPresent(table, forKey: .table)
        try c.encodeIfPresent(chart, forKey: .chart)
        if type == Docs.checklist { try c.encode(checked == true, forKey: .checked) }
    }
}

/// A Doc's pages: A4 or US Letter, and their margins in points.
struct DocPage: Codable, Equatable {
    var size = Docs.letter
    var margins = 72.0

    init(size: String = Docs.letter, margins: Double = 72) {
        self.size = size
        self.margins = margins
    }

    private enum CodingKeys: String, CodingKey { case size, margins }

    /// A size it does not know is Letter; margins not 0…216 are 72.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let size = (try? c.decode(String.self, forKey: .size)) ?? Docs.letter
        self.size = size == Docs.a4 ? Docs.a4 : Docs.letter
        let m = (try? c.decode(Double.self, forKey: .margins)) ?? 72
        margins = m.isFinite && (0...216).contains(m) ? m : 72
    }
}

/// A Doc template from the generator (Content.json's "docs", the Android
/// twin's DocTemplates from templates/docs.json).
struct DocTemplate: Codable, Identifiable {
    var id: String
    var name: String
    var category: String
    var docPage: DocPage
    var blocks: [Lossy<DocBlock>]

    private enum CodingKeys: String, CodingKey { case id, name, category, docPage, blocks }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(docPage, forKey: .docPage)
        try c.encode(blocks.compactMap(\.value), forKey: .blocks)
    }
}

enum Docs {

    static let kind = "doc"

    /// The Doc design type's id.
    static let presetId = "doc"

    static let h1 = "h1"
    static let h2 = "h2"
    static let h3 = "h3"
    static let p = "p"
    static let bullet = "bullet"
    static let number = "number"
    static let checklist = "checklist"
    static let quote = "quote"
    static let divider = "divider"
    static let image = "image"
    static let table = "table"
    static let chart = "chart"
    static let pagebreak = "pagebreak"

    /// Every block type, in the order the '/' menu offers them.
    static let types = [h1, h2, h3, p, bullet, number, checklist, quote, divider, image, table, chart, pagebreak]

    /// The types whose words are typed.
    static let textTypes: Set<String> = [h1, h2, h3, p, bullet, number, checklist, quote]

    static let a4 = "a4"
    static let letter = "letter"

    static func newId() -> String {
        "blk_" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12))
    }

    static func isDoc(_ design: Design) -> Bool { design.kind == kind }

    static func blocks(_ design: Design) -> [DocBlock] { design.blocks ?? [] }

    static func pageSetup(_ design: Design) -> DocPage { design.docPage ?? DocPage() }

    /// `design` with `blocks` as its words.
    static func withBlocks(_ design: Design, _ blocks: [DocBlock]) -> Design {
        var out = design
        out.blocks = blocks
        return out
    }

    /// `design` on pages of `setup`, its size the page's.
    static func withPageSetup(_ design: Design, _ setup: DocPage) -> Design {
        var out = design
        let size = pageSize(setup)
        out.width = Double(size.width)
        out.height = Double(size.height)
        out.docPage = setup
        return out
    }

    /// A page's size in pixels at 96 dpi: A4 794 × 1123, US Letter 816 × 1056.
    static func pageSize(_ setup: DocPage) -> CGSize {
        setup.size == a4 ? CGSize(width: 794, height: 1123) : CGSize(width: 816, height: 1056)
    }

    /// The margins in the page's pixels: points at 96 dpi.
    static func margin(_ setup: DocPage) -> Double { setup.margins * 96 / 72 }

    /// A new Doc called `title`: a heading and a paragraph to type into.
    static func started(_ title: String, setup: DocPage = DocPage()) -> Design {
        let size = pageSize(setup)
        var d = Design(title: title, width: Double(size.width), height: Double(size.height))
        d.kind = kind
        d.blocks = [DocBlock(type: h1), DocBlock(type: p)]
        d.docPage = setup
        return d
    }

    // MARK: templates

    /// The Doc templates, generated from templates/docs.json.
    static var templates: [DocTemplate] { ContentLibrary.docTemplates }

    /// A new Doc from `template`: its page and blocks, under its name —
    /// each block a fresh id, so two Docs from it never share one.
    static func fromTemplate(_ template: DocTemplate) -> Design {
        let blocks = template.blocks.compactMap(\.value).map { block -> DocBlock in
            var b = block
            b.id = newId()
            return b
        }
        return withBlocks(started(tr(template.name), setup: template.docPage), blocks)
    }

    // MARK: words

    /// Every block's words, as a search or Find reads them: one a line.
    static func text(_ design: Design) -> String {
        blocks(design).filter { textTypes.contains($0.type) }.map { RichText.strip($0.text) }.joined(separator: "\n")
    }

    /// A table block's rows, and whether its first is the header.
    static func tableRows(_ block: DocBlock) -> (rows: [[String]], header: Bool) {
        guard let t = block.table else { return ([], true) }
        return (t.rows, t.header)
    }

    /// What a picture or chart block says to a reader: its alt text, else a
    /// chart's summary (ChartSpeech).
    static func altOf(_ block: DocBlock) -> String? {
        if let alt = block.alt?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty { return alt }
        guard let spec = block.chart, let kind = DataGraphics.ChartKind(rawValue: spec.kind) else { return nil }
        return ChartSpeech.summary(spec, data: DataGraphics.chartData(spec.data, kind: kind))
    }

    // MARK: laying out

    /// The room between one block and the next, in page pixels.
    static let gap = 12.0

    /// A picture's and a chart's height, as a share of the text's width.
    static let pictureRatio = 0.6

    /// The faces the words are set in: the brand kit's heading and body
    /// roles, or the default face for none.
    struct Styles {
        var heading: BrandFont?
        var body: BrandFont?
    }

    /// A block type's font size in page pixels.
    static func fontSize(_ type: String) -> Double {
        switch type {
        case h1: return 36
        case h2: return 28
        case h3: return 22
        case quote: return 20
        default: return 16
        }
    }

    /// What lays out as one: a run of bullets, or of numbered items, is one
    /// list — numbered on through it — and every other block itself. Each
    /// unit the indices of its blocks.
    static func units(_ blocks: [DocBlock]) -> [ClosedRange<Int>] {
        var out: [ClosedRange<Int>] = []
        var i = 0
        while i < blocks.count {
            var j = i
            if blocks[i].type == bullet || blocks[i].type == number {
                while j + 1 < blocks.count && blocks[j + 1].type == blocks[i].type { j += 1 }
            }
            out.append(i...j)
            i = j + 1
        }
        return out
    }

    /// The words a checklist item draws: its tick, then its words.
    static func checklistText(_ block: DocBlock) -> String {
        (block.checked == true ? "☑ " : "☐ ") + block.text
    }

    /// A text box for a block's words, set in its role (TextRoles) and its
    /// face, measured by `heightFor`.
    private static func textBox(_ words: String, type: String, x: Double, y: Double, width: Double, styles: Styles,
                                heightFor: (Element) -> Double) -> Element {
        let heading = type == h1 || type == h2 || type == h3
        let face = heading ? (styles.heading ?? styles.body) : (styles.body ?? styles.heading)
        var el = Element.text(words, fontSize: fontSize(type), w: width)
        el.x = x
        el.y = y
        el.align = "left"
        el.lineHeight = 1.35
        el.fontFamily = face?.family ?? "sans"
        el.fontWeight = face?.weight ?? (heading ? 700 : 400)
        if type == quote { el.italic = true }
        el = TextRoles.with(el, heading ? type : (type == quote ? TextRoles.quote : TextRoles.body))
        el.h = heightFor(el)
        return el
    }

    /// The elements one unit of blocks (`units`) lays out as, at `x`, `y`,
    /// `width` wide: a text box set in its role (TextRoles) — a list one
    /// box with its list style — a line for a divider, a photo for an
    /// image, a table's cells, a chart's parts.
    static func elements(_ blocks: [DocBlock], unit: ClosedRange<Int>, x: Double, y: Double, width: Double,
                         styles: Styles, heightFor: @escaping (Element) -> Double) -> [Element] {
        let first = blocks[unit.lowerBound]
        func text(_ words: String, _ type: String) -> Element {
            textBox(words, type: type, x: x, y: y, width: width, styles: styles, heightFor: heightFor)
        }
        switch first.type {
        case h1, h2, h3, p, quote:
            return [text(first.text, first.type)]
        case checklist:
            return [text(checklistText(first), p)]
        case bullet, number:
            var listed = text(unit.map { blocks[$0].text }.joined(separator: "\n"), p)
            listed.setListStyle(first.type == bullet ? "bullet" : "number")
            listed.h = heightFor(listed)
            return [listed]
        case divider:
            var line = Element.line(w: width)
            line.x = x
            line.y = y
            line.h = 8
            line.thickness = 1
            line.color = "#c9ccd3"
            return [line]
        case image:
            guard let src = first.src else { return [] }
            var picture = Element.image(src, w: width, h: (width * pictureRatio + 0.5).rounded(.down))
            picture.x = x
            picture.y = y
            if let alt = first.alt?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty { picture.altText = alt }
            return [picture]
        case table:
            let (rows, header) = tableRows(first)
            guard !rows.isEmpty else { return [] }
            let made = DataGraphics.table(rows, in: CGRect(x: x, y: y, width: width, height: 0), accent: "#e9ebf0",
                                          heightFor: heightFor)
            guard !header, let id = made.lazy.compactMap({ $0.table?.id }).first else { return made }
            return DataGraphics.withTableHeader(made, id: id, on: false, accent: "#e9ebf0", heightFor: heightFor)
        case chart:
            guard let spec = first.chart else { return [] }
            let frame = CGRect(x: x, y: y, width: width, height: (width * pictureRatio + 0.5).rounded(.down))
            let palette = ContentLibrary.palettes.first?.colors ?? ["#8b5cf6", "#06b6d4", "#f59e0b", "#ef4444"]
            return DataGraphics.chart(spec, in: frame, palette: palette, heightFor: heightFor)
        default:
            return []
        }
    }

    /// How tall `elements` stand, from their top.
    static func heightOf(_ elements: [Element]) -> Double {
        guard let top = elements.map(\.y).min() else { return 0 }
        return Double(Geometry.union(elements.map { Geometry.aabb($0) }).maxY) - top
    }

    /// Where the pages break — the shared rule both phones paginate by: the
    /// index of the first block of every page after the first. `heights` is
    /// each unit's height (`units`), in page pixels, the page
    /// `contentHeight` tall inside its margins. Units stack `gap` apart from
    /// the top. One that would run past the foot starts the next page —
    /// with the heading just before it, when a heading would otherwise end
    /// the page and that is not the page's first unit. A page break ends
    /// the page, unless the page is still empty. A unit taller than a page
    /// has a page of its own, and runs past its foot.
    static func paginate(_ blocks: [DocBlock], heights: [Double], contentHeight: Double) -> [Int] {
        let units = Self.units(blocks)
        var breaks: [Int] = []
        var cursor = 0.0
        var onPage = 0
        var u = 0
        while u < units.count {
            let unit = units[u]
            let type = blocks[unit.lowerBound].type
            if type == pagebreak {
                if onPage > 0 && u + 1 < units.count {
                    breaks.append(units[u + 1].lowerBound)
                    cursor = 0
                    onPage = 0
                }
                u += 1
                continue
            }
            let h = u < heights.count ? heights[u] : 0
            let need = onPage == 0 ? h : gap + h
            if onPage > 0 && cursor + need > contentHeight {
                let before = units[u - 1]
                let heading = [h1, h2, h3].contains(blocks[before.lowerBound].type)
                if heading && onPage > 1 {
                    breaks.append(before.lowerBound)
                    cursor = heights[u - 1] + gap + h
                    onPage = 2
                } else {
                    breaks.append(unit.lowerBound)
                    cursor = h
                    onPage = 1
                }
                u += 1
                continue
            }
            cursor += need
            onPage += 1
            u += 1
        }
        return breaks
    }

    /// The Doc laid out as an ordinary design of pages — for a PDF, a print,
    /// a thumbnail and Convert to design: each unit's elements placed down
    /// its page inside the margins, the pages broken by `paginate`. The
    /// Doc's own keys are left behind; its title, id and times kept.
    static func paginated(_ design: Design, styles: Styles = Styles(),
                          heightFor: @escaping (Element) -> Double = FontLibrary.layoutHeight(for:)) -> Design {
        let setup = pageSetup(design)
        let size = pageSize(setup)
        let margin = Self.margin(setup)
        let width = Double(size.width) - 2 * margin
        let contentHeight = Double(size.height) - 2 * margin
        let blocks = Self.blocks(design)
        let units = Self.units(blocks)
        let measured = units.map { elements(blocks, unit: $0, x: margin, y: 0, width: width, styles: styles, heightFor: heightFor) }
        let heights = measured.map(heightOf)
        let breaks = Set(paginate(blocks, heights: heights, contentHeight: contentHeight))
        var pages: [Page] = []
        var current: [Element] = []
        var cursor = margin
        for (u, unit) in units.enumerated() {
            if breaks.contains(unit.lowerBound) && (!current.isEmpty || !pages.isEmpty || cursor > margin) {
                pages.append(Page(elements: current))
                current = []
                cursor = margin
            }
            if blocks[unit.lowerBound].type == pagebreak { continue }
            let els = measured[u]
            guard let top = els.map(\.y).min() else { continue }
            let dy = cursor - top
            current += els.map { el -> Element in
                var moved = el
                moved.y += dy
                return moved
            }
            cursor += heights[u] + gap
        }
        pages.append(Page(elements: current))
        var out = design
        out.width = Double(size.width)
        out.height = Double(size.height)
        out.pages = pages
        out.kind = nil
        out.blocks = nil
        out.docPage = nil
        return out
    }

    // MARK: turn into a presentation

    /// A presentation's slide.
    static let slide = CGSize(width: 1920, height: 1080)

    /// Turn into presentation: a slide for each first-level heading, the
    /// heading its title and the blocks after it, up to the next, its body —
    /// words as one text box (lists as lists), the first picture beside
    /// them. Blocks before the first heading make a slide of their own,
    /// titled by the design. Laid out as the Presentation type's
    /// title-and-body slide: 120 px margins, the title 72 px bold, the body
    /// 36 px.
    static func presentation(_ design: Design,
                             heightFor: @escaping (Element) -> Double = FontLibrary.layoutHeight(for:)) -> Design {
        var groups: [(title: String, body: [DocBlock])] = []
        var title: String?
        var body: [DocBlock] = []
        for b in blocks(design) {
            if b.type == h1 {
                if title != nil || !body.isEmpty { groups.append((title ?? design.title, body)) }
                title = b.text
                body = []
            } else if b.type != pagebreak {
                body.append(b)
            }
        }
        if title != nil || !body.isEmpty { groups.append((title ?? design.title, body)) }
        if groups.isEmpty { groups.append((design.title, [])) }
        var out = Design(title: design.title, width: Double(slide.width), height: Double(slide.height))
        out.pages = groups.map { slidePage($0.title, $0.body, heightFor: heightFor) }
        return out
    }

    private static func slidePage(_ heading: String, _ rest: [DocBlock], heightFor: (Element) -> Double) -> Page {
        var els: [Element] = []
        var t = TextRoles.with(Element.text(heading, fontSize: 72, w: 1680), TextRoles.h1)
        t.x = 120
        t.y = 100
        t.align = "left"
        t.fontWeight = 700
        t.h = heightFor(t)
        els.append(t)
        let picture = rest.first { $0.type == image && $0.src != nil }
        let textWidth: Double = picture != nil ? 1000 : 1680
        let words = rest.filter { textTypes.contains($0.type) }
        if !words.isEmpty {
            let lines = words.map { $0.type == checklist ? checklistText($0) : $0.text }
            var b = Element.text(lines.joined(separator: "\n"), fontSize: 36, w: textWidth)
            b.x = 120
            b.y = t.y + t.h + 48
            b.align = "left"
            let listed = words.map { w -> TextParagraph in
                switch w.type {
                case bullet: return TextParagraph(list: "bullet")
                case number: return TextParagraph(list: "number")
                default: return TextParagraph()
                }
            }
            if listed.contains(where: \.isListed) { b.setLines(listed) }
            b.h = heightFor(b)
            els.append(b)
        }
        if let picture, let src = picture.src {
            var pic = Element.image(src, w: 600, h: 600)
            pic.x = 1200
            pic.y = t.y + t.h + 48
            if let alt = picture.alt?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty { pic.altText = alt }
            els.append(pic)
        }
        return Page(elements: els)
    }
}
