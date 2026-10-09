// Loads the bundled content library (Content.json): shapes, templates,
// palettes, gradients, font pairings, sticker groups and procedural photo
// specs. The JSON was generated and validated by the Canvia web build.

import Foundation

struct ShapeDef: Codable, Identifiable {
    var id: String
    var name: String
    var category: String
    var path: String
    var rectLike: Bool?
}

struct Template: Codable, Identifiable {
    var id: String
    var name: String
    var category: String
    var width: Double
    var height: Double
    var background: Background
    var elements: [Element]

    /// A fresh Design at the template's native size.
    func instantiate() -> Design {
        var design = Design(title: name, width: width, height: height)
        design.pages = [makePage(scale: 1, dx: 0, dy: 0)]
        return design
    }

    /// A page scaled uniformly into a target canvas (Canva-style apply).
    /// Scale to *fit* — the smaller of the two ratios — then centre on both
    /// axes, so applying a tall template to a wide canvas (or vice versa)
    /// keeps every element on the page instead of spilling off the bottom.
    func makePage(for design: Design) -> Page {
        makePage(width: design.width, height: design.height)
    }

    /// The same, onto a page of this size — the page's own, which in a
    /// design of mixed sizes need not be the document's. As the Android
    /// twin's instantiate(width, height).
    func makePage(width pageWidth: Double, height pageHeight: Double) -> Page {
        guard width > 0, height > 0 else { return Page(background: background) }
        let scale = min(pageWidth / width, pageHeight / height)
        let dx = (pageWidth - width * scale) / 2
        let dy = (pageHeight - height * scale) / 2
        return makePage(scale: scale, dx: dx, dy: dy)
    }

    private func makePage(scale: Double, dx: Double, dy: Double) -> Page {
        var page = Page(background: background)
        page.elements = elements.map { spec in
            var el = spec
            el.id = UID.make()
            el.x = el.x * scale + dx
            el.y = el.y * scale + dy
            el.w *= scale
            el.h *= scale
            // A shape's words scale with it, as a text box's do.
            if ShapeText.carriesWords(el), let fs = el.fontSize { el.fontSize = fs * scale }
            if ShapeText.carriesWords(el), let ls = el.letterSpacing { el.letterSpacing = ls * scale }
            if el.type == .line, let t = el.thickness { el.thickness = max(1, t * scale) }
            // Rounding scales with the box it rounds, as on the Android twin,
            // so a card is as round on either phone and both write the same
            // radius. Per-corner radii are left as they are on both.
            if let r = el.radius { el.radius = r * scale }
            // Measure after scaling: the spec carries no height, and the
            // decoder's line-count estimate ignores leading and wrapping.
            if el.type == .text { el.h = FontLibrary.layoutHeight(for: el) }
            return el
        }
        return page
    }
}

struct Palette: Codable, Identifiable {
    var id: String
    var name: String
    var colors: [String]
}

struct GradientPreset: Codable, Identifiable {
    var id: String
    var name: String
    var angle: Double
    var stops: [GradientStop]

    var paint: Paint { Paint(kind: "gradient", color: nil, angle: angle, stops: stops) }

    /// The shapes a gradient comes in, in the order the pickers offer them.
    static let kinds = ["linear", "radial", "angular"]

    /// This preset in `kind`'s shape. Linear is written as no shape at all,
    /// as both phones write it.
    func paint(kind: String) -> Paint {
        var p = paint
        p.gradientKind = kind == "linear" ? nil : kind
        return p
    }

    /// The shape a paint is in: linear when it names none, or one this app
    /// does not know.
    static func kind(of paint: Paint?) -> String {
        let kind = paint?.gradientKind ?? "linear"
        return kinds.contains(kind) ? kind : "linear"
    }

    /// Whether two gradients are the same one — kind, angle, shape and every
    /// stop, colours compared ignoring case — so tapping the gradient already
    /// there records nothing, as on the Android twin.
    static func same(_ a: Paint?, _ b: Paint) -> Bool {
        guard let a, a.kind == b.kind, a.angle == b.angle, kind(of: a) == kind(of: b) else { return false }
        let sa = a.stops ?? [], sb = b.stops ?? []
        guard sa.count == sb.count else { return false }
        return zip(sa, sb).allSatisfy { $0.offset == $1.offset && $0.color.lowercased() == $1.color.lowercased() }
    }
}

