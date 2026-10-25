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
    /// Its name in English, as the catalogue keys it, for a library shape;
    /// `name` is what the app calls it.
    var englishName: String? = nil

    private enum CodingKeys: String, CodingKey { case id, name, category, path, rectLike }
}

/// One page of a template that has several: what is on it, and the title
/// and presenter notes the page it makes is given, when it has them — and,
/// for an animated one, how it plays, as a design's page keeps it: its own
/// animation, how it gives way to the next and the seconds it holds.
struct TemplatePage: Codable {
    var background: Background
    var elements: [Element]
    var title: String? = nil
    var notes: String? = nil
    var pageAnimation: PageAnimation? = nil
    var transition: String? = nil
    var holdSeconds: Double? = nil

    init(background: Background, elements: [Element], title: String? = nil, notes: String? = nil,
         pageAnimation: PageAnimation? = nil, transition: String? = nil, holdSeconds: Double? = nil) {
        self.background = background
        self.elements = elements
        self.title = title
        self.notes = notes
        self.pageAnimation = pageAnimation
        self.transition = transition
        self.holdSeconds = holdSeconds
    }

    /// How it plays, read leniently: a key of the wrong kind is none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decode(Background.self, forKey: .background)
        elements = try c.decode([Element].self, forKey: .elements)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        notes = try? c.decodeIfPresent(String.self, forKey: .notes)
        pageAnimation = try? c.decodeIfPresent(PageAnimation.self, forKey: .pageAnimation)
        transition = try? c.decodeIfPresent(String.self, forKey: .transition)
        holdSeconds = try? c.decodeIfPresent(Double.self, forKey: .holdSeconds)
    }

    private enum CodingKeys: String, CodingKey {
        case background, elements, title, notes, pageAnimation, transition, holdSeconds
    }
}

struct Template: Codable, Identifiable {
    var id: String
    var name: String
    var category: String
    var width: Double
    var height: Double
    var background: Background
    var elements: [Element]
    /// Every page, for a template that has several, as the Android twin
    /// reads them: {"background", "elements", "title"?, "notes"?} each.
    /// Nil or empty is the one page `background` and `elements` describe;
    /// when there are pages, `background` and `elements` are the first's.
    var pages: [TemplatePage]? = nil
    /// What the Filters sheet filters it by, worked out by the templates
    /// generator (TemplateFacets); nil, for one written before, is a
    /// template of no colour, still, without photos, of its pages.
    var facets: TemplateFacets? = nil
    /// How a template of one page plays, at its top as the generator writes
    /// it (TemplatePage); a template of several has them on each page.
    var pageAnimation: PageAnimation? = nil
    var transition: String? = nil
    var holdSeconds: Double? = nil
    /// The industry it was written for — "real-estate", "fitness", … — or
    /// "animated", as the generator's packs name it; nil for the rest.
    var topic: String? = nil
    /// The template this is a colourway of, its base; nil for a base or a
    /// template with no colourways.
    var variantOf: String? = nil
    /// The sound an animated template starts with, as a design's tracks
    /// ("audio"), which a design made from it keeps.
    var audio: [AudioTrack]? = nil

    private enum CodingKeys: String, CodingKey {
        case id, name, category, width, height, background, elements, pages, facets
        case pageAnimation, transition, holdSeconds, topic, variantOf, audio
    }

    /// Its base and every colourway of it share this: the base's id.
    var family: String { variantOf ?? id }

    /// Its facets, or those of a template with none written.
    var shownFacets: TemplateFacets { facets ?? TemplateFacets(pages: pageCount) }

    /// The template's pages, in order: one for a single-page template.
    var pageSpecs: [TemplatePage] {
        if let pages, !pages.isEmpty { return pages }
        return [TemplatePage(background: background, elements: elements, pageAnimation: pageAnimation,
                             transition: transition, holdSeconds: holdSeconds)]
    }

    var pageCount: Int { pageSpecs.count }

    /// A fresh Design at the template's native size, every page of it — in
    /// the unit of the print type made at exactly that size, so an A4
    /// template prints on A4, and cut into the slides of the carousel type
    /// made at it (SizePreset.carouselAt).
    func instantiate() -> Design {
        var design = Design(title: name, width: width, height: height)
        design.pages = pageSpecs.map { makePage($0, scale: 1, dx: 0, dy: 0) }
        // The sound an animated template starts with goes with it.
        design.audio = audio
        if let type = SizePreset.all.first(where: { $0.unit != nil && $0.w == width && $0.h == height }) {
            design.unit = type.unit
            design.dpi = type.dpi
        } else if let columns = SizePreset.carouselAt(width: width, height: height)?.split {
            design = PageSplit.splitAll(design, columns: columns)
        }
        return design
    }

