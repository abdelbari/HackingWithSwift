// Apply colours to page: the page recoloured from the selected photo's
// palette, as Canva's element menu does it. The page's own colours — its
// background, and the fills, borders and inks of its shapes, words, lines,
// tables and charts — are ranked by lightness and mapped onto the photo's,
// as Document theme maps a palette (ColorTools.shuffle), on this page only.
// Photos, what is locked and the photo itself keep theirs, and any words
// left under WCAG AA on what is now behind them take ContrastAudit's fix.
// Each tap turns the palette one place further round, so the same photo
// gives a new combination each time. The Android twin's PhotoColours, with
// the same rows.

import Foundation

enum PhotoColours {

    /// Whether `el` offers Apply colours to page: a photo or clip showing a
    /// picture — not a QR code or barcode, nor an empty frame.
    static func offered(_ el: Element) -> Bool {
        el.type == .image && !PhotoFrames.isEmpty(el) && !CodeGenerator.isCode(el.src)
    }

    /// Whether `el` is recoloured: a shape, words or a line — a table's
    /// cells and a chart's parts among them — not locked, and not `photo`.
    static func recolours(_ el: Element, photo: String) -> Bool {
        guard !el.locked, el.id != photo else { return false }
        return el.type == .shape || el.type == .text || el.type == .line
    }

    /// `palette` ranked dark to light, then turned `turn` places round: the
    /// darkest first at 0, the next darkest first at 1, and so on, back to
    /// the start after the last.
    static func turned(_ palette: [String], by turn: Int) -> [String] {
        let ranked = palette.map { $0.lowercased() }.sorted { ColorTools.luminance($0) < ColorTools.luminance($1) }
        guard !ranked.isEmpty else { return [] }
        let start = ((turn % ranked.count) + ranked.count) % ranked.count
        return Array(ranked[start...] + ranked[..<start])
    }

    /// The colours `page` gives the mapping: its background's and those of
    /// what is recoloured (recolours), each once in first-seen order, none
    /// that is mostly see-through (ContrastAudit.isFaint).
    static func pageColours(_ page: Page, photo: String) -> [String] {
        var out: [String] = []
        var seen = Set<String>()
        func add(_ colour: String?) {
            guard let colour, colour.hasPrefix("#"), !ContrastAudit.isFaint(colour) else { return }
            if seen.insert(colour.lowercased()).inserted { out.append(colour.lowercased()) }
        }
        func addPaint(_ paint: Paint?) {
            guard let paint else { return }
            if paint.kind == "gradient" { paint.stops?.forEach { add($0.color) } } else if paint.kind != "image" { add(paint.color) }
        }
        switch page.background {
        case .color(let c): add(c)
        case .gradient(let p): addPaint(p)
        case .image: break
        }
        for el in page.elements where recolours(el, photo: photo) {
            addPaint(el.fill)
            add(el.stroke)
            add(el.color)
        }
        return out
    }

    /// `page` recoloured from `palette` turned `turn` places (turned): its
    /// colours (pageColours), darkest first, each taking the palette colour
    /// at the same share of the way along — the theme's lightness mapping —
    /// on the background and on what is recoloured; then any words of those
    /// that fall under AA on what is behind them now given ContrastAudit's
    /// fix. The page as it was for an empty palette or nothing to recolour.
    static func applied(_ page: Page, palette: [String], turn: Int, photo: String) -> Page {
        let colours = turned(palette, by: turn)
        let used = pageColours(page, photo: photo).sorted { ColorTools.luminance($0) < ColorTools.luminance($1) }
        guard !colours.isEmpty, !used.isEmpty else { return page }
        var map: [String: String] = [:]
        for (i, c) in used.enumerated() {
            let at = used.count <= 1 ? 0
                : Int((Double(i) / Double(used.count - 1) * Double(colours.count - 1)).rounded())
            map[c] = colours[at]
        }
        func remap(_ c: String?) -> String? {
            guard let c else { return nil }
            return map[c.lowercased()] ?? c
        }
        func remapPaint(_ p: Paint?) -> Paint? {
            guard var p else { return nil }
            if p.kind == "gradient" {
                p.stops = p.stops?.map { GradientStop(offset: $0.offset, color: remap($0.color) ?? $0.color) }
            } else if p.kind != "image" {
                p.color = remap(p.color)
            }
            return p
        }
        var out = page
        switch page.background {
        case .color(let c): out.background = .color(remap(c) ?? c)
        case .gradient(let p): out.background = .gradient(remapPaint(p) ?? p)
        case .image: break
        }
        for i in out.elements.indices where recolours(out.elements[i], photo: photo) {
            out.elements[i].fill = remapPaint(out.elements[i].fill)
            out.elements[i].stroke = remap(out.elements[i].stroke)
            out.elements[i].color = remap(out.elements[i].color)
        }
        return readable(out, photo: photo)
    }

    /// `page` with every recoloured text that falls under AA on what is
    /// behind it given ContrastAudit's fix: the ink that passes there.
    static func readable(_ page: Page, photo: String) -> Page {
        var out = page
        for i in out.elements.indices {
            let el = out.elements[i]
            guard el.type == .text, recolours(el, photo: photo), el.textFill == nil, !el.isHidden,
                  el.opacity > 0.05 else { continue }
            let back = ContrastAudit.backdrop(for: el, in: out)
            let ink = el.color ?? "#1f2430"
            let need = ContrastAudit.required(for: el)
            let ratio = ContrastAudit.ratio(ContrastAudit.drawn(ink, over: back, opacity: el.opacity), back)
            guard ratio < need else { continue }
            let finding = ContrastAudit.Finding(pageIndex: 0, elementId: el.id, text: el.text ?? "", ratio: ratio,
                                                required: need, backdrop: back,
                                                suggestion: ContrastAudit.suggestion(on: back, need: need))
            out.elements[i] = ContrastAudit.fixed(el, for: finding)
        }
        return out
    }
}