struct PairingSpec: Codable {
    var fontFamily: String
    var fontWeight: Int
    var fontSize: Double
    var letterSpacing: Double?
    var text: String
}

struct FontPairing: Codable, Identifiable {
    var name: String
    var heading: PairingSpec
    var body: PairingSpec
    var id: String { name }
}

struct StickerGroup: Codable, Identifiable {
    var name: String
    var emoji: [String]
    var id: String { name }
}

struct MeshSpec: Codable { var id: String; var name: String; var colors: [String]; var seed: Double }
struct WaveSpec: Codable { var id: String; var name: String; var colors: [String] }
struct StripeSpec: Codable { var id: String; var name: String; var colors: [String]; var angle: Double }

struct PhotoSpecs: Codable {
    var meshes: [MeshSpec]
    var waves: [WaveSpec]
    var stripes: [StripeSpec]
}

struct ContentBundle: Codable {
    var shapes: [ShapeDef]
    var templates: [Template]
    var palettes: [Palette]
    var gradients: [GradientPreset]
    var pairings: [FontPairing]
    var stickerGroups: [StickerGroup]
    var photoSpecs: PhotoSpecs
}

enum ContentLibrary {
    static let bundle: ContentBundle = {
        guard let url = Bundle.main.url(forResource: "Content", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ContentBundle.self, from: data) else {
            assertionFailure("Content.json missing or invalid")
            return ContentBundle(
                shapes: [fallbackShape],
                templates: [], palettes: [], gradients: [], pairings: [],
                stickerGroups: [],
                photoSpecs: PhotoSpecs(meshes: [], waves: [], stripes: []))
        }
        return decoded
    }()

    static var shapes: [ShapeDef] { bundle.shapes }
    static var templates: [Template] { bundle.templates }
    static var palettes: [Palette] { bundle.palettes }
    static var gradients: [GradientPreset] { bundle.gradients }
    static var pairings: [FontPairing] { bundle.pairings }
    static var stickerGroups: [StickerGroup] { bundle.stickerGroups }

    /// A plain square, used whenever a shape id cannot be resolved.
    static let fallbackShape = ShapeDef(id: "rect", name: "Square",
                                        category: "Basic", path: "M0,0H100V100H0Z",
                                        rectLike: true)

    // `uniqueKeysWithValues:` traps on a duplicate id, and the trap would
    // happen at launch, on first access. A duplicate in the content library
    // is a content bug, not a reason to take the app down: keep the first.
    static let shapeMap: [String: ShapeDef] = Dictionary(
        bundle.shapes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func shape(_ id: String?) -> ShapeDef {
        shapeMap[id ?? "rect"] ?? shapeMap["rect"] ?? fallbackShape
    }

    /// The geometry an element draws: its own path data if it has any,
    /// else the library shape it names.
    static func shape(for el: Element) -> ShapeDef {
        if let d = el.pathData, !d.isEmpty {
            return ShapeDef(id: "custom", name: "Custom shape", category: "Custom", path: d, rectLike: false)
        }
        return shape(el.shapeId)
    }

    /// Template categories in the order they first appear.
    static var templateCategories: [String] {
        var seen: [String] = []
        for t in templates where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }

    /// Templates in a category (nil is all of them) whose name or category
    /// matches the query (empty is all of them).
    static func filteredTemplates(in category: String?, matching query: String) -> [Template] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return templates.filter { t in
            (category == nil || t.category == category)
                && (needle.isEmpty || t.name.localizedCaseInsensitiveContains(needle)
                    || t.category.localizedCaseInsensitiveContains(needle))
        }
    }

    /// Templates whose page is exactly this size, in library order, and
    /// only `category`'s when one is given. The size just named is the way
    /// in, as on the Android twin: eighty-odd templates organised by the job
    /// in hand never leave more than a screenful to choose from, and topic
    /// becomes a filter inside that rather than the front door.
    static func sizedTemplates(width: Double, height: Double, category: String?) -> [Template] {
        templates.filter { t in
            t.width == width && t.height == height && (category == nil || t.category == category)
        }
    }