    /// A fresh Design of page `index` alone — "Use this page" on Home.
    func instantiate(onlyPage index: Int) -> Design {
        var design = instantiate()
        if design.pages.indices.contains(index) { design.pages = [design.pages[index]] }
        return design
    }

    /// A fresh Design of page `index` alone at a design type's size —
    /// "Use this page" in the Start sheet.
    func instantiate(for preset: SizePreset, onlyPage index: Int) -> Design {
        var design = instantiate(for: preset)
        if design.pages.indices.contains(index) { design.pages = [design.pages[index]] }
        return design
    }

    /// Every page fitted to a page of this size, in order: what "Apply all
    /// N pages" puts in the editor.
    func makePages(width pageWidth: Double, height pageHeight: Double) -> [Page] {
        pageSpecs.indices.map { makePage(at: $0, width: pageWidth, height: pageHeight) }
    }

    /// A fresh Design at a design type's size and in its unit: the
    /// template as it is when made at that size, else fitted to it — a
    /// flyer made before the flyer became true A5.
    func instantiate(for preset: SizePreset) -> Design {
        var design: Design
        if width == preset.w && height == preset.h {
            design = instantiate()
        } else {
            design = Design(title: name, width: preset.w, height: preset.h)
            design.pages = pageSpecs.indices.map { makePage(at: $0, width: preset.w, height: preset.h) }
            design.audio = audio
        }
        design.unit = preset.unit
        design.dpi = preset.dpi
        return preset.started(design)
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
        makePage(at: 0, width: pageWidth, height: pageHeight)
    }

    /// Page `index` of the template (the first when there is no such page)
    /// fitted to a page of this size, as above.
    func makePage(at index: Int, width pageWidth: Double, height pageHeight: Double) -> Page {
        let specs = pageSpecs
        let spec = specs.indices.contains(index) ? specs[index] : specs[0]
        guard width > 0, height > 0 else { return Page(background: spec.background) }
        let scale = min(pageWidth / width, pageHeight / height)
        let dx = (pageWidth - width * scale) / 2
        let dy = (pageHeight - height * scale) / 2
        return makePage(spec, scale: scale, dx: dx, dy: dy)
    }

    private func makePage(_ spec: TemplatePage, scale: Double, dx: Double, dy: Double) -> Page {
        var page = Page(background: spec.background, notes: spec.notes?.isEmpty == false ? spec.notes : nil)
        page.title = spec.title.flatMap(PageTitles.kept)
        page.pageAnimation = spec.pageAnimation
        page.transition = spec.transition
        page.holdSeconds = spec.holdSeconds
        page.elements = spec.elements.map { item in
            var el = Self.fitted(item, scale: scale, dx: dx, dy: dy)
            el.id = UID.make()
            // Measure after scaling: the spec carries no height, and the
            // decoder's line-count estimate ignores leading and wrapping.
            if el.type == .text { el.h = FontLibrary.layoutHeight(for: el) }
            return el
        }
        return page
    }

    /// An element of a template fitted onto a page, as the Android twin's
    /// Template.instantiate(width, height) fits one — a built-in template
    /// or one of your own alike: its box scaled and moved by `dx`, `dy`;
    /// its type and spacing, wherever it has them, scaled with it; a
    /// line's or a drawing's thickness too, never under 1. Rounding scales
    /// with the box it rounds, so a card is as round on either phone and
    /// both write the same radius. A stroke's width and per-corner radii
    /// are left as they are on both. A table cell's spacing scales with
    /// its box (TableCell.scaledPad), so its next relayout holds its rows.
    static func fitted(_ item: Element, scale: Double, dx: Double, dy: Double) -> Element {
        var el = item
        el.x = el.x * scale + dx
        el.y = el.y * scale + dy
        el.w *= scale
        el.h *= scale
        if let fs = el.fontSize { el.fontSize = fs * scale }
        if let ls = el.letterSpacing { el.letterSpacing = ls * scale }
        if let t = el.thickness { el.thickness = max(1, t * scale) }
        if let r = el.radius { el.radius = r * scale }
        el.table = TableCell.scaledPad(el.table, by: scale)
        return el
    }
}

