// "Make brand guidelines": a brand kit laid out as a design to share — A4
// landscape (3508 × 2480 px, measured in mm at 300 dpi) — on both phones by
// one deterministic layout, so the same kit gives the same frames (Tests/
// BrandGuidelinesTests and the Android twin's BrandGuidelinesTest):
//
//  - Cover: the first logo, "Brand guidelines", the kit's name, and a strip
//    of its colours along the foot.
//  - Colours: a page per palette with colours, a swatch each — four to a
//    row — with its name, HEX, RGB and CMYK (Cmyk).
//  - Typography: each role the kit sets (or heading and body in the default
//    face), named with its face, weight and size, and a sample line set in
//    it.
//  - Logos: each logo on a light and a dark tile, clear space round it, two
//    logos to a page.
//  - Imagery: up to six of the brand photos, then graphics — pictures only;
//    an SVG graphic needs its file, which this does not read.
//
// Every text is in the kit's fonts (BrandFonts.fontFor), "sans" where it
// sets none. The design opens in the editor like any other, so it prints,
// exports and shares as one.

import Foundation

enum BrandGuidelines {

    static let width = 3508.0
    static let height = 2480.0
    static let margin = 200.0
    static let gap = 80.0
    static let ink = "#16181d"
    static let muted = "#5b6474"
    static let dark = "#16181d"
    static let light = "#ffffff"
    static let edge = "#d6dbe4"

    /// How many swatches a row has, logos a page and pictures the page.
    static let swatchesPerRow = 4
    static let logosPerPage = 2
    static let imageryLimit = 6

    /// Each text's line height, as Add ▸ Text sets one.
    private static let leading = 1.25

    /// The new design's name: "Acme guidelines".
    static func title(_ kit: BrandKit) -> String { tr("%@ guidelines", kit.name) }

    /// The kit as a design, made at `now` (epoch milliseconds).
    static func design(_ kit: BrandKit, now: Double) -> Design {
        var pages = [cover(kit)]
        for palette in kit.palettes where !palette.colors.isEmpty {
            pages.append(colours(kit, palette))
        }
        pages.append(typography(kit))
        var logos = kit.logos[...]
        while !logos.isEmpty {
            pages.append(logoPage(kit, Array(logos.prefix(logosPerPage))))
            logos = logos.dropFirst(logosPerPage)
        }
        let pictures = Array((kit.photos + kit.graphics.filter { BrandKit.svgID($0) == nil }).prefix(imageryLimit))
        if !pictures.isEmpty { pages.append(imagery(kit, pictures, photos: kit.photos.count)) }
        var made = Design(title: title(kit), width: width, height: height)
        made.createdAt = now
        made.updatedAt = now
        made.pages = pages
        made.titleAuto = false
        made.unit = "mm"
        made.dpi = 300
        return made
    }

    // MARK: pages

    private static func cover(_ kit: BrandKit) -> Page {
        var els: [Element] = []
        if let logo = kit.logos.first { els.append(picture(logo, margin, margin, 600, 600, fit: true)) }
        els.append(text(kit, .caption, tr("Brand guidelines"), margin, 1000, width - 2 * margin, 80, muted))
        els.append(text(kit, .title, kit.name, margin, 1120, width - 2 * margin, 260, ink))
        let strip = Array(kit.colors.prefix(BrandKit.limit))
        if !strip.isEmpty {
            let w = (width - 2 * margin) / Double(strip.count)
            for (i, hex) in strip.enumerated() {
                els.append(block(hex, margin + Double(i) * w, height - margin - 200, w, 200))
            }
        }
        return page(els)
    }

    private static func colours(_ kit: BrandKit, _ palette: BrandPalette) -> Page {
        var els = [kicker(kit, tr("Colours")), heading(kit, palette.name)]
        let perRow = Double(swatchesPerRow)
        let cell = (width - 2 * margin - (perRow - 1) * gap) / perRow
        for (i, hex) in palette.colors.prefix(BrandKit.limit).enumerated() {
            let x = margin + Double(i % swatchesPerRow) * (cell + gap)
            let y = 560 + Double(i / swatchesPerRow) * 560
            var swatch = block(hex, x, y, cell, 280)
            swatch.stroke = edge
            swatch.strokeWidth = 4
            els.append(swatch)
            els.append(text(kit, .body, describe(hex), x, y + 304, cell, 40, ink))
        }
        return page(els)
    }

    /// A swatch's words: its name, then HEX, RGB and CMYK, a line each.
    static func describe(_ hex: String) -> String {
        let rgb = Cmyk.rgb(hex) ?? (0, 0, 0)
        let press = Cmyk.fromRGB(rgb.r, rgb.g, rgb.b)
        func pc(_ v: Double) -> Int { Int((v * 100).rounded()) }
        let named = ElementNames.colourName(hex)
        let name = named.prefix(1).uppercased() + named.dropFirst()
        let code = String(format: "#%02x%02x%02x", rgb.r, rgb.g, rgb.b)
        return [
            name,
            "HEX \(code)",
            "RGB \(rgb.r) \(rgb.g) \(rgb.b)",
            "CMYK \(pc(press.c)) \(pc(press.m)) \(pc(press.y)) \(pc(press.k))",
        ].joined(separator: "\n")
    }

    /// The roles the page shows: each the kit sets a face for, in role
    /// order, or a heading and body text when it sets none.
    static func roles(_ kit: BrandKit) -> [BrandFonts.Role] {
        let set = BrandFonts.Role.allCases.filter { kit.fonts[$0] != nil }
        return set.isEmpty ? [.heading, .body] : set
    }