    /// The editor's Templates tab: those made for this page's size lead,
    /// and every size (fitted to the page) is shown once asked for — or
    /// from the start when nothing is made for it. Found by name or kind.
    /// As the Android twin's TemplatesPanel.
    static func editorTemplates(width: Double, height: Double, everySize: Bool,
                                matching query: String) -> [Template] {
        let exact = sizedTemplates(width: width, height: height, category: nil)
        let pool = everySize || exact.isEmpty ? templates : exact
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return pool }
        return pool.filter {
            $0.name.localizedCaseInsensitiveContains(needle) || $0.category.localizedCaseInsensitiveContains(needle)
        }
    }

    /// The line over the editor's templates: what a tap will do, and why
    /// every size is there when none is made for this one.
    static func editorTemplatesNote(exactCount: Int) -> String {
        exactCount == 0
            ? "Nothing is made for this exact size, so every template is fitted to it. It replaces this page; Undo brings it back."
            : "Replaces what is on this page. Undo brings it back."
    }

    static func sizedTemplates(for preset: SizePreset) -> [Template] {
        sizedTemplates(width: preset.w, height: preset.h, category: nil)
    }

    /// How many ready-made starts each size has, by preset id: the line
    /// under a size tile.
    static let templateCounts: [String: Int] = Dictionary(
        SizePreset.all.map { ($0.id, sizedTemplates(for: $0).count) },
        uniquingKeysWith: { first, _ in first })

    /// A size's topics, once each and alphabetical, for its chip row.
    static func topics(in bucket: [Template]) -> [String] {
        Array(Set(bucket.map(\.category))).sorted()
    }

    /// Whether a size has enough, and varied enough, templates for a topic
    /// row to earn its space: more than eight, in more than one topic.
    static func showsTopics(_ bucket: [Template]) -> Bool {
        bucket.count > 8 && topics(in: bucket).count > 1
    }

    /// What each shape category is called where people see it, as the
    /// Android twin names its groups — a search for "badge" or "speech"
    /// should find the whole group, and a header should read as words.
    static let shapeGroupNames: [String: String] = [
        "Basic": "Basic shapes", "Stars": "Stars and badges", "Arrows": "Arrows",
        "Callouts": "Speech and labels", "Symbols": "Symbols", "Blobs": "Blobs", "Decor": "Decorative",
    ]

    static func shapeGroupName(_ category: String) -> String {
        shapeGroupNames[category] ?? category
    }

    /// Whether a shape answers a search: by its own name or its group's.
    static func shape(_ shape: ShapeDef, matches query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return needle.isEmpty
            || shape.name.localizedCaseInsensitiveContains(needle)
            || shapeGroupName(shape.category).localizedCaseInsensitiveContains(needle)
    }

    static var shapeCategories: [String] {
        var seen: [String] = []
        for s in shapes where !seen.contains(s.category) { seen.append(s.category) }
        return seen
    }

    static let defaultSwatches: [String] = [
        "#0d1216", "#545d6b", "#9aa4b2", "#e3e6ea", "#ffffff",
        "#e5484d", "#ff7b54", "#ffb02e", "#ffe066", "#8fce5f",
        "#16c79a", "#00b4d8", "#3e63dd", "#8b3dff", "#d6409f",
        "#f9d8e7", "#ffe8cc", "#fff8d6", "#d9f2e6", "#dbeafe",
    ]
}

// MARK: size presets

struct SizePreset: Identifiable {
    var id: String
    var name: String
    var w: Double
    var h: Double
    var icon: String

