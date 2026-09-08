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
        let scale = min(design.width / width, design.height / height)
        let dx = (design.width - width * scale) / 2
        let dy = (design.height - height * scale) / 2
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
            if el.type == .text, let fs = el.fontSize { el.fontSize = fs * scale }
            if el.type == .text, let ls = el.letterSpacing { el.letterSpacing = ls * scale }
            if el.type == .line, let t = el.thickness { el.thickness = max(1, t * scale) }
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
        .init(id: "poster", name: "Poster", w: 1587, h: 2245, icon: "doc.richtext"),
        .init(id: "flyer", name: "Flyer A5", w: 1240, h: 1748, icon: "doc"),
        .init(id: "a4", name: "A4 Document", w: 1240, h: 1754, icon: "doc.text"),
        .init(id: "business-card", name: "Business Card", w: 1050, h: 600, icon: "person.crop.rectangle"),
        .init(id: "quote-card", name: "Quote Card", w: 1440, h: 1080, icon: "quote.opening"),
        .init(id: "logo", name: "Logo", w: 800, h: 800, icon: "seal"),
    ]
}

// MARK: document colors + shuffle

enum ColorTools {
    static func documentColors(_ design: Design, limit: Int = 10) -> [String] {
        var counts: [String: Int] = [:]
        func add(_ c: String?) {
            guard let c, c.hasPrefix("#") else { return }
            counts[c.lowercased(), default: 0] += 1
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
        return counts.sorted { $0.value > $1.value }.prefix(limit).map(\.key)
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