extension Template {
    /// Lenient about the page it describes: a template with "pages" may
    /// leave the top-level background and elements out, and when it has
    /// pages they are the first page's whatever the top level says. One of
    /// a single page reads as it always did.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        let listed = try c.decodeIfPresent([TemplatePage].self, forKey: .pages) ?? []
        pages = listed.isEmpty ? nil : listed
        facets = try? c.decodeIfPresent(TemplateFacets.self, forKey: .facets)
        pageAnimation = try? c.decodeIfPresent(PageAnimation.self, forKey: .pageAnimation)
        transition = try? c.decodeIfPresent(String.self, forKey: .transition)
        holdSeconds = try? c.decodeIfPresent(Double.self, forKey: .holdSeconds)
        topic = try? c.decodeIfPresent(String.self, forKey: .topic)
        variantOf = try? c.decodeIfPresent(String.self, forKey: .variantOf)
        audio = try? c.decodeIfPresent([AudioTrack].self, forKey: .audio)
        if let first = listed.first {
            background = first.background
            elements = first.elements
        } else {
            background = try c.decode(Background.self, forKey: .background)
            elements = try c.decode([Element].self, forKey: .elements)
        }
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
    /// Words to find each sticker by, by glyph (see Stickers).
    var stickerNames: [String: [String]]?
    var photoSpecs: PhotoSpecs
    /// The design types: every size a design can start at.
    var sizes: [SizePreset]?
    /// The first launch's "What will you use Canvia for?" (UseProfile).
    var uses: [UseCase]?
    /// The Doc templates (Docs), from templates/docs.json.
    var docs: [DocTemplate]?
}