    static let all: [SizePreset] = [
        .init(id: "insta-post", name: "Instagram Post", w: 1080, h: 1080, icon: "square"),
        .init(id: "insta-story", name: "Instagram Story", w: 1080, h: 1920, icon: "iphone"),
        .init(id: "presentation", name: "Presentation", w: 1920, h: 1080, icon: "display"),
        .init(id: "youtube-thumb", name: "YouTube Thumbnail", w: 1280, h: 720, icon: "play.rectangle"),
        // Where the Android twin has it, and the size seven of the bundled
        // templates were already made at with no tile to reach them by.
        .init(id: "facebook-post", name: "Facebook Post", w: 1200, h: 630, icon: "rectangle"),
        .init(id: "poster", name: "Poster", w: 1587, h: 2245, icon: "doc.richtext"),
        .init(id: "flyer", name: "Flyer A5", w: 1240, h: 1748, icon: "doc"),
        // A4 at 300 dpi, the size the bundled A4 templates (a resume, a
        // certificate, a menu, an invoice, a travel plan) were made at and
        // the Android twin's; at 150 dpi the tile opened on no templates.
        .init(id: "a4", name: "A4 Document", w: 2480, h: 3508, icon: "doc.text"),
        .init(id: "business-card", name: "Business Card", w: 1050, h: 600, icon: "person.crop.rectangle"),
        .init(id: "quote-card", name: "Quote Card", w: 1440, h: 1080, icon: "quote.opening"),
        .init(id: "logo", name: "Logo", w: 800, h: 800, icon: "seal"),
    ]
}

// MARK: document colors + shuffle

enum ColorTools {
    static func documentColors(_ design: Design, limit: Int = 10) -> [String] {
        var counts: [String: Int] = [:]
        // First-seen order, so colours used equally often come out the same
        // way every launch — a Dictionary's own order changes with each run
        // — and the same way as on the Android twin.
        var order: [String] = []
        func add(_ c: String?) {
            guard let c, c.hasPrefix("#") else { return }
            let key = c.lowercased()
            if counts[key] == nil { order.append(key) }
            counts[key, default: 0] += 1
        }
        func addPaint(_ p: Paint?) {
            guard let p else { return }
            if p.kind == "gradient" { p.stops?.forEach { add($0.color) } }
            else if p.kind == "pattern" { add(p.color); add(p.secondary) }
            else if p.kind != "image" { add(p.color) }
        }
        for page in design.pages {
            switch page.background {
            case .color(let c): add(c)
            case .gradient(let p): addPaint(p)
            case .image: break
            }
            for el in page.elements {
                addPaint(el.fill)
                add(el.stroke)
                add(el.color)
            }
        }
        let ranked: [(offset: Int, element: String)] = Array(order.enumerated())
        let sorted = ranked.sorted { (a: (offset: Int, element: String), b: (offset: Int, element: String)) -> Bool in
            let ca: Int = counts[a.element] ?? 0
            let cb: Int = counts[b.element] ?? 0
            if ca != cb { return ca > cb }
            return a.offset < b.offset
        }
        // Faint colours — below half alpha, a wash rather than a colour —
        // are left out before the limit is taken, as on the Android twin,
        // so they never crowd a solid one out of "In this design".
        return sorted.map { $0.element }.filter { !ContrastAudit.isFaint($0) }.prefix(limit).map { $0 }
    }

    // MARK: a palette that goes with the page

    /// Every colour a page paints with — the background, then each element
    /// back to front — repeats kept, so a colour used more weighs more.
    /// Text and lines give their colour; a shape its fill (every stop of a
    /// gradient) and its border when it has one, which is all a drawing is.
    static func pageColours(_ page: Page) -> [String] {
        var out: [String] = []
        switch page.background {
        case .color(let c): out.append(c)
        case .gradient(let p):
            if let stops = p.stops { out += stops.map(\.color) } else if let c = p.color { out.append(c) }
        case .image: break
        }
        for el in page.elements {
            switch el.type {
            case .text, .line:
                if let c = el.color { out.append(c) }
            case .shape:
                if let fill = el.fill {
                    switch fill.kind {
                    case "gradient": out += (fill.stops ?? []).map(\.color)
                    case "none": break
                    default: if let c = fill.color { out.append(c) }
                    }
                }
                if let stroke = el.stroke, (el.strokeWidth ?? 0) > 0 { out.append(stroke) }
            case .image, .sticker:
                break
            }
        }
        return out
    }