    private static func typography(_ kit: BrandKit) -> Page {
        var els = [kicker(kit, tr("Typography")), heading(kit, tr("Fonts"))]
        let shown = roles(kit)
        let top = 560.0
        let row = (height - margin - top) / Double(shown.count)
        for (i, role) in shown.enumerated() {
            let face = kit.fonts.fontFor(role)
            let family = face?.family ?? "sans"
            let weight = face?.weight ?? role.defaultWeight
            let own = BrandFonts.sized(face, pageWidth: width) ?? role.widthFraction * width
            let size = (min(own, min(220, (row - 100) / leading)) * 10).rounded() / 10
            let y = top + Double(i) * row
            let label = ([role.label, family, "\(weight)", "\(Int(own.rounded())) px"] + attributes(face, kit))
                .joined(separator: " · ")
            els.append(text(kit, .caption, label, margin, y, width - 2 * margin, 40, muted))
            var sample = Element.text(tr("The quick brown fox jumps over the lazy dog"), fontSize: size, w: width - 2 * margin)
            sample.x = margin
            sample.y = y + 64
            sample.h = size * leading
            sample.align = "left"
            sample.fontFamily = family
            sample.fontWeight = weight
            sample.lineHeight = leading
            sample.color = ink
            // The rest of the role's type, as Add text sets it.
            BrandFonts.typeSettings(face, role: role, to: &sample, pageWidth: width, palettes: kit.palettes)
            els.append(sample)
        }
        return page(els)
    }

    /// What a role's face sets beyond its family, weight and size, in the
    /// order the brand kit lists them: its colour as hex, its letter
    /// spacing whole, its line spacing to two places, capitals and italic —
    /// each only when set.
    static func attributes(_ face: BrandFont?, _ kit: BrandKit) -> [String] {
        guard let face else { return [] }
        var out: [String] = []
        if let colour = BrandFont.resolved(face.color, palettes: kit.palettes) { out.append(colour) }
        if let spacing = face.letterSpacing { out.append(tr("Spacing %d", Int(spacing.rounded()))) }
        if let line = face.lineHeight { out.append(tr("Line %@", String(format: "%.2f", line))) }
        if face.uppercase == true { out.append(tr("Uppercase")) }
        if face.italic == true { out.append(tr("Italic")) }
        return out
    }

    private static func logoPage(_ kit: BrandKit, _ logos: [String]) -> Page {
        var els = [kicker(kit, tr("Logos")), heading(kit, tr("Logo and clear space"))]
        let top = 560.0
        let tileW = (width - 2 * margin - gap) / 2
        let tileH = (height - margin - top - gap) / Double(logosPerPage)
        for (i, src) in logos.enumerated() {
            let y = top + Double(i) * (tileH + gap)
            for (j, colour) in [light, dark].enumerated() {
                let x = margin + Double(j) * (tileW + gap)
                var tile = block(colour, x, y, tileW, tileH)
                tile.stroke = edge
                tile.strokeWidth = 4
                els.append(tile)
                // The clear space: a fifth of the tile's shorter side all round.
                let space = min(tileW, tileH) * 0.2
                els.append(picture(src, x + space, y + space, tileW - 2 * space, tileH - 2 * space, fit: true))
            }
        }
        return page(els)
    }

    private static func imagery(_ kit: BrandKit, _ pictures: [String], photos: Int) -> Page {
        var els = [kicker(kit, tr("Imagery")), heading(kit, tr("Photos and graphics"))]
        let top = 560.0
        let cellW = (width - 2 * margin - 2 * gap) / 3
        let cellH = (height - margin - top - gap) / 2
        for (i, src) in pictures.enumerated() {
            // Photos fill their cell; graphics are shown whole.
            els.append(picture(src, margin + Double(i % 3) * (cellW + gap), top + Double(i / 3) * (cellH + gap),
                               cellW, cellH, fit: i >= photos))
        }
        return page(els)
    }

    // MARK: parts

    private static func page(_ elements: [Element]) -> Page {
        Page(background: .color(light), elements: elements)
    }

    private static func kicker(_ kit: BrandKit, _ words: String) -> Element {
        text(kit, .caption, words, margin, margin, width - 2 * margin, 60, muted)
    }

    private static func heading(_ kit: BrandKit, _ words: String) -> Element {
        text(kit, .heading, words, margin, margin + 100, width - 2 * margin, 140, ink)
    }

    /// A text in the kit's face for `role`: its box as tall as its lines.
    private static func text(_ kit: BrandKit, _ role: BrandFonts.Role, _ words: String,
                             _ x: Double, _ y: Double, _ w: Double, _ size: Double, _ colour: String) -> Element {
        let face = kit.fonts.fontFor(role)
        let lines = Double(words.split(separator: "\n", omittingEmptySubsequences: false).count)
        var el = Element.text(words, fontSize: size, w: w)
        el.x = x
        el.y = y
        el.h = size * leading * lines
        el.align = "left"
        el.fontFamily = face?.family ?? "sans"
        el.fontWeight = face?.weight ?? role.defaultWeight
        el.lineHeight = leading
        el.color = colour
        return el
    }

    private static func block(_ hex: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Element {
        var el = Element.shape("rect", w: w, h: h)
        el.x = x
        el.y = y
        el.fill = .solid(hex)
        el.radius = 0
        return el
    }

    private static func picture(_ src: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double, fit: Bool) -> Element {
        var el = Element.image(src, w: w, h: h)
        el.x = x
        el.y = y
        el.cropFit = fit ? true : nil
        return el
    }
}