enum ContentLibrary {
    static let bundle: ContentBundle = {
        guard let url = Bundle.main.url(forResource: "Content", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              var decoded = try? JSONDecoder().decode(ContentBundle.self, from: data) else {
            assertionFailure("Content.json missing or invalid")
            return ContentBundle(
                shapes: [fallbackShape],
                templates: [], palettes: [], gradients: [], pairings: [],
                stickerGroups: [],
                photoSpecs: PhotoSpecs(meshes: [], waves: [], stripes: []))
        }
        // A shape's name is the app's words, as the Android twin's
        // ShapeLibrary has them; its id is what a design keeps.
        for i in decoded.shapes.indices {
            decoded.shapes[i].englishName = decoded.shapes[i].name
            decoded.shapes[i].name = tr(decoded.shapes[i].name)
        }
        return decoded
    }()

    static var shapes: [ShapeDef] { bundle.shapes }
    static var templates: [Template] { bundle.templates }
    static var palettes: [Palette] { bundle.palettes }
    static var gradients: [GradientPreset] { bundle.gradients }
    static var pairings: [FontPairing] { bundle.pairings }
    static var stickerGroups: [StickerGroup] { bundle.stickerGroups }
    static var uses: [UseCase] { bundle.uses ?? [] }
    static var docTemplates: [DocTemplate] { bundle.docs ?? [] }

    /// The design-type catalogue; the eleven Home has always shown should
    /// it fail to load, so a size is always there to start from.
    static let sizes: [SizePreset] = {
        let listed = bundle.sizes ?? []
        return listed.isEmpty ? fallbackSizes : listed
    }()

    static let fallbackSizes: [SizePreset] = [
        SizePreset(id: "insta-post", name: "Instagram Post", category: "Social", width: 1080, height: 1080),
        SizePreset(id: "insta-story", name: "Instagram Story", category: "Social", width: 1080, height: 1920),
        SizePreset(id: "presentation", name: "Presentation", category: "Presentations", width: 1920, height: 1080),
        SizePreset(id: "youtube-thumb", name: "YouTube Thumbnail", category: "Video", width: 1280, height: 720),
        SizePreset(id: "facebook-post", name: "Facebook Post", category: "Social", width: 1200, height: 630),
        SizePreset(id: "poster", name: "Poster", category: "Print", width: 420, height: 594, unit: "mm", dpi: 96),
        SizePreset(id: "flyer", name: "Flyer A5", category: "Print", width: 148, height: 210, unit: "mm", dpi: 300),
        SizePreset(id: "a4", name: "A4 Document", category: "Documents", width: 210, height: 297, unit: "mm", dpi: 300),
        SizePreset(id: "business-card", name: "Business Card", category: "Print", width: 3.5, height: 2, unit: "in", dpi: 300),
        SizePreset(id: "quote-card", name: "Quote Card", category: "Social", width: 1440, height: 1080),
        SizePreset(id: "logo", name: "Logo", category: "Marketing", width: 800, height: 800),
    ]

    /// A plain square, used whenever a shape id cannot be resolved.
    static let fallbackShape = ShapeDef(id: "rect", name: tr("Square"),
                                        category: "Basic", path: "M0,0H100V100H0Z",
                                        rectLike: true, englishName: "Square")

    // `uniqueKeysWithValues:` traps on a duplicate id, and the trap would
    // happen at launch, on first access. A duplicate in the content library
    // is a content bug, not a reason to take the app down: keep the first.
    static let shapeMap: [String: ShapeDef] = Dictionary(
        bundle.shapes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func shape(_ id: String?) -> ShapeDef {
        shapeMap[id ?? "rect"] ?? shapeMap["rect"] ?? fallbackShape
    }

    /// The shape a photo's `maskShapeId` clips it to: a library shape, a
    /// letter or number frame (GlyphFrames) or a mask frame ("mask:<id>",
    /// MaskFrames); nil for none, or an id this build does not have, which
    /// is no frame rather than a wrong one.
    static func frameShape(_ id: String?) -> ShapeDef? {
        guard let id else { return nil }
        return shapeMap[id] ?? GlyphFrames.shape(id) ?? MaskFrames.shape(id)
    }

    /// The shape photo `el` is clipped to: its frame (`frameShape`), or
    /// with none, a grid's cut cell's cut (PhotoGrids.clipShape(of:)), as
    /// the Android twin's PhotoFrames.shapeOf.
    static func frameShape(of el: Element) -> ShapeDef? {
        frameShape(el.maskShapeId) ?? PhotoGrids.clipShape(of: el)
    }

    /// The geometry an element draws: its own path data if it has any,
    /// else the library shape it names.
    static func shape(for el: Element) -> ShapeDef {
        if let d = el.pathData, !d.isEmpty {
            return ShapeDef(id: "custom", name: tr("Custom shape"), category: "Custom", path: d, rectLike: false)
        }
        return shape(el.shapeId)
    }

    /// Template categories in the order they first appear.
    static var templateCategories: [String] {
        var seen: [String] = []
        for t in templates where !seen.contains(t.category) { seen.append(t.category) }
        return seen
    }

    /// Templates in a category (nil is all of them) whose name, category or
    /// topic (its words, "real estate" for "real-estate") matches the query
    /// (empty is all of them), and that `facets` lets through
    /// (TemplateFilter.admits; an empty filter lets all through) — the
    /// Android twin's Templates.filtered.
    static func filteredTemplates(in category: String?, matching query: String,
                                  facets: TemplateFilter = TemplateFilter(),
                                  among library: [Template] = templates) -> [Template] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return library.filter { t in
            (category == nil || t.category == category) && facets.admits(t.shownFacets)
                && (needle.isEmpty || t.name.localizedCaseInsensitiveContains(needle)
                    || t.category.localizedCaseInsensitiveContains(needle)
                    || topicWords(t).localizedCaseInsensitiveContains(needle))
        }
    }

    /// A template's topic as words: "real estate" for "real-estate"; empty
    /// for none.
    static func topicWords(_ template: Template) -> String {
        template.topic?.replacingOccurrences(of: "-", with: " ") ?? ""
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

    /// The line over the editor's templates: what a tap will do — on a page
    /// with something on it (`addsPage`, DesignStore.templateAddsPage), go on
    /// a new page after it — and why every size is there when none is made
    /// for this one.
    static func editorTemplatesNote(exactCount: Int, addsPage: Bool = false) -> String {
        if addsPage { return tr("Each one goes on a new page after this one. Hold one to use it on this page instead.") }
        return exactCount == 0
            ? tr("Nothing is made for this exact size, so every template is fitted to it. It replaces this page; Undo brings it back.")
            : tr("Replaces what is on this page. Undo brings it back.")
    }

    /// A size's templates: those made at exactly its pixels, then any made
    /// at the pixels it had before it became its true size.
    static func sizedTemplates(for preset: SizePreset) -> [Template] {
        var bucket = sizedTemplates(width: preset.w, height: preset.h, category: nil)
        if let former = SizePreset.formerPixels[preset.id],
           former.width != preset.w || former.height != preset.h {
            bucket += sizedTemplates(width: former.width, height: former.height, category: nil)
        }
        return bucket
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
        "Basic": tr("Basic shapes"), "Stars": tr("Stars and badges"), "Arrows": tr("Arrows"),
        "Callouts": tr("Speech and labels"), "Symbols": tr("Symbols"), "Blobs": tr("Blobs"),
        "Decor": tr("Decorative"),
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

/// A design type: a size a design starts at, from the catalogue every phone
/// reads — Content.json's "sizes", which is the Android twin's
/// templates/sizes.json entry for entry, written in by its generator
/// (`tools/generate_templates.py --ios`) and never edited here, so an id,
/// a name and an order mean the same on both. Each is written in its own
/// unit (an A4 page as 210 × 297 mm at 300 dpi) and made whole pixels here,
/// which is what a page is.
struct SizePreset: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    /// "Social", "Video", "Presentations", "Print", "Documents" or
    /// "Marketing".
    var category: String
    /// The size in pixels, which is what a design made at it gets.
    var w: Double
    var h: Double
    /// The size as the catalogue writes it, in `unit`.
    var width: Double
    var height: Double
    /// "mm", "cm" or "in" for a print size; nil is pixels.
    var unit: String?
    var dpi: Double?
    /// Other words it is found by: "cv" for a resume, "twitter" for X.
    var keywords: [String]
    /// How many slides across a carousel type's page is cut into — its
    /// `"split": {"columns": n}` in the catalogue, carried onto each page
    /// it starts with as the page's split (PageSplit); nil for the rest.
    var split: Int?

    init(id: String, name: String, category: String, width: Double, height: Double,
         unit: String? = nil, dpi: Double? = nil, keywords: [String] = [], split: Int? = nil) {
        self.id = id
        self.name = name
        self.category = category
        self.width = width
        self.height = height
        self.unit = Units.isPhysical(unit) ? unit : nil
        self.dpi = self.unit == nil ? nil : (dpi ?? Units.printDPI)
        self.keywords = keywords
        self.split = split
        let d = self.dpi ?? Units.screenDPI
        w = Units.pixels(width, unit: self.unit ?? "px", dpi: d)
        h = Units.pixels(height, unit: self.unit ?? "px", dpi: d)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, category, width, height, unit, dpi, keywords, split
    }

    /// The catalogue's "split": {"columns": n}.
    private struct Split: Codable {
        var columns: Int
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  name: try c.decode(String.self, forKey: .name),
                  category: (try? c.decode(String.self, forKey: .category)) ?? "Social",
                  width: try c.decode(Double.self, forKey: .width),
                  height: try c.decode(Double.self, forKey: .height),
                  unit: try? c.decode(String.self, forKey: .unit),
                  dpi: try? c.decode(Double.self, forKey: .dpi),
                  keywords: (try? c.decode([String].self, forKey: .keywords)) ?? [],
                  split: (try? c.decode(Split.self, forKey: .split))?.columns)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(category, forKey: .category)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(dpi, forKey: .dpi)
        try c.encode(keywords, forKey: .keywords)
        try c.encodeIfPresent(split.map { Split(columns: $0) }, forKey: .split)
    }

    /// A blank design at this size, in its unit, under `title` — a folded
    /// card's two pages, a mind map's starter with it (DesignTypes).
    func makeDesign(title: String? = nil) -> Design {
        var design = Design(title: title ?? name, width: w, height: h)
        design.unit = unit
        design.dpi = dpi
        return DesignTypes.started(self, started(design))
    }

    /// `design`, made at this type, as it starts: a carousel's pages cut
    /// into its slides (PageSplit), at the Whiteboard type — and the mind
    /// map and flowchart made on one — its pages expanded (Whiteboards), at
    /// the Doc type blocks to type into on Letter pages (Docs), any other
    /// as it is — the Android twin's SizePreset.measured.
    func started(_ design: Design) -> Design {
        let made = split.map { PageSplit.splitAll(design, columns: $0) } ?? design
        if DesignTypes.whiteboards.contains(id) { return Whiteboards.started(made) }
        guard id == Docs.presetId else { return made }
        var doc = Docs.started(design.title)
        doc.id = design.id
        return doc
    }

    /// "210 × 297 mm", or "1080 × 1920" for a size in pixels.
    var dimensions: String {
        Units.dimensions(width: w, height: h, unit: unit, dpi: dpi)
    }

    /// The symbol a size is drawn with: its own for the eleven on Home's
    /// row and the website, else its category's.
    var icon: String {
        if let own = Self.icons[id] { return own }
        switch category {
        case "Video": return "play.rectangle"
        case "Presentations": return "display"
        case "Print": return "doc.richtext"
        case "Documents": return "doc.text"
        case "Marketing": return "megaphone"
        default: return w > h ? "rectangle" : (w < h ? "rectangle.portrait" : "square")
        }
    }

    private static let icons: [String: String] = [
        "insta-post": "square", "insta-story": "iphone", "presentation": "display",
        "youtube-thumb": "play.rectangle", "facebook-post": "rectangle", "poster": "doc.richtext",
        "flyer": "doc", "a4": "doc.text", "business-card": "person.crop.rectangle",
        "quote-card": "quote.opening", "logo": "seal", "website": "globe", "doc": "doc.plaintext",
    ]

    /// How many of the catalogue's first sizes Home's row shows: the
    /// eleven it always had, in their order, before "More sizes".
    static let heroCount = 11

    /// Every design type, in catalogue order.
    static var all: [SizePreset] { ContentLibrary.sizes }

    /// The eleven on Home's row and in the Start sheet.
    static var hero: [SizePreset] { Array(all.prefix(heroCount)) }

    static func byId(_ id: String) -> SizePreset? { all.first { $0.id == id } }

    /// The categories, in the order the Design types sheet lists them —
    /// Android's SizePresets.categories, word for word.
    static let categories = ["Social", "Video", "Presentations", "Print", "Documents", "Marketing"]

    /// The pixel size a type's templates were made at before it became
    /// its true size: the A5 flyer's were made at 1240 × 1748, and are its
    /// templates still — fitted to the page when picked — as on Android.
    /// Flyer (A5), the same paper as a type of its own, takes the same.
    static let formerPixels: [String: (width: Double, height: Double)] = [
        "flyer": (1240, 1748), "flyer-a5": (1240, 1748),
    ]

    /// The first carousel type in the catalogue whose pixels are `width` ×
    /// `height` — Instagram Carousel for 3240 × 1350 — or nil: what a
    /// template made at that size is cut into slides as.
    static func carouselAt(width: Double, height: Double) -> SizePreset? {
        all.first { $0.split != nil && $0.w == width && $0.h == height }
    }

    // MARK: search

    /// A query as it is compared: case, accents and the space around it
    /// gone — "Résumé" finds "resume".
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The design types a search finds, best first — Android's
    /// SizePresets.search, rule for rule. Capitals and accents aside, every
    /// word of the query must be in the name or the keywords; or it is a
    /// size in pixels — "1080x1920", "1080 × 1920" — and finds the types of
    /// that size. Ranked by one rule: a name that starts with the query,
    /// then a name with a word starting with its first word, then the rest
    /// — each tier in catalogue order, so "tiktok" leads with TikTok Video.
    /// Nothing for a blank query.
    static func search(_ query: String, in presets: [SizePreset] = SizePreset.all) -> [SizePreset] {
        let needle = folded(query).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !needle.isEmpty else { return [] }
        if let size = pixelQuery(needle) {
            return presets.filter { $0.w == size.width && $0.h == size.height }
        }
        let words = needle.split(separator: " ").map(String.init)
        let found = presets.filter { preset in
            let haystack = ([preset.name] + preset.keywords).map(folded)
            return words.allSatisfy { word in haystack.contains { $0.contains(word) } }
        }
        let first = words[0]
        func rank(_ preset: SizePreset) -> Int {
            let name = folded(preset.name)
            if name.hasPrefix(needle) { return 0 }
            let nameWords = name.split(whereSeparator: { $0 == " " || $0 == "(" || $0 == ")" })
            return nameWords.contains { $0.hasPrefix(first) } ? 1 : 2
        }
        let ranked = found.map { (preset: $0, rank: rank($0)) }
        return (0...2).flatMap { tier in ranked.filter { $0.rank == tier }.map { $0.preset } }
    }

    /// "1080x1920" or "1080 × 1920" — whole numbers either side of one x —
    /// as a size, or nil.
    static func pixelQuery(_ needle: String) -> (width: Double, height: Double)? {
        let parts = needle.replacingOccurrences(of: "×", with: "x")
            .split(separator: "x", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              parts.allSatisfy({ side in !side.isEmpty && side.allSatisfy { $0.isASCII && $0.isNumber } }),
              let w = Double(parts[0]), let h = Double(parts[1]) else { return nil }
        return (w, h)
    }
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

    /// How light a colour reads, 0…1: what the theme's mapping ranks
    /// colours by (shuffle), and Apply colours to page (PhotoColours).
    static func luminance(_ hex: String) -> Double {
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