    /// The palette that best covers what is already on the page: each
    /// palette scored by how far every colour on the page is from that
    /// palette's nearest colour, lowest total winning and the earlier on a
    /// tie. Not the distance from the page's average colour — a navy and
    /// coral poster averages to a mauve close to neither. A page with no
    /// colour to go by gets the first palette. The Android twin's
    /// Palettes.suggestFor, measure for measure.
    static func suggestedPalette(for page: Page, from palettes: [Palette]) -> Palette? {
        let used = pageColours(page).compactMap(rgb255)
        guard let first = palettes.first else { return nil }
        guard !used.isEmpty else { return first }
        var best = first
        var bestScore = Double.infinity
        for palette in palettes {
            let colours = palette.colors.compactMap(rgb255)
            guard !colours.isEmpty else { continue }
            var score: Double = 0
            for u in used {
                score += colours.map { redmean(u, $0) }.min() ?? 0
            }
            if score < bestScore {
                bestScore = score
                best = palette
            }
        }
        return best
    }

    static func suggestedPalette(for page: Page) -> Palette? {
        suggestedPalette(for: page, from: ContentLibrary.palettes)
    }

    /// "Redmean" distance, squared: RGB distance with each channel weighted
    /// by how much the eye cares about it at that level of red — far closer
    /// to what looks alike than plain RGB, for a few multiplications.
    static func redmean(_ a: (r: Int, g: Int, b: Int), _ b: (r: Int, g: Int, b: Int)) -> Double {
        let rMean: Double = Double(a.r + b.r) / 2
        let dr: Double = Double(a.r - b.r)
        let dg: Double = Double(a.g - b.g)
        let db: Double = Double(a.b - b.b)
        let red: Double = (2 + rMean / 256) * dr * dr
        let green: Double = 4 * dg * dg
        let blue: Double = (2 + (255 - rMean) / 256) * db * db
        return red + green + blue
    }

    /// "#rgb", "#rrggbb" or "#rrggbbaa" (alpha last, ignored) in 0…255, or
    /// nil for anything else.
    static func rgb255(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        switch digits.count {
        case 3: digits = digits.map { "\($0)\($0)" }.joined()
        case 6: break
        case 8: digits = String(digits.prefix(6))
        default: return nil
        }
        guard let value = Int(digits, radix: 16) else { return nil }
        return ((value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff)
    }

    private static func luminance(_ hex: String) -> Double {
        let ui = UIKitColorBox(hex)
        return 0.299 * ui.r + 0.587 * ui.g + 0.114 * ui.b
    }

    /// Remap the page's colors onto a palette by luminance rank.
    static func shuffle(page: inout Page, docColors: [String], palette: [String]) {
        let sortedDoc = docColors.sorted { luminance($0) < luminance($1) }
        let sortedPal = palette.sorted { luminance($0) < luminance($1) }
        var map: [String: String] = [:]
        for (i, c) in sortedDoc.enumerated() {
            let idx = sortedDoc.count <= 1 ? 0
                : Int((Double(i) / Double(sortedDoc.count - 1) * Double(sortedPal.count - 1)).rounded())
            map[c] = sortedPal[idx]
        }
        func remap(_ c: String?) -> String? {
            guard let c else { return nil }
            return map[c.lowercased()] ?? c
        }
        func remapPaint(_ p: Paint?) -> Paint? {
            guard var p else { return nil }
            if p.kind == "gradient" {
                p.stops = p.stops?.map { GradientStop(offset: $0.offset, color: remap($0.color) ?? $0.color) }
            } else {
                p.color = remap(p.color)
            }
            return p
        }
        switch page.background {
        case .color(let c): page.background = .color(remap(c) ?? c)
        case .gradient(let p): page.background = .gradient(remapPaint(p) ?? p)
        case .image: break
        }
        for i in page.elements.indices {
            page.elements[i].fill = remapPaint(page.elements[i].fill)
            page.elements[i].stroke = remap(page.elements[i].stroke)
            page.elements[i].color = remap(page.elements[i].color)
        }
    }
}

private struct UIKitColorBox {
    let r: Double, g: Double, b: Double
    init(_ hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        r = Double((v >> 16) & 0xff) / 255
        g = Double((v >> 8) & 0xff) / 255
        b = Double(v & 0xff) / 255
    }
}
